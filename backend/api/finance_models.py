"""Revenue ledger + cashout review workflow — see
FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md / FINANCE_ADMIN_CASHOUT_WORKFLOW.md.

Both tables extend the existing `payments`/`subscriptions` models rather than
duplicating a parallel billing system (see finance_admin_extension.sql for
the schema, applied against the existing hand-written-SQL convention this
project uses instead of Django migrations).
"""
import uuid

from django.conf import settings
from django.db import models


class RevenueEntry(models.Model):
    """One recognized revenue event. Idempotent per (source_payment_id,
    category) — see the unique index in finance_admin_extension.sql."""

    CATEGORY_SUBSCRIPTION = 'subscription'
    CATEGORY_REFUND_ADJUSTMENT = 'refund_adjustment'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    source_payment_id = models.UUIDField()
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=5, default='BDT')
    category = models.CharField(max_length=30, default=CATEGORY_SUBSCRIPTION)
    recognized_at = models.DateTimeField()
    user_id = models.UUIDField(blank=True, null=True)
    subscription_id = models.UUIDField(blank=True, null=True)
    plan_id = models.IntegerField(blank=True, null=True)
    created_by = models.UUIDField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'revenue_entries'
        ordering = ['-recognized_at']


class CashoutReview(models.Model):
    """The Finance Admin review state machine for one cashout-type `Payment`.

    requested -> under_review -> approved -> paid   (settled_at set on 'paid')
                                -> rejected
                              -> cancelled (requester withdrew, or admin voided)
    """

    STATUS_REQUESTED = 'requested'
    STATUS_UNDER_REVIEW = 'under_review'
    STATUS_APPROVED = 'approved'
    STATUS_REJECTED = 'rejected'
    STATUS_PAID = 'paid'
    STATUS_CANCELLED = 'cancelled'
    PENDING_STATUSES = (STATUS_REQUESTED, STATUS_UNDER_REVIEW)
    # "Approved Cashout Requests" shows approved *and* paid — paid is just the
    # settled continuation of approved, not a different review outcome.
    APPROVED_STATUSES = (STATUS_APPROVED, STATUS_PAID)

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    payment_id = models.UUIDField()
    status = models.CharField(max_length=20, default=STATUS_REQUESTED)
    requested_at = models.DateTimeField(auto_now_add=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='reviewed_by',
        related_name='reviewed_cashouts', blank=True, null=True)
    reviewed_at = models.DateTimeField(blank=True, null=True)
    rejection_reason = models.TextField(blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    settled_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'cashout_reviews'
        ordering = ['-requested_at']
