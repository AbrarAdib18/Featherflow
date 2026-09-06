import uuid
from django.conf import settings
from django.db import models


class Article(models.Model):
    """Unified content table backing research papers, disease/cure updates,
    innovation posts, news, and Team Featherflow announcements — one table
    with content_type discriminating the kind, per featherflow_schema.sql."""

    CONTENT_TYPE_CHOICES = [
        ('research_paper', 'Research paper'),
        ('news', 'News'),
        ('innovation', 'Innovation'),
        ('disease_study', 'Disease study'),
        ('feed_study', 'Feed study'),
        ('market_report', 'Market report'),
        ('team_update', 'Team Featherflow update'),
    ]
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('pending_review', 'Pending review'),
        ('needs_revision', 'Needs revision'),
        ('published', 'Published'),
        ('archived', 'Archived'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.DO_NOTHING, related_name='authored_articles',
    )
    title = models.CharField(max_length=300)
    abstract = models.TextField()
    body = models.TextField()
    content_type = models.CharField(max_length=20, choices=CONTENT_TYPE_CHOICES, null=True, blank=True)
    category = models.CharField(max_length=100, blank=True, null=True)
    keywords = models.JSONField(default=list, blank=True)
    references_list = models.JSONField(default=list, blank=True)
    pdf_url = models.TextField(blank=True, null=True)
    farmer_summary = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    version = models.IntegerField(default=1)
    read_count = models.IntegerField(default=0)
    co_authors = models.JSONField(default=list, blank=True)
    content_details = models.JSONField(default=dict, blank=True)
    review_notes = models.TextField(blank=True, null=True)
    is_featured = models.BooleanField(default=False)
    published_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    tags = models.ManyToManyField(
        'research.ResearchTag', through='research.ArticleTag', related_name='articles', blank=True,
    )

    class Meta:
        managed = False
        db_table = 'articles'
        verbose_name_plural = 'Articles'


class ArticleAuthor(models.Model):
    """Multi-author support for platform-registered co-authors/editors.
    Free-text co-authors (people without a Featherflow account) live in
    Article.co_authors instead — see article model docstring."""

    pk = models.CompositePrimaryKey('article_id', 'user_id')
    article = models.ForeignKey(Article, on_delete=models.CASCADE, related_name='article_authors')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='article_author_roles')
    author_role = models.CharField(max_length=15, choices=[
        ('lead_author', 'Lead author'), ('co_author', 'Co-author'), ('editor', 'Editor'),
    ])
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'article_authors'
