import uuid
from django.conf import settings
from django.db import models
class PostCategory(models.Model):
    name=models.CharField(max_length=50,unique=True);created_at=models.DateTimeField(auto_now_add=True)
class Post(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False);author=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='community_posts');content=models.TextField();media_urls=models.JSONField(default=list,blank=True);category=models.ForeignKey(PostCategory,on_delete=models.SET_NULL,null=True,blank=True);is_anonymous=models.BooleanField(default=False);is_pinned=models.BooleanField(default=False);is_official=models.BooleanField(default=False);status=models.CharField(max_length=10,default='active');created_at=models.DateTimeField(auto_now_add=True);updated_at=models.DateTimeField(auto_now=True)
class Comment(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False);post=models.ForeignKey(Post,on_delete=models.CASCADE,related_name='comments');author=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE);parent_comment=models.ForeignKey('self',on_delete=models.CASCADE,null=True,blank=True,related_name='replies');content=models.TextField();is_best_answer=models.BooleanField(default=False);status=models.CharField(max_length=10,default='active');created_at=models.DateTimeField(auto_now_add=True);updated_at=models.DateTimeField(auto_now=True)
class Reaction(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False);user=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE);post=models.ForeignKey(Post,on_delete=models.CASCADE,related_name='reactions');reaction_type=models.CharField(max_length=20,default='helpful');created_at=models.DateTimeField(auto_now_add=True)
    class Meta:constraints=[models.UniqueConstraint(fields=['user','post'],name='unique_user_post_reaction')]
class Bookmark(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False);user=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE);post=models.ForeignKey(Post,on_delete=models.CASCADE,related_name='bookmarks');created_at=models.DateTimeField(auto_now_add=True)
    class Meta:constraints=[models.UniqueConstraint(fields=['user','post'],name='unique_user_post_bookmark')]
class Follow(models.Model):
    follower=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='following');following=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='followers');created_at=models.DateTimeField(auto_now_add=True)
    class Meta:constraints=[models.UniqueConstraint(fields=['follower','following'],name='unique_follow')]
class CommunityNotification(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False);recipient=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='community_notifications');actor=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='community_actions');post=models.ForeignKey(Post,on_delete=models.CASCADE,null=True,blank=True);action=models.CharField(max_length=30);message=models.CharField(max_length=255);is_read=models.BooleanField(default=False);created_at=models.DateTimeField(auto_now_add=True)

from audit.models import AdminPanelRecord

class CommunityReport(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Community reports'

class CommunityMember(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Community moderation members'
