from audit.models import AdminPanelRecord

class Article(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Research articles'
