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


POST_TYPE_CHOICES = [('text', 'Text'), ('poll', 'Poll'), ('question', 'Question')]
# 'flagged' = auto-hidden at the report threshold pending review; 'hidden' = an
# admin hid it after review; 'removed' = deleted by the author or an admin.
POST_STATUS_CHOICES = [
    ('active', 'Active'), ('flagged', 'Flagged'), ('hidden', 'Hidden'), ('removed', 'Removed'),
]
REACTION_TYPE_CHOICES = [
    ('like', 'Like'), ('love', 'Love'), ('helpful', 'Helpful'), ('insightful', 'Insightful'),
]
# reactions/bookmarks/reports are polymorphic on target_type.
TARGET_POST, TARGET_COMMENT, TARGET_USER, TARGET_ARTICLE = 'post', 'comment', 'user', 'article'


class Post(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='community_posts')
    post_type = models.CharField(max_length=10, choices=POST_TYPE_CHOICES, default='text')
    title = models.TextField(blank=True, null=True)
    content = models.TextField()
    media_urls = models.JSONField(default=list, blank=True, null=True)
    tags = models.JSONField(default=list, blank=True)
    mentions = models.JSONField(default=list, blank=True)
    poll_options = models.JSONField(blank=True, null=True)
    poll_multi = models.BooleanField(default=False)
    category = models.ForeignKey(PostCategory, models.DO_NOTHING, null=True, blank=True)
    is_anonymous = models.BooleanField(default=False, blank=True, null=True)
    is_pinned = models.BooleanField(default=False, blank=True, null=True)
    is_official = models.BooleanField(default=False, blank=True, null=True)
    is_trending = models.BooleanField(default=False)
    status = models.CharField(max_length=10, choices=POST_STATUS_CHOICES, default='active', blank=True, null=True)
    hidden_reason = models.TextField(blank=True, null=True)
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
    is_anonymous = models.BooleanField(default=False)
    is_best_answer = models.BooleanField(default=False, blank=True, null=True)
    status = models.CharField(max_length=10, choices=POST_STATUS_CHOICES, default='active', blank=True, null=True)
    hidden_reason = models.TextField(blank=True, null=True)
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
    reaction_type = models.CharField(max_length=20, choices=REACTION_TYPE_CHOICES, default='helpful')
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


class Report(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    reporter = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='content_reports')
    target_id = models.UUIDField()
    target_type = models.CharField(max_length=10)
    reason = models.TextField()
    status = models.CharField(max_length=15, default='pending')
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING, null=True, blank=True,
        db_column='reviewed_by', related_name='reviewed_reports',
    )
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'reports'


class Follow(models.Model):
    pk = models.CompositePrimaryKey('follower_id', 'following_id')
    follower = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='following')
    following = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='followers')
    created_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'follows'
        unique_together = (('follower', 'following'),)


class PollVote(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    post = models.ForeignKey(Post, models.DO_NOTHING, related_name='poll_votes')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='poll_votes')
    option_indexes = models.JSONField(default=list)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'poll_votes'
        unique_together = (('post', 'user'),)


class Repost(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    post = models.ForeignKey(Post, models.DO_NOTHING, related_name='reposts')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='reposts')
    comment = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'post_reposts'
        unique_together = (('post', 'user'),)


class UserBlock(models.Model):
    """A member hiding another member's content from their own feed. Personal
    and reversible — unrelated to the admin-issued CommunityMute."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    blocker = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='community_blocks')
    blocked = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='community_blocked_by')
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'user_blocks'
        unique_together = (('blocker', 'blocked'),)


class CommunityMute(models.Model):
    """An admin silencing a member in the community layer only — they keep their
    account but cannot post, comment, react, or follow until unmuted. Anonymous
    posts stay traceable here because the mute is keyed to the real user."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='community_mutes')
    muted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='muted_by',
        related_name='community_mutes_issued', blank=True, null=True,
    )
    reason = models.TextField(blank=True, null=True)
    is_active = models.BooleanField(default=True)
    expires_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'community_mutes'


# Community alerts are stored in the shared notifications table; this name is
# retained as an import-compatible alias for older code.
from notifications.models import Notification as CommunityNotification


from audit.models import AdminPanelRecord


class CommunityReport(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Community reports'


class CommunityMember(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Community moderation members'
