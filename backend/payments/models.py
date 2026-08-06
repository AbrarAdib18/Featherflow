from audit.models import AdminPanelRecord

class Payment(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Payments and refunds'
