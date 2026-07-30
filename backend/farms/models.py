import uuid
from django.conf import settings
from django.db import models


class Farm(models.Model):
    FARM_TYPES = [(v, v.title()) for v in ('broiler', 'layer', 'breeder', 'hatchery', 'mixed', 'backyard')]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farmer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='farms')
    farm_name = models.CharField(max_length=150)
    farm_type = models.CharField(max_length=20, choices=FARM_TYPES, default='mixed')
    location = models.TextField()
    address = models.TextField()
    registration_number = models.CharField(max_length=100, blank=True)
    total_sheds = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
