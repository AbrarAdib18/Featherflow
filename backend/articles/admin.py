from django.contrib import admin
from articles.models import Article


@admin.register(Article)
class ArticleAdmin(admin.ModelAdmin):
    list_display = ('title', 'author', 'content_type', 'status', 'is_featured', 'published_at')
    list_filter = ('content_type', 'status', 'is_featured')
    search_fields = ('title', 'abstract', 'category')
    readonly_fields = ('id', 'created_at', 'updated_at')
