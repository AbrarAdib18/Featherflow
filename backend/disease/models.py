from audit.models import AdminPanelRecord

class Disease(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Disease reference records'

class DiseaseScan(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Disease scans'
