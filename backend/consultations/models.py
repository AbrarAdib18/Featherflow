import uuid
from django.conf import settings
from django.db import models


class Consultation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farmer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name='farmer_consultations',
    )
    doctor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name='doctor_consultations',
    )
    scan_id = models.UUIDField(db_column='scan_id', null=True, blank=True)
    # ``offline`` is the legacy PostgreSQL/API value for an in-person visit;
    # it is unrelated to the doctor's availability/presence status.
    mode = models.CharField(max_length=10, choices=[('online', 'Online'), ('offline', 'In-person')])
    status = models.CharField(max_length=20, default='requested')
    urgency_level = models.CharField(max_length=15, default='routine')
    appointment_date = models.DateField()
    appointment_time = models.TimeField()
    consultation_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    payment_id = models.UUIDField(db_column='payment_id', null=True, blank=True)
    rating = models.PositiveSmallIntegerField(null=True, blank=True)
    review_text = models.TextField(blank=True)
    rated_at = models.DateTimeField(null=True, blank=True)
    proposed_date = models.DateField(null=True, blank=True)
    proposed_time = models.TimeField(null=True, blank=True)
    decision_reason = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'consultations'
