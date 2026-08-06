from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from payments.models import Payment

@admin.register(Payment)
class PaymentAdmin(ModuleRecordAdmin):
    module_name = 'payments'
