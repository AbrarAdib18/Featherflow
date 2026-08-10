import uuid
from django.conf import settings
from django.db import models


class PostCategory(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=50, unique=True)
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'post_categories'


class Post(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='community_posts')
    content = models.TextField()
    media_urls = models.JSONField(default=list, blank=True, null=True)
    category = models.ForeignKey(PostCategory, models.DO_NOTHING, null=True, blank=True)
    is_anonymous = models.BooleanField(default=False, blank=True, null=True)
    is_pinned = models.BooleanField(default=False, blank=True, null=True)
    is_official = models.BooleanField(default=False, blank=True, null=True)
    status = models.CharField(max_length=10, default='active', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'posts'


class Comment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    post = models.ForeignKey(Post, models.DO_NOTHING, related_name='comments')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    parent_comment = models.ForeignKey('self', models.DO_NOTHING, null=True, blank=True, related_name='replies')
    content = models.TextField()
    is_best_answer = models.BooleanField(default=False, blank=True, null=True)
    status = models.CharField(max_length=10, default='active', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'comments'


class Reaction(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    target_id = models.UUIDField()
    target_type = models.CharField(max_length=10)
    reaction_type = models.CharField(max_length=20)
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'reactions'
        unique_together = (('user', 'target_id', 'target_type'),)


class Bookmark(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    target_id = models.UUIDField()
    target_type = models.CharField(max_length=10)
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'bookmarks'
        unique_together = (('user', 'target_id', 'target_type'),)


class Follow(models.Model):
    pk = models.CompositePrimaryKey('follower_id', 'following_id')
    follower = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='following')
    following = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='followers')
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'follows'
        unique_together = (('follower', 'following'),)


# Community alerts are stored in the shared notifications table; this name is
# retained as an import-compatible alias for older code.
from notifications.models import Notification as CommunityNotification
