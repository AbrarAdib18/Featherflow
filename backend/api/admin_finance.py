"""Finance module — real data instead of the JSON seed rows.

Transactions are the union of:
  * ``payments``          — one row per payment (subscription, order, cashout, refund)
  * ``subscriptions``     — surfaced as "Subscription" transactions with the plan price
  * ``delivery_earnings`` — surfaced as rider "Payout" transactions

``finance_summary`` reports MRR, lifetime revenue, pending payout liability and
refunds. ``finance_action`` processes a refund (routed through the approval queue
above the threshold, per ``admin_rbac.requires_approval``).
"""
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework.response import Response

from audit.models import ActivityLog
from delivery.models import DeliveryEarning
from notifications.models import Notification
from subscriptions.models import Subscription, SubscriptionPlan
from users.models import User  # noqa: F401  (kept for parity with sibling modules)

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
                Payment.objects.filter(pk=sub.payment_id).update(
                    status='refunded', notes=reason)
            _notify_refund(sub.user, sub.plan.price if sub.plan_id else 0, reason)
            _audit(request, 'Refund subscription', 'refund', sub.id, reason)
        return Response(_sub_row(sub))

    if Payment is None:
        return Response({'detail': 'Payments backend is not available.'}, status=400)
    payment = Payment.objects.select_related('user').filter(pk=record_id).first()
    if not payment:
        return Response({'detail': 'Payment not found.'}, status=404)
    if request.data.get('status') == 'Refunded' or request.data.get('action') == 'refund':
        if payment.status == 'refunded':
            return Response({'detail': 'This payment was already refunded.'}, status=409)
        payment.status = 'refunded'
        payment.notes = f'{payment.notes or ""}\nRefund: {reason}'.strip()
        payment.save(update_fields=['status', 'notes'])
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
