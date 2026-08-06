from django.contrib import admin
from articles.models import Article
from audit.admin_base import ModuleRecordAdmin

@admin.register(Article)
class ArticleAdmin(ModuleRecordAdmin):
    module_name = 'articles'
