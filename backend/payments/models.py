import uuid
from django.conf import settings
from django.db import models

class Payment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=5, default='BDT')
    payment_method = models.CharField(max_length=20, null=True, blank=True)
    payment_type = models.CharField(max_length=30, null=True, blank=True)
    reference_id = models.UUIDField(null=True, blank=True)
    reference_type = models.CharField(max_length=50, null=True, blank=True)
    status = models.CharField(max_length=20, default='pending')
    transaction_id = models.CharField(max_length=100, unique=True, null=True, blank=True)
    receipt_url = models.TextField(null=True, blank=True)
    notes = models.TextField(null=True, blank=True)
    platform_charge = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    net_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = 'payments'
