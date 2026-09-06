import uuid

from django.db import models

from audit.models import AdminPanelRecord
from profiles.models import DeliveryProfile


class DeliveryQueueRecord(AdminPanelRecord):
    """Orders awaiting admin review/assignment (no rider yet, so no real
    delivery_orders row can exist — that table requires delivery_person_id)."""

    class Meta:
        proxy = True
        verbose_name = 'Delivery queue entry'
        verbose_name_plural = 'Delivery queue entries'


class DeliveryOrder(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    delivery_person = models.ForeignKey(
        DeliveryProfile, on_delete=models.DO_NOTHING,
        db_column='delivery_person_id', related_name='delivery_orders',
    )
    order_reference_id = models.UUIDField()
    order_type = models.CharField(
        max_length=15, choices=[('medicine', 'Medicine'), ('marketplace', 'Marketplace')],
    )
    pickup_address = models.TextField()
    delivery_address = models.TextField()
    pickup_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    pickup_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    delivery_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    delivery_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    status = models.CharField(max_length=20, default='pending')
    otp_code = models.CharField(max_length=10, blank=True, null=True)
    proof_of_delivery_url = models.TextField(blank=True, null=True)
    failure_reason = models.TextField(blank=True, null=True)
    is_pharmacy_delivery = models.BooleanField(default=False)
    is_cold_chain = models.BooleanField(default=False)
    is_prescription_required = models.BooleanField(default=False)
    notes = models.TextField(blank=True, null=True)
    assigned_at = models.DateTimeField(blank=True, null=True)
    delivered_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'delivery_orders'


class DeliveryEarning(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    delivery_person = models.ForeignKey(
        DeliveryProfile, on_delete=models.DO_NOTHING,
        db_column='delivery_person_id', related_name='earnings',
    )
    delivery_order = models.OneToOneField(
        DeliveryOrder, on_delete=models.DO_NOTHING,
        db_column='delivery_order_id', related_name='earning',
    )
    base_pay = models.DecimalField(max_digits=10, decimal_places=2)
    bonus = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    penalty = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_earned = models.DecimalField(max_digits=10, decimal_places=2)
    payout_status = models.CharField(max_length=10, default='pending')
    payout_date = models.DateField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'delivery_earnings'


class DeliveryAttendance(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    delivery_person = models.ForeignKey(
        DeliveryProfile, on_delete=models.DO_NOTHING,
        db_column='delivery_person_id', related_name='attendance',
    )
    attendance_date = models.DateField()
    check_in_time = models.DateTimeField(blank=True, null=True)
    check_out_time = models.DateTimeField(blank=True, null=True)
    status = models.CharField(max_length=10, default='present')
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'delivery_attendance'
        unique_together = (('delivery_person', 'attendance_date'),)
