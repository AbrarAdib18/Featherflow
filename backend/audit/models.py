import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class AdminPanelRecord(models.Model):
    """Persistent backing data for admin modules not migrated to Django yet."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    module = models.CharField(max_length=40, db_index=True)
    record_id = models.CharField(max_length=80)
    payload = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'backend_admin_records'
        constraints = [
            models.UniqueConstraint(
                fields=['module', 'record_id'], name='unique_admin_module_record'
            )
        ]
        ordering = ['created_at']


class ActivityLog(models.Model):
    """Django representation of featherflow_schema.sql activity_logs.

    Append-only: a BEFORE UPDATE OR DELETE trigger on the table rejects any
    mutation, and ``save()`` refuses to re-save an existing row. Overriding a
    logged action writes a *new* row (``action_type='override'``) instead.
    """

    ACTION_TYPES = [
        ('create', 'Create'), ('edit', 'Edit'), ('delete', 'Delete'),
        ('approve', 'Approve'), ('reject', 'Reject'), ('suspend', 'Suspend'),
        ('assign', 'Assign'), ('export', 'Export'), ('refund', 'Refund'),
        ('override', 'Override'), ('login', 'Login'),
        ('shift_start', 'Shift start'), ('shift_end', 'Shift end'),
        ('break_start', 'Break start'), ('break_end', 'Break end'),
        ('force_end_shift', 'Force-end shift'), ('rate_changed', 'Rate changed'),
        ('payment_made', 'Payment made'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='admin_activity_logs',
    )
    module = models.CharField(max_length=50)
    action = models.CharField(max_length=100)
    action_type = models.CharField(max_length=20, choices=ACTION_TYPES, blank=True, null=True)
    entity_type = models.CharField(max_length=50, db_column='target_type', blank=True, null=True)
    entity_id = models.UUIDField(db_column='target_id', blank=True, null=True)
    old_values = models.JSONField(db_column='old_value', null=True, blank=True)
    new_values = models.JSONField(db_column='new_value', null=True, blank=True)
    reason = models.TextField(blank=True, null=True)
    ip_address = models.CharField(max_length=45, null=True, blank=True)
    user_agent = models.TextField(blank=True, null=True)
    request_id = models.UUIDField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now, blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'activity_logs'
        ordering = ['-created_at']

    def save(self, *args, **kwargs):
        if not self._state.adding:
            raise ValueError('activity_logs rows are immutable and cannot be updated.')
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError('activity_logs rows are immutable and cannot be deleted.')


class AdminApprovalQueue(models.Model):
    """A sensitive admin action parked until a higher tier approves it."""

    STATUS_CHOICES = [
        ('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected'),
        ('overridden', 'Overridden'), ('cancelled', 'Cancelled'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='requested_by', related_name='approval_requests',
    )
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='approved_by', related_name='approval_decisions', null=True, blank=True,
    )
    action_type = models.CharField(max_length=20)
    module_affected = models.CharField(max_length=40)
    target_id = models.UUIDField(null=True, blank=True)
    target_type = models.CharField(max_length=50, blank=True, null=True)
    request_data = models.JSONField(default=dict)
    status = models.CharField(max_length=15, choices=STATUS_CHOICES, default='pending')
    required_tier = models.SmallIntegerField(default=2)
    reason = models.TextField(blank=True, null=True)
    rejection_reason = models.TextField(blank=True, null=True)
    result_ref_id = models.UUIDField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = 'admin_approval_queue'
        ordering = ['-created_at']


class AdminEscalation(models.Model):
    STATUS_CHOICES = [('open', 'Open'), ('in_progress', 'In progress'), ('resolved', 'Resolved')]
    PRIORITY_CHOICES = [('low', 'Low'), ('medium', 'Medium'), ('high', 'High'), ('critical', 'Critical')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    raised_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='raised_by', related_name='raised_escalations',
    )
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='assigned_to', related_name='assigned_escalations', null=True, blank=True,
    )
    module = models.CharField(max_length=40)
    target_id = models.UUIDField(null=True, blank=True)
    target_type = models.CharField(max_length=50, blank=True, null=True)
    priority = models.CharField(max_length=10, choices=PRIORITY_CHOICES, default='medium')
    subject = models.CharField(max_length=200)
    detail = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=15, choices=STATUS_CHOICES, default='open')
    resolution = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='resolved_by', related_name='resolved_escalations', null=True, blank=True,
    )

    class Meta:
        managed = False
        db_table = 'admin_escalations'
        ordering = ['-created_at']


class SupportTicket(models.Model):
    STATUS_CHOICES = [
        ('open', 'Open'), ('in_progress', 'In progress'), ('escalated', 'Escalated'),
        ('resolved', 'Resolved'), ('closed', 'Closed'),
    ]
    PRIORITY_CHOICES = [('low', 'Low'), ('medium', 'Medium'), ('high', 'High'), ('critical', 'Critical')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ticket_number = models.CharField(max_length=20, unique=True)
    raised_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='raised_by', related_name='support_tickets', null=True, blank=True,
    )
    raised_by_name = models.CharField(max_length=150, blank=True, null=True)
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='assigned_to', related_name='assigned_support_tickets', null=True, blank=True,
    )
    category = models.CharField(max_length=40, default='general')
    subject = models.CharField(max_length=200)
    description = models.TextField(blank=True, null=True)
    priority = models.CharField(max_length=10, choices=PRIORITY_CHOICES, default='medium')
    status = models.CharField(max_length=15, choices=STATUS_CHOICES, default='open')
    is_escalated = models.BooleanField(default=False)
    escalation = models.ForeignKey(
        AdminEscalation, models.SET_NULL, db_column='escalation_id',
        related_name='support_tickets', null=True, blank=True,
    )
    resolution = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = 'support_tickets'
        ordering = ['-created_at']


class SupportTicketReply(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ticket = models.ForeignKey(
        SupportTicket, models.CASCADE, db_column='ticket_id', related_name='replies',
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='author_id', related_name='support_ticket_replies', null=True, blank=True,
    )
    author_role = models.CharField(max_length=30, blank=True, null=True)
    body = models.TextField()
    is_internal = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'support_ticket_replies'
        ordering = ['created_at']


class SecurityFlag(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Security flags'
