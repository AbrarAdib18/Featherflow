"""Admin Panel — pharmacy oversight: medicine approval, expiry monitoring,
order/delivery monitoring, pharmacy suspension and per-pharmacy analytics.

Prescription medicines need admin approval (industry decision §E.7); OTC items
auto-approve at the pharmacy tier and only surface here for monitoring.
"""

from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog, AdminPanelRecord
from delivery.models import DeliveryOrder
from notifications.models import Notification
from users.models import User

from api.admin_rbac import IsAdminUser, can_perform_action
from pharmacy.models import PharmacyExpiryAlert, PharmacyMedicine
from pharmacy.services import (
    expiry_alert_json, medicine_json, pharmacy_public_profile,
    regenerate_expiry_alerts,
)
from pharmacy.catalogue_views import order_json


def _deny(user, action):
    if not can_perform_action(user, 'pharmacy', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the pharmacy module.',
             'code': 'forbidden_module_action'}, status=403)
    return None


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
    rows = [order_json(r, detail=False) for r in qs]
    status_filter = request.query_params.get('status')
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(',')}
        rows = [r for r in rows if r['status'] in wanted or r['bridge_status'] in wanted]
    if request.query_params.get('view') == 'delivery':
        rows = [r for r in rows if r.get('delivery')]
    return Response({'results': rows})


# ── Pharmacy suspension & analytics ────────────────────────────────────────

@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_suspend(request, pharmacy_id):
    denied = _deny(request.user, 'suspend')
    if denied:
        return denied
    try:
        user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValueError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    action = request.data.get('action', 'suspend')
    if action == 'suspend':
        user.account_status = 'suspended'
        user.is_verified = False
        PharmacyMedicine.objects.filter(pharmacy_user=user).update(is_active=False, updated_at=timezone.now())
        body = 'Your pharmacy account has been suspended by an administrator.'
    elif action in ('reactivate', 'activate'):
        user.account_status = 'active'
        user.is_verified = True
        body = 'Your pharmacy account has been reactivated.'
    else:
        return Response({'detail': 'action must be "suspend" or "reactivate".'}, status=400)
    user.save(update_fields=['account_status', 'is_verified', 'updated_at'])
    _audit(request, f'Pharmacy {action}', 'suspend' if action == 'suspend' else 'edit',
           pharmacy_id, reason=str(request.data.get('reason', '')))
    Notification.objects.create(user=user, title=f'Pharmacy {action}d', body=body,
                                notification_type='alert', reference_type='admin_pharmacy')
    return Response({'id': str(user.id), 'account_status': user.account_status,
                    'is_verified': user.is_verified})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_analytics(request, pharmacy_id):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    try:
        user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValueError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    medicines = PharmacyMedicine.objects.filter(pharmacy_user=user)
    order_records = AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__owner_id=str(user.id))
    delivered = [r.payload for r in order_records if r.payload.get('status') == 'delivered']
    revenue = sum(float(p.get('total_amount', 0) or 0) for p in delivered)
    active_deliveries = DeliveryOrder.objects.filter(
        is_pharmacy_delivery=True,
        order_reference_id__in=list(order_records.values_list('id', flat=True)),
        status__in=['pending', 'accepted', 'picked_up', 'on_the_way'],
    ).count()
    return Response({
        'pharmacy': pharmacy_public_profile(user),
        'total_medicines': medicines.count(),
        'active_medicines': medicines.filter(is_active=True, is_approved=True).count(),
        'pending_approval': medicines.filter(is_approved=False, is_active=True).count(),
        'total_orders': order_records.count(),
        'delivered_orders': len(delivered),
        'active_deliveries': active_deliveries,
        'total_revenue': round(revenue, 2),
        'expiry_alerts': PharmacyExpiryAlert.objects.filter(pharmacy_user=user).count(),
    })
