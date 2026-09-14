"""Payment intents for subscription checkout.

``billing`` is not schema-owned, so this table is a plain Django migration
(nothing in ``featherflow_schema.sql`` touches it). The legacy ``payments`` and
``subscriptions`` tables are still the source of truth for *completed* money and
*active* plans — a ``PaymentIntent`` is the short-lived order object that tracks
a checkout attempt from creation through to a provider result.

No card data ever lands here: in development mode the "card" method is just a
label; in production the provider hosts the card form and we only see a
tokenised reference.
"""
import uuid

from django.conf import settings
from django.db import models

STATUS_CHOICES = [
    ('created', 'Created'),        # intent made, no method chosen yet
    ('pending', 'Pending'),        # method chosen, awaiting provider result
    ('succeeded', 'Succeeded'),    # provider confirmed payment
    ('failed', 'Failed'),
    ('cancelled', 'Cancelled'),
    ('refunded', 'Refunded'),
    ('disputed', 'Disputed'),      # cardholder/provider opened a chargeback — pending admin review
]

METHOD_CHOICES = [
    ('card', 'Card (Visa / Mastercard)'),
    ('bkash', 'bKash'),
    ('nagad', 'Nagad'),
]

TERMINAL_STATUSES = {'succeeded', 'failed', 'cancelled', 'refunded'}


class PaymentIntent(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='payment_intents')

    # Plan snapshot — the plan row is unmanaged and could change; the amount
    # charged is frozen here at checkout time and never trusted from the client.
    plan_id = models.IntegerField()
    plan_code = models.CharField(max_length=50)
    plan_name = models.CharField(max_length=80)
    interval = models.CharField(max_length=16, default='month')  # month / year / one_time
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=5, default='BDT')

    payment_method = models.CharField(
        max_length=16, choices=METHOD_CHOICES, blank=True, default='')
    provider = models.CharField(max_length=24, default='dev')
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default='created')

    # Provider's own reference (a dev txn id, or a Stripe PaymentIntent id, …).
    provider_ref = models.CharField(max_length=120, blank=True, default='')
    # Client-supplied de-dupe key — one intent per (user, plan, key).
    idempotency_key = models.CharField(max_length=80, blank=True, default='')
    failure_reason = models.CharField(max_length=200, blank=True, default='')

    # The Payment / Subscription rows created on success (for cross-reference).
    payment_id = models.UUIDField(null=True, blank=True)
    subscription_id = models.UUIDField(null=True, blank=True)

    metadata = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'billing_payment_intents'
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'idempotency_key'],
                condition=models.Q(idempotency_key__gt=''),
                name='billing_intent_idempotency_unique'),
            # DB-level backstop matching the legacy payments/subscriptions
            # tables' CHECK constraints (production_hardening_extension.sql) —
            # `choices=` only validates through the ORM/serializer layer, not
            # a direct DB write.
            models.CheckConstraint(
                condition=models.Q(status__in=[c[0] for c in STATUS_CHOICES]),
                name='billing_intent_status_valid'),
            models.CheckConstraint(
                condition=models.Q(payment_method__in=[''] + [c[0] for c in METHOD_CHOICES]),
                name='billing_intent_payment_method_valid'),
            models.CheckConstraint(
                condition=models.Q(amount__gt=0),
                name='billing_intent_amount_positive'),
        ]
        indexes = [models.Index(fields=['user', 'status'])]

    @property
    def is_terminal(self):
        return self.status in TERMINAL_STATUSES

    def __str__(self):
        return f'{self.plan_code} {self.amount}{self.currency} [{self.status}]'


class WebhookEvent(models.Model):
    """Replay / duplicate-delivery ledger for provider webhooks.

    Providers retry webhook delivery (network blips, no 2xx response, etc.)
    and a malicious replay of a captured callback is a plausible attack —
    both must be no-ops the second time. Each provider's payload carries its
    own unique delivery id (Stripe ``event.id``, bKash/Nagad equivalents);
    a verifier records that id here as ``event_id``. The unique constraint
    makes "have we processed this delivery before" an atomic DB check
    instead of a race-prone read-then-write.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    provider = models.CharField(max_length=24)
    event_id = models.CharField(max_length=200)
    intent = models.ForeignKey(
        PaymentIntent, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='webhook_events')
    received_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'billing_webhook_events'
        ordering = ['-received_at']
        constraints = [
            models.UniqueConstraint(
                fields=['provider', 'event_id'], name='billing_webhook_event_unique'),
        ]

    def __str__(self):
        return f'{self.provider}:{self.event_id}'
