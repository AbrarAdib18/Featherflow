from django.contrib import admin

from audit.admin_base import ModuleRecordAdmin
from pharmacy.models import (
    PharmacyExpiryAlert, PharmacyMedicine, PharmacyMedicineRecord,
    PharmacyOrganization, PharmacySupplier,
)


@admin.register(PharmacyOrganization)
class PharmacyOrganizationAdmin(ModuleRecordAdmin):
    module_name = 'pharmacies'


@admin.register(PharmacyMedicineRecord)
class PharmacyMedicineRecordAdmin(ModuleRecordAdmin):
    module_name = 'medicines'


@admin.register(PharmacyMedicine)
class PharmacyMedicineAdmin(admin.ModelAdmin):
    list_display = (
        'name', 'category', 'pharmacy_user', 'stock_quantity', 'price',
        'prescription_required', 'is_approved', 'is_active', 'expiry_date',
    )
    list_filter = ('category', 'prescription_required', 'is_approved', 'is_active', 'cold_chain_required')
    search_fields = ('name', 'generic_name', 'manufacturer', 'batch_number')
    readonly_fields = ('id', 'legacy_record_id', 'views_count', 'orders_count', 'created_at', 'updated_at')


@admin.register(PharmacySupplier)
class PharmacySupplierAdmin(admin.ModelAdmin):
    list_display = ('supplier_name', 'pharmacy_user', 'contact_person', 'phone', 'is_active')
    list_filter = ('is_active',)
    search_fields = ('supplier_name', 'contact_person', 'products_supplied')
    readonly_fields = ('id', 'created_at', 'updated_at')


@admin.register(PharmacyExpiryAlert)
class PharmacyExpiryAlertAdmin(admin.ModelAdmin):
    list_display = ('medicine', 'pharmacy_user', 'alert_level', 'expires_in_days', 'is_acknowledged')
    list_filter = ('alert_level', 'is_acknowledged')
    readonly_fields = ('id', 'created_at')
