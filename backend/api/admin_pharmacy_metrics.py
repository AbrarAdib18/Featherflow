"""Pharmacy Admin — dashboard metrics, sales/commission listings and
settlement generation, all period-filtered with live-DB Decimal aggregates
(no hardcoded/mock values). Kept separate from admin_pharmacy.py so that
file's medicine/account-lifecycle concerns don't grow unbounded.
"""
from datetime import datetime, timedelta
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from api.admin_rbac import IsAdminUser, can_perform_action
from pharmacy.models import (
    LOW_STOCK_THRESHOLD, PharmacyAppeal, PharmacyCommission, PharmacyEmployee,
    PharmacyMedicine, PharmacySale, PharmacySettlement,
)
from pharmacy.services import log_pharmacy_action, notify
from users.models import User


def _deny(user, action):
    if not can_perform_action(user, 'pharmacy', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the pharmacy module.',
             'code': 'forbidden_module_action'}, status=403)
    return None


def _parse_date(value, *, end_of_day=False):
    try:
        dt = datetime.strptime(str(value)[:10], '%Y-%m-%d')
    except (TypeError, ValueError):
        return None
    if end_of_day:
        dt = dt.replace(hour=23, minute=59, second=59)
    return timezone.make_aware(dt)


def _period_range(request):
    """(start, end) datetimes for period=today|week|month|year|lifetime|custom.
    `end` defaults to now; `start=None` means lifetime (no lower bound)."""
    period = request.query_params.get('period', 'lifetime')
    now = timezone.now()
    if period == 'custom':
        start = _parse_date(request.query_params.get('start'))
        end = _parse_date(request.query_params.get('end'), end_of_day=True) or now
        return start, end
    if period == 'today':
        return now.replace(hour=0, minute=0, second=0, microsecond=0), now
    if period == 'week':
        return now - timedelta(days=7), now
    if period == 'month':
        return now - timedelta(days=30), now
    if period == 'year':
        return now - timedelta(days=365), now
    return None, now  # lifetime


def _money(value):
    return str((value or Decimal('0')).quantize(Decimal('0.01')))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_metrics(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    period = request.query_params.get('period', 'lifetime')
    start, end = _period_range(request)

    accounts = User.objects.filter(roles__name='pharmacy')
    appeal_pending = PharmacyAppeal.objects.filter(
        status__in=PharmacyAppeal.OPEN_STATUSES).values('pharmacy_user').distinct().count()
    account_holders = accounts.count()  # one authorized holder per pharmacy account today
    employees_total = PharmacyEmployee.objects.filter(is_active=True).count()

    medicines = PharmacyMedicine.objects.all()
    active_medicines = medicines.filter(is_active=True)

    sales = PharmacySale.objects.filter(status='completed')
    if start:
        sales = sales.filter(completed_at__gte=start)
    sales = sales.filter(completed_at__lte=end)
    refunded_sales = PharmacySale.objects.filter(status='refunded')
    if start:
        refunded_sales = refunded_sales.filter(updated_at__gte=start)
    refunded_sales = refunded_sales.filter(updated_at__lte=end)
    commissions = PharmacyCommission.objects.filter(sale__in=sales)
    commission_totals = commissions.aggregate(
        commission=Sum('commission_amount'), pharmacy_amount=Sum('pharmacy_amount'))
    gross_total = sales.aggregate(v=Sum('gross_amount'))['v'] or Decimal('0')

    pending_settlement = PharmacySettlement.objects.filter(status='pending').aggregate(
        v=Sum('payable_amount'))['v'] or Decimal('0')
    completed_settlement = PharmacySettlement.objects.filter(status='paid').aggregate(
        v=Sum('payable_amount'))['v'] or Decimal('0')

    return Response({
        'period': period,
        'period_start': start.isoformat() if start else None,
        'period_end': end.isoformat(),
        'accounts': {
            'total': account_holders,
            'pending_review': accounts.filter(account_status='pending').count(),
            'active': accounts.filter(account_status='active').count(),
            'suspended': accounts.filter(account_status='suspended').count(),
            'appeal_pending': appeal_pending,
            'account_holders': account_holders,
            'employees': employees_total,
            'total_workforce': account_holders + employees_total,
        },
        'medicines': {
            'total': medicines.count(),
            'active': active_medicines.count(),
            'inactive': medicines.filter(is_active=False).count(),
            'categories': active_medicines.values('category').distinct().count(),
            'low_stock': active_medicines.filter(
                stock_quantity__lt=LOW_STOCK_THRESHOLD, stock_quantity__gt=0).count(),
            'out_of_stock': active_medicines.filter(stock_quantity__lte=0).count(),
            'pending_approval': active_medicines.filter(
                prescription_required=True, is_approved=False).count(),
        },
        'sales': {
            'total_orders': sales.count(),
            'gross_sales': _money(gross_total),
            'featherflow_commission': _money(commission_totals['commission']),
            'pharmacy_share': _money(commission_totals['pharmacy_amount']),
            'cancelled_or_refunded': refunded_sales.count(),
            'pending_settlement': _money(pending_settlement),
            'completed_settlement': _money(completed_settlement),
        },
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_sales(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    start, end = _period_range(request)
    qs = PharmacySale.objects.select_related('commission', 'pharmacy_user').order_by('-completed_at')
    if request.query_params.get('pharmacy'):
        qs = qs.filter(pharmacy_user_id=request.query_params['pharmacy'])
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)
    if start:
        qs = qs.filter(completed_at__gte=start)
    qs = qs.filter(completed_at__lte=end)

    page = max(1, int(request.query_params.get('page', 1) or 1))
    page_size = min(100, max(1, int(request.query_params.get('page_size', 25) or 25)))
    total = qs.count()
    rows = qs[(page - 1) * page_size: page * page_size]

    def row(sale):
        commission = getattr(sale, 'commission', None)
        return {
            'id': str(sale.id), 'order_reference': sale.order_reference,
            'pharmacy_id': str(sale.pharmacy_user_id),
            'pharmacy_name': sale.pharmacy_user.full_name or sale.pharmacy_user.email,
            'gross_amount': _money(sale.gross_amount), 'status': sale.status,
            'commission_amount': _money(commission.commission_amount) if commission else '0.00',
            'pharmacy_amount': _money(commission.pharmacy_amount) if commission else '0.00',
            'completed_at': sale.completed_at.isoformat() if sale.completed_at else None,
        }

    return Response({'results': [row(s) for s in rows], 'count': total, 'page': page, 'page_size': page_size})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_commissions(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    start, end = _period_range(request)
    qs = PharmacyCommission.objects.select_related('sale', 'sale__pharmacy_user').order_by('-created_at')
    if request.query_params.get('pharmacy'):
        qs = qs.filter(sale__pharmacy_user_id=request.query_params['pharmacy'])
    if start:
        qs = qs.filter(sale__completed_at__gte=start)
    qs = qs.filter(sale__completed_at__lte=end)

    page = max(1, int(request.query_params.get('page', 1) or 1))
    page_size = min(100, max(1, int(request.query_params.get('page_size', 25) or 25)))
    total = qs.count()
    rows = qs[(page - 1) * page_size: page * page_size]

    return Response({'results': [{
        'id': str(c.id), 'sale_id': str(c.sale_id),
        'order_reference': c.sale.order_reference, 'pharmacy_id': str(c.sale.pharmacy_user_id),
        'pharmacy_name': c.sale.pharmacy_user.full_name or c.sale.pharmacy_user.email,
        'rate_percent': str((c.rate * 100).quantize(Decimal('0.01'))),
        'gross_amount': _money(c.gross_amount), 'commission_amount': _money(c.commission_amount),
        'pharmacy_amount': _money(c.pharmacy_amount), 'sale_status': c.sale.status,
        'created_at': c.created_at.isoformat() if c.created_at else None,
    } for c in rows], 'count': total, 'page': page, 'page_size': page_size})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_settlements(request):
    """List settlements, optionally scoped to one pharmacy (?pharmacy=<id>) or
    status (?status=pending|approved|paid|failed|reversed)."""
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = PharmacySettlement.objects.select_related('pharmacy_user').order_by('-period_start')
    if request.query_params.get('pharmacy'):
        qs = qs.filter(pharmacy_user_id=request.query_params['pharmacy'])
    if request.query_params.get('status'):
        qs = qs.filter(status=request.query_params['status'])
    return Response({'results': [_settlement_json(s) | {
        'pharmacy_id': str(s.pharmacy_user_id),
        'pharmacy_name': s.pharmacy_user.full_name or s.pharmacy_user.email,
    } for s in qs[:200]]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_settlement_generate(request, pharmacy_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    user = User.objects.filter(pk=pharmacy_id, roles__name='pharmacy').first()
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    period_start = _parse_date(request.data.get('period_start'))
    period_end = _parse_date(request.data.get('period_end'), end_of_day=True)
    if not period_start or not period_end:
        return Response({'detail': 'period_start and period_end (YYYY-MM-DD) are required.'}, status=400)

    sales = PharmacySale.objects.filter(
        pharmacy_user=user, status='completed',
        completed_at__gte=period_start, completed_at__lte=period_end)
    commissions = PharmacyCommission.objects.filter(sale__in=sales)
    totals = commissions.aggregate(commission=Sum('commission_amount'), pharmacy_amount=Sum('pharmacy_amount'))
    gross = sales.aggregate(v=Sum('gross_amount'))['v'] or Decimal('0')
    if sales.count() == 0:
        return Response({'detail': 'No completed sales in this period.'}, status=400)

    settlement = PharmacySettlement.objects.create(
        pharmacy_user=user, period_start=period_start.date(), period_end=period_end.date(),
        gross_sales=gross, commission=totals['commission'] or Decimal('0'),
        payable_amount=totals['pharmacy_amount'] or Decimal('0'), status='pending',
        created_by=request.user, created_at=timezone.now(), updated_at=timezone.now(),
    )
    log_pharmacy_action(request.user, 'Generate pharmacy settlement', 'create', 'pharmacy_settlement',
                        settlement.id, request=request)
    return Response(_settlement_json(settlement), status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_settlement_update(request, settlement_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    settlement = PharmacySettlement.objects.filter(pk=settlement_id).first()
    if settlement is None:
        return Response({'detail': 'Settlement not found.'}, status=404)
    new_status = request.data.get('status')
    if new_status not in ('approved', 'paid', 'failed', 'reversed'):
        return Response({'detail': 'status must be one of approved/paid/failed/reversed.'}, status=400)
    old_status = settlement.status
    settlement.status = new_status
    if new_status == 'paid':
        settlement.paid_at = timezone.now()
        settlement.payment_reference = str(request.data.get('payment_reference', '') or '')
    settlement.updated_at = timezone.now()
    settlement.save(update_fields=['status', 'paid_at', 'payment_reference', 'updated_at'])
    log_pharmacy_action(request.user, f'Pharmacy settlement {new_status}', 'edit', 'pharmacy_settlement',
                        settlement.id, old={'status': old_status}, new={'status': new_status}, request=request)
    if new_status == 'paid':
        notify(settlement.pharmacy_user, 'Settlement paid',
               f'Your settlement of BDT {_money(settlement.payable_amount)} for '
               f'{settlement.period_start} to {settlement.period_end} has been paid.',
               reference_type='pharmacy_settlement', notification_type='system')
    return Response(_settlement_json(settlement))


def _settlement_json(settlement):
    return {
        'id': str(settlement.id), 'pharmacy_id': str(settlement.pharmacy_user_id),
        'period_start': settlement.period_start.isoformat(), 'period_end': settlement.period_end.isoformat(),
        'gross_sales': _money(settlement.gross_sales), 'commission': _money(settlement.commission),
        'payable_amount': _money(settlement.payable_amount), 'status': settlement.status,
        'paid_at': settlement.paid_at.isoformat() if settlement.paid_at else None,
        'payment_reference': settlement.payment_reference or '',
    }
