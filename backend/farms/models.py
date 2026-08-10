import uuid
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
