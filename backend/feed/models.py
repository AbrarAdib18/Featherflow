import uuid
from django.db import models
from farms.constants import BIRD_TYPE_CHOICES
from farms.models import Farm, Flock


class FeedType(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    brand = models.CharField(max_length=100, blank=True, null=True)
    nutritional_info = models.JSONField(null=True, blank=True)
    unit = models.CharField(max_length=10, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'feed_types'


class FeedStock(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, models.DO_NOTHING, related_name='feed_stock')
    feed_type = models.ForeignKey(FeedType, models.DO_NOTHING, related_name='stock')
    quantity_available = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    last_restocked_at = models.DateTimeField(null=True, blank=True)
    supplier_name = models.CharField(max_length=150, blank=True, null=True)
    cost_per_unit = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'feed_stock'
        unique_together = (('farm', 'feed_type'),)

    @property
    def stock_status(self):
        if self.quantity_available <= 0:
            return 'out'
        return 'low' if self.quantity_available < 50 else 'good'


class FeedSchedule(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    flock = models.ForeignKey(Flock, models.DO_NOTHING, related_name='feed_schedules')
    feed_type = models.ForeignKey(FeedType, models.DO_NOTHING)
    scheduled_time = models.TimeField()
    quantity_per_feeding = models.DecimalField(max_digits=10, decimal_places=2)
    frequency = models.CharField(max_length=20, default='daily', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'feed_schedules'


class FeedConsumption(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    flock = models.ForeignKey(Flock, models.DO_NOTHING, related_name='feed_consumption')
    feed_type = models.ForeignKey(FeedType, models.DO_NOTHING, related_name='consumption')
    consumed_date = models.DateField()
    quantity_consumed = models.DecimalField(max_digits=10, decimal_places=2)
    recorded_by = models.ForeignKey('users.User', models.DO_NOTHING, db_column='recorded_by', related_name='feed_consumption_logs')
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'feed_consumption'
        ordering = ['-consumed_date']


class FeedingGuideline(models.Model):
    """Age-range + bird-type feeding reference data (Priority 4) — distinct
    from FeedSchedule (a farm's own time-of-day feeding reminders). This is
    general guidance seeded by the platform, not flock-specific and never a
    veterinary/medical recommendation — both the API and UI must label it as
    such and point farmers to a qualified poultry professional for anything
    beyond general feeding stage guidance."""
    BIRD_TYPES = BIRD_TYPE_CHOICES
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    bird_type = models.CharField(max_length=20, choices=BIRD_TYPE_CHOICES)
    min_age_days = models.IntegerField()
    max_age_days = models.IntegerField()
    stage_label = models.CharField(max_length=60)
    feed_type_label = models.CharField(max_length=100)
    recommended_grams_per_bird_per_day = models.DecimalField(max_digits=6, decimal_places=2, blank=True, null=True)
    frequency_per_day = models.IntegerField(default=2)
    guidance_text = models.TextField()
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'feeding_guidelines'
        ordering = ['bird_type', 'min_age_days']

    @classmethod
    def for_age(cls, bird_type, age_days):
        return cls.objects.filter(
            bird_type=bird_type, is_active=True,
            min_age_days__lte=age_days, max_age_days__gte=age_days,
        ).first()


class FeedStockMovement(models.Model):
    """Append-only audit log for feed_stock.quantity_available changes — see
    feed_stock_integrity_extension.sql. quantity_available itself stays the
    one source of truth for "current stock"; this table is never read to
    compute it, only to show real purchase/consumption history (replacing
    the previous fake "history" that just relabeled current stock rows)."""
    MOVEMENT_TYPES = (
        ('purchase', 'Purchase'), ('consumption', 'Consumption'),
        ('adjustment', 'Adjustment'), ('removal', 'Removal'),
    )
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, models.DO_NOTHING, related_name='feed_stock_movements')
    feed_type = models.ForeignKey(FeedType, models.DO_NOTHING, related_name='stock_movements')
    movement_type = models.CharField(max_length=20, choices=MOVEMENT_TYPES)
    quantity_delta = models.DecimalField(max_digits=10, decimal_places=2)
    quantity_after = models.DecimalField(max_digits=10, decimal_places=2)
    unit_cost = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    note = models.TextField(blank=True, null=True)
    created_by = models.ForeignKey(
        'users.User', models.DO_NOTHING, db_column='created_by',
        related_name='feed_stock_movements', null=True, blank=True)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'feed_stock_movements'
        ordering = ['-created_at']


# These concepts do not exist in featherflow_schema.sql. Keeping aliases out of
# the ORM prevents Django from silently creating duplicate schema-owned tables.
FeedPurchase = None
FeedOrder = None
