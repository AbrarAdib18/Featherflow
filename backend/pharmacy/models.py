from audit.models import AdminPanelRecord

class PharmacyOrganization(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Pharmacy organizations'

class PharmacyMedicine(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Pharmacy medicines'
