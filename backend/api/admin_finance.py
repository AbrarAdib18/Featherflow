"""Finance module — real data instead of the JSON seed rows.

Transactions are the union of:
  * ``payments``          — one row per payment (subscription, order, cashout, refund)
  * ``subscriptions``     — surfaced as "Subscription" transactions with the plan price
  * ``delivery_earnings`` — surfaced as rider "Payout" transactions

``finance_summary`` reports MRR, lifetime revenue, pending payout liability and
refunds. ``finance_action`` processes a refund (routed through the approval queue
above the threshold, per ``admin_rbac.requires_approval``).
"""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from delivery.models import DeliveryEarning
from notifications.models import Notification
from subscriptions.models import Subscription, SubscriptionPlan
from users.models import User

from api.admin_rbac import IsAdminUser, can_perform_action
from api.finance_models import CashoutReview, RevenueEntry

try:  # payments app model
    from payments.models import Payment
except Exception:  # pragma: no cover
    Payment = None


def _row(id_, user, type_, plan, status, amount, when, *, source):
    return {
        'id': str(id_),
        'user': user,
        'type': type_,
        'plan': plan,
        'method': plan,
        'status': status,
        'amount': float(amount or 0),
        'date': when.strftime('%b %d, %Y') if when else '',
        'source': source,
    }


def finance_rows(request):
    rows = []

    if Payment is not None:
        for p in Payment.objects.select_related('user').order_by('-created_at')[:400]:
            rows.append(_row(
                p.id,
                (p.user.full_name or p.user.email) if p.user_id else 'Unknown',
                (p.payment_type or 'payment').replace('_', ' ').title(),
                p.payment_method or '',
                p.status.title(),
                p.amount, p.created_at, source='payment',
            ))

    subs = Subscription.objects.select_related('user', 'plan').order_by('-created_at')[:200]
    for s in subs:
        rows.append(_row(
            f'sub:{s.id}',
            (s.user.full_name or s.user.email) if s.user_id else 'Unknown',
            'Subscription',
            s.plan.name if s.plan_id else '',
            {'active': 'Paid', 'pending': 'Pending', 'cancelled': 'Cancelled',
             'expired': 'Expired'}.get(s.status, s.status.title()),
            s.plan.price if s.plan_id else 0,
            s.started_at or s.created_at, source='subscription',
        ))

    earnings = (DeliveryEarning.objects.select_related('delivery_person__user')
                .order_by('-created_at')[:200])
    for e in earnings:
        rows.append(_row(
            f'payout:{e.id}',
            e.delivery_person.user.full_name or e.delivery_person.user.email,
            'Payout',
            'Delivery earnings',
            'Paid' if e.payout_status == 'paid' else 'Pending',
            e.total_earned, e.payout_date or e.created_at, source='payout',
        ))

    rows.sort(key=lambda r: r['date'], reverse=True)
    return rows


def finance_summary(request):
    now = timezone.now()
    active_subs = Subscription.objects.filter(status='active').select_related('plan')
    mrr = sum(
        (s.plan.price / (Decimal(s.plan.duration_days) / 30) if s.plan and s.plan.duration_days else Decimal(0))
        for s in active_subs
    )
    lifetime = Decimal(0)
    if Payment is not None:
        lifetime = Payment.objects.filter(status__in=['completed', 'paid']).aggregate(
            v=Sum('amount'))['v'] or Decimal(0)
    lifetime += (Subscription.objects.filter(status='active').select_related('plan')
                 .aggregate(v=Sum('plan__price'))['v'] or Decimal(0))
    pending_payouts = DeliveryEarning.objects.filter(payout_status='pending').aggregate(
        v=Sum('total_earned'))['v'] or Decimal(0)
    paid_payouts = DeliveryEarning.objects.filter(
        payout_status='paid', payout_date__month=now.month, payout_date__year=now.year,
    ).aggregate(v=Sum('total_earned'))['v'] or Decimal(0)
    refunds = Decimal(0)
    if Payment is not None:
        refunds = Payment.objects.filter(status='refunded').aggregate(
            v=Sum('amount'))['v'] or Decimal(0)
    return Response({
        'mrr': float(mrr),
        'lifetime_revenue': float(lifetime),
        'active_subscriptions': active_subs.count(),
        'pending_payout_liability': float(pending_payouts),
        'payouts_paid_this_month': float(paid_payouts),
        'total_refunds': float(refunds),
        'plans': [
            {'name': p.name, 'price': float(p.price), 'currency': p.currency,
             'active_count': Subscription.objects.filter(plan=p, status='active').count()}
            for p in SubscriptionPlan.objects.filter(is_active=True)
        ],
    })


def finance_action(request, record_id):
    """Refund / edit a finance transaction. Called from admin_record for the
    ``payments`` module; the RBAC gate + approval routing already ran upstream."""
    reason = str(request.data.get('reason', '')) or 'Refund issued by admin.'

    if record_id.startswith('payout:'):
        earning = DeliveryEarning.objects.filter(pk=record_id.split(':', 1)[1]).first()
        if not earning:
            return Response({'detail': 'Payout not found.'}, status=404)
        if request.data.get('status') == 'Refunded' or request.data.get('action') == 'refund':
            return Response({'detail': 'Payouts are reversed from the Delivery payouts view, not here.'},
                            status=400)
        return Response(_payout_row(earning))

    if record_id.startswith('sub:'):
        sub = Subscription.objects.select_related('user', 'plan').filter(pk=record_id.split(':', 1)[1]).first()
        if not sub:
            return Response({'detail': 'Subscription not found.'}, status=404)
        wants_refund = request.data.get('status') == 'Refunded' or request.data.get('action') == 'refund'
        if wants_refund:
            sub.status = 'cancelled'
            sub.save(update_fields=['status'])
            if Payment is not None and sub.payment_id:
                sub_payment = Payment.objects.filter(pk=sub.payment_id).first()
                if sub_payment is not None:
                    sub_payment.status = 'refunded'
                    sub_payment.notes = reason
                    sub_payment.save(update_fields=['status', 'notes'])
                    from billing.services import reverse_revenue
                    reverse_revenue(sub_payment, reason=reason)
            from billing.services import mark_intents_refunded
            mark_intents_refunded(subscription_id=sub.id)
            _notify_refund(sub.user, sub.plan.price if sub.plan_id else 0, reason)
            _audit(request, 'Refund subscription', 'refund', sub.id, reason)
        return Response(_sub_row(sub))

    if Payment is None:
        return Response({'detail': 'Payments backend is not available.'}, status=400)
    payment = Payment.objects.select_related('user').filter(pk=record_id).first()
    if not payment:
        return Response({'detail': 'Payment not found.'}, status=404)
    if payment.payment_type == 'cashout':
        return Response(
            {'detail': 'Cashout requests are reviewed from the Pending/Approved Cashout '
                       'Requests pages, not here.', 'code': 'use_cashout_review'}, status=400)
    if request.data.get('status') == 'Refunded' or request.data.get('action') == 'refund':
        if payment.status == 'refunded':
            return Response({'detail': 'This payment was already refunded.'}, status=409)
        payment.status = 'refunded'
        payment.notes = f'{payment.notes or ""}\nRefund: {reason}'.strip()
        payment.save(update_fields=['status', 'notes'])
        from billing.services import mark_intents_refunded, reverse_revenue
        mark_intents_refunded(payment_id=payment.id)
        reverse_revenue(payment, reason=reason)
        if payment.user_id:
            _notify_refund(payment.user, payment.amount, reason)
        _audit(request, 'Refund payment', 'refund', payment.id, reason)
    else:
        for field in ('status',):
            if field in request.data:
                payment.status = str(request.data[field]).lower()
        payment.save()
        _audit(request, 'Edit payment', 'edit', payment.id)
    return Response(_payment_row(payment))


# ── row helpers ─────────────────────────────────────────────────────────────

def _payment_row(p):
    return _row(p.id, (p.user.full_name or p.user.email) if p.user_id else 'Unknown',
               (p.payment_type or 'payment').replace('_', ' ').title(),
               p.payment_method or '', p.status.title(), p.amount, p.created_at, source='payment')


def _sub_row(s):
    return _row(f'sub:{s.id}', (s.user.full_name or s.user.email) if s.user_id else 'Unknown',
               'Subscription', s.plan.name if s.plan_id else '',
               {'active': 'Paid', 'cancelled': 'Cancelled'}.get(s.status, s.status.title()),
               s.plan.price if s.plan_id else 0, s.started_at or s.created_at, source='subscription')


def _payout_row(e):
    return _row(f'payout:{e.id}', e.delivery_person.user.full_name or e.delivery_person.user.email,
               'Payout', 'Delivery earnings',
               'Paid' if e.payout_status == 'paid' else 'Pending',
               e.total_earned, e.payout_date or e.created_at, source='payout')


def _notify_refund(user, amount, reason):
    Notification.objects.create(
        user=user, title='Refund issued',
        body=f'A refund of ৳{amount} was issued to your account. {reason}',
        notification_type='system',
    )


def _audit(request, action, action_type, target_id, reason=''):
    ActivityLog.objects.create(
        user=request.user, module='payments', action=action, action_type=action_type,
        entity_type='finance', entity_id=_uuid(target_id), reason=reason or None,
        ip_address=(request.META.get('HTTP_X_FORWARDED_FOR') or request.META.get('REMOTE_ADDR')),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


def _uuid(v):
    import uuid
    try:
        return uuid.UUID(str(v))
    except (TypeError, ValueError, AttributeError):
        return None


# ── Finance Admin dashboard (FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md) ──

def _month_bounds(dt=None):
    """[1st of this month 00:00, 1st of next month 00:00) in the project's
    configured timezone — same Asia/Dhaka convention as api/admin_shifts.py."""
    local = timezone.localtime(dt or timezone.now())
    start = local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end = (start.replace(year=start.year + 1, month=1) if start.month == 12
           else start.replace(month=start.month + 1))
    return start, end


def _recent_payment_row(p):
    return {
        'id': str(p.id),
        'reference': str(p.id)[:8],
        'user': (p.user.full_name or p.user.email) if p.user_id else 'Unknown',
        'plan': (p.payment_type or 'payment').replace('_', ' ').title(),
        'amount': float(p.amount),
        'currency': p.currency,
        'status': p.status,
        'method': p.payment_method or '',
        'created_at': p.created_at.isoformat() if p.created_at else None,
        'confirmed_at': p.confirmed_at.isoformat() if p.confirmed_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_finance_dashboard(request):
    """Every value here is a live DB aggregate/query — see the module-level
    docstring at the top of FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md for
    the full "widget -> field -> query -> table -> rule" trace of each one.
    """
    if not can_perform_action(request.user, 'finance', 'view'):
        return Response({'detail': 'You cannot view the finance dashboard.'}, status=403)

    now = timezone.now()
    mo0, mo1 = _month_bounds(now)

    monthly_revenue = RevenueEntry.objects.filter(
        recognized_at__gte=mo0, recognized_at__lt=mo1).aggregate(v=Sum('amount'))['v'] or Decimal(0)
    total_revenue = RevenueEntry.objects.aggregate(v=Sum('amount'))['v'] or Decimal(0)

    active_subscriptions = Subscription.objects.filter(status='active').count()
    expiring_soon = Subscription.objects.filter(
        status='active', expires_at__gte=now, expires_at__lt=now + timedelta(days=7)).count()

    # Active Users — non-deleted accounts with account_status='active',
    # excluding suspended/pending/rejected — same definition used on the
    # Operations Admin dashboard (see OPERATIONS_ADMIN_DASHBOARD_AUDIT.md §4).
    # Finance Admin sees only this single aggregate, never the underlying
    # user rows (no `users` permission on this role — see
    # FINANCE_ADMIN_RBAC_CHANGES.md).
    active_users = User.objects.filter(account_status='active').count()

    failed_payments_30d = 0
    recent_payments = []
    if Payment is not None:
        failed_payments_30d = Payment.objects.filter(
            status='failed', created_at__gte=now - timedelta(days=30)).count()
        recent_payments = [
            _recent_payment_row(p) for p in
            Payment.objects.select_related('user').order_by('-created_at')[:10]
        ]

    pending_cashouts = CashoutReview.objects.filter(status__in=CashoutReview.PENDING_STATUSES).count()
    approved_cashouts = CashoutReview.objects.filter(status__in=CashoutReview.APPROVED_STATUSES).count()

    return Response({
        'generated_at': now.isoformat(),
        'monthly_revenue': float(monthly_revenue),
        'total_revenue': float(total_revenue),
        'active_subscriptions': active_subscriptions,
        'expiring_subscriptions_7d': expiring_soon,
        'active_users': active_users,
        'failed_payments_30d': failed_payments_30d,
        'pending_cashout_requests': pending_cashouts,
        'approved_cashout_requests': approved_cashouts,
        'recent_payments': recent_payments,
    })
