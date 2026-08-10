import uuid
from django.conf import settings
from django.db import models

class SubscriptionPlan(models.Model):
    id=models.AutoField(primary_key=True);name=models.CharField(max_length=50);price=models.DecimalField(max_digits=10,decimal_places=2);currency=models.CharField(max_length=5,default='BDT');duration_days=models.IntegerField(null=True,blank=True);features_unlocked=models.JSONField(default=list);disease_scan_limit=models.IntegerField(null=True,blank=True);is_active=models.BooleanField(default=True);created_at=models.DateTimeField(null=True,blank=True)
    class Meta: managed=False;db_table='subscription_plans'

class Subscription(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4);user=models.ForeignKey(settings.AUTH_USER_MODEL,models.DO_NOTHING);plan=models.ForeignKey(SubscriptionPlan,models.DO_NOTHING);status=models.CharField(max_length=20,default='pending');started_at=models.DateTimeField();expires_at=models.DateTimeField(null=True,blank=True);auto_renew=models.BooleanField(default=False);payment_id=models.UUIDField(null=True,blank=True);created_at=models.DateTimeField(null=True,blank=True)
    class Meta: managed=False;db_table='subscriptions'

class FeatureUsage(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4);user=models.ForeignKey(settings.AUTH_USER_MODEL,models.DO_NOTHING);feature_name=models.CharField(max_length=50);usage_count=models.IntegerField(default=0);limit_count=models.IntegerField();last_used_at=models.DateTimeField(null=True,blank=True);reset_at=models.DateTimeField(null=True,blank=True);created_at=models.DateTimeField(null=True,blank=True)
    class Meta: managed=False;db_table='feature_usage';unique_together=(('user','feature_name'),)
