"""Delivery arrival + proof-review lifecycle (fault F-005).

    accepted -> picked_up -> on_the_way ("out for delivery") -> arrived
        -> proof_submitted ("proof under review") -> delivered   (admin approves)
    proof_submitted -> proof_rejected (reason) -> proof_submitted -> ... -> delivered

The rider can never complete an order: `delivered` is reached only through
`approve_proof`, which is also the single place the financial records
(rider earning, farmer expense mirror) are created — exactly once, guarded by
the order's row lock, the status guard and the unique constraints those
records already carry.
"""
from django.db import transaction
from django.utils import timezone

from audit.models import ActivityLog
from notifications.models import Notification
from users.models import User

from .models import DeliveryEarning, DeliveryOrder, DeliveryOrderEvent, DeliveryProof

# Rider-driven transitions through PATCH /orders/<id>/status/.
RIDER_TRANSITIONS = {
    'accepted': {'picked_up', 'failed'},
    'picked_up': {'on_the_way', 'failed'},
    'on_the_way': {'arrived', 'failed'},
    'arrived': {'failed'},               # proof is submitted through the proof endpoint
    'proof_rejected': {'failed'},        # ...or resubmitted through it
}
# Statuses from which the rider may submit (or resubmit) a proof photo.
PROOF_SUBMIT_FROM = ('arrived', 'proof_rejected')

STAGE_LABELS = {
    'pending': 'Assigned — awaiting rider response',
    'accepted': 'Assigned', 'picked_up': 'Picked up', 'on_the_way': 'Out for delivery',
    'arrived': 'Arrived', 'proof_submitted': 'Proof under review',
    'proof_rejected': 'Proof rejected — resubmission required',
    'delivered': 'Completed', 'failed': 'Failed', 'cancelled': 'Cancelled', 'rejected': 'Rejected',
}


class LifecycleError(Exception):
    def __init__(self, detail, status=409):
        super().__init__(detail)
        self.detail = detail
        self.status = status


def record_event(order, from_status, to_status, actor=None, note=''):
    role = None
    if actor is not None:
        role = (actor.roles.values_list('name', flat=True).first() or '')[:20] or None
    return DeliveryOrderEvent.objects.create(
        delivery_order=order, from_status=from_status, to_status=to_status,
        actor=actor, actor_role=role, note=note or None, created_at=timezone.now())


def audit(actor, action, proof_or_order, old=None, new=None, reason='', request=None, module='delivery-proofs'):
    ip = None
    ua = None
    if request is not None:
        fwd = request.META.get('HTTP_X_FORWARDED_FOR', '')
        ip = (fwd.split(',')[0].strip() if fwd else request.META.get('REMOTE_ADDR')) or None
        ua = (request.META.get('HTTP_USER_AGENT') or '')[:1000] or None
    ActivityLog.objects.create(
        user=actor, module=module, action=action,
        action_type='approve' if 'pprove' in action else ('reject' if 'eject' in action else 'edit'),
        entity_type=module, entity_id=proof_or_order.id, old_values=old, new_values=new,
        reason=reason or None, ip_address=ip, user_agent=ua)


def _notify(user, title, body, order, kind='system'):
    if user is None:
        return
    Notification.objects.create(
        user=user, title=title, body=body, notification_type=kind,
        reference_id=order.id, reference_type='delivery_order')


def admins_for(order):
    """Admin accounts that may review this order's proof."""
    roles = ['admin_super', 'admin_operations', 'admin_delivery']
    roles.append('feed_admin' if order.order_type == 'marketplace' else 'admin_pharmacy')
    return User.objects.filter(roles__name__in=roles).distinct()


def proof_json(p, include_url=True):
    return {
        'id': str(p.id), 'attempt': p.attempt, 'status': p.status,
        'url': p.proof_url if include_url else None, 'note': p.note or '',
        'review_reason': p.review_reason or '',
        'submitted_at': p.submitted_at.isoformat() if p.submitted_at else None,
        'reviewed_at': p.reviewed_at.isoformat() if p.reviewed_at else None,
        'reviewed_by': (p.reviewed_by.full_name or p.reviewed_by.email) if p.reviewed_by_id else None,
    }


def event_json(e):
    return {
        'from': e.from_status, 'to': e.to_status, 'label': STAGE_LABELS.get(e.to_status, e.to_status),
        'actor': (e.actor.full_name or e.actor.email) if e.actor_id else None,
        'actor_role': e.actor_role, 'note': e.note or '',
        'at': e.created_at.isoformat() if e.created_at else None,
    }


def submit_proof(order_id, rider_user, rider_profile, *, proof_url, otp_code='', note='', sync, request=None):
    """Rider submits (or resubmits) a proof photo. Never completes the order."""
    with transaction.atomic():
        try:
            order = DeliveryOrder.objects.select_for_update().get(id=order_id, delivery_person=rider_profile)
        except DeliveryOrder.DoesNotExist:
            raise LifecycleError('Delivery order not found.', 404)
        if order.status not in PROOF_SUBMIT_FROM:
            if order.status == 'proof_submitted':
                raise LifecycleError('A proof for this delivery is already awaiting admin review.', 409)
            if order.status == 'delivered':
                raise LifecycleError('This delivery is already completed.', 409)
            raise LifecycleError(
                f'Mark the order as arrived before submitting proof (currently {order.status}).', 409)
        if order.is_pharmacy_delivery:
            # Pharmacy deliveries keep their handover OTP; it is checked at submission.
            if not order.otp_code or str(otp_code).strip() != order.otp_code:
                raise LifecycleError('Incorrect or missing delivery OTP.', 400)
        attempt = (order.proofs.count() or 0) + 1
        previous = order.status
        proof = DeliveryProof.objects.create(
            delivery_order=order, submitted_by=rider_user, attempt=attempt, proof_url=proof_url,
            note=(note or '').strip() or None, status='submitted', submitted_at=timezone.now())
        order.status = 'proof_submitted'
        order.proof_of_delivery_url = proof_url
        order.save(update_fields=['status', 'proof_of_delivery_url'])
        record_event(order, previous, 'proof_submitted', rider_user,
                     f'Proof attempt {attempt} submitted' + (' (resubmission)' if attempt > 1 else ''))
        audit(rider_user, 'Proof submitted', proof, old={'status': previous},
              new={'status': 'proof_submitted', 'attempt': attempt, 'proof_url': proof_url}, request=request)
        for admin in admins_for(order):
            _notify(admin, 'Delivery proof awaiting review',
                    f'Order {str(order.order_reference_id)[:8]}: proof attempt {attempt} was submitted by '
                    f'{rider_user.full_name or rider_user.email}.', order, 'alert')
        sync(order, rider_user, 'proof_submitted')
    return order, proof


def reject_proof(proof_id, admin_user, reason, *, sync, request=None):
    reason = (reason or '').strip()
    if len(reason) < 3:
        raise LifecycleError('A rejection reason is required.', 400)
    with transaction.atomic():
        try:
            proof = DeliveryProof.objects.select_for_update().select_related(
                'delivery_order__delivery_person__user').get(pk=proof_id)
        except (DeliveryProof.DoesNotExist, ValueError):
            raise LifecycleError('Proof not found.', 404)
        order = DeliveryOrder.objects.select_for_update().get(pk=proof.delivery_order_id)
        if proof.status != 'submitted' or order.status != 'proof_submitted':
            raise LifecycleError(f'This proof was already reviewed ({proof.status}).', 409)
        proof.status = 'rejected'
        proof.review_reason = reason
        proof.reviewed_by = admin_user
        proof.reviewed_at = timezone.now()
        proof.save(update_fields=['status', 'review_reason', 'reviewed_by', 'reviewed_at'])
        order.status = 'proof_rejected'
        order.save(update_fields=['status'])
        record_event(order, 'proof_submitted', 'proof_rejected', admin_user,
                     f'Proof attempt {proof.attempt} rejected: {reason}')
        audit(admin_user, 'Proof rejected', proof, old={'status': 'submitted'},
              new={'status': 'rejected', 'attempt': proof.attempt}, reason=reason, request=request)
        _notify(order.delivery_person.user, 'Delivery proof rejected',
                f'Order {str(order.order_reference_id)[:8]}: {reason} Please upload a new proof photo.',
                order, 'alert')
        sync(order, admin_user, 'proof_rejected')
    return order, proof


def approve_proof(proof_id, admin_user, *, sync, create_earning, request=None):
    """Approval is THE completion event: order -> delivered, earning + expense
    mirror created once, farmer/rider notified."""
    with transaction.atomic():
        try:
            proof = DeliveryProof.objects.select_for_update().get(pk=proof_id)
        except (DeliveryProof.DoesNotExist, ValueError):
            raise LifecycleError('Proof not found.', 404)
        order = DeliveryOrder.objects.select_for_update().select_related(
            'delivery_person__user').get(pk=proof.delivery_order_id)
        if proof.status != 'submitted' or order.status != 'proof_submitted':
            raise LifecycleError(
                f'This proof was already reviewed ({proof.status}); the order is {order.status}.', 409)
        now = timezone.now()
        proof.status = 'approved'
        proof.reviewed_by = admin_user
        proof.reviewed_at = now
        proof.save(update_fields=['status', 'reviewed_by', 'reviewed_at'])
        order.status = 'delivered'
        order.delivered_at = now
        order.proof_of_delivery_url = proof.proof_url
        order.save(update_fields=['status', 'delivered_at', 'proof_of_delivery_url'])
        record_event(order, 'proof_submitted', 'delivered', admin_user,
                     f'Proof attempt {proof.attempt} approved — delivery completed')
        audit(admin_user, 'Proof approved', proof, old={'status': 'submitted'},
              new={'status': 'approved', 'attempt': proof.attempt, 'order_status': 'delivered'}, request=request)
        rider = order.delivery_person
        earned = create_earning(order)  # idempotent (one earning per delivery_order)
        rider.total_deliveries = (rider.total_deliveries or 0) + 1
        rider.save(update_fields=['total_deliveries', 'updated_at'])
        _notify(rider.user, 'Delivery completed',
                f'Your proof was approved. You earned ৳{earned} for this delivery.', order)
        sync(order, admin_user, 'delivered')
    return order, proof
