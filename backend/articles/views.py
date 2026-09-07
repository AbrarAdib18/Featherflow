import math

from django.db.models import Count, IntegerField, OuterRef, Q, Subquery
from django.db.models.functions import Coalesce
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from community.models import Bookmark, Report
from research.models import ResearchTag

from .models import Article

_SORT_FIELDS = {
    'latest': '-published_at',
    'most_read': '-read_count',
    'trending': '-read_count',
}
_TAG_CATEGORY_PARAMS = ('disease', 'breed', 'age_group', 'nutrition', 'market')

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50
_SUMMARY_MAX = 320

# content_type -> the "source_type" label the farmer news panel groups by.
_SOURCE_TYPE = {
    'research_paper': 'Research',
    'disease_study': 'Research',
    'feed_study': 'Research',
    'innovation': 'Innovation',
    'news': 'News',
    'market_report': 'Market',
    'team_update': 'Team FeatherFlow',
}
# Deterministic placeholder image per content_type. Routed through the
# weserv.nl image proxy so the response carries CORS headers (Flutter web /
# CanvasKit fetches images with XHR and needs `Access-Control-Allow-Origin`).
# Real images, when an author uploads one, live in
# Article.content_details['image_url'] and win over this default.
def _placeholder(seed):
    return f'https://images.weserv.nl/?url=picsum.photos/seed/{seed}/800/450&w=800&output=jpg'


_PLACEHOLDER_IMAGE = {
    'research_paper': _placeholder('ff-research'),
    'disease_study': _placeholder('ff-disease'),
    'feed_study': _placeholder('ff-feed'),
    'innovation': _placeholder('ff-innovation'),
    'news': _placeholder('ff-news'),
    'market_report': _placeholder('ff-market'),
    'team_update': _placeholder('ff-team'),
}


def _source_type(article):
    details = article.content_details or {}
    return details.get('source_type') or _SOURCE_TYPE.get(article.content_type, 'News')


def _image_url(article):
    details = article.content_details or {}
    return details.get('image_url') or _PLACEHOLDER_IMAGE.get(
        article.content_type, _placeholder('ff-article'))


def _read_minutes(article, *, body=None):
    text = body if body is not None else (article.body or '')
    words = len(text.split())
    return max(1, min(60, math.ceil(words / 200))) if words else 3


def _short(text):
    text = (text or '').strip()
    return text if len(text) <= _SUMMARY_MAX else text[: _SUMMARY_MAX - 1].rstrip() + '…'


def _author_json(author):
    profile = getattr(author, 'researcher_profile', None)
    return {
        'id': str(author.id),
        'name': author.full_name or author.email,
        'institution': profile.institution_name if profile else '',
        'is_verified': bool(profile and profile.is_verified),
    }


def _list_json(article, *, bookmark_counts, bookmarked_ids):
    """Compact list-view row — deliberately excludes the full ``body`` and other
    large blobs so a page of 20 stays small."""
    return {
        'id': str(article.id),
        'content_type': article.content_type,
        'title': article.title,
        'summary': _short(article.abstract),
        'category': article.category,
        'source_type': _source_type(article),
        'image_url': _image_url(article),
        'pdf_url': article.pdf_url,
        'keywords': (article.keywords or [])[:6],
        'read_minutes': _read_minutes(article),
        'views_count': article.read_count,
        'bookmarks_count': bookmark_counts.get(article.id, 0),
        'bookmarked': article.id in bookmarked_ids,
        'is_featured': article.is_featured,
        'published_at': article.published_at,
        'created_at': article.created_at,
        'updated_at': article.updated_at,
        'author': _author_json(article.author),
    }


def _public_json(article, viewer=None):
    """Full detail-view row — includes body, references, tags, farmer summary."""
    return {
        'id': str(article.id),
        'content_type': article.content_type,
        'title': article.title,
        'summary': article.abstract,
        'body': article.body,
        'category': article.category,
        'source_type': _source_type(article),
        'image_url': _image_url(article),
        'keywords': article.keywords or [],
        'tags': [{'id': str(t.id), 'name': t.name, 'slug': t.slug, 'category': t.category}
                 for t in article.tags.all()],
        'references': article.references_list or [],
        'pdf_url': article.pdf_url,
        'farmer_summary': article.farmer_summary,
        'co_authors': article.co_authors or [],
        'views_count': article.read_count,
        'read_minutes': _read_minutes(article),
        'bookmarks_count': Bookmark.objects.filter(target_type='article', target_id=article.id).count(),
        'bookmarked': bool(viewer and viewer.is_authenticated and Bookmark.objects.filter(
            user=viewer, target_type='article', target_id=article.id).exists()),
        'is_featured': article.is_featured,
        'published_at': article.published_at,
        'created_at': article.created_at,
        'updated_at': article.updated_at,
        'author': _author_json(article.author),
    }


def _page_params(params):
    try:
        page = max(1, int(params.get('page', 1)))
    except (TypeError, ValueError):
        page = 1
    try:
        page_size = int(params.get('page_size', DEFAULT_PAGE_SIZE))
    except (TypeError, ValueError):
        page_size = DEFAULT_PAGE_SIZE
    page_size = max(1, min(MAX_PAGE_SIZE, page_size))
    return page, page_size


@api_view(['GET'])
@permission_classes([AllowAny])
def feed(request):
    """Paginated article feed for the farmer news / research panel.

    ``GET /api/articles/all/?page=1&page_size=20&type=news&sort=latest``

    Only ``status='published'`` rows are returned. The list payload is compact
    (no ``body``); use the detail endpoint for the full article. Bookmark counts
    and the viewer's bookmark state are resolved in two batch queries for the
    whole page, not per row.
    """
    params = request.query_params
    qs = Article.objects.filter(status='published').select_related(
        'author', 'author__researcher_profile')

    content_type = params.get('type')
    if content_type:
        qs = qs.filter(content_type=content_type)

    tag = params.get('tag')
    if tag:
        qs = qs.filter(Q(tags__slug=tag) | Q(category__iexact=tag) | Q(keywords__contains=[tag]))

    for category_param in _TAG_CATEGORY_PARAMS:
        value = params.get(category_param)
        if value:
            qs = qs.filter(tags__category=category_param, tags__slug=value)

    author = params.get('author')
    if author:
        qs = qs.filter(
            Q(author__full_name__icontains=author) |
            Q(author__researcher_profile__institution_name__icontains=author)
        )

    year = params.get('year')
    if year:
        try:
            qs = qs.filter(published_at__year=int(year))
        except (TypeError, ValueError):
            return Response({'detail': 'year must be a number.'}, status=400)
    year_from = params.get('year_from')
    year_to = params.get('year_to')
    try:
        if year_from:
            qs = qs.filter(published_at__year__gte=int(year_from))
        if year_to:
            qs = qs.filter(published_at__year__lte=int(year_to))
    except (TypeError, ValueError):
        return Response({'detail': 'year_from/year_to must be numbers.'}, status=400)

    search = params.get('search')
    if search:
        qs = qs.filter(Q(title__icontains=search) | Q(abstract__icontains=search) | Q(body__icontains=search))

    if params.get('featured') in ('1', 'true', 'True'):
        qs = qs.filter(is_featured=True)

    qs = qs.distinct()

    sort = params.get('sort', 'latest')
    if sort == 'most_bookmarked':
        bookmark_count = (
            Bookmark.objects.filter(target_type='article', target_id=OuterRef('pk'))
            .order_by().values('target_id').annotate(c=Count('id')).values('c')
        )
        qs = qs.annotate(
            bm_count=Coalesce(Subquery(bookmark_count, output_field=IntegerField()), 0)
        ).order_by('-bm_count', '-published_at', '-created_at')
    else:
        qs = qs.order_by(_SORT_FIELDS.get(sort, '-published_at'), '-created_at')

    total = qs.count()
    page, page_size = _page_params(params)
    total_pages = max(1, math.ceil(total / page_size))
    start = (page - 1) * page_size
    results = list(qs.prefetch_related('tags')[start:start + page_size])

    page_ids = [a.id for a in results]
    bookmark_counts = dict(
        Bookmark.objects.filter(target_type='article', target_id__in=page_ids)
        .order_by().values_list('target_id').annotate(c=Count('id'))
    )
    bookmarked_ids = set()
    viewer = request.user if request.user.is_authenticated else None
    if viewer and page_ids:
        bookmarked_ids = set(
            Bookmark.objects.filter(
                user=viewer, target_type='article', target_id__in=page_ids
            ).values_list('target_id', flat=True)
        )

    return Response({
        'results': [
            _list_json(a, bookmark_counts=bookmark_counts, bookmarked_ids=bookmarked_ids)
            for a in results
        ],
        'count': total,
        'page': page,
        'page_size': page_size,
        'total_pages': total_pages,
        'has_next': page < total_pages,
        'has_previous': page > 1,
    })


@api_view(['GET'])
@permission_classes([AllowAny])
def detail(request, content_type, content_id):
    try:
        article = Article.objects.select_related(
            'author', 'author__researcher_profile').prefetch_related('tags').get(
            pk=content_id, content_type=content_type, status='published')
    except (Article.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Article not found.'}, status=404)
    Article.objects.filter(pk=article.id).update(read_count=article.read_count + 1)
    article.read_count += 1
    viewer = request.user if request.user.is_authenticated else None
    return Response(_public_json(article, viewer))


@api_view(['GET'])
@permission_classes([AllowAny])
def tags(request):
    rows = ResearchTag.objects.annotate(
        count=Count('articles', filter=Q(articles__status='published'), distinct=True),
    ).order_by('category', '-count', 'name')
    return Response({'results': [
        {'id': str(t.id), 'name': t.name, 'slug': t.slug, 'category': t.category, 'count': t.count}
        for t in rows
    ]})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def report_content(request):
    content_id = request.data.get('content_id') or request.data.get('article_id')
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A reason is required to report content.'}, status=400)
    try:
        Article.objects.get(pk=content_id, status='published')
    except (Article.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Published article not found.'}, status=404)
    report, created = Report.objects.get_or_create(
        reporter=request.user, target_id=content_id, target_type='article',
        status='pending', defaults={'reason': reason},
    )
    if not created:
        return Response({'detail': 'You have already reported this content.'}, status=409)
    return Response({'id': str(report.id), 'status': report.status}, status=201)
