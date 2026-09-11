"""Subscription-plan normalisation + checkout / activation logic.

Money boundary
--------------
* The amount charged is always computed here from the DB plan row — never read
  from the request body.
* In **development mode** (no real provider keys, ``BILLING_MODE != 'live'``)
  the "provider" is a local simulation: the client tells us the outcome it
  wants (success / failure / cancel) and we mark the intent accordingly. This
  is clearly labelled in the API (``mode: 'dev'``) and the UI.
* In **live mode** confirmation must come from a verified provider webhook
  (see ``billing.webhooks``); the dev-confirm endpoint is rejected.
"""
from datetime import timedelta, timezone as dt_timezone
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone


def _aware(dt):
    """The legacy ``subscriptions`` / ``payments`` columns are
    ``timestamp without time zone`` (naive UTC); label them before comparing."""
    if dt is not None and timezone.is_naive(dt):
        return dt.replace(tzinfo=dt_timezone.utc)
    return dt

from payments.models import Payment
from subscriptions.models import Subscription, SubscriptionPlan

from .models import PaymentIntent

# DB plan code -> presentation. Only these are offered as paid subscriptions;
# ``free`` is the implicit default and ``one_time_scan`` is a separate add-on.
_PLAN_PRESENTATION = {
    'monthly_basic': {
        'name': 'Basic', 'interval': 'month', 'recommended': False,
        'tagline': 'Core farm tools for a single flock.',
    },
    'monthly_premium': {
        'name': 'Pro', 'interval': 'month', 'recommended': True,
        'tagline': 'Everything to run the farm — unlimited disease scans, cost, tax, vet.',
    },
    'yearly': {
        'name': 'Pro (Yearly)', 'interval': 'year', 'recommended': False,
        'tagline': 'The Pro plan billed once a year — two months free.',
    },
}

_FEATURE_LABELS = {
    'disease_scan_free': '3 free disease scans / month',
    'disease_scan': 'Unlimited disease scans',
    'cost_management': 'Full cost management',
    'labor_management': 'Labor & attendance',
    'tax_calculation': 'Tax calculator & filing help',
    'blog': 'Post in the community',
    'researcher_panel': 'Researcher panel access',
}

_INTERVAL_LABEL = {'month': '/mo', 'year': '/yr', 'one_time': ' one-time'}


def billing_mode():
    """'dev' (simulated) or 'live' (real provider)."""
    return 'live' if str(getattr(settings, 'BILLING_MODE', 'dev')).lower() == 'live' else 'dev'


def _money(value):
    return Decimal(str(value or 0)).quantize(Decimal('0.01'))


def plan_display(plan):
    pres = _PLAN_PRESENTATION.get(plan.name, {
        'name': plan.name.replace('_', ' ').title(),
        'interval': 'month' if (plan.duration_days or 0) <= 31 else 'year',
        'recommended': False, 'tagline': '',
    })
    price = _money(plan.price)
    return {
        'id': plan.id,
        'code': plan.name,
        'name': pres['name'],
        'interval': pres['interval'],
        'tagline': pres['tagline'],
        'price': float(price),
        'currency': plan.currency or 'BDT',
        'price_display': f'{plan.currency or "BDT"} {price:,.0f}{_INTERVAL_LABEL.get(pres["interval"], "")}',
        'duration_days': plan.duration_days,
        'disease_scan_limit': plan.disease_scan_limit,
        'features': [_FEATURE_LABELS.get(f, f.replace('_', ' ').title())
                     for f in (plan.features_unlocked or [])],
        'raw_features': list(plan.features_unlocked or []),
        'recommended': pres['recommended'],
        'is_active': bool(plan.is_active),
    }


def subscribable_plans():
    rows = SubscriptionPlan.objects.filter(
        is_active=True, name__in=list(_PLAN_PRESENTATION)).order_by('price')
    return [plan_display(p) for p in rows]


def free_plan():
    p = SubscriptionPlan.objects.filter(name='free').first()
    return plan_display(p) if p else None


def get_plan_or_none(plan_id):
    return SubscriptionPlan.objects.filter(pk=plan_id, is_active=True).first()


def current_subscription(user):
    now = timezone.now()
    sub = (Subscription.objects
           .filter(user=user, status='active')
           .select_related('plan').order_by('-started_at').first())
    if sub is None:
        return None
    exp = _aware(sub.expires_at)
    if exp and exp < now:
        Subscription.objects.filter(pk=sub.id).update(status='expired')
        return None
    return {
        'id': str(sub.id),
        'plan': plan_display(sub.plan),
        'status': sub.status,
        'started_at': _aware(sub.started_at).isoformat() if sub.started_at else None,
        'expires_at': exp.isoformat() if exp else None,
        'auto_renew': bool(sub.auto_renew),
    }


def intent_json(intent):
    return {
        'id': str(intent.id),
        'status': intent.status,
        'plan': {
            'id': intent.plan_id, 'code': intent.plan_code,
            'name': intent.plan_name, 'interval': intent.interval,
        },
        'amount': float(intent.amount),
        'currency': intent.currency,
        'amount_display': f'{intent.currency} {intent.amount:,.0f}',
        'payment_method': intent.payment_method or None,
        'provider': intent.provider,
        'mode': billing_mode(),
        'provider_ref': intent.provider_ref or None,
        'failure_reason': intent.failure_reason or None,
        'subscription_id': str(intent.subscription_id) if intent.subscription_id else None,
        'payment_id': str(intent.payment_id) if intent.payment_id else None,
        'created_at': intent.created_at.isoformat() if intent.created_at else None,
        'confirmed_at': intent.confirmed_at.isoformat() if intent.confirmed_at else None,
    }


# ── checkout ───────────────────────────────────────────────────────────────

class CheckoutError(Exception):
    def __init__(self, detail, status=400):
        super().__init__(detail)
        self.detail = detail
        self.status = status


def create_checkout(user, plan_id, idempotency_key=''):
    """Create (or return the existing) PaymentIntent for ``user`` + ``plan``.

    Idempotent on ``idempotency_key`` — a retried tap returns the same intent
    instead of a second charge.
    """
    plan = get_plan_or_none(plan_id)
    if plan is None:
        raise CheckoutError('That plan is not available.', status=404)
    if plan.name not in _PLAN_PRESENTATION:
        raise CheckoutError('That plan cannot be purchased here.', status=400)

    key = (idempotency_key or '').strip()[:80]
    if key:
        existing = PaymentIntent.objects.filter(user=user, idempotency_key=key).first()
        if existing is not None:
            return existing, False

    # An unfinished intent for the same plan? Reuse it rather than pile up.
    if not key:
        open_intent = (PaymentIntent.objects
                       .filter(user=user, plan_id=plan.id, status__in=('created', 'pending'))
                       .first())
        if open_intent is not None:
            return open_intent, False

    pres = _PLAN_PRESENTATION[plan.name]
    intent = PaymentIntent.objects.create(
        user=user,
        plan_id=plan.id,
        plan_code=plan.name,
        plan_name=pres['name'],
        interval=pres['interval'],
        amount=_money(plan.price),           # server-side amount — never trusted from client
        currency=plan.currency or 'BDT',
        provider=billing_mode(),
        status='created',
        idempotency_key=key,
        metadata={'duration_days': plan.duration_days,
                  'features': list(plan.features_unlocked or [])},
    )
    return intent, True


def select_method(intent, method):
    if intent.is_terminal:
        raise CheckoutError('This payment is already finished.', status=409)
    from .models import METHOD_CHOICES
    valid = {m[0] for m in METHOD_CHOICES}
    if method not in valid:
        raise CheckoutError(f'Payment method must be one of: {", ".join(sorted(valid))}.')
    intent.payment_method = method
    intent.status = 'pending'
    intent.provider = billing_mode() if billing_mode() == 'dev' else _provider_for(method)
    intent.save(update_fields=['payment_method', 'status', 'provider', 'updated_at'])
    return intent


def _provider_for(method):
    return {'card': 'stripe', 'bkash': 'bkash', 'nagad': 'nagad'}.get(method, 'unknown')


def cancel_intent(intent, reason='Cancelled by user.'):
    if intent.status == 'succeeded':
        raise CheckoutError('This payment already succeeded and cannot be cancelled here.',
                            status=409)
    if intent.status in ('cancelled', 'failed'):
        return intent
    intent.status = 'cancelled'
    intent.failure_reason = reason[:200]
    intent.save(update_fields=['status', 'failure_reason', 'updated_at'])
    return intent


# ── confirmation / activation ─────────────────────────────────────────────

def confirm_dev(intent, outcome, provider_ref=''):
    """Development-mode confirmation. ``outcome`` in success|failure|cancel.

    NOT valid in live mode — real confirmation comes from a signed webhook.
    """
    if billing_mode() != 'dev':
        raise CheckoutError(
            'This server is in live payment mode. Complete the payment with the '
            'provider — it will confirm automatically.', status=409)
    return _apply_outcome(intent, outcome, provider_ref or f'dev_{intent.id.hex[:12]}',
                          via='dev-simulation')


def confirm_provider(intent, outcome, provider_ref, via='webhook'):
    """Live-mode confirmation from a verified provider webhook."""
    return _apply_outcome(intent, outcome, provider_ref, via=via)


def _apply_outcome(intent, outcome, provider_ref, via):
    if intent.status == 'succeeded':
        return intent                         # idempotent — already done
    if intent.status in ('cancelled', 'refunded'):
        raise CheckoutError('This payment can no longer be confirmed.', status=409)

    if outcome == 'success':
        return _activate(intent, provider_ref, via)
    if outcome == 'cancel':
        return cancel_intent(intent, reason='Cancelled at the payment step.')
    # failure
    intent.status = 'failed'
    intent.provider_ref = provider_ref
    intent.failure_reason = 'The payment did not go through.'
    intent.save(update_fields=['status', 'provider_ref', 'failure_reason', 'updated_at'])
    return intent


@transaction.atomic
def _activate(intent, provider_ref, via):
    """Create the Payment row + the active Subscription, atomically.

    Re-fetches the intent ``FOR UPDATE`` so two confirmations (a retry + a
    webhook) can't both activate.
    """
    locked = PaymentIntent.objects.select_for_update().get(pk=intent.pk)
    if locked.status == 'succeeded':
        return locked

    plan = get_plan_or_none(locked.plan_id) or \
        SubscriptionPlan.objects.filter(pk=locked.plan_id).first()
    if plan is None:
        raise CheckoutError('The plan no longer exists.', status=409)

    now = timezone.now()
    payment = Payment.objects.create(
        user=locked.user,
        amount=locked.amount,
        currency=locked.currency,
        payment_method=locked.payment_method or 'card',
        payment_type='subscription',
        reference_type='subscription_plan',
        status='completed',
        transaction_id=f'{locked.provider}:{provider_ref}'[:100],
        net_amount=locked.amount,
        notes=f'Subscription "{locked.plan_name}" via {via} ({billing_mode()} mode).',
        confirmed_at=now,
    )

    # One active subscription per user — retire the rest.
    Subscription.objects.filter(user=locked.user, status='active').update(status='replaced')
    expires = now + timedelta(days=plan.duration_days) if plan.duration_days else None
    sub = Subscription.objects.create(
        user=locked.user, plan=plan, status='active',
        started_at=now, expires_at=expires, auto_renew=True,
        payment_id=payment.id,
    )

    locked.status = 'succeeded'
    locked.provider_ref = provider_ref
    locked.payment_id = payment.id
    locked.subscription_id = sub.id
    locked.confirmed_at = now
    locked.failure_reason = ''
    locked.save(update_fields=['status', 'provider_ref', 'payment_id',
                               'subscription_id', 'confirmed_at', 'failure_reason',
                               'updated_at'])
    return locked
