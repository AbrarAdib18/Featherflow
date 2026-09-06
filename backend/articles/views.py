from django.db.models import Count, Q
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


def _public_json(article, viewer=None):
    author = article.author
    author_profile = getattr(author, 'researcher_profile', None)
    return {
        'id': str(article.id),
        'content_type': article.content_type,
        'title': article.title,
        'summary': article.abstract,
        'body': article.body,
        'category': article.category,
        'keywords': article.keywords or [],
        'tags': [{'id': str(t.id), 'name': t.name, 'slug': t.slug, 'category': t.category}
                 for t in article.tags.all()],
        'references': article.references_list or [],
        'pdf_url': article.pdf_url,
        'farmer_summary': article.farmer_summary,
        'co_authors': article.co_authors or [],
        'views_count': article.read_count,
        'bookmarks_count': Bookmark.objects.filter(target_type='article', target_id=article.id).count(),
        'bookmarked': bool(viewer and viewer.is_authenticated and Bookmark.objects.filter(
            user=viewer, target_type='article', target_id=article.id).exists()),
        'is_featured': article.is_featured,
        'published_at': article.published_at,
        'created_at': article.created_at,
        'author': {
            'id': str(author.id),
            'name': author.full_name or author.email,
            'institution': author_profile.institution_name if author_profile else '',
            'is_verified': bool(author_profile and author_profile.is_verified),
        },
    }


@api_view(['GET'])
@permission_classes([AllowAny])
def feed(request):
    params = request.query_params
    qs = Article.objects.filter(status='published').select_related('author').prefetch_related('tags')

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

    featured_only = params.get('featured')
    if featured_only in ('1', 'true', 'True'):
        qs = qs.filter(is_featured=True)

    qs = qs.distinct()

    sort = params.get('sort', 'latest')
    if sort == 'most_bookmarked':
        bookmark_ids = list(
            Bookmark.objects.filter(target_type='article').values('target_id')
            .annotate(count=Count('id')).order_by('-count').values_list('target_id', flat=True)
        )
        by_id = {a.id: a for a in qs}
        ordered = [by_id[i] for i in bookmark_ids if i in by_id]
        ordered += [a for a in qs if a.id not in bookmark_ids]
        results = ordered
    else:
        qs = qs.order_by(_SORT_FIELDS.get(sort, '-published_at'))
        results = list(qs)

    viewer = request.user if request.user.is_authenticated else None
    pinned = list(Article.objects.filter(status='published', content_type='team_update').order_by('-published_at')[:5])
    return Response({
        'results': [_public_json(a, viewer) for a in results],
        'pinned': [_public_json(a, viewer) for a in pinned],
        'related': [_public_json(a, viewer) for a in results[:5]] if not search and not content_type else [],
        'recent': [_public_json(a, viewer) for a in list(
            Article.objects.filter(status='published').order_by('-published_at')[:5])],
        'trending': [_public_json(a, viewer) for a in list(
            Article.objects.filter(status='published').order_by('-read_count')[:5])],
    })


@api_view(['GET'])
@permission_classes([AllowAny])
def detail(request, content_type, content_id):
    try:
        article = Article.objects.select_related('author').prefetch_related('tags').get(
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
