from django.contrib import admin
from audit.admin_base import ModuleRecordAdmin
from disease.models import Disease, DiseaseScan

@admin.register(Disease)
class DiseaseAdmin(ModuleRecordAdmin): module_name = 'diseases'

@admin.register(DiseaseScan)
class DiseaseScanAdmin(ModuleRecordAdmin): module_name = 'disease-scans'
