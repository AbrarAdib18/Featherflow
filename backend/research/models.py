import uuid

from django.conf import settings
from django.db import models


class ResearchTag(models.Model):
    CATEGORY_CHOICES = [
        ('disease', 'Disease'), ('breed', 'Breed'), ('age_group', 'Age group'),
        ('nutrition', 'Nutrition'), ('research_field', 'Research field'),
        ('market', 'Market'), ('other', 'Other'),
    ]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=120, unique=True)
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'research_tags'

    def __str__(self):
        return self.name


class ArticleTag(models.Model):
    pk = models.CompositePrimaryKey('article_id', 'tag_id')
    article = models.ForeignKey('articles.Article', on_delete=models.CASCADE, related_name='article_tags')
    tag = models.ForeignKey(ResearchTag, on_delete=models.CASCADE, related_name='article_tags')

    class Meta:
        managed = False
        db_table = 'article_tags'


class ArticleVersionSnapshot(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    article = models.ForeignKey('articles.Article', on_delete=models.CASCADE, related_name='version_snapshots')
    version = models.IntegerField()
    snapshot = models.JSONField(default=dict)
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        db_column='changed_by', related_name='article_version_changes',
    )
    change_note = models.CharField(max_length=200, blank=True, null=True)
    changed_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'article_version_snapshots'
        ordering = ['version']


class ProfileChangeApplication(models.Model):
    STATUS_CHOICES = [('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='profile_change_applications',
    )
    field_name = models.CharField(max_length=60)
    old_value = models.TextField(blank=True, null=True)
    new_value = models.TextField()
    reason = models.TextField()
    status = models.CharField(max_length=15, choices=STATUS_CHOICES, default='pending')
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        db_column='reviewed_by', related_name='reviewed_profile_change_applications',
    )
    review_note = models.TextField(blank=True, null=True)
    decided_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'profile_change_applications'
        ordering = ['-created_at']
