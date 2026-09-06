from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from delivery.models import DeliveryQueueRecord

@admin.register(DeliveryQueueRecord)
class DeliveryQueueRecordAdmin(ModuleRecordAdmin):
    module_name = 'delivery-queue'
