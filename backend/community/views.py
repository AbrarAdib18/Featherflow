from django.utils.timesince import timesince
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
import uuid
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import PostCategory,Post,Comment,Reaction,Bookmark,Follow
from notifications.models import Notification
def notify(user,title,body,post):
    Notification.objects.create(user=user,title=title,body=body,notification_type='message',reference_id=post.id,reference_type='community_post')
def serialize_comment(c):
    author=c.author;roles=author.role_names
    return {'id':str(c.id),'author':author.full_name or author.email,'initial':(author.full_name or author.email)[0].upper(),'role':roles[0].replace('_',' ').title() if roles else 'Community member','verified':author.is_verified,'is_vet':'doctor' in roles,'content':c.content,'time':f"{timesince(c.created_at).split(',')[0]} ago",'parent_comment_id':str(c.parent_comment_id) if c.parent_comment_id else None}
def serialize(p,user):
    author=p.author;anonymous=p.is_anonymous
    name='Anonymous Farmer' if anonymous else (author.full_name or author.email)
    category=p.category.name if p.category else 'All Posts'
    return {
        'id':str(p.id),'author':name,'author_id':str(author.id),'initial':name[0].upper(),
        'role':author.role_names[0].replace('_',' ').title() if author.role_names else 'Community member',
        'time':f"{timesince(p.created_at).split(',')[0]} ago",
        'tag':f"#{category.replace(' ','')}" if p.category else '','category':category,
        'body':p.content,'hasImage':bool(p.media_urls),'pinned':p.is_pinned,
        'media_urls':p.media_urls,
        'verified':author.is_verified,'official':p.is_official,
        'helpful_count':Reaction.objects.filter(target_id=p.id,target_type='post').count(),'comment_count':p.comments.filter(status='active').count(),
        'reacted':Reaction.objects.filter(user=user,target_id=p.id,target_type='post').exists(),
        'bookmarked':Bookmark.objects.filter(user=user,target_id=p.id,target_type='post').exists(),
        'following':Follow.objects.filter(follower=user,following=author).exists(),
        'comments':[serialize_comment(c) for c in p.comments.filter(status='active').select_related('author').order_by('created_at')],
    }
@api_view(['GET','POST'])
def feed(request):
    if request.method=='POST':
        content=str(request.data.get('content','')).strip()
        if not content:return Response({'detail':'Post content is required.'},status=400)
        category=None
        if request.data.get('category'):category,_=PostCategory.objects.get_or_create(name=request.data['category'])
        p=Post.objects.create(author=request.user,content=content,category=category,is_anonymous=request.data.get('is_anonymous',False),media_urls=request.data.get('media_urls',[]))
        return Response(serialize(p,request.user),status=201)
    defaults=['Feed Prices','Disease Help','Market News','Success Stories','Team Featherflow']
    for name in defaults:PostCategory.objects.get_or_create(name=name)
    if not Post.objects.filter(status='active').exists():
        official=request.user.__class__.objects.filter(is_staff=True).first() or request.user
        category=PostCategory.objects.get(name='Team Featherflow')
        Post.objects.create(author=official,content='Welcome to the Featherflow Community. Share farm updates, ask questions, compare prices, and help other farmers.',category=category,is_official=True,is_pinned=True)
        Post.objects.create(author=official,content='Use Feed Prices to share current supplier rates, or Disease Help when you need advice from the community.',category=category,is_official=True)
        sample=Post.objects.create(author=official,content='Today’s community sample: share the feed price in your district and compare supplier quality with other farmers.',category=PostCategory.objects.get(name='Feed Prices'),is_official=True)
        Comment.objects.create(post=sample,author=official,content='Add your district, feed brand, unit price, and purchase date so the comparison stays useful.')
    qs=Post.objects.filter(status='active').select_related('author','category').order_by('-is_pinned','-created_at')
    category=request.query_params.get('category')
    if category and category!='All Posts':qs=qs.filter(category__name=category)
    posts=[serialize(p,request.user) for p in qs]
    categories=['All Posts']+list(PostCategory.objects.values_list('name',flat=True))
    trending=[f"#{x.replace(' ','')}" for x in PostCategory.objects.order_by('-post__created_at').values_list('name',flat=True).distinct()[:5]]
    return Response({'posts':posts,'topics':categories,'trending':trending})
@api_view(['POST'])
def react(request):
    p=Post.objects.get(pk=request.data['post_id']);obj,created=Reaction.objects.get_or_create(user=request.user,target_id=p.id,target_type='post',defaults={'reaction_type':request.data.get('reaction_type','helpful')})
    if not created:obj.delete()
    if created and p.author_id!=request.user.id:
        message=f'{request.user.full_name or request.user.email} found your post helpful.'
        notify(p.author,'New reaction',message,p)
    return Response({'reacted':created,'count':Reaction.objects.filter(target_id=p.id,target_type='post').count()})
@api_view(['POST'])
def comment(request):
    p=Post.objects.get(pk=request.data['post_id']);parent=Comment.objects.filter(pk=request.data.get('parent_comment_id')).first();c=Comment.objects.create(post=p,author=request.user,parent_comment=parent,content=request.data['content'])
    recipient=parent.author if parent else p.author
    if recipient.id!=request.user.id:
        target='comment' if parent else 'post'
        notify(recipient,'New community reply',f'{request.user.full_name or request.user.email} replied to your {target}.',p)
    return Response({'comment':serialize_comment(c),'count':p.comments.count()},status=201)
@api_view(['POST'])
def bookmark(request):
    p=Post.objects.get(pk=request.data['post_id']);obj,created=Bookmark.objects.get_or_create(user=request.user,target_id=p.id,target_type='post')
    if not created:obj.delete()
    return Response({'bookmarked':created})
@api_view(['POST'])
def follow(request):
    p=Post.objects.get(pk=request.data['post_id'])
    if p.author_id==request.user.id:return Response({'detail':'You cannot follow yourself.'},status=400)
    obj,created=Follow.objects.get_or_create(follower=request.user,following=p.author)
    if not created:obj.delete()
    if created:
        message=f'{request.user.full_name or request.user.email} followed you from a community post.'
        notify(p.author,'New follower',message,p)
    return Response({'following':created})

@api_view(['POST'])
def upload(request):
    file=request.FILES.get('file')
    if not file:return Response({'detail':'An image file is required.'},status=400)
    if not str(file.content_type).startswith('image/'):return Response({'detail':'Only image files are supported.'},status=400)
    if file.size>5*1024*1024:return Response({'detail':'Image must be 5 MB or smaller.'},status=400)
    extension=file.name.rsplit('.',1)[-1].lower() if '.' in file.name else 'jpg'
    path=default_storage.save(f'community/{request.user.id}/{uuid.uuid4()}.{extension}',ContentFile(file.read()))
    return Response({'url':request.build_absolute_uri(default_storage.url(path))},status=201)

@api_view(['GET','PATCH'])
def notifications(request):
    qs=request.user.notifications.filter(reference_type='community_post').order_by('-created_at')
    if request.method=='PATCH':
        qs.filter(is_read=False).update(is_read=True);return Response({'unread_count':0})
    rows=[{'id':str(x.id),'action':x.notification_type,'message':x.body,'post_id':str(x.reference_id) if x.reference_id else None,'is_read':x.is_read,'time':f"{timesince(x.created_at).split(',')[0]} ago"} for x in qs[:50]]
    return Response({'notifications':rows,'unread_count':qs.filter(is_read=False).count()})
