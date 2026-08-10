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
    """Django representation of featherflow_schema.sql activity_logs."""

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
    entity_type = models.CharField(max_length=50, db_column='target_type', blank=True, null=True)
    entity_id = models.UUIDField(db_column='target_id', blank=True, null=True)
    old_values = models.JSONField(db_column='old_value', null=True, blank=True)
    new_values = models.JSONField(db_column='new_value', null=True, blank=True)
    ip_address = models.CharField(max_length=45, null=True, blank=True)
    created_at = models.DateTimeField(default=timezone.now, blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'activity_logs'
        ordering = ['-created_at']


class SupportTicket(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Support tickets'


class SecurityFlag(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Security flags'
