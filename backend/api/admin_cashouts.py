"""Finance Admin cashout review workflow.

State machine (see FINANCE_ADMIN_CASHOUT_WORKFLOW.md):

    requested / under_review  --approve-->  approved  --settle-->  paid
                               --reject-->  rejected

"Pending Cashout Requests" = requested + under_review (still needs Finance
Admin action). "Approved Cashout Requests" = approved + paid (Finance Admin
already made the call; paid is just the settled continuation of approved,
not a second decision).

A cashout is a `payments.Payment` row with `payment_type='cashout'`
(created by the farmer-facing `farmers.cost_views.cashout` view) — this
workflow *extends* that existing record with a `CashoutReview` row rather
than duplicating amount/currency/requester data.
"""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from notifications.models import Notification
from payments.models import Payment
from users.models import User

from api.admin_approvals import enqueue_approval
from api.admin_rbac import (
    IsAdminUser, REFUND_APPROVAL_THRESHOLD, TIER_OPERATIONS, admin_tier,
    can_perform_action,
)
from api.finance_models import CashoutReview


def _require_cashout_permission(request, action):
    if not can_perform_action(request.user, 'cashouts', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" cashout requests.',
             'code': 'forbidden_module_action'}, status=403)
    return None


def _row(review, payment):
    return {
        'id': str(review.id),
        'payment_id': str(payment.id),
        'requester_id': str(payment.user_id) if payment.user_id else None,
        'requester_name': (payment.user.full_name or payment.user.email) if payment.user_id else 'Unknown',
        'requester_role': [r.name for r in payment.user.roles.all()][:1] if payment.user_id else [],
        'amount': float(payment.amount),
        'currency': payment.currency,
        'method': payment.payment_method or '',
        'status': review.status,
        'requested_at': payment.created_at.isoformat() if payment.created_at else None,
        'reviewed_by': (review.reviewed_by.full_name or review.reviewed_by.email) if review.reviewed_by_id else None,
        'reviewed_at': review.reviewed_at.isoformat() if review.reviewed_at else None,
        'settled_at': review.settled_at.isoformat() if review.settled_at else None,
        'rejection_reason': review.rejection_reason or '',
        'notes': review.notes or '',
        'reference': str(payment.id),
    }


def _client_ip(request):
    fwd = request.META.get('HTTP_X_FORWARDED_FOR')
    return fwd.split(',')[0].strip() if fwd else request.META.get('REMOTE_ADDR')


def _audit(request, action, action_type, target_id, old=None, new=None, reason=''):
    ActivityLog.objects.create(
        user=request.user, module='cashouts', action=action, action_type=action_type,
        entity_type='cashout', entity_id=target_id, old_values=old, new_values=new,
        reason=reason or None, ip_address=_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


def _paginate(request, qs):
    try:
        limit = min(int(request.query_params.get('limit', 50)), 200)
        offset = max(int(request.query_params.get('offset', 0)), 0)
    except ValueError:
        limit, offset = 50, 0
    total = qs.count()
    page = list(qs.select_related()[offset:offset + limit])
    return page, total, limit, offset


@api_view(['GET'])
@permission_classes([IsAdminUser])
def cashout_pending_list(request):
    """Pending Cashout Requests — status IN (requested, under_review)."""
    denied = _require_cashout_permission(request, 'view')
    if denied:
        return denied
    qs = CashoutReview.objects.filter(status__in=CashoutReview.PENDING_STATUSES)
    page, total, limit, offset = _paginate(request, qs)
    payments = {p.id: p for p in Payment.objects.select_related('user').filter(
        pk__in=[r.payment_id for r in page])}
    rows = [_row(r, payments[r.payment_id]) for r in page if r.payment_id in payments]
    return Response({'results': rows, 'count': total, 'limit': limit, 'offset': offset})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def cashout_approved_list(request):
    """Approved Cashout Requests — status IN (approved, paid)."""
    denied = _require_cashout_permission(request, 'view')
    if denied:
        return denied
    qs = CashoutReview.objects.filter(status__in=CashoutReview.APPROVED_STATUSES)
    page, total, limit, offset = _paginate(request, qs)
    payments = {p.id: p for p in Payment.objects.select_related('user').filter(
        pk__in=[r.payment_id for r in page])}
    rows = [_row(r, payments[r.payment_id]) for r in page if r.payment_id in payments]
    return Response({'results': rows, 'count': total, 'limit': limit, 'offset': offset})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def cashout_review_action(request, review_id):
    """Body: {"decision": "approve" | "reject" | "settle", "reason": "..."}.

    approve/reject require 'cashouts.approve'/'cashouts.reject'; settle
    (marking an already-approved cashout as paid) requires 'cashouts.approve'
    too — it's the same authority continuing the same request, not a new
    permission.
    """
    decision = request.data.get('decision')
    if decision not in ('approve', 'reject', 'settle'):
        return Response({'detail': 'decision must be approve / reject / settle.'}, status=400)
    denied = _require_cashout_permission(request, 'reject' if decision == 'reject' else 'approve')
    if denied:
        return denied

    with transaction.atomic():
        try:
            review = CashoutReview.objects.select_for_update().get(pk=review_id)
        except (CashoutReview.DoesNotExist, ValueError):
            return Response({'detail': 'Cashout request not found.'}, status=404)
        try:
            # No select_related('user') here: Payment.user is nullable, and
            # Postgres refuses SELECT ... FOR UPDATE across the resulting
            # outer join. The user is only needed for notification/display
            # after the lock is held, so it's fetched via the plain FK
            # access below instead.
            payment = Payment.objects.select_for_update().get(pk=review.payment_id)
        except Payment.DoesNotExist:
            return Response({'detail': 'Underlying payment record is missing.'}, status=404)

        # Cannot approve/reject/settle your own cashout request.
        if payment.user_id == request.user.id:
            return Response({'detail': 'You cannot review your own cashout request.'}, status=403)

        if decision in ('approve', 'reject'):
            if review.status not in CashoutReview.PENDING_STATUSES:
                return Response(
                    {'detail': f'This request was already {review.status}.', 'code': 'already_decided'},
                    status=409)
        elif decision == 'settle':
            if review.status != CashoutReview.STATUS_APPROVED:
                return Response(
                    {'detail': 'Only an approved (not yet settled) request can be marked paid.',
                     'code': 'invalid_transition'}, status=409)

        # Above-threshold approvals need Operations Admin/Super Admin —
        # amount is always the server-recorded payment amount, never a
        # client-supplied figure (see FINANCE_ADMIN_RBAC_CHANGES.md).
        if decision == 'approve':
            tier = admin_tier(request.user) or 4
            if float(payment.amount) > REFUND_APPROVAL_THRESHOLD and tier > TIER_OPERATIONS:
                entry = enqueue_approval(
                    request, action_type='approve', module='cashouts',
                    target_id=review.id, target_type='cashouts',
                    request_data={'decision': decision, 'reason': request.data.get('reason', '')},
                    required_tier=TIER_OPERATIONS,
                )
                review.status = CashoutReview.STATUS_UNDER_REVIEW
                review.save(update_fields=['status', 'updated_at'])
                return Response({
                    'detail': 'This cashout exceeds the auto-approval threshold and has been '
                              'queued for Operations/Super Admin approval.',
                    'code': 'approval_required', 'approval_id': str(entry.id),
                    'required_tier': TIER_OPERATIONS, 'status': 'pending',
                }, status=202)

        old_status = review.status
        now = timezone.now()
        if decision == 'approve':
            review.status = CashoutReview.STATUS_APPROVED
            review.reviewed_by = request.user
            review.reviewed_at = now
        elif decision == 'reject':
            reason = str(request.data.get('reason', '')).strip()
            if not reason:
                return Response({'detail': 'A reason is required to reject a cashout request.'}, status=400)
            review.status = CashoutReview.STATUS_REJECTED
            review.reviewed_by = request.user
            review.reviewed_at = now
            review.rejection_reason = reason
            # payments.status only allows pending/completed/failed/refunded
            # (DB check constraint) — 'failed' is the closest fit for "this
            # cashout did not go through"; the review's own status
            # ('rejected') is the actual source of truth for why.
            payment.status = 'failed'
            payment.save(update_fields=['status'])
        else:  # settle
            review.status = CashoutReview.STATUS_PAID
            review.settled_at = now
            payment.status = 'completed'
            payment.confirmed_at = now
            payment.save(update_fields=['status', 'confirmed_at'])
        review.notes = request.data.get('notes', review.notes)
        review.save(update_fields=['status', 'reviewed_by', 'reviewed_at',
                                    'rejection_reason', 'settled_at', 'notes', 'updated_at'])

    Notification.objects.create(
        user=payment.user, title=f'Cashout request {review.status}',
        body=f'Your cashout request of {payment.currency} {payment.amount} is now "{review.status}".',
        notification_type='system', reference_id=payment.id, reference_type='cashout',
    )
    _audit(request, f'{decision.title()} cashout', decision if decision != 'settle' else 'edit',
           review.id, old={'status': old_status}, new={'status': review.status},
           reason=str(request.data.get('reason', '')))
    return Response(_row(review, payment))
