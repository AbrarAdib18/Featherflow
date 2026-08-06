from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from subscriptions.models import Subscription, SubscriptionPlan

@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(ModuleRecordAdmin):
    module_name = 'subscription-plans'

@admin.register(Subscription)
class SubscriptionAdmin(ModuleRecordAdmin):
    module_name = 'subscriptions'
