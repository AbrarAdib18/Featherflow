"""Unmanaged ORM models over the schema-owned ``diseases`` and ``disease_scans``
tables (see featherflow_schema.sql TABLE 37 / TABLE 38). Django does not create
or migrate them.
"""
import uuid

from django.conf import settings
from django.db import models


class DiseaseRef(models.Model):
    """Reference card for one disease — symptoms and first-aid advice."""

    SEVERITY = [('low', 'Low'), ('medium', 'Medium'), ('high', 'High'),
                ('critical', 'Critical')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=150, unique=True)
    description = models.TextField()
    symptoms = models.JSONField(default=list)
    what_to_do = models.TextField()
    what_not_to_do = models.TextField()
    prevention_tips = models.TextField(blank=True, null=True)
    severity_level = models.CharField(max_length=10, choices=SEVERITY, null=True, blank=True)
    requires_immediate_vet = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'diseases'

    def __str__(self):
        return self.name


class DiseaseScan(models.Model):
    """One disease-detection run for a farmer."""

    QUALITY = [('good', 'Good'), ('blurry', 'Blurry'), ('dark', 'Dark'),
               ('wrong_angle', 'Wrong angle'), ('rejected', 'Rejected')]
    STATUS = [('processing', 'Processing'), ('completed', 'Completed'),
              ('failed', 'Failed')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             db_column='user_id', related_name='disease_scans')
    farm_id = models.UUIDField(db_column='farm_id', null=True, blank=True)
    flock_id = models.UUIDField(db_column='flock_id', null=True, blank=True)
    image_urls = models.JSONField(default=list)
    image_quality_status = models.CharField(max_length=20, choices=QUALITY,
                                            default='good', null=True, blank=True)
    detected_disease = models.ForeignKey(DiseaseRef, on_delete=models.SET_NULL,
                                         db_column='detected_disease_id',
                                         null=True, blank=True, related_name='scans')
    confidence_score = models.DecimalField(max_digits=5, decimal_places=2,
                                           null=True, blank=True)
    severity_level = models.CharField(max_length=10, null=True, blank=True)
    scan_status = models.CharField(max_length=20, choices=STATUS, default='processing',
                                   null=True, blank=True)
    is_free_scan = models.BooleanField(default=True)
    chatbot_session_id = models.UUIDField(db_column='chatbot_session_id',
                                          null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'disease_scans'
        ordering = ['-created_at']
