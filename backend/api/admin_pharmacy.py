"""Admin Panel — pharmacy oversight: medicine approval, expiry monitoring,
order/delivery monitoring, pharmacy suspension and per-pharmacy analytics.

Prescription medicines need admin approval (industry decision §E.7); OTC items
auto-approve at the pharmacy tier and only surface here for monitoring.
"""

import csv
import io

from django.db import transaction
from django.core.exceptions import ValidationError
from django.db.models import Sum
from django.http import HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework.decorators import api_view, permission_classes, renderer_classes
from rest_framework.renderers import JSONRenderer
from rest_framework.response import Response

from api.admin_extra import CSVRenderer

from audit.models import ActivityLog, AdminPanelRecord
from delivery.models import DeliveryOrder
from notifications.models import Notification
from users.models import User

from api.admin_approvals import enqueue_approval
from api.admin_rbac import IsAdminUser, can_perform_action, requires_approval
from pharmacy.models import (
    PharmacyAppeal, PharmacyCommission, PharmacyEmployee, PharmacyExpiryAlert,
    PharmacyMedicine, PharmacySale, PharmacySettlement,
)
from pharmacy.services import (
    apply_auto_approval, clean_medicine_payload, expiry_alert_json, log_pharmacy_action,
    medicine_json, pharmacy_permission_snapshot, pharmacy_public_profile,
    regenerate_expiry_alerts, transition_pharmacy_status,
)
from pharmacy.catalogue_views import _store_image, order_json


def _deny(user, action):
    if not can_perform_action(user, 'pharmacy', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the pharmacy module.',
             'code': 'forbidden_module_action'}, status=403)
    return None


def _get_pharmacy_user(pharmacy_id):
    return User.objects.filter(pk=pharmacy_id, roles__name='pharmacy').first()


def _status_for_transition_error(exc):
    # Missing/blank input (e.g. no reason given) is a validation error; an
    # otherwise-well-formed request against the wrong current state (already
    # approved, already suspended, ...) is a conflict.
    return 400 if 'required' in str(exc) else 409


def _pharmacy_account_json(user):
    # Real bug fixed here (found via live end-to-end testing, not the test
    # suite): every status-transition endpoint below fetches `user` once via
    # `_get_pharmacy_user()`, then calls `transition_pharmacy_status()`, which
    # mutates and saves its OWN separately-fetched `User` row (it takes a
    # `select_for_update().get(...)` copy internally, not the caller's
    # object). The database write was always correct; the caller's in-memory
    # `user` object never reflected it, so the API response returned to the
    # admin — and therefore whatever the Flutter screen rendered from it —
    # showed the pharmacy as still pending/locked immediately after a
    # successful approve/suspend/reinstate. A follow-up GET would show the
    # correct state, but the immediate action response, the one thing an
    # admin actually watches after clicking a button, lied.
    user.refresh_from_db()
    return {
        'id': str(user.id),
        'pharmacy': pharmacy_public_profile(user, include_private=True),
        **pharmacy_permission_snapshot(user),
    }


def _audit(request, action, action_type, entity_id=None, old=None, new=None, reason=''):
    try:
        import uuid
        target = uuid.UUID(str(entity_id)) if entity_id else None
    except (TypeError, ValueError):
        target = None
    ActivityLog.objects.create(
        user=request.user, module='pharmacy', action=action, action_type=action_type,
        entity_type='pharmacy_medicine', entity_id=target, old_values=old, new_values=new,
        reason=reason or None,
        ip_address=request.META.get('REMOTE_ADDR'),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


# ── Dashboard (spec §4/§11) ──────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_dashboard(request):
    """Assembles every live-data section the Pharmacy Admin dashboard needs
    in one call: account/medicine/sales metrics (delegates to
    admin_pharmacy_metrics.admin_pharmacy_metrics's math), pending-verification
    queue, suspension/appeal queue, recent chat previews, medicine alerts,
    orders needing delivery assignment, and recent audit events."""
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    from api.admin_pharmacy_metrics import _period_range, _money
    from doctor.models import Conversation
    from django.db.models import Q

    start, end = _period_range(request)
    accounts = User.objects.filter(roles__name='pharmacy')
    sales = PharmacySale.objects.filter(status='completed')
    if start:
        sales = sales.filter(completed_at__gte=start)
    sales = sales.filter(completed_at__lte=end)
    commission_totals = PharmacyCommission.objects.filter(sale__in=sales).aggregate(
        commission=Sum('commission_amount'), pharmacy_amount=Sum('pharmacy_amount'))
    gross_total = sales.aggregate(v=Sum('gross_amount'))['v'] or 0

    from pharmacy.services import get_pharmacy_org
    pending_queue = accounts.filter(account_status='pending').select_related('pharmacy_organization')[:20]
    appeal_queue = PharmacyAppeal.objects.filter(
        status__in=PharmacyAppeal.OPEN_STATUSES).select_related('pharmacy_user').order_by('-created_at')[:20]
    recent_chats = Conversation.objects.filter(consultation__isnull=True).filter(
        Q(participant_one__roles__name='pharmacy') | Q(participant_two__roles__name='pharmacy'),
    ).distinct().order_by('-last_message_at')[:10]
    medicines = PharmacyMedicine.objects.filter(is_active=True)
    all_medicines = PharmacyMedicine.objects.all()
    delivery_queue_count = AdminPanelRecord.objects.filter(
        module='delivery-queue', payload__is_pharmacy_delivery=True).count()
    recent_audit = ActivityLog.objects.filter(
        entity_type__in=['pharmacy_account', 'pharmacy_medicine', 'pharmacy_appeal',
                         'pharmacy_conversation', 'pharmacy_sale', 'pharmacy_settlement'],
    ).order_by('-created_at')[:20]

    return Response({
        'summary': {
            'pharmacy_accounts': accounts.count(),
            'pending_verification': accounts.filter(account_status='pending').count(),
            'total_medicines': all_medicines.count(),
            'active_medicines': medicines.count(),
            'archived_medicines': all_medicines.filter(is_active=False).count(),
            'medicine_categories': medicines.values('category').distinct().count(),
            'total_brands': medicines.exclude(manufacturer__isnull=True).exclude(
                manufacturer__exact='').values('manufacturer').distinct().count(),
            'total_employees': PharmacyEmployee.objects.filter(is_active=True).count(),
            'total_sold': sales.count(),
            'gross_sales': _money(gross_total),
            'featherflow_commission': _money(commission_totals['commission']),
            'pharmacy_share': _money(commission_totals['pharmacy_amount']),
        },
        'pending_verification_queue': [{
            'id': str(u.id), 'name': u.full_name or u.email,
            'business_name': getattr(get_pharmacy_org(u), 'business_name', '') or '',
            'submitted_date': u.created_at.isoformat() if getattr(u, 'created_at', None) else None,
        } for u in pending_queue],
        'suspension_appeal_queue': [{
            'id': str(a.id), 'pharmacy_id': str(a.pharmacy_user_id),
            'pharmacy_name': a.pharmacy_user.full_name or a.pharmacy_user.email,
            'status': a.status, 'reason': a.reason, 'created_at': a.created_at.isoformat() if a.created_at else None,
        } for a in appeal_queue],
        'recent_chats': [{
            'id': str(c.id), 'status': c.pharmacy_chat_status or 'open',
            'last_message_at': (c.last_message_at or c.created_at).isoformat()
                                if (c.last_message_at or c.created_at) else None,
        } for c in recent_chats],
        'medicine_alerts': {
            'pending_approval': medicines.filter(prescription_required=True, is_approved=False).count(),
            'low_stock': medicines.filter(stock_quantity__lt=10, stock_quantity__gt=0).count(),
            'out_of_stock': medicines.filter(stock_quantity__lte=0).count(),
        },
        'orders_needing_delivery_assignment': delivery_queue_count,
        'recent_audit_events': [{
            'id': str(log.id), 'module': log.module, 'action': log.action, 'entity_type': log.entity_type,
            'admin': (log.user.full_name or log.user.email) if log.user else 'System',
            'created_at': log.created_at.isoformat() if log.created_at else None,
        } for log in recent_audit],
    })


# ── Medicines ──────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicines(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = PharmacyMedicine.objects.select_related('pharmacy_user').all()
    if request.query_params.get('pharmacy'):
        qs = qs.filter(pharmacy_user_id=request.query_params['pharmacy'])
    if request.query_params.get('category'):
        qs = qs.filter(category=request.query_params['category'])
    presc = request.query_params.get('prescription_required')
    if presc in ('true', 'false'):
        qs = qs.filter(prescription_required=(presc == 'true'))
    approved = request.query_params.get('is_approved')
    if approved in ('true', 'false'):
        qs = qs.filter(is_approved=(approved == 'true'))
    if request.query_params.get('pending') == 'true':
        qs = qs.filter(is_approved=False, prescription_required=True, is_active=True)
    return Response({'results': [medicine_json(m, include_pharmacy=True) for m in qs.order_by('-created_at')]})


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_approve(request, medicine_id):
    denied = _deny(request.user, 'approve')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    old = medicine_json(medicine)
    medicine.is_approved = True
    medicine.approval_rejected_reason = None
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['is_approved', 'approval_rejected_reason', 'updated_at'])
    _audit(request, f'Approved medicine "{medicine.name}"', 'approve', medicine.id,
           old=old, new=medicine_json(medicine))
    Notification.objects.create(
        user_id=medicine.pharmacy_user_id, title='Medicine approved',
        body=f'"{medicine.name}" was approved and is now visible to farmers.',
        notification_type='approval', reference_type='pharmacy_medicine',
        reference_id=medicine.id)
    return Response(medicine_json(medicine, include_pharmacy=True))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_reject(request, medicine_id):
    denied = _deny(request.user, 'reject')
    if denied:
        return denied
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A rejection reason is required.'}, status=400)
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    old = medicine_json(medicine)
    medicine.is_approved = False
    medicine.approval_rejected_reason = reason
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['is_approved', 'approval_rejected_reason', 'updated_at'])
    _audit(request, f'Rejected medicine "{medicine.name}"', 'reject', medicine.id,
           old=old, new=medicine_json(medicine), reason=reason)
    Notification.objects.create(
        user_id=medicine.pharmacy_user_id, title='Medicine rejected',
        body=f'"{medicine.name}" was rejected: {reason}',
        notification_type='approval', reference_type='pharmacy_medicine',
        reference_id=medicine.id)
    return Response(medicine_json(medicine, include_pharmacy=True))


# ── Medicine CRUD (admin authority) ─────────────────────────────────────────
# Mirrors pharmacy/catalogue_views.py's request/response shape exactly (same
# clean_medicine_payload validation, same apply_auto_approval rule) but acts
# on behalf of a pharmacy the admin chooses, and logs through
# log_pharmacy_action instead of the pharmacy-facing log_action. No hard
# delete is exposed anywhere — archive/restore only, matching the existing
# pharmacy-side convention, since order history is snapshot-based and never
# depends on a medicine row surviving.

@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_create(request):
    denied = _deny(request.user, 'create')
    if denied:
        return denied
    pharmacy_id = request.data.get('pharmacy_id') or request.data.get('pharmacy')
    pharmacy_user = _get_pharmacy_user(pharmacy_id) if pharmacy_id else None
    if pharmacy_user is None:
        return Response({'detail': 'A valid pharmacy_id is required.'}, status=400)
    cleaned, error = clean_medicine_payload(request.data, partial=False)
    if error:
        return Response({'detail': error}, status=400)
    now = timezone.now()
    medicine = PharmacyMedicine(pharmacy_user=pharmacy_user, created_at=now, updated_at=now, **cleaned)
    apply_auto_approval(medicine)
    medicine.save()
    regenerate_expiry_alerts(pharmacy_user)
    log_pharmacy_action(request.user, f'Admin added medicine "{medicine.name}"', 'create',
                        'pharmacy_medicine', medicine.id, new=medicine_json(medicine), request=request)
    return Response(medicine_json(medicine, include_pharmacy=True), status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_update(request, medicine_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    old = medicine_json(medicine)
    cleaned, error = clean_medicine_payload(request.data, partial=True)
    if error:
        return Response({'detail': error}, status=400)
    prescription_changed = 'prescription_required' in cleaned and \
        cleaned['prescription_required'] != medicine.prescription_required
    for field, value in cleaned.items():
        setattr(medicine, field, value)
    if prescription_changed:
        apply_auto_approval(medicine)
    medicine.updated_at = timezone.now()
    medicine.save()
    regenerate_expiry_alerts(medicine.pharmacy_user)
    result = medicine_json(medicine, include_pharmacy=True)
    log_pharmacy_action(request.user, f'Admin updated medicine "{medicine.name}"', 'edit',
                        'pharmacy_medicine', medicine.id, old=old, new=result, request=request)
    return Response(result)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_archive(request, medicine_id):
    denied = _deny(request.user, 'delete')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    reason = str(request.data.get('reason', '')).strip()
    medicine.is_active = False
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['is_active', 'updated_at'])
    PharmacyExpiryAlert.objects.filter(medicine=medicine).delete()
    log_pharmacy_action(request.user, f'Admin archived medicine "{medicine.name}"', 'delete',
                        'pharmacy_medicine', medicine.id, reason=reason, request=request)
    return Response(medicine_json(medicine, include_pharmacy=True))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_restore(request, medicine_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    medicine.is_active = True
    apply_auto_approval(medicine)  # a restored OTC medicine auto-approves; Rx still needs review
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['is_active', 'is_approved', 'approval_rejected_reason', 'updated_at'])
    regenerate_expiry_alerts(medicine.pharmacy_user)
    log_pharmacy_action(request.user, f'Admin restored medicine "{medicine.name}"', 'edit',
                        'pharmacy_medicine', medicine.id, request=request)
    return Response(medicine_json(medicine, include_pharmacy=True))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_upload_image(request, medicine_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    url, error = _store_image(request, f'pharmacy_medicines/{medicine.pharmacy_user_id}/{medicine.id}')
    if error:
        return Response({'detail': error}, status=400)
    images = list(medicine.images or [])
    if len(images) >= 5:
        return Response({'detail': 'A medicine can have at most 5 images.'}, status=400)
    images.append(url)
    medicine.images = images
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['images', 'updated_at'])
    log_pharmacy_action(request.user, f'Admin uploaded image for "{medicine.name}"', 'edit',
                        'pharmacy_medicine', medicine.id, request=request)
    return Response({'image_url': url, 'images': images}, status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_stock(request, medicine_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    if 'stock_quantity' in request.data:
        try:
            new_stock = int(request.data['stock_quantity'])
        except (TypeError, ValueError):
            return Response({'detail': 'stock_quantity must be a whole number.'}, status=400)
    elif 'delta' in request.data:
        try:
            new_stock = medicine.stock_quantity + int(request.data['delta'])
        except (TypeError, ValueError):
            return Response({'detail': 'delta must be a whole number.'}, status=400)
    else:
        return Response({'detail': 'Provide stock_quantity or delta.'}, status=400)
    if new_stock < 0:
        return Response({'detail': 'Stock quantity cannot be negative.'}, status=400)
    medicine.stock_quantity = new_stock
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['stock_quantity', 'updated_at'])
    log_pharmacy_action(request.user, 'Admin updated stock', 'edit', 'pharmacy_medicine',
                        medicine.id, new={'stock_quantity': new_stock}, request=request)
    return Response(medicine_json(medicine, include_pharmacy=True))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_medicine_price(request, medicine_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    medicine = PharmacyMedicine.objects.filter(pk=medicine_id).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    try:
        price = round(float(request.data.get('price')), 2)
    except (TypeError, ValueError):
        return Response({'detail': 'price must be a number.'}, status=400)
    if price <= 0:
        return Response({'detail': 'Price must be greater than 0.'}, status=400)
    medicine.price = price
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['price', 'updated_at'])
    log_pharmacy_action(request.user, 'Admin updated price', 'edit', 'pharmacy_medicine',
                        medicine.id, new={'price': price}, request=request)
    return Response(medicine_json(medicine, include_pharmacy=True))


# ── Expiry monitoring ──────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_expiry_alerts(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    regenerate_expiry_alerts()
    qs = PharmacyExpiryAlert.objects.select_related('medicine', 'pharmacy_user').all()
    if request.query_params.get('alert_level'):
        qs = qs.filter(alert_level=request.query_params['alert_level'])
    if request.query_params.get('pharmacy'):
        qs = qs.filter(pharmacy_user_id=request.query_params['pharmacy'])
    grouped = {}
    for alert in qs.order_by('expires_in_days'):
        row = expiry_alert_json(alert)
        row['pharmacy_name'] = pharmacy_public_profile(alert.pharmacy_user)['name']
        grouped.setdefault(row['pharmacy_name'], []).append(row)
    return Response({
        'results': [r for rows in grouped.values() for r in rows],
        'by_pharmacy': [{'pharmacy': k, 'alerts': v} for k, v in grouped.items()],
    })


# ── Orders / delivery monitoring ───────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_orders(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = AdminPanelRecord.objects.filter(module='pharmacy-orders').order_by('-created_at')
    if request.query_params.get('pharmacy'):
        qs = qs.filter(payload__owner_id=request.query_params['pharmacy'])
    try:
        limit = max(1, min(int(request.query_params.get('limit', 500)), 1000))
        offset = max(0, int(request.query_params.get('offset', 0)))
    except ValueError:
        limit, offset = 500, 0
    from pharmacy.catalogue_views import bulk_rider_map
    total = qs.count()
    records = list(qs[offset:offset + limit])
    riders = bulk_rider_map(records)
    rows = [order_json(r, detail=False, riders=riders) for r in records]
    status_filter = request.query_params.get('status')
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(',')}
        rows = [r for r in rows if r['status'] in wanted or r['bridge_status'] in wanted]
    if request.query_params.get('view') == 'delivery':
        rows = [r for r in rows if r.get('delivery')]
    return Response({'results': rows, 'total': total, 'limit': limit, 'offset': offset})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_order_refund(request, order_id):
    """Reverses a delivered pharmacy order. No refund path existed at all
    before this build — a delivered order could only ever stay delivered.
    Excludes the sale from every completed-sales aggregate going forward
    without mutating the original PharmacyCommission row (see
    pharmacy.services.reverse_pharmacy_sale)."""
    denied = _deny(request.user, 'refund')
    if denied:
        return denied
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A refund reason is required.'}, status=400)
    # Orders are keyed by `<pharmacy_user_id>:<order_id>` (record_id), not the
    # row's own primary key — but the admin surface only knows the order's
    # own AdminPanelRecord id (`record_pk` from order_json), so look up by
    # that directly rather than reconstructing the composite key.
    from pharmacy.services import reverse_pharmacy_sale
    with transaction.atomic():
        record = AdminPanelRecord.objects.select_for_update().filter(
            module='pharmacy-orders', pk=order_id).first()
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        if payload.get('status') != 'delivered':
            return Response(
                {'detail': f'Only a delivered order can be refunded (currently {payload.get("status")}).'},
                status=409)
        payload['status'] = 'refunded'
        payload['payment_status'] = 'refunded'
        payload['refund_reason'] = reason
        history = list(payload.get('status_history', []))
        history.append({
            'from': 'delivered', 'to': 'refunded', 'message': reason,
            'changed_at': timezone.now().isoformat(),
            'changed_by': request.user.full_name or request.user.email,
        })
        payload['status_history'] = history
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
        reverse_pharmacy_sale(payload.get('id'))
    log_pharmacy_action(request.user, 'Refund pharmacy order', 'refund', 'pharmacy_sale',
                        entity_id=None, reason=reason, request=request)
    farmer_id = payload.get('farmer_id')
    if farmer_id:
        try:
            Notification.objects.create(
                user_id=farmer_id, title='Order refunded',
                body=f'{payload.get("order_number", "Your order")} was refunded: {reason}',
                notification_type='alert', reference_type='pharmacy_order')
        except (ValueError, TypeError):
            pass
    return Response(order_json(record, detail=True))


# ── Employees (roster only — no login credentials, per confirmed decision) ──

def _employee_json(e):
    return {
        'id': str(e.id), 'pharmacy_id': str(e.pharmacy_user_id), 'name': e.name,
        'role_title': e.role_title or '', 'phone': e.phone or '', 'email': e.email or '',
        'license_number': e.license_number or '', 'access_level': e.access_level,
        'is_active': e.is_active,
        'added_at': e.added_at.isoformat() if e.added_at else None,
        'updated_at': e.updated_at.isoformat() if e.updated_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_employees(request, pharmacy_id):
    denied = _deny(request.user, 'view' if request.method == 'GET' else 'edit')
    if denied:
        return denied
    pharmacy_user = _get_pharmacy_user(pharmacy_id)
    if pharmacy_user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)

    if request.method == 'GET':
        qs = PharmacyEmployee.objects.filter(pharmacy_user=pharmacy_user).order_by('name')
        return Response({'results': [_employee_json(e) for e in qs]})

    name = str(request.data.get('name', '')).strip()
    if not name:
        return Response({'detail': 'Employee name is required.'}, status=400)
    access_level = request.data.get('access_level', 'staff')
    if access_level not in dict(PharmacyEmployee.ACCESS_LEVEL_CHOICES):
        return Response({'detail': 'Invalid access_level.'}, status=400)
    employee = PharmacyEmployee.objects.create(
        pharmacy_user=pharmacy_user, name=name,
        role_title=str(request.data.get('role_title', '')).strip(),
        phone=str(request.data.get('phone', '')).strip(),
        email=str(request.data.get('email', '')).strip(),
        license_number=str(request.data.get('license_number', '')).strip() or None,
        access_level=access_level, is_active=True, added_by=request.user,
        added_at=timezone.now(), updated_at=timezone.now(),
    )
    log_pharmacy_action(request.user, f'Added employee "{employee.name}"', 'create',
                        'pharmacy_employee', employee.id, new=_employee_json(employee), request=request)
    return Response(_employee_json(employee), status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_employee_detail(request, pharmacy_id, employee_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    employee = PharmacyEmployee.objects.filter(pk=employee_id, pharmacy_user_id=pharmacy_id).first()
    if employee is None:
        return Response({'detail': 'Employee not found.'}, status=404)
    old = _employee_json(employee)
    for field in ('name', 'role_title', 'phone', 'email'):
        if field in request.data:
            setattr(employee, field, str(request.data[field]).strip())
    if 'license_number' in request.data:
        employee.license_number = str(request.data['license_number'] or '').strip() or None
    if 'access_level' in request.data:
        access_level = request.data['access_level']
        if access_level not in dict(PharmacyEmployee.ACCESS_LEVEL_CHOICES):
            return Response({'detail': 'Invalid access_level.'}, status=400)
        employee.access_level = access_level
    if 'is_active' in request.data:
        employee.is_active = bool(request.data['is_active'])
    if not employee.name.strip():
        return Response({'detail': 'Employee name cannot be empty.'}, status=400)
    employee.updated_at = timezone.now()
    employee.save()
    result = _employee_json(employee)
    log_pharmacy_action(request.user, f'Updated employee "{employee.name}"', 'edit',
                        'pharmacy_employee', employee.id, old=old, new=result, request=request)
    return Response(result)


# ── Appeals ──────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_appeals(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = PharmacyAppeal.objects.select_related('pharmacy_user').order_by('-created_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)
    return Response({'results': [{
        'id': str(a.id), 'pharmacy_id': str(a.pharmacy_user_id),
        'pharmacy_name': a.pharmacy_user.full_name or a.pharmacy_user.email,
        'reason': a.reason, 'explanation': a.explanation, 'attachments': a.attachments or [],
        'status': a.status, 'admin_response': a.admin_response or '',
        'created_at': a.created_at.isoformat() if a.created_at else None,
    } for a in qs]})


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_appeal_decide(request, appeal_id):
    denied = _deny(request.user, 'approve')
    if denied:
        return denied
    appeal = PharmacyAppeal.objects.select_related('pharmacy_user').filter(pk=appeal_id).first()
    if appeal is None:
        return Response({'detail': 'Appeal not found.'}, status=404)
    if appeal.status not in PharmacyAppeal.OPEN_STATUSES:
        return Response({'detail': f'This appeal was already {appeal.status}.'}, status=409)
    action = request.data.get('action')
    admin_response = str(request.data.get('admin_response', '')).strip()
    if action not in ('more_info', 'approve', 'deny'):
        return Response({'detail': 'action must be one of more_info/approve/deny.'}, status=400)
    if action in ('more_info', 'deny') and not admin_response:
        return Response({'detail': 'admin_response is required for this action.'}, status=400)

    if action == 'approve':
        try:
            transition_pharmacy_status(request.user, appeal.pharmacy_user, 'reinstate', request=request)
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=409)
        appeal.status = 'approved'
    elif action == 'deny':
        appeal.status = 'denied'
    else:
        appeal.status = 'more_info_required'

    appeal.admin_response = admin_response
    appeal.resolved_by = request.user
    if action in ('approve', 'deny'):
        appeal.resolved_at = timezone.now()
    appeal.updated_at = timezone.now()
    appeal.save(update_fields=['status', 'admin_response', 'resolved_by', 'resolved_at', 'updated_at'])
    log_pharmacy_action(request.user, f'Pharmacy appeal {appeal.status}', 'edit', 'pharmacy_appeal',
                        appeal.id, reason=admin_response, request=request)
    from pharmacy.services import notify as _notify_pharmacy_user
    _notify_pharmacy_user(
        appeal.pharmacy_user, 'Your appeal has been updated',
        f'Your appeal is now {appeal.status.replace("_", " ")}.' + (f' {admin_response}' if admin_response else ''),
        reference_type='pharmacy_appeal', notification_type='approval')
    return Response({'id': str(appeal.id), 'status': appeal.status})


# ── Delivery assignment surfacing ───────────────────────────────────────────
# Reuses the existing delivery-queue/assignment mechanics verbatim
# (api.admin_views._assign_from_queue already correctly checks rider approval
# and capacity, and deletes the queue entry exactly once) — this only adds a
# pharmacy-admin-scoped list/assign surface, not new assignment logic.

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_delivery_queue(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    from delivery.offers import sweep_stale_offers
    sweep_stale_offers()
    qs = AdminPanelRecord.objects.filter(module='delivery-queue').order_by('-created_at')
    rows = []
    for r in qs:
        payload = r.payload or {}
        if not payload.get('is_pharmacy_delivery'):
            continue
        rows.append({'queue_record_id': r.record_id, **payload})
    if request.query_params.get('pharmacy'):
        rows = [row for row in rows if row.get('pharmacy_id') == request.query_params['pharmacy']]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_available_riders(request):
    # Pharmacy Admin has no 'delivery' module permission, so it cannot call
    # the generic /admin-panel/riders/ collection (delivery-module-gated).
    # This thin, pharmacy-scoped wrapper reuses the same rider serializer so
    # the delivery-assignment rider picker works for the real dedicated
    # Pharmacy Admin account, not only for admin_super/admin_operations.
    denied = _deny(request.user, 'assign')
    if denied:
        return denied
    from profiles.models import DeliveryProfile
    from api.admin_views import _rider_json, _bulk_rider_context
    qs = DeliveryProfile.objects.select_related('user').order_by('-created_at')
    rows = list(qs)
    ctx = _bulk_rider_context(rows)
    return Response({'results': [_rider_json(p, ctx=ctx) for p in rows]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_delivery_assign(request, queue_record_id):
    denied = _deny(request.user, 'assign')
    if denied:
        return denied
    rider_id = request.data.get('rider_id')
    if not rider_id:
        return Response({'detail': 'rider_id is required.'}, status=400)
    from profiles.models import DeliveryProfile
    from api.admin_views import _assign_from_queue
    rider = DeliveryProfile.objects.filter(pk=rider_id).first()
    result = _assign_from_queue(request, queue_record_id, rider_id, notes=request.data.get('notes', ''))
    if result.status_code == 201 and rider is not None and not rider.is_online:
        # Confirmed decision: warn, don't hard-block, when the chosen rider is
        # currently offline — the assignment still succeeds.
        data = dict(result.data) if isinstance(result.data, dict) else {}
        data['warning'] = 'The assigned rider is currently marked offline.'
        result.data = data
    return result


# ── Pharmacy suspension & analytics ────────────────────────────────────────

@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_suspend(request, pharmacy_id):
    denied = _deny(request.user, 'suspend')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    action = request.data.get('action', 'suspend')
    if action not in ('suspend', 'reactivate', 'activate'):
        return Response({'detail': 'action must be "suspend" or "reactivate".'}, status=400)
    reason = str(request.data.get('reason', '')).strip()
    reason_code = str(request.data.get('reason_code', '') or '').strip()

    if action == 'suspend':
        if not reason:
            return Response({'detail': 'A suspension reason is required.'}, status=400)
        # Same tier-escalation rule the generic /admin-panel/pharmacies/<id>/
        # path already enforces (api.admin_views._maybe_enqueue) — a
        # module-tier admin_pharmacy user suspending an already-verified
        # pharmacy needs Operations+ sign-off. This endpoint previously
        # executed immediately regardless of tier, which was a real gap.
        needed = requires_approval(request.user, 'pharmacy', 'suspend',
                                   {'target_verified': bool(user.is_verified)})
        if needed is not None:
            entry = enqueue_approval(
                request, action_type='suspend', module='pharmacies', target_id=str(user.id),
                target_type='pharmacy', request_data=dict(request.data), required_tier=needed,
                reason=reason,
            )
            return Response({
                'detail': 'This action needs approval from a higher-tier admin. It has been queued.',
                'code': 'approval_required', 'approval_id': str(entry.id),
                'required_tier': needed, 'status': 'pending',
            }, status=202)

    transition_action = 'suspend' if action == 'suspend' else 'reinstate'
    try:
        transition_pharmacy_status(request.user, user, transition_action, reason=reason, request=request)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=_status_for_transition_error(exc))
    return Response(_pharmacy_account_json(user))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_approve(request, pharmacy_id):
    denied = _deny(request.user, 'approve')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    try:
        transition_pharmacy_status(request.user, user, 'approve', request=request)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=_status_for_transition_error(exc))
    return Response(_pharmacy_account_json(user))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_reject(request, pharmacy_id):
    denied = _deny(request.user, 'reject')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    reason = str(request.data.get('reason', '')).strip()
    try:
        transition_pharmacy_status(request.user, user, 'reject', reason=reason, request=request)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=_status_for_transition_error(exc))
    return Response(_pharmacy_account_json(user))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_request_info(request, pharmacy_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    reason = str(request.data.get('reason', '')).strip()
    try:
        transition_pharmacy_status(request.user, user, 'request_more_info', reason=reason, request=request)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=_status_for_transition_error(exc))
    return Response(_pharmacy_account_json(user))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_reinstate(request, pharmacy_id):
    denied = _deny(request.user, 'suspend')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    try:
        transition_pharmacy_status(request.user, user, 'reinstate', request=request)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=_status_for_transition_error(exc))
    return Response(_pharmacy_account_json(user))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_account_detail(request, pharmacy_id):
    """Full pharmacy-account review payload: profile, workforce counts,
    medicine/order/sales/commission summary, and recent audit history — the
    single-call source for the Pharmacy Admin account review screen."""
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    user = _get_pharmacy_user(pharmacy_id)
    if user is None:
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    from pharmacy.services import get_pharmacy_org

    org = get_pharmacy_org(user)
    medicines = PharmacyMedicine.objects.filter(pharmacy_user=user)
    employees_active = PharmacyEmployee.objects.filter(pharmacy_user=user, is_active=True).count()
    order_count = AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__owner_id=str(user.id)).count()
    sales = PharmacySale.objects.filter(pharmacy_user=user, status='completed')
    commission_totals = PharmacyCommission.objects.filter(sale__in=sales).aggregate(
        commission=Sum('commission_amount'), pharmacy_amount=Sum('pharmacy_amount'))
    recent_logs = ActivityLog.objects.filter(
        entity_type='pharmacy_account', entity_id=user.id).order_by('-created_at')[:20]
    open_appeal = PharmacyAppeal.objects.filter(
        pharmacy_user=user, status__in=PharmacyAppeal.OPEN_STATUSES).order_by('-created_at').first()

    return Response({
        **_pharmacy_account_json(user),
        'profile': {
            'business_name': getattr(org, 'business_name', ''),
            'authorized_contact_person': getattr(org, 'authorized_contact_person', ''),
            'business_registration_number': getattr(org, 'business_registration_number', ''),
            'trade_license_url': getattr(org, 'trade_license_url', ''),
            'tax_vat_tin_number': getattr(org, 'tax_vat_tin_number', ''),
            'business_address': getattr(org, 'business_address', ''),
            'warehouse_address': getattr(org, 'warehouse_address', '') or '',
            'number_of_pharmacists': getattr(org, 'number_of_pharmacists', 0) or 0,
            'responsible_pharmacist_name': getattr(org, 'responsible_pharmacist_name', '') or '',
            'created_at': org.created_at.isoformat() if getattr(org, 'created_at', None) else None,
        },
        'workforce': {
            'account_holders': 1,
            'employees': employees_active,
            'total_workforce': 1 + employees_active,
        },
        'counts': {
            'total_medicines': medicines.count(),
            'active_medicines': medicines.filter(is_active=True).count(),
            'pending_approval': medicines.filter(
                is_approved=False, is_active=True, prescription_required=True).count(),
            'total_orders': order_count,
        },
        'sales_summary': {
            'total_sales': sales.count(),
            'gross_amount': str(sales.aggregate(v=Sum('gross_amount'))['v'] or 0),
            'commission_amount': str(commission_totals['commission'] or 0),
            'pharmacy_amount': str(commission_totals['pharmacy_amount'] or 0),
        },
        'open_appeal': {'id': str(open_appeal.id), 'status': open_appeal.status} if open_appeal else None,
        'recent_audit': [{
            'id': str(log.id), 'action': log.action, 'action_type': log.action_type,
            'reason': log.reason or '', 'admin': (log.user.full_name or log.user.email) if log.user else 'System',
            'created_at': log.created_at.isoformat() if log.created_at else None,
        } for log in recent_logs],
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_analytics(request, pharmacy_id):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    try:
        user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValueError, ValidationError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    medicines = PharmacyMedicine.objects.filter(pharmacy_user=user)
    order_records = AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__owner_id=str(user.id))
    delivered = [r.payload for r in order_records if r.payload.get('status') == 'delivered']
    revenue = sum(float(p.get('total_amount', 0) or 0) for p in delivered)
    active_deliveries = DeliveryOrder.objects.filter(
        is_pharmacy_delivery=True,
        order_reference_id__in=list(order_records.values_list('id', flat=True)),
        status__in=['pending', 'accepted', 'picked_up', 'on_the_way', 'arrived', 'proof_submitted', 'proof_rejected'],
    ).count()
    return Response({
        'pharmacy': pharmacy_public_profile(user, include_private=True),
        'total_medicines': medicines.count(),
        'active_medicines': medicines.filter(is_active=True, is_approved=True).count(),
        'pending_approval': medicines.filter(is_approved=False, is_active=True).count(),
        'total_orders': order_records.count(),
        'delivered_orders': len(delivered),
        'active_deliveries': active_deliveries,
        'total_revenue': round(revenue, 2),
        'expiry_alerts': PharmacyExpiryAlert.objects.filter(pharmacy_user=user).count(),
    })


# ── Reports & Audit export (spec §15) ───────────────────────────────────────
# One dedicated CSV export surface covering every pharmacy-admin report type,
# since the generic `/admin-panel/<module>/export/` dispatcher
# (api/admin_extra.py::admin_module_export -> api/admin_views.py::_collection_rows)
# only recognizes the `pharmacies` module today, not orders/sales/commissions/
# settlements/employees/appeals/chat-activity/admin-actions. This reuses the
# same query filters (date range, pharmacy, status) already proven correct in
# the list endpoints above rather than re-deriving them.

REPORT_TYPES = (
    'accounts', 'approvals', 'suspensions', 'medicines', 'inventory', 'orders',
    'sales', 'commissions', 'settlements', 'employees', 'appeals',
    'delivery-assignments', 'chat-activity', 'admin-actions',
)


def _parse_report_date_range(request):
    start = parse_date(request.query_params.get('date_from', '') or '') if request.query_params.get('date_from') else None
    end = parse_date(request.query_params.get('date_to', '') or '') if request.query_params.get('date_to') else None
    return start, end


def _pharmacy_report_rows(request, report_type):
    pharmacy_filter = request.query_params.get('pharmacy')
    status_filter = request.query_params.get('status')
    start, end = _parse_report_date_range(request)

    if report_type == 'accounts':
        qs = User.objects.filter(roles__name='pharmacy').select_related('pharmacy_organization')
        if pharmacy_filter:
            qs = qs.filter(pk=pharmacy_filter)
        rows = []
        for u in qs:
            snap = pharmacy_permission_snapshot(u)
            if status_filter and snap.get('status') != status_filter:
                continue
            profile = pharmacy_public_profile(u, include_private=True)
            rows.append({
                'id': str(u.id), 'business_name': profile.get('name', ''),
                'account_status': u.account_status, 'lifecycle_status': snap.get('status'),
                'is_verified': u.is_verified, 'created_at': u.created_at.isoformat() if u.created_at else '',
            })
        return rows

    if report_type in ('approvals', 'suspensions'):
        wanted_types = ('approve', 'reject') if report_type == 'approvals' else ('suspend', 'reinstate')
        qs = ActivityLog.objects.filter(entity_type='pharmacy_account', action_type__in=wanted_types)
        if start:
            qs = qs.filter(created_at__date__gte=start)
        if end:
            qs = qs.filter(created_at__date__lte=end)
        return [{
            'id': str(a.id), 'pharmacy_id': str(a.entity_id) if a.entity_id else '',
            'admin': (a.user.full_name or a.user.email) if a.user else 'System',
            'action': a.action, 'action_type': a.action_type, 'reason': a.reason or '',
            'created_at': a.created_at.isoformat() if a.created_at else '',
        } for a in qs.order_by('-created_at')]

    if report_type in ('medicines', 'inventory'):
        qs = PharmacyMedicine.objects.select_related('pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(pharmacy_user_id=pharmacy_filter)
        if status_filter == 'active':
            qs = qs.filter(is_active=True)
        elif status_filter == 'archived':
            qs = qs.filter(is_active=False)
        elif status_filter == 'low_stock':
            qs = qs.filter(stock_quantity__lt=10, stock_quantity__gt=0)
        elif status_filter == 'pending_approval':
            qs = qs.filter(is_approved=False, prescription_required=True)
        return [{
            'id': str(m.id), 'pharmacy': m.pharmacy_user.full_name or m.pharmacy_user.email,
            'name': m.name, 'generic_name': m.generic_name or '', 'category': m.category,
            'price': str(m.price), 'stock_quantity': m.stock_quantity, 'is_active': m.is_active,
            'is_approved': m.is_approved, 'prescription_required': m.prescription_required,
            'expiry_date': m.expiry_date.isoformat() if m.expiry_date else '',
            'updated_at': m.updated_at.isoformat() if m.updated_at else '',
        } for m in qs.order_by('name')]

    if report_type == 'orders':
        qs = AdminPanelRecord.objects.filter(module='pharmacy-orders').order_by('-created_at')
        if pharmacy_filter:
            qs = qs.filter(payload__owner_id=pharmacy_filter)
        rows = []
        for r in qs:
            row = order_json(r, detail=False)
            if status_filter and row.get('status') != status_filter:
                continue
            rows.append({
                'order_id': row.get('order_number') or row.get('order_id', ''),
                'pharmacy_id': pharmacy_filter or '', 'status': row.get('status', ''),
                'total_amount': row.get('total_amount', ''), 'created_at': row.get('created_at', ''),
            })
        return rows

    if report_type == 'sales':
        qs = PharmacySale.objects.select_related('pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(pharmacy_user_id=pharmacy_filter)
        if status_filter:
            qs = qs.filter(status=status_filter)
        if start:
            qs = qs.filter(completed_at__date__gte=start)
        if end:
            qs = qs.filter(completed_at__date__lte=end)
        return [{
            'id': str(s.id), 'order_reference': s.order_reference,
            'pharmacy': s.pharmacy_user.full_name or s.pharmacy_user.email,
            'gross_amount': str(s.gross_amount), 'status': s.status,
            'completed_at': s.completed_at.isoformat() if s.completed_at else '',
        } for s in qs.order_by('-completed_at')]

    if report_type == 'commissions':
        qs = PharmacyCommission.objects.select_related('sale__pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(sale__pharmacy_user_id=pharmacy_filter)
        if start:
            qs = qs.filter(created_at__date__gte=start)
        if end:
            qs = qs.filter(created_at__date__lte=end)
        return [{
            'id': str(c.id), 'pharmacy': c.sale.pharmacy_user.full_name or c.sale.pharmacy_user.email,
            'rate': str(c.rate), 'gross_amount': str(c.gross_amount),
            'commission_amount': str(c.commission_amount), 'pharmacy_amount': str(c.pharmacy_amount),
            'sale_status': c.sale.status, 'created_at': c.created_at.isoformat() if c.created_at else '',
        } for c in qs.order_by('-created_at')]

    if report_type == 'settlements':
        qs = PharmacySettlement.objects.select_related('pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(pharmacy_user_id=pharmacy_filter)
        if status_filter:
            qs = qs.filter(status=status_filter)
        return [{
            'id': str(s.id), 'pharmacy': s.pharmacy_user.full_name or s.pharmacy_user.email,
            'period_start': s.period_start.isoformat(), 'period_end': s.period_end.isoformat(),
            'gross_sales': str(s.gross_sales), 'commission': str(s.commission),
            'payable_amount': str(s.payable_amount), 'status': s.status,
            'payment_reference': s.payment_reference or '',
            'paid_at': s.paid_at.isoformat() if s.paid_at else '',
        } for s in qs.order_by('-period_end')]

    if report_type == 'employees':
        qs = PharmacyEmployee.objects.select_related('pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(pharmacy_user_id=pharmacy_filter)
        if status_filter == 'active':
            qs = qs.filter(is_active=True)
        elif status_filter == 'inactive':
            qs = qs.filter(is_active=False)
        return [{
            'id': str(e.id), 'pharmacy': e.pharmacy_user.full_name or e.pharmacy_user.email,
            'name': e.name, 'role_title': e.role_title, 'access_level': e.access_level,
            'is_active': e.is_active, 'added_at': e.added_at.isoformat() if e.added_at else '',
        } for e in qs.order_by('name')]

    if report_type == 'appeals':
        qs = PharmacyAppeal.objects.select_related('pharmacy_user').all()
        if pharmacy_filter:
            qs = qs.filter(pharmacy_user_id=pharmacy_filter)
        if status_filter:
            qs = qs.filter(status=status_filter)
        return [{
            'id': str(a.id), 'pharmacy': a.pharmacy_user.full_name or a.pharmacy_user.email,
            'reason': a.reason, 'status': a.status, 'admin_response': a.admin_response or '',
            'created_at': a.created_at.isoformat() if a.created_at else '',
            'resolved_at': a.resolved_at.isoformat() if a.resolved_at else '',
        } for a in qs.order_by('-created_at')]

    if report_type == 'delivery-assignments':
        qs = ActivityLog.objects.filter(module='delivery', action_type='assign')
        if start:
            qs = qs.filter(created_at__date__gte=start)
        if end:
            qs = qs.filter(created_at__date__lte=end)
        return [{
            'id': str(a.id), 'admin': (a.user.full_name or a.user.email) if a.user else 'System',
            'action': a.action, 'created_at': a.created_at.isoformat() if a.created_at else '',
        } for a in qs.order_by('-created_at')[:2000]]

    if report_type == 'chat-activity':
        from doctor.models import Conversation
        from django.db.models import Q
        qs = Conversation.objects.filter(consultation__isnull=True).filter(
            Q(participant_one__roles__name='pharmacy') | Q(participant_two__roles__name='pharmacy'),
        ).distinct()
        return [{
            'id': str(c.id), 'status': c.pharmacy_chat_status or 'open',
            'last_message_at': (c.last_message_at or c.created_at).isoformat()
                                if (c.last_message_at or c.created_at) else '',
        } for c in qs.order_by('-last_message_at')]

    if report_type == 'admin-actions':
        qs = ActivityLog.objects.filter(module='pharmacy')
        if start:
            qs = qs.filter(created_at__date__gte=start)
        if end:
            qs = qs.filter(created_at__date__lte=end)
        return [{
            'id': str(a.id), 'admin': (a.user.full_name or a.user.email) if a.user else 'System',
            'role': ', '.join(a.user.roles.values_list('name', flat=True)) if a.user else '',
            'action': a.action, 'action_type': a.action_type, 'entity_type': a.entity_type,
            'reason': a.reason or '', 'created_at': a.created_at.isoformat() if a.created_at else '',
            'ip_address': a.ip_address or '',
        } for a in qs.order_by('-created_at')[:5000]]

    return []


@api_view(['GET'])
@permission_classes([IsAdminUser])
@renderer_classes([JSONRenderer, CSVRenderer])
def admin_pharmacy_export(request, report_type):
    """GET /api/admin-panel/pharmacy/export/<report_type>/ — CSV export for
    every pharmacy report type the spec's Reports & Audit section lists.
    Never exposes unauthorized sensitive data: gated the same way every other
    mutating/viewing pharmacy endpoint is (can_perform_action 'export')."""
    denied = _deny(request.user, 'export')
    if denied:
        return denied
    if report_type not in REPORT_TYPES:
        return Response({'detail': f'Unknown report type "{report_type}".'}, status=404)
    rows = _pharmacy_report_rows(request, report_type)
    fields = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=fields or ['id'], extrasaction='ignore')
    writer.writeheader()
    for row in rows:
        writer.writerow({k: ('' if v is None else v) for k, v in row.items()})
    log_pharmacy_action(request.user, f'Exported pharmacy report "{report_type}" ({len(rows)} rows)',
                        'export', 'pharmacy_report', entity_id=None, request=request)
    response = HttpResponse(buffer.getvalue(), content_type='text/csv')
    stamp = timezone.now().strftime('%Y%m%d-%H%M')
    response['Content-Disposition'] = f'attachment; filename="pharmacy-{report_type}-{stamp}.csv"'
    return response


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_audit(request):
    """GET /api/admin-panel/pharmacy/audit/ — dedicated pharmacy audit log
    view (actor/role/action/entity/before/after/reason/timestamp/IP), filtered
    server-side so this surface never leaks non-pharmacy audit rows."""
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = ActivityLog.objects.filter(
        entity_type__in=['pharmacy_account', 'pharmacy_medicine', 'pharmacy_appeal',
                         'pharmacy_conversation', 'pharmacy_sale', 'pharmacy_settlement',
                         'pharmacy_employee', 'pharmacy_report'],
    ).select_related('user').order_by('-created_at')
    start, end = _parse_report_date_range(request)
    if start:
        qs = qs.filter(created_at__date__gte=start)
    if end:
        qs = qs.filter(created_at__date__lte=end)
    action_type = request.query_params.get('action_type')
    if action_type:
        qs = qs.filter(action_type=action_type)
    search = request.query_params.get('search')
    if search:
        qs = qs.filter(action__icontains=search)
    return Response({'results': [{
        'id': str(a.id), 'actor': (a.user.full_name or a.user.email) if a.user else 'System',
        'role': ', '.join(a.user.roles.values_list('name', flat=True)) if a.user else '',
        'action': a.action, 'action_type': a.action_type, 'entity_type': a.entity_type,
        'entity_id': str(a.entity_id) if a.entity_id else '',
        'old_values': a.old_values, 'new_values': a.new_values,
        'reason': a.reason or '', 'ip_address': a.ip_address or '',
        'created_at': a.created_at.isoformat() if a.created_at else '',
    } for a in qs[:500]]})
