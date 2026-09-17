import uuid
from datetime import date

from django.db import models
from profiles.models import FarmerProfile


class Farm(models.Model):
    FARM_TYPES = [(v, v.title()) for v in ('broiler', 'layer', 'breeder', 'hatchery', 'mixed', 'backyard')]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farmer = models.ForeignKey(FarmerProfile, models.DO_NOTHING, related_name='farms')
    farm_name = models.CharField(max_length=150)
    farm_type = models.CharField(max_length=20, choices=FARM_TYPES, default='mixed', blank=True, null=True)
    location = models.TextField()
    address = models.TextField()
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    registration_number = models.CharField(max_length=100, blank=True, null=True)
    total_sheds = models.PositiveIntegerField(default=0, blank=True, null=True)
    is_active = models.BooleanField(default=True, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'farms'


class Shed(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, models.DO_NOTHING, related_name='sheds')
    shed_name = models.CharField(max_length=100)
    capacity = models.IntegerField()
    current_bird_count = models.IntegerField(blank=True, null=True)
    shed_type = models.CharField(max_length=50, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'sheds'


class Flock(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    shed = models.ForeignKey(Shed, models.DO_NOTHING, blank=True, null=True)
    farm = models.ForeignKey(Farm, models.DO_NOTHING, related_name='flocks')
    batch_name = models.CharField(max_length=100)
    bird_type = models.CharField(max_length=20, blank=True, null=True)
    breed = models.CharField(max_length=100, blank=True, null=True)
    quantity = models.IntegerField()
    current_quantity = models.IntegerField()
    start_date = models.DateField()
    end_date = models.DateField(blank=True, null=True)
    status = models.CharField(max_length=10, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'flocks'

    @property
    def age_days(self):
        """Age in days, always derived from start_date — never stored, so it
        can't drift out of sync (Priority 4)."""
        end = self.end_date or date.today()
        return max(0, (end - self.start_date).days)


class FlockEvent(models.Model):
    """Immutable history log for a flock — mortality, sale, transfer,
    vaccination, feed consumption, weight measurement. Mortality/sale/transfer
    events also decrement Flock.current_quantity transactionally (see
    farmers/feed_views.py::flock_events) so the bird count stays accurate
    without a separate manual edit."""
    EVENT_TYPES = [(v, v.replace('_', ' ').title()) for v in (
        'mortality', 'sale', 'transfer', 'vaccination',
        'feed_consumption', 'weight_measurement',
    )]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    flock = models.ForeignKey(Flock, models.CASCADE, related_name='events')
    event_type = models.CharField(max_length=20, choices=EVENT_TYPES)
    quantity = models.IntegerField(blank=True, null=True)
    weight_kg = models.DecimalField(max_digits=8, decimal_places=3, blank=True, null=True)
    event_date = models.DateField()
    notes = models.TextField(blank=True, null=True)
    recorded_by = models.ForeignKey(
        'users.User', models.SET_NULL, db_column='recorded_by', blank=True, null=True,
        related_name='flock_events_recorded')
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'flock_events'
        ordering = ['-event_date', '-created_at']
