import uuid
from django.db import models
from farms.models import Farm


class FeedType(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    brand = models.CharField(max_length=100, blank=True)
    nutritional_info = models.JSONField(null=True, blank=True)
    unit = models.CharField(max_length=10, choices=[('kg', 'kg'), ('bag', 'bag'), ('liter', 'liter')])
    created_at = models.DateTimeField(auto_now_add=True)


class FeedStock(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='feed_stock')
    feed_type = models.ForeignKey(FeedType, on_delete=models.PROTECT, related_name='stock')
    quantity_available = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    last_restocked_at = models.DateTimeField(null=True, blank=True)
    supplier_name = models.CharField(max_length=150, blank=True)
    cost_per_unit = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    stock_status = models.CharField(max_length=10, choices=[('good','Good'),('low','Low'),('out','Out')], default='good')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['farm', 'feed_type'], name='unique_farm_feed_stock')]

class FeedSchedule(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='feed_schedules')
    feed_type = models.ForeignKey(FeedType, on_delete=models.PROTECT)
    scheduled_time = models.TimeField()
    quantity_per_feeding = models.DecimalField(max_digits=10, decimal_places=2)
    frequency = models.CharField(max_length=20, choices=[('daily','Daily'),('twice_daily','Twice daily'),('custom','Custom')], default='daily')
    created_at = models.DateTimeField(auto_now_add=True)

class FeedPurchase(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='feed_purchases')
    feed_type = models.ForeignKey(FeedType, on_delete=models.PROTECT)
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    cost_per_unit = models.DecimalField(max_digits=10, decimal_places=2)
    supplier_name = models.CharField(max_length=150, blank=True)
    purchased_at = models.DateTimeField(auto_now_add=True)

class FeedOrder(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='feed_orders')
    feed_type=models.ForeignKey(FeedType,on_delete=models.PROTECT)
    supplier_name=models.CharField(max_length=150)
    quantity=models.DecimalField(max_digits=10,decimal_places=2)
    expected_date=models.DateField()
    status=models.CharField(max_length=12,choices=[('pending','Pending'),('ordered','Ordered'),('received','Received'),('cancelled','Cancelled')],default='pending')
    created_at=models.DateTimeField(auto_now_add=True)
