from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from pharmacy.models import PharmacyMedicine, PharmacyOrganization

@admin.register(PharmacyOrganization)
class PharmacyOrganizationAdmin(ModuleRecordAdmin):
    module_name = 'pharmacies'

@admin.register(PharmacyMedicine)
class PharmacyMedicineAdmin(ModuleRecordAdmin):
    module_name = 'medicines'
