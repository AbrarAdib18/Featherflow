from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from delivery.models import DeliveryOrder, DeliveryRider

@admin.register(DeliveryOrder)
class DeliveryOrderAdmin(ModuleRecordAdmin):
    module_name = 'delivery-orders'

@admin.register(DeliveryRider)
class DeliveryRiderAdmin(ModuleRecordAdmin):
    module_name = 'riders'
