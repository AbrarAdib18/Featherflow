"""Delivery offer lifecycle: a rider's pending offer can be rejected or expire.

NF-7: before this module an unanswered offer stayed `pending` forever unless the
rider happened to open the app, and a feed order kept the stale label
"assigned". Now an offer that is rejected or past OFFER_WINDOW is *released*:
  * the delivery order becomes `rejected` with a reason,
  * the source feed order returns to its pre-assignment status
    (`delivery_status` = offer_expired | offer_rejected) so the Feed Admin sees
    a normal, actionable order with an "Assign rider" button,
  * delivery admins are notified.
`sweep_stale_offers()` runs lazily whenever an admin lists orders and from the
`expire_stale_offers` management command, so expiry no longer depends on the rider.
"""
import os
from datetime import timedelta, timezone as dt_timezone

from django.db import transaction
from django.utils import timezone

from audit.models import AdminPanelRecord
from notifications.models import Notification
from users.models import User

from .models import DeliveryOrder

# How long a rider has to answer an offer. Overridable for tests / staging (seconds).
OFFER_WINDOW = timedelta(seconds=int(os.environ.get('DELIVERY_OFFER_WINDOW_SECONDS', '180')))

REASONS = {
    'offer_expired': ('Offer expired', 'did not respond in time'),
    'offer_rejected': ('Rejected by rider', 'rejected the offer'),
}


def _aware(dt):
    # `timestamp without time zone` columns hold UTC wall-clock (see delivery.views._aware).
    return dt.replace(tzinfo=dt_timezone.utc) if timezone.is_naive(dt) else dt


def _restore_source(order, code):
    if order.order_type != 'marketplace':
        return
    rec = AdminPanelRecord.objects.select_for_update().filter(
        module='feed-orders', id=order.order_reference_id).first()
    if rec is None:
        return
    payload = dict(rec.payload or {})
    if payload.get('status') != 'assigned' or payload.get('delivery_order_id') != str(order.id):
        return
    payload['status'] = payload.pop('status_before_assignment', None) or 'confirmed'
    payload['last_delivery_order_id'] = str(order.id)
    payload['delivery_order_id'] = None
    payload['assigned_rider_id'] = None
    payload['delivery_status'] = code
    history = list(payload.get('status_history', []))
    history.append({'from': 'assigned', 'to': payload['status'],
                    'message': REASONS[code][0] + ' - ready to be assigned again.',
                    'changed_at': timezone.now().isoformat()})
    payload['status_history'] = history
    rec.payload = payload
    rec.save(update_fields=['payload', 'updated_at'])


def release_offer(order_id, code='offer_expired'):
    """Release a *pending* offer. Returns True if it was released."""
    reason, verb = REASONS[code]
    with transaction.atomic():
        order = DeliveryOrder.objects.select_for_update().select_related('delivery_person__user').get(pk=order_id)
        if order.status != 'pending':
            return False
        order.status = 'rejected'
        order.failure_reason = reason
        order.save(update_fields=['status', 'failure_reason'])
        _restore_source(order, code)
        label = str(order.order_reference_id)[:8]
        rider = order.delivery_person.user
        for admin in User.objects.filter(
                roles__name__in=['admin_super', 'admin_operations', 'admin_delivery', 'feed_admin']).distinct():
            Notification.objects.create(
                user=admin, title='Delivery offer ' + ('expired' if code == 'offer_expired' else 'rejected'),
                body=f'{rider.full_name or rider.email} {verb} for order {label}. It needs reassignment.',
                notification_type='alert', reference_id=order.id, reference_type='delivery_order')
    return True


def sweep_stale_offers():
    """Release every pending offer older than OFFER_WINDOW. Returns the count."""
    cutoff = timezone.now() - OFFER_WINDOW
    ids = [o.id for o in DeliveryOrder.objects.filter(status='pending', assigned_at__isnull=False)
           if _aware(o.assigned_at) < cutoff]
    return sum(1 for i in ids if release_offer(i, 'offer_expired'))
