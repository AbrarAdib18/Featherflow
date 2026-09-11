"""Community blogging layer — the X-style social feed from requirements §8.

Function views in the same shape as articles/research: compact ``@api_view``
handlers, hand-built dict payloads, ``managed = False`` models over the
featherflow_schema tables. The older body-keyed endpoints (``react/``,
``comment/``, ``bookmark/``, ``follow/``) are kept verbatim so the existing
Flutter feed keeps working; everything else is new.
"""

import re
import uuid
from collections import Counter
from datetime import timezone as _dt_timezone

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.utils.timesince import timesince
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from notifications.models import Notification

from .models import (
    REACTION_TYPE_CHOICES, Bookmark, Comment, Follow, PollVote, Post, PostCategory,
    Reaction, Report, Repost, UserBlock,
)
from .permissions import (
    MAX_COMMENT_LENGTH, MAX_POLL_OPTIONS, MAX_POST_LENGTH, MIN_POLL_OPTIONS,
    REPORT_AUTOHIDE_THRESHOLD, active_mute, display_author, is_moderator,
    poll_quota_ok, verified_badge,
)

_REACTION_TYPES = {value for value, _ in REACTION_TYPE_CHOICES}
_DEFAULT_CATEGORIES = [
    'Feed Prices', 'Disease Help', 'Market News', 'Equipment', 'Birds',
    'Success Stories', 'Team Featherflow',
]
_HASHTAG_RE = re.compile(r'#(\w{2,50})')
_MENTION_RE = re.compile(r'@([\w.\-]{2,150})')


# ── notifications ──────────────────────────────────────────────────────────

def _notify(user, title, body, post_id):
    Notification.objects.create(
        user=user, title=title, body=body, notification_type='message',
        reference_id=post_id, reference_type='community_post',
    )


# ── small helpers ─────────────────────────────────────────────────────────

def _ago(dt):
    return f"{timesince(dt).split(',')[0]} ago" if dt else ''


def _aware(dt):
    """DB TIMESTAMP columns are naive; treat them as UTC for time maths."""
    if dt is not None and timezone.is_naive(dt):
        return timezone.make_aware(dt, _dt_timezone.utc)
    return dt


def _extract_hashtags(*texts):
    found = []
    for text in texts:
        found += [m.lower() for m in _HASHTAG_RE.findall(text or '')]
    return list(dict.fromkeys(found))


def _blocked_ids(viewer):
    return set(UserBlock.objects.filter(blocker=viewer).values_list('blocked_id', flat=True))


def _visible_posts(viewer):
    """Active posts minus anyone the viewer has personally blocked."""
    qs = Post.objects.filter(status='active').select_related('author', 'category')
    blocked = _blocked_ids(viewer)
    return qs.exclude(author_id__in=blocked) if blocked else qs


def _get_post(pk, *, include_hidden=False):
    try:
        post = Post.objects.select_related('author', 'category').get(pk=pk)
    except (Post.DoesNotExist, ValueError, TypeError):
        return None
    if not include_hidden and post.status in ('hidden', 'removed'):
        return None
    return post


def _muted_response(request):
    """403 Response if the caller is muted from the community, else None."""
    mute = active_mute(request.user)
    if mute is not None:
        return Response({
            'detail': 'Your community access is currently muted by a moderator.'
                      + (f' Reason: {mute.reason}' if mute.reason else ''),
            'code': 'community_muted',
        }, status=403)
    return None


def _reaction_summary(target_id, target_type, viewer):
    rows = Reaction.objects.filter(target_id=target_id, target_type=target_type)
    by_type = Counter(r.reaction_type for r in rows)
    mine = next((r.reaction_type for r in rows if r.user_id == viewer.id), None)
    return {
        'total': sum(by_type.values()),
        'by_type': {t: by_type.get(t, 0) for t in _REACTION_TYPES},
        'my_reaction': mine,
    }


def _poll_block(post, viewer):
    options = post.poll_options or []
    votes = list(PollVote.objects.filter(post=post))
    tally = Counter()
    for vote in votes:
        for idx in vote.option_indexes or []:
            tally[idx] += 1
    my_vote = next((v.option_indexes for v in votes if v.user_id == viewer.id), None)
    return {
        'multi': post.poll_multi,
        'total_votes': len(votes),
        'my_vote': my_vote,
        'options': [
            {'index': i, 'text': text, 'votes': tally.get(i, 0)}
            for i, text in enumerate(options)
        ],
    }


def _serialize_comment(comment, viewer, is_mod):
    author = comment.author
    anon = bool(comment.is_anonymous)
    block = display_author(author, anon)
    if not is_mod:
        block.pop('real_author_id', None)
    return {
        'id': str(comment.id),
        'post_id': str(comment.post_id),
        'parent_comment_id': str(comment.parent_comment_id) if comment.parent_comment_id else None,
        'author': block,
        'content': comment.content,
        'is_best_answer': bool(comment.is_best_answer),
        'status': comment.status,
        'hidden_reason': comment.hidden_reason if is_mod else None,
        'reactions': _reaction_summary(comment.id, 'comment', viewer),
        'time': _ago(comment.created_at),
        'created_at': comment.created_at,
    }


def _serialize_post(post, viewer, is_mod, *, with_comments=False):
    author = post.author
    anon = bool(post.is_anonymous)
    block = display_author(author, anon)
    if not is_mod:
        block.pop('real_author_id', None)

    comments_qs = post.comments.filter(status='active').select_related('author')
    data = {
        'id': str(post.id),
        'post_type': post.post_type,
        'title': post.title,
        'author': block,
        'category': post.category.name if post.category else None,
        'tag': f"#{post.category.name.replace(' ', '')}" if post.category else '',
        'content': post.content,
        'body': post.content,
        'tags': post.tags or [],
        'mentions': post.mentions or [],
        'media_urls': post.media_urls or [],
        'has_image': bool(post.media_urls),
        'is_pinned': bool(post.is_pinned),
        'is_official': bool(post.is_official),
        'is_trending': bool(post.is_trending),
        'status': post.status,
        'hidden_reason': post.hidden_reason if is_mod else None,
        'reactions': _reaction_summary(post.id, 'post', viewer),
        'comments_count': comments_qs.count(),
        'reposts_count': post.reposts.count(),
        'reposted': post.reposts.filter(user=viewer).exists(),
        'bookmarked': Bookmark.objects.filter(
            user=viewer, target_id=post.id, target_type='post').exists(),
        'following_author': (not anon) and Follow.objects.filter(
            follower=viewer, following=author).exists(),
        'reports_count': Report.objects.filter(
            target_id=post.id, target_type='post').count() if is_mod else None,
        'time': _ago(post.created_at),
        'created_at': post.created_at,
        'updated_at': post.updated_at,
    }
    if post.post_type == 'poll':
        data['poll'] = _poll_block(post, viewer)
    if post.post_type == 'question':
        best = comments_qs.filter(is_best_answer=True).first()
        data['best_answer_id'] = str(best.id) if best else None
        data['can_mark_best_answer'] = (not anon) and author.id == viewer.id
    if with_comments:
        blocked = _blocked_ids(viewer)
        data['comments'] = [
            _serialize_comment(c, viewer, is_mod)
            for c in comments_qs.order_by('created_at')
            if c.author_id not in blocked
        ]
    return data


def _trending_score(post, now):
    created = _aware(post.created_at)
    hours = max((now - created).total_seconds() / 3600, 1) if created else 1
    reactions = Reaction.objects.filter(target_id=post.id, target_type='post').count()
    comments = post.comments.filter(status='active').count()
    reposts = post.reposts.count()
    return (reactions + comments * 2 + reposts * 3) / (hours ** 0.6)


def _ensure_seed_categories():
    for name in _DEFAULT_CATEGORIES:
        PostCategory.objects.get_or_create(name=name)


# ── feed: list + create ───────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def feed(request):
    viewer = request.user
    is_mod = is_moderator(viewer)

    if request.method == 'POST':
        return _create_post(request)

    _ensure_seed_categories()
    qs = _visible_posts(viewer)

    tab = request.query_params.get('tab', 'latest')
    category = request.query_params.get('category')
    if category and category not in ('All Posts', 'all'):
        qs = qs.filter(category__name=category)

    search = request.query_params.get('search') or request.query_params.get('q')
    if search:
        qs = qs.filter(
            Q(content__icontains=search) | Q(title__icontains=search)
            | Q(tags__contains=[search.lower().lstrip('#')])
        )

    if tab == 'following':
        followed = Follow.objects.filter(follower=viewer).values_list('following_id', flat=True)
        qs = qs.filter(author_id__in=list(followed), is_anonymous=False)

    now = timezone.now()
    if tab == 'trending':
        posts = sorted(qs, key=lambda p: _trending_score(p, now), reverse=True)[:50]
    else:
        posts = list(qs.order_by('-is_pinned', '-created_at')[:50])

    categories = ['All Posts'] + list(PostCategory.objects.values_list('name', flat=True))
    return Response({
        'posts': [_serialize_post(p, viewer, is_mod) for p in posts],
        'topics': categories,
        'trending': _hashtag_rows(limit=6),
        'tab': tab,
    })


def _create_post(request):
    viewer = request.user
    muted = _muted_response(request)
    if muted is not None:
        return muted

    post_type = str(request.data.get('post_type', 'text')).strip() or 'text'
    if post_type not in ('text', 'poll', 'question'):
        return Response({'detail': 'post_type must be text, poll, or question.'}, status=400)

    content = str(request.data.get('content', '')).strip()
    title = str(request.data.get('title', '')).strip() or None
    if not content and post_type != 'poll':
        return Response({'detail': 'Post content is required.'}, status=400)
    if len(content) > MAX_POST_LENGTH:
        return Response({'detail': f'Posts are limited to {MAX_POST_LENGTH} characters.'}, status=400)
    if post_type == 'question' and not title:
        return Response({'detail': 'A question needs a title.'}, status=400)

    poll_options = None
    poll_multi = bool(request.data.get('poll_multi', False))
    if post_type == 'poll':
        if not poll_quota_ok(viewer):
            return Response({
                'detail': 'You have reached the limit of 2 polls per week.',
            }, status=429)
        raw = request.data.get('poll_options') or []
        poll_options = [str(o).strip() for o in raw if str(o).strip()]
        if not (MIN_POLL_OPTIONS <= len(poll_options) <= MAX_POLL_OPTIONS):
            return Response({
                'detail': f'A poll needs between {MIN_POLL_OPTIONS} and {MAX_POLL_OPTIONS} options.',
            }, status=400)
        if not content:
            content = title or 'Poll'

    category = None
    if request.data.get('category'):
        category, _ = PostCategory.objects.get_or_create(name=str(request.data['category']).strip())

    tags = _extract_hashtags(content, title)
    extra_tags = request.data.get('tags') or []
    tags = list(dict.fromkeys(tags + [str(t).lower().lstrip('#') for t in extra_tags if str(t).strip()]))
    mentions = [m.lower() for m in _MENTION_RE.findall(f'{content} {title or ""}')]

    now = timezone.now()
    post = Post.objects.create(
        author=viewer, post_type=post_type, title=title, content=content,
        media_urls=request.data.get('media_urls', []), tags=tags, mentions=mentions,
        poll_options=poll_options, poll_multi=poll_multi, category=category,
        is_anonymous=bool(request.data.get('is_anonymous', False)),
        status='active', created_at=now, updated_at=now,
    )
    _notify_mentions(viewer, mentions, post)
    return Response(
        _serialize_post(post, viewer, is_moderator(viewer), with_comments=True), status=201)


def _notify_mentions(actor, mentions, post):
    if not mentions:
        return
    from users.models import User

    targets = User.objects.filter(
        Q(full_name__in=mentions) | Q(email__in=mentions),
    ).exclude(pk=actor.id)[:10]
    for user in targets:
        _notify(user, 'You were mentioned',
                f'{actor.full_name or actor.email} mentioned you in a community post.', post.id)


# ── post detail ──────────────────────────────────────────────────────────

@api_view(['GET', 'PUT', 'DELETE'])
@permission_classes([IsAuthenticated])
def post_detail(request, pk):
    viewer = request.user
    is_mod = is_moderator(viewer, 'edit') or is_moderator(viewer, 'delete')
    post = _get_post(pk, include_hidden=is_mod)
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)

    if request.method == 'GET':
        return Response(_serialize_post(post, viewer, is_moderator(viewer), with_comments=True))

    is_owner = post.author_id == viewer.id
    if request.method == 'DELETE':
        if not (is_owner or is_moderator(viewer, 'delete')):
            return Response({'detail': 'You can only delete your own posts.'}, status=403)
        post.status = 'removed'
        if not is_owner:
            post.hidden_reason = str(request.data.get('reason', '')).strip() or 'Removed by moderator'
        post.save(update_fields=['status', 'hidden_reason', 'updated_at'])
        return Response(status=204)

    # PUT — posts are immutable in Pass 1 except for a small set of author edits.
    if not is_owner:
        return Response({'detail': 'You can only edit your own posts.'}, status=403)
    if 'category' in request.data:
        name = str(request.data['category']).strip()
        post.category = PostCategory.objects.get_or_create(name=name)[0] if name else None
    if 'content' in request.data and post.post_type != 'poll':
        content = str(request.data['content']).strip()
        if not content:
            return Response({'detail': 'Post content is required.'}, status=400)
        if len(content) > MAX_POST_LENGTH:
            return Response({'detail': f'Posts are limited to {MAX_POST_LENGTH} characters.'}, status=400)
        post.content = content
        post.tags = _extract_hashtags(content, post.title)
    post.updated_at = timezone.now()
    post.save()
    return Response(_serialize_post(post, viewer, is_moderator(viewer), with_comments=True))


# ── comments ─────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def post_comments(request, pk):
    viewer = request.user
    post = _get_post(pk)
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)
    is_mod = is_moderator(viewer)

    if request.method == 'GET':
        blocked = _blocked_ids(viewer)
        rows = post.comments.filter(status='active').select_related('author').order_by('created_at')
        return Response({'comments': [
            _serialize_comment(c, viewer, is_mod) for c in rows if c.author_id not in blocked
        ]})

    return _create_comment(request, post)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def comment(request):
    """Back-compat: create a comment addressed by ``post_id`` in the body."""
    post = _get_post(request.data.get('post_id'))
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)
    return _create_comment(request, post)


def _create_comment(request, post):
    viewer = request.user
    muted = _muted_response(request)
    if muted is not None:
        return muted
    content = str(request.data.get('content', '')).strip()
    if not content:
        return Response({'detail': 'A comment cannot be empty.'}, status=400)
    if len(content) > MAX_COMMENT_LENGTH:
        return Response({'detail': f'Comments are limited to {MAX_COMMENT_LENGTH} characters.'}, status=400)
    parent = Comment.objects.filter(pk=request.data.get('parent_comment_id'), post=post).first()
    now = timezone.now()
    new_comment = Comment.objects.create(
        post=post, author=viewer, parent_comment=parent, content=content,
        is_anonymous=bool(request.data.get('is_anonymous', False)),
        status='active', created_at=now, updated_at=now,
    )
    recipient = parent.author if parent else post.author
    if recipient.id != viewer.id:
        _notify(recipient, 'New community reply',
                f'{viewer.full_name or viewer.email} replied to your '
                f'{"comment" if parent else "post"}.', post.id)
    return Response({
        'comment': _serialize_comment(new_comment, viewer, is_moderator(viewer)),
        'comments_count': post.comments.filter(status='active').count(),
        'count': post.comments.filter(status='active').count(),
    }, status=201)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def best_answer(request, pk):
    try:
        comment = Comment.objects.select_related('post', 'author').get(pk=pk, status='active')
    except (Comment.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Comment not found.'}, status=404)
    post = comment.post
    if post.post_type != 'question':
        return Response({'detail': 'Only question posts can have a best answer.'}, status=400)
    if post.is_anonymous or post.author_id != request.user.id:
        return Response({'detail': 'Only the question author can mark the best answer.'}, status=403)

    mark = bool(request.data.get('is_best_answer', True))
    with transaction.atomic():
        post.comments.filter(is_best_answer=True).update(is_best_answer=False)
        if mark:
            comment.is_best_answer = True
            comment.save(update_fields=['is_best_answer', 'updated_at'])
            if comment.author_id != request.user.id:
                _notify(comment.author, 'Your answer was accepted',
                        f'{request.user.full_name or request.user.email} marked your reply as the best answer.',
                        post.id)
    return Response({'comment_id': str(comment.id), 'is_best_answer': mark})


# ── reactions (back-compat body endpoint + comment variant) ───────────────

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def react(request):
    return _toggle_reaction(request, request.data.get('post_id'), 'post')


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def comment_react(request, pk):
    return _toggle_reaction(request, pk, 'comment')


def _toggle_reaction(request, target_id, target_type):
    muted = _muted_response(request)
    if muted is not None:
        return muted
    model = Post if target_type == 'post' else Comment
    try:
        target = model.objects.get(pk=target_id)
    except (model.DoesNotExist, ValueError, TypeError):
        return Response({'detail': f'{target_type.title()} not found.'}, status=404)

    reaction_type = str(request.data.get('reaction_type', 'helpful'))
    if reaction_type not in _REACTION_TYPES:
        return Response({'detail': f'Unknown reaction "{reaction_type}".'}, status=400)

    existing = Reaction.objects.filter(
        user=request.user, target_id=target.id, target_type=target_type).first()
    if existing and existing.reaction_type == reaction_type:
        existing.delete()
        reacted = None
    elif existing:
        existing.reaction_type = reaction_type
        existing.save(update_fields=['reaction_type'])
        reacted = reaction_type
    else:
        Reaction.objects.create(
            user=request.user, target_id=target.id, target_type=target_type,
            reaction_type=reaction_type, created_at=timezone.now())
        reacted = reaction_type
        author_id = target.author_id
        if author_id != request.user.id:
            post_id = target.id if target_type == 'post' else target.post_id
            _notify(target.author, 'New reaction',
                    f'{request.user.full_name or request.user.email} reacted to your {target_type}.',
                    post_id)

    summary = _reaction_summary(target.id, target_type, request.user)
    return Response({'reacted': reacted, 'count': summary['total'], 'reactions': summary})


# ── poll voting ──────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def vote(request):
    muted = _muted_response(request)
    if muted is not None:
        return muted
    post = _get_post(request.data.get('post_id'))
    if post is None or post.post_type != 'poll':
        return Response({'detail': 'Poll not found.'}, status=404)

    raw = request.data.get('option_indexes')
    if raw is None and request.data.get('option_index') is not None:
        raw = [request.data.get('option_index')]
    try:
        indexes = sorted({int(i) for i in raw or []})
    except (TypeError, ValueError):
        return Response({'detail': 'option_indexes must be a list of numbers.'}, status=400)

    option_count = len(post.poll_options or [])
    if not indexes or any(i < 0 or i >= option_count for i in indexes):
        return Response({'detail': 'Choose a valid poll option.'}, status=400)
    if not post.poll_multi and len(indexes) != 1:
        return Response({'detail': 'This poll only allows one choice.'}, status=400)

    PollVote.objects.update_or_create(
        post=post, user=request.user,
        defaults={'option_indexes': indexes, 'created_at': timezone.now()},
    )
    return Response(_poll_block(post, request.user))


# ── repost ───────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def repost(request):
    muted = _muted_response(request)
    if muted is not None:
        return muted
    post = _get_post(request.data.get('post_id'))
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)
    obj, created = Repost.objects.get_or_create(
        post=post, user=request.user,
        defaults={'comment': str(request.data.get('comment', '')).strip() or None,
                  'created_at': timezone.now()},
    )
    if not created:
        obj.delete()
    elif post.author_id != request.user.id:
        _notify(post.author, 'Your post was shared',
                f'{request.user.full_name or request.user.email} reposted your post.', post.id)
    return Response({'reposted': created, 'count': post.reposts.count()})


# ── bookmarks ────────────────────────────────────────────────────────────

@api_view(['POST', 'DELETE'])
@permission_classes([IsAuthenticated])
def bookmark(request):
    post = _get_post(request.data.get('post_id'))
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)
    obj, created = Bookmark.objects.get_or_create(
        user=request.user, target_id=post.id, target_type='post',
        defaults={'created_at': timezone.now()})
    if request.method == 'DELETE' or not created:
        obj.delete()
        return Response({'bookmarked': False})
    return Response({'bookmarked': True})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def bookmarks(request):
    marks = Bookmark.objects.filter(
        user=request.user, target_type='post').order_by('-created_at')
    ids = [m.target_id for m in marks]
    posts = {p.id: p for p in Post.objects.filter(id__in=ids, status='active').select_related('author', 'category')}
    ordered = [posts[i] for i in ids if i in posts]
    is_mod = is_moderator(request.user)
    return Response({'posts': [_serialize_post(p, request.user, is_mod) for p in ordered]})


# ── follows ──────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def follow(request):
    """Back-compat: follow the author of a post by post_id."""
    post = _get_post(request.data.get('post_id'))
    if post is None:
        return Response({'detail': 'Post not found.'}, status=404)
    if post.is_anonymous:
        return Response({'detail': 'You cannot follow an anonymous author.'}, status=400)
    return _toggle_follow(request.user, post.author, post_id=post.id)


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def follows(request):
    from users.models import User

    if request.method == 'GET':
        rows = Follow.objects.filter(follower=request.user).select_related('following')
        return Response({'following': [_user_card(f.following) for f in rows]})

    target_id = request.data.get('user_id')
    try:
        target = User.objects.get(pk=target_id)
    except (User.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'User not found.'}, status=404)
    return _toggle_follow(request.user, target)


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def unfollow(request, user_id):
    deleted, _n = Follow.objects.filter(follower=request.user, following_id=user_id).delete()
    return Response({'following': False, 'removed': bool(deleted)})


def _toggle_follow(follower, target, post_id=None):
    if target.id == follower.id:
        return Response({'detail': 'You cannot follow yourself.'}, status=400)
    obj, created = Follow.objects.get_or_create(
        follower=follower, following=target, defaults={'created_at': timezone.now()})
    if not created:
        obj.delete()
    elif post_id is not None:
        _notify(target, 'New follower',
                f'{follower.full_name or follower.email} followed you from a community post.', post_id)
    elif created:
        Notification.objects.create(
            user=target, title='New follower',
            body=f'{follower.full_name or follower.email} started following you.',
            notification_type='message', reference_type='community_follow')
    return Response({'following': created})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def follow_suggestions(request):
    """Verified experts and Team Featherflow the viewer isn't following yet."""
    from users.models import User

    already = set(Follow.objects.filter(
        follower=request.user).values_list('following_id', flat=True))
    already.add(request.user.id)
    candidates = User.objects.filter(
        Q(roles__name__in=['researcher', 'doctor', 'pharmacy'])
        | Q(roles__panel_type='admin'),
    ).exclude(id__in=already).distinct()[:20]
    return Response({'suggestions': [_user_card(u) for u in candidates if verified_badge(u)]})


@api_view(['GET', 'POST', 'DELETE'])
@permission_classes([IsAuthenticated])
def blocks(request):
    """Personal mute: hide a member's posts and replies from your own view."""
    from users.models import User

    if request.method == 'GET':
        rows = UserBlock.objects.filter(blocker=request.user).select_related('blocked')
        return Response({'blocked': [_user_card(b.blocked) for b in rows]})

    try:
        target = User.objects.get(pk=request.data.get('user_id'))
    except (User.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'User not found.'}, status=404)
    if target.id == request.user.id:
        return Response({'detail': 'You cannot block yourself.'}, status=400)

    if request.method == 'DELETE':
        UserBlock.objects.filter(blocker=request.user, blocked=target).delete()
        return Response({'blocked': False})
    _obj, created = UserBlock.objects.get_or_create(
        blocker=request.user, blocked=target, defaults={'created_at': timezone.now()})
    if not created:
        _obj.delete()
        return Response({'blocked': False})
    Follow.objects.filter(follower=request.user, following=target).delete()
    return Response({'blocked': True}, status=201)


def _user_card(user):
    name = user.full_name or user.email
    return {
        'id': str(user.id), 'name': name, 'initial': (name or '?')[0].upper(),
        'role': user.role_names[0].replace('_', ' ').title() if user.role_names else 'Community member',
        'badge': verified_badge(user),
        'followers': Follow.objects.filter(following=user).count(),
    }


# ── search / discovery ───────────────────────────────────────────────────

def _hashtag_rows(limit=10):
    counter = Counter()
    for tags in Post.objects.filter(status='active').values_list('tags', flat=True):
        counter.update(tags or [])
    return [{'tag': f'#{tag}', 'count': n} for tag, n in counter.most_common(limit)]


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def search(request):
    viewer = request.user
    is_mod = is_moderator(viewer)
    qs = _visible_posts(viewer)

    query = (request.query_params.get('q') or request.query_params.get('query') or '').strip()
    if query:
        qs = qs.filter(
            Q(content__icontains=query) | Q(title__icontains=query)
            | Q(tags__contains=[query.lower().lstrip('#')])
        )
    category = request.query_params.get('category')
    if category and category not in ('All Posts', 'all'):
        qs = qs.filter(category__name=category)
    tag = request.query_params.get('tag')
    if tag:
        qs = qs.filter(tags__contains=[tag.lower().lstrip('#')])
    if request.query_params.get('post_type'):
        qs = qs.filter(post_type=request.query_params['post_type'])
    if request.query_params.get('verified') in ('1', 'true', 'True'):
        expert_ids = [
            p.author_id for p in qs if not p.is_anonymous and verified_badge(p.author)
        ]
        qs = qs.filter(author_id__in=expert_ids)

    sort = request.query_params.get('sort', 'latest')
    if sort == 'popular':
        now = timezone.now()
        results = sorted(qs, key=lambda p: _trending_score(p, now), reverse=True)[:50]
    else:
        results = list(qs.order_by('-created_at')[:50])
    return Response({'results': [_serialize_post(p, viewer, is_mod) for p in results]})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def categories(request):
    _ensure_seed_categories()
    rows = []
    for cat in PostCategory.objects.all():
        rows.append({
            'id': cat.id, 'name': cat.name,
            'post_count': Post.objects.filter(category=cat, status='active').count(),
        })
    return Response({'results': sorted(rows, key=lambda r: -r['post_count'])})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def hashtags(request):
    return Response({'results': _hashtag_rows(limit=int(request.query_params.get('limit', 15)))})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def trending(request):
    viewer, is_mod, now = request.user, is_moderator(request.user), timezone.now()
    posts = sorted(
        _visible_posts(request.user),
        key=lambda p: _trending_score(p, now), reverse=True,
    )[:30]
    return Response({'posts': [_serialize_post(p, viewer, is_mod) for p in posts]})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def latest(request):
    viewer, is_mod = request.user, is_moderator(request.user)
    posts = _visible_posts(request.user).order_by('-is_pinned', '-created_at')[:50]
    return Response({'posts': [_serialize_post(p, viewer, is_mod) for p in posts]})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def following_feed(request):
    viewer, is_mod = request.user, is_moderator(request.user)
    followed = list(Follow.objects.filter(follower=viewer).values_list('following_id', flat=True))
    posts = Post.objects.filter(
        status='active', author_id__in=followed, is_anonymous=False,
    ).select_related('author', 'category').order_by('-created_at')[:50]
    return Response({'posts': [_serialize_post(p, viewer, is_mod) for p in posts]})


# ── user profile ─────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def user_posts(request, user_id):
    from users.models import User

    try:
        target = User.objects.get(pk=user_id)
    except (User.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'User not found.'}, status=404)
    viewer, is_mod = request.user, is_moderator(request.user)
    qs = Post.objects.filter(
        author=target, status='active', is_anonymous=False,
    ).select_related('author', 'category').order_by('-created_at')[:50]
    return Response({'posts': [_serialize_post(p, viewer, is_mod) for p in qs]})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def user_stats(request, user_id):
    from users.models import User

    try:
        target = User.objects.get(pk=user_id)
    except (User.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'User not found.'}, status=404)
    public_posts = Post.objects.filter(author=target, status='active', is_anonymous=False)
    return Response({
        **_user_card(target),
        'posts_count': public_posts.count(),
        'following_count': Follow.objects.filter(follower=target).count(),
        'followers_count': Follow.objects.filter(following=target).count(),
        'is_following': Follow.objects.filter(follower=request.user, following=target).exists(),
        'is_blocked': UserBlock.objects.filter(blocker=request.user, blocked=target).exists(),
    })


# ── reports (post + comment) ─────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def report(request):
    target_type = str(request.data.get('target_type', 'post'))
    if target_type not in ('post', 'comment'):
        return Response({'detail': 'target_type must be post or comment.'}, status=400)
    target_id = request.data.get('target_id') or request.data.get('post_id') or request.data.get('comment_id')
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A reason is required to report content.'}, status=400)

    model = Post if target_type == 'post' else Comment
    try:
        target = model.objects.get(pk=target_id)
    except (model.DoesNotExist, ValueError, TypeError):
        return Response({'detail': f'{target_type.title()} not found.'}, status=404)
    if target.author_id == request.user.id:
        return Response({'detail': 'You cannot report your own content.'}, status=400)

    _report, created = Report.objects.get_or_create(
        reporter=request.user, target_id=target.id, target_type=target_type, status='pending',
        defaults={'reason': reason, 'created_at': timezone.now(), 'updated_at': timezone.now()},
    )
    if not created:
        return Response({'detail': 'You have already reported this content.'}, status=409)

    pending = Report.objects.filter(
        target_id=target.id, target_type=target_type, status='pending').count()
    auto_hidden = False
    if pending >= REPORT_AUTOHIDE_THRESHOLD and target.status == 'active':
        target.status = 'flagged'
        target.hidden_reason = f'Auto-hidden after {pending} reports, pending moderator review.'
        target.save(update_fields=['status', 'hidden_reason', 'updated_at'])
        auto_hidden = True
        _notify_moderators(
            'Content auto-hidden',
            f'A {target_type} was auto-hidden after {pending} reports and needs review.')
    return Response({'reported': True, 'pending_reports': pending, 'auto_hidden': auto_hidden}, status=201)


def _notify_moderators(title, body):
    from users.models import User

    for admin in User.objects.filter(roles__panel_type='admin').distinct():
        Notification.objects.create(
            user=admin, title=title, body=body, notification_type='alert',
            reference_type='community_moderation')


# ── media upload ─────────────────────────────────────────────────────────

_MAX_IMAGE = 10 * 1024 * 1024
_MAX_VIDEO = 50 * 1024 * 1024
_MAX_DOC = 15 * 1024 * 1024

# ext -> (kind, size limit). The extension is the primary check; the browser /
# Flutter-web content-type is often generic ('application/octet-stream') so it
# can't be relied on. Magic bytes are verified for the formats that have them.
_UPLOAD_EXT = {
    'jpg': ('image', _MAX_IMAGE), 'jpeg': ('image', _MAX_IMAGE),
    'png': ('image', _MAX_IMAGE), 'webp': ('image', _MAX_IMAGE),
    'gif': ('image', _MAX_IMAGE),
    'mp4': ('video', _MAX_VIDEO), 'mov': ('video', _MAX_VIDEO),
    'pdf': ('document', _MAX_DOC),
}
_UPLOAD_MAGIC = {
    'jpg': (b'\xff\xd8\xff',), 'jpeg': (b'\xff\xd8\xff',),
    'png': (b'\x89PNG\r\n\x1a\n',), 'gif': (b'GIF87a', b'GIF89a'),
    'pdf': (b'%PDF-',),
}


def _upload_magic_ok(head, ext):
    if ext == 'webp':
        return head[:4] == b'RIFF' and head[8:12] == b'WEBP'
    sigs = _UPLOAD_MAGIC.get(ext)
    if sigs is None:
        return True  # mp4/mov — no cheap reliable signature, trust the ext
    return any(head.startswith(s) for s in sigs)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def upload(request):
    file = request.FILES.get('file') or request.FILES.get('media')
    if not file:
        return Response({'detail': 'Choose a file to upload.'}, status=400)

    ext = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''
    spec = _UPLOAD_EXT.get(ext)
    if spec is None:
        return Response(
            {'detail': 'That file type is not supported. Upload a JPG, PNG, '
                       'WebP, GIF, MP4 or PDF file.'},
            status=400)
    kind, limit = spec

    if file.size > limit:
        mb = file.size / (1024 * 1024)
        return Response(
            {'detail': f'That {kind} is {mb:.1f} MB. The limit is '
                       f'{limit // (1024 * 1024)} MB — choose a smaller file.'},
            status=400)

    head = file.read(16)
    file.seek(0)
    if not _upload_magic_ok(head, ext):
        return Response(
            {'detail': f'That file does not look like a valid {ext.upper()} '
                       f'file. Re-export it and try again.'},
            status=400)

    path = default_storage.save(
        f'community_posts/{request.user.id}/{uuid.uuid4()}.{ext}',
        ContentFile(file.read()))
    return Response({
        'media_url': request.build_absolute_uri(default_storage.url(path)),
        'url': request.build_absolute_uri(default_storage.url(path)),
        'kind': kind,
    }, status=201)


# ── notifications ────────────────────────────────────────────────────────

@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def notifications(request):
    qs = request.user.notifications.filter(
        reference_type__in=['community_post', 'community_follow', 'community_moderation'],
    ).order_by('-created_at')
    if request.method == 'PATCH':
        qs.filter(is_read=False).update(is_read=True)
        return Response({'unread_count': 0})
    rows = [{
        'id': str(n.id), 'title': n.title, 'message': n.body,
        'post_id': str(n.reference_id) if n.reference_id else None,
        'is_read': n.is_read, 'time': _ago(n.created_at),
    } for n in qs[:50]]
    return Response({'notifications': rows, 'unread_count': qs.filter(is_read=False).count()})
