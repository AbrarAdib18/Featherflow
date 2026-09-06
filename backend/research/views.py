import uuid

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from articles.models import Article
from audit.models import ActivityLog, SecurityFlag
from community.models import Bookmark
from notifications.models import Notification
from profiles.models import ResearcherProfile
from users.models import User

from .models import ArticleVersionSnapshot, ProfileChangeApplication, ResearchTag
from .permissions import (
    CONTENT_ADMIN_ROLES, VERIFIED_PROFILE_FIELDS, IsResearcher,
    has_research_subscription, is_research_content_admin, is_verified_researcher,
)
from .validation import (
    MAX_TAGS_PER_ARTICLE, check_and_increment_daily_submission, check_length,
    check_url, flagged_terms,
)

_KIND_TO_TYPE = {
    'papers': 'research_paper',
    'disease-updates': 'disease_study',
    'innovations': 'innovation',
}
_EDITABLE_STATUSES = {'draft', 'needs_revision'}
_SNAPSHOT_FIELDS = [
    'title', 'abstract', 'body', 'category', 'keywords', 'references_list',
    'farmer_summary', 'co_authors', 'content_details',
]


def _log(request, action, article_id, values=None):
    ActivityLog.objects.create(
        user=request.user, module='Research', action=action,
        entity_type='article', entity_id=article_id, new_values=values,
    )


def _notify_content_admins(title, body, reference_id=None, reference_type='article'):
    admins = User.objects.filter(roles__name__in=CONTENT_ADMIN_ROLES).distinct()
    for admin in admins:
        Notification.objects.create(
            user=admin, title=title, body=body,
            notification_type='approval', reference_id=reference_id, reference_type=reference_type,
        )


def _flag_content(request, article, terms):
    SecurityFlag.objects.create(
        module='security-flags', record_id=f'ARTICLE-{article.id}',
        payload={
            'user': request.user.full_name or request.user.email,
            'type': 'Content Abuse', 'severity': 'Medium', 'cleared': False,
            'description': f'Flagged terms in "{article.title}": {", ".join(terms)}',
            'date': timezone.now().date().isoformat(),
            'article_id': str(article.id),
        },
    )


def _snapshot(article, changed_by, note):
    ArticleVersionSnapshot.objects.create(
        article=article, version=article.version,
        snapshot={field: getattr(article, field) for field in _SNAPSHOT_FIELDS},
        changed_by=changed_by, change_note=note,
    )


def _tag_json(tag):
    return {'id': str(tag.id), 'name': tag.name, 'slug': tag.slug, 'category': tag.category}


def _profile_json(profile):
    user = profile.user
    articles = Article.objects.filter(author=user)
    published = articles.filter(status='published')
    bookmarks_count = Bookmark.objects.filter(
        target_type='article', target_id__in=published.values('id')).count()
    verification_status = (
        'suspended' if user.account_status == 'suspended'
        else ('verified' if profile.is_verified else 'pending')
    )
    contributions_qs = articles.exclude(status='draft').order_by('-created_at')
    return {
        'id': str(profile.id), 'full_name': user.full_name, 'email': user.email, 'phone': user.phone,
        'institution_name': profile.institution_name, 'institutional_email': profile.institutional_email,
        'department': profile.department, 'highest_degree': profile.highest_degree,
        'field_of_study': profile.field_of_study, 'university_name': profile.university_name,
        'graduation_year': profile.graduation_year, 'cv_url': profile.cv_url,
        'publications_portfolio_url': profile.publications_portfolio_url,
        'areas_of_expertise': profile.areas_of_expertise or [],
        'years_of_research_experience': profile.years_of_research_experience,
        'poultry_specific_experience': profile.poultry_specific_experience,
        'research_role_type': profile.research_role_type,
        'ethics_certificate_url': profile.ethics_certificate_url,
        'conflict_of_interest_declaration': profile.conflict_of_interest_declaration,
        'publication_consent': profile.publication_consent, 'ip_agreement': profile.ip_agreement,
        'reference_name': profile.reference_name, 'reference_title': profile.reference_title,
        'reference_email': profile.reference_email,
        'is_verified': bool(profile.is_verified), 'verification_status': verification_status,
        'has_premium_subscription': has_research_subscription(user),
        'verified_fields': sorted(VERIFIED_PROFILE_FIELDS),
        'fields_locked': bool(profile.is_verified),
        'stats': {
            'total_publications': published.count(),
            'drafts': articles.filter(status='draft').count(),
            'pending_review': articles.filter(status='pending_review').count(),
            'needs_revision': articles.filter(status='needs_revision').count(),
            'total_views': published.aggregate(v=Sum('read_count'))['v'] or 0,
            'total_bookmarks': bookmarks_count,
            'by_type': {
                'research_paper': articles.filter(content_type='research_paper').exclude(status='draft').count(),
                'disease_study': articles.filter(content_type='disease_study').exclude(status='draft').count(),
                'innovation': articles.filter(content_type='innovation').exclude(status='draft').count(),
            },
        },
        'contributions': [
            {
                'id': str(a.id), 'title': a.title, 'content_type': a.content_type,
                'status': a.status, 'views_count': a.read_count,
                'bookmarks_count': Bookmark.objects.filter(target_type='article', target_id=a.id).count(),
                'published_at': a.published_at, 'created_at': a.created_at,
            }
            for a in contributions_qs[:50]
        ],
    }


def _article_json(article, viewer=None):
    author = article.author
    author_profile = getattr(author, 'researcher_profile', None)
    details = article.content_details if isinstance(article.content_details, dict) else {}
    bookmarks_count = Bookmark.objects.filter(target_type='article', target_id=article.id).count()
    return {
        'id': str(article.id),
        'content_type': article.content_type,
        'title': article.title,
        'abstract': article.abstract,
        'summary': article.abstract,
        'body': article.body,
        'description': article.body,
        'category': article.category,
        'keywords': article.keywords or [],
        'tags': [_tag_json(t) for t in article.tags.all()],
        'references': article.references_list or [],
        'pdf_url': article.pdf_url,
        'farmer_summary': article.farmer_summary,
        'practical_summary': article.farmer_summary,
        'co_authors': article.co_authors or [],
        'disease_name': article.title if article.content_type == 'disease_study' else None,
        'symptoms': details.get('symptoms'),
        'treatment': details.get('treatment'),
        'prevention': details.get('prevention'),
        'source_details': details.get('source_details'),
        'media_urls': details.get('media_urls', []),
        'status': article.status,
        'version': article.version,
        'views_count': article.read_count,
        'downloads_count': 0,
        'bookmarks_count': bookmarks_count,
        'bookmarked': bool(viewer and viewer.is_authenticated and Bookmark.objects.filter(
            user=viewer, target_type='article', target_id=article.id).exists()),
        'is_featured': article.is_featured,
        'review_notes': article.review_notes,
        'published_at': article.published_at,
        'created_at': article.created_at,
        'updated_at': article.updated_at,
        'author': {
            'id': str(author.id),
            'name': author.full_name or author.email,
            'institution': author_profile.institution_name if author_profile else '',
            'is_verified': bool(author_profile and author_profile.is_verified),
        },
    }


def _extract_tags(data):
    """Returns (tag_queryset_or_None, error). Tags are optional but, when
    given, must exist and stay within MAX_TAGS_PER_ARTICLE."""
    tag_ids = data.get('tag_ids')
    if not tag_ids:
        return None, None
    if not isinstance(tag_ids, list):
        return None, 'tag_ids must be a list.'
    if len(tag_ids) > MAX_TAGS_PER_ARTICLE:
        return None, f'A maximum of {MAX_TAGS_PER_ARTICLE} tags is allowed.'
    try:
        tags = list(ResearchTag.objects.filter(id__in=tag_ids))
    except (ValueError, TypeError, DjangoValidationError):
        return None, 'One or more tag_ids are not valid UUIDs.'
    if len(tags) != len(set(tag_ids)):
        return None, 'One or more tag_ids are invalid.'
    return tags, None


def _extract_fields(kind, data):
    title = str(data.get('title') or data.get('disease_name') or '').strip()
    if not title:
        return None, 'Title is required.'
    if error := check_length('title', title):
        return None, error
    keywords = data.get('keywords') or []
    if not isinstance(keywords, list):
        keywords = [k.strip() for k in str(keywords).split(',') if k.strip()]
    co_authors = data.get('co_authors') or []
    if not isinstance(co_authors, list):
        co_authors = [c.strip() for c in str(co_authors).split(',') if c.strip()]
    fields = {
        'title': title,
        'category': data.get('category') or None,
        'keywords': keywords,
        'co_authors': co_authors,
        'farmer_summary': data.get('farmer_summary') or data.get('practical_summary') or '',
    }
    if kind == 'papers':
        abstract = str(data.get('abstract') or '').strip()
        body = str(data.get('body') or '').strip()
        if not abstract or not body:
            return None, 'Abstract and body are required for a research paper.'
        if error := (check_length('abstract', abstract) or check_length('body', body)):
            return None, error
        pdf_url = data.get('pdf_url') or None
        if error := check_url('pdf_url', pdf_url):
            return None, error
        references = data.get('references') or data.get('references_list') or []
        if not isinstance(references, list):
            references = [r.strip() for r in str(references).split(',') if r.strip()]
        fields.update({
            'abstract': abstract, 'body': body, 'references_list': references,
            'pdf_url': pdf_url, 'content_details': {},
        })
    elif kind == 'disease-updates':
        symptoms = str(data.get('symptoms') or '').strip()
        treatment = str(data.get('treatment') or '').strip()
        if not symptoms or not treatment:
            return None, 'Symptoms and treatment are required for a disease/cure update.'
        abstract = str(data.get('abstract') or symptoms)
        body = str(data.get('body') or treatment)
        if error := (check_length('abstract', abstract) or check_length('body', body)):
            return None, error
        fields.update({
            'abstract': abstract, 'body': body,
            'references_list': [], 'pdf_url': None,
            'content_details': {
                'symptoms': symptoms, 'treatment': treatment,
                'prevention': str(data.get('prevention') or ''),
            },
        })
    else:
        summary = str(data.get('summary') or data.get('abstract') or '').strip()
        description = str(data.get('description') or data.get('body') or '').strip()
        if not summary or not description:
            return None, 'Summary and description are required for an innovation post.'
        if error := (check_length('abstract', summary) or check_length('body', description)):
            return None, error
        media_urls = data.get('media_urls') or []
        if not isinstance(media_urls, list):
            media_urls = [media_urls]
        for url in media_urls:
            if error := check_url('media_urls', url):
                return None, error
        fields.update({
            'abstract': summary, 'body': description,
            'references_list': [], 'pdf_url': None,
            'content_details': {
                'source_details': str(data.get('source_details') or ''),
                'media_urls': media_urls,
            },
        })
    return fields, None


@api_view(['GET', 'PUT'])
@permission_classes([IsResearcher])
def profile(request):
    try:
        researcher_profile = request.user.researcher_profile
    except ResearcherProfile.DoesNotExist:
        return Response({'detail': 'Researcher profile not found. Complete researcher signup first.'}, status=404)
    if request.method == 'PUT':
        unlocked_editable = [
            'cv_url', 'publications_portfolio_url', 'years_of_research_experience',
            'reference_name', 'reference_title', 'reference_email',
        ]
        locked_attempted = [
            field for field in VERIFIED_PROFILE_FIELDS
            if field in request.data and researcher_profile.is_verified
        ]
        if locked_attempted:
            return Response({
                'detail': (
                    f'These fields are locked after verification: {", ".join(sorted(locked_attempted))}. '
                    'Submit a profile change application via '
                    'POST /api/research/profile/change-applications/ to request an update.'
                ),
            }, status=403)
        editable = unlocked_editable + (
            [] if researcher_profile.is_verified else sorted(VERIFIED_PROFILE_FIELDS)
        )
        for url_field in ('cv_url', 'publications_portfolio_url'):
            if url_field in request.data:
                if error := check_url(url_field, request.data[url_field]):
                    return Response({'detail': error}, status=400)
        changed = []
        for field in editable:
            if field in request.data:
                setattr(researcher_profile, field, request.data[field])
                changed.append(field)
        if changed:
            researcher_profile.save(update_fields=changed + ['updated_at'])
            _log(request, 'Update profile', researcher_profile.id, {'fields': changed})
    return Response(_profile_json(researcher_profile))


@api_view(['GET', 'POST'])
@permission_classes([IsResearcher])
def change_applications(request):
    try:
        researcher_profile = request.user.researcher_profile
    except ResearcherProfile.DoesNotExist:
        return Response({'detail': 'Researcher profile not found.'}, status=404)

    if request.method == 'GET':
        apps = ProfileChangeApplication.objects.filter(user=request.user).order_by('-created_at')
        return Response({'results': [_application_json(a) for a in apps]})

    field_name = str(request.data.get('field_name', '')).strip()
    new_value = request.data.get('new_value')
    reason = str(request.data.get('reason', '')).strip()
    if field_name not in VERIFIED_PROFILE_FIELDS:
        return Response({'detail': f'"{field_name}" is not a verified field that requires an application.'}, status=400)
    if new_value is None or str(new_value).strip() == '':
        return Response({'detail': 'new_value is required.'}, status=400)
    if not reason:
        return Response({'detail': 'A reason is required for a profile change application.'}, status=400)
    if not researcher_profile.is_verified:
        return Response({
            'detail': 'This field is still directly editable — you only need an application once your profile is verified.',
        }, status=400)
    if ProfileChangeApplication.objects.filter(
            user=request.user, field_name=field_name, status='pending').exists():
        return Response({'detail': f'You already have a pending application for "{field_name}".'}, status=409)

    old_value = getattr(researcher_profile, field_name)
    application = ProfileChangeApplication.objects.create(
        user=request.user, field_name=field_name,
        old_value='' if old_value is None else str(old_value),
        new_value=str(new_value), reason=reason,
    )
    _log(request, 'Submit profile change application', application.id, {
        'field_name': field_name, 'old_value': application.old_value, 'new_value': application.new_value,
    })
    _notify_content_admins(
        'New profile change application',
        f'{request.user.full_name or request.user.email} requested to change "{field_name}".',
        reference_id=application.id, reference_type='profile_change_application',
    )
    return Response(_application_json(application), status=201)


def _application_json(app):
    return {
        'id': str(app.id), 'user_id': str(app.user_id),
        'researcher_name': app.user.full_name or app.user.email,
        'field_name': app.field_name, 'old_value': app.old_value, 'new_value': app.new_value,
        'reason': app.reason, 'status': app.status,
        'reviewed_by': (app.reviewed_by.full_name or app.reviewed_by.email) if app.reviewed_by else None,
        'review_note': app.review_note, 'decided_at': app.decided_at, 'created_at': app.created_at,
    }


@api_view(['GET'])
@permission_classes([IsResearcher])
def tag_options(request):
    return Response({'results': [_tag_json(t) for t in ResearchTag.objects.order_by('category', 'name')]})


MAX_PDF_SIZE = 25 * 1024 * 1024


@api_view(['POST'])
@permission_classes([IsResearcher])
def upload_pdf(request):
    if not is_verified_researcher(request.user):
        return Response({'detail': 'Only verified researchers can upload a paper PDF.'}, status=403)
    if not has_research_subscription(request.user):
        return Response({
            'detail': 'An active premium subscription is required to use the Researchers Panel.',
        }, status=403)
    file = request.FILES.get('file')
    if not file:
        return Response({'detail': 'A PDF file is required.'}, status=400)
    is_pdf = str(file.content_type) == 'application/pdf' or file.name.lower().endswith('.pdf')
    if not is_pdf:
        return Response({'detail': 'Only PDF files are supported.'}, status=400)
    if file.size > MAX_PDF_SIZE:
        return Response({'detail': 'PDF must be 25 MB or smaller.'}, status=400)
    path = default_storage.save(
        f'research/papers/{request.user.id}/{uuid.uuid4()}.pdf', ContentFile(file.read()))
    return Response({'url': request.build_absolute_uri(default_storage.url(path))}, status=201)


@api_view(['GET', 'POST'])
@permission_classes([IsResearcher])
def collection(request, kind):
    content_type = _KIND_TO_TYPE.get(kind)
    if not content_type:
        return Response({'detail': 'Unknown research content type.'}, status=404)

    if request.method == 'GET':
        qs = Article.objects.filter(
            author=request.user, content_type=content_type,
        ).select_related('author').prefetch_related('tags').order_by('-updated_at')
        status_filter = request.query_params.get('status')
        if status_filter:
            qs = qs.filter(status=status_filter)
        search = request.query_params.get('search')
        if search:
            qs = qs.filter(title__icontains=search)
        return Response({'results': [_article_json(a, request.user) for a in qs]})

    if not is_verified_researcher(request.user):
        return Response({'detail': 'Only verified researchers can submit content.'}, status=403)
    if not has_research_subscription(request.user):
        return Response({
            'detail': 'An active premium subscription is required to use the Researchers Panel.',
        }, status=403)

    fields, error = _extract_fields(kind, request.data)
    if error:
        return Response({'detail': error}, status=400)
    tags, tag_error = _extract_tags(request.data)
    if tag_error:
        return Response({'detail': tag_error}, status=400)

    with transaction.atomic():
        article = Article.objects.create(
            author=request.user, content_type=content_type, status='draft', **fields,
        )
        if tags is not None:
            article.tags.set(tags)
    terms = flagged_terms(fields.get('title'), fields.get('abstract'), fields.get('body'))
    if terms:
        _flag_content(request, article, terms)
    _log(request, f'Create {content_type}', article.id, fields)
    payload = _article_json(article, request.user)
    if terms:
        payload['warning'] = (
            'Your submission contains language that may need review before publishing. '
            'It has still been saved as a draft.'
        )
    return Response(payload, status=201)


def _get_own_article(request, kind, pk):
    content_type = _KIND_TO_TYPE.get(kind)
    if not content_type:
        return None, Response({'detail': 'Unknown research content type.'}, status=404)
    try:
        article = Article.objects.select_related('author').prefetch_related('tags').get(
            pk=pk, content_type=content_type)
    except (Article.DoesNotExist, ValueError, TypeError):
        return None, Response({'detail': 'Not found.'}, status=404)
    is_owner = article.author_id == request.user.id
    if not is_owner and not is_research_content_admin(request.user) and article.status != 'published':
        return None, Response({'detail': 'Not found.'}, status=404)
    return article, None


@api_view(['GET', 'PUT', 'DELETE'])
@permission_classes([IsResearcher])
def detail(request, kind, pk):
    article, error = _get_own_article(request, kind, pk)
    if error:
        return error

    if request.method == 'GET':
        return Response(_article_json(article, request.user))

    is_owner = article.author_id == request.user.id
    if not is_owner:
        return Response({'detail': 'You may only modify your own content.'}, status=403)

    if request.method == 'DELETE':
        if article.status not in _EDITABLE_STATUSES:
            return Response({
                'detail': 'Only drafts or content needing revision can be withdrawn. '
                          'Published or submitted content must be archived by an admin.',
            }, status=409)
        article.status = 'archived'
        article.save(update_fields=['status', 'updated_at'])
        _log(request, 'Withdraw', article.id)
        return Response(status=204)

    if article.status not in _EDITABLE_STATUSES:
        return Response({'detail': 'Only drafts or content needing revision can be edited.'}, status=409)
    if not is_verified_researcher(request.user):
        return Response({'detail': 'Only verified researchers can edit content.'}, status=403)
    if not has_research_subscription(request.user):
        return Response({
            'detail': 'An active premium subscription is required to use the Researchers Panel.',
        }, status=403)

    fields, error_message = _extract_fields(kind, request.data)
    if error_message:
        return Response({'detail': error_message}, status=400)
    tags, tag_error = _extract_tags(request.data)
    if tag_error:
        return Response({'detail': tag_error}, status=400)

    with transaction.atomic():
        for name, value in fields.items():
            setattr(article, name, value)
        article.save()
        if tags is not None:
            article.tags.set(tags)
    terms = flagged_terms(fields.get('title'), fields.get('abstract'), fields.get('body'))
    if terms:
        _flag_content(request, article, terms)
    _log(request, 'Update', article.id, fields)
    payload = _article_json(article, request.user)
    if terms:
        payload['warning'] = 'Your edit contains language that may need review before publishing.'
    return Response(payload)


@api_view(['GET'])
@permission_classes([IsResearcher])
def versions(request, kind, pk):
    article, error = _get_own_article(request, kind, pk)
    if error:
        return error
    if article.author_id != request.user.id and not is_research_content_admin(request.user):
        return Response({'detail': 'You may only view version history for your own content.'}, status=403)
    snaps = article.version_snapshots.select_related('changed_by').all()
    return Response({'results': [{
        'id': str(s.id), 'version': s.version, 'snapshot': s.snapshot,
        'changed_by': (s.changed_by.full_name or s.changed_by.email) if s.changed_by else None,
        'change_note': s.change_note, 'changed_at': s.changed_at,
    } for s in snaps]})


@api_view(['POST'])
@permission_classes([IsResearcher])
def submit_review(request, kind, pk):
    article, error = _get_own_article(request, kind, pk)
    if error:
        return error
    if article.author_id != request.user.id:
        return Response({'detail': 'You may only submit your own content.'}, status=403)
    if article.status not in _EDITABLE_STATUSES:
        return Response({'detail': f'Cannot submit content from "{article.status}" for review.'}, status=409)
    if not is_verified_researcher(request.user):
        return Response({'detail': 'Only verified researchers can submit content for review.'}, status=403)
    if not has_research_subscription(request.user):
        return Response({
            'detail': 'An active premium subscription is required to use the Researchers Panel.',
        }, status=403)
    if not check_and_increment_daily_submission(request.user):
        return Response({
            'detail': 'Daily submission limit reached. Please try again tomorrow.',
        }, status=429)

    was_revision = article.status == 'needs_revision'
    article.status = 'pending_review'
    if was_revision:
        article.version += 1
    article.save(update_fields=['status', 'version', 'updated_at'])
    _snapshot(article, request.user, 'Resubmitted for review' if was_revision else 'Submitted for review')
    _log(request, 'Submit for review', article.id)
    _notify_content_admins(
        'New content submitted for review',
        f'{request.user.full_name or request.user.email} submitted "{article.title}" for review.',
        reference_id=article.id, reference_type='article',
    )
    return Response(_article_json(article, request.user))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def toggle_bookmark(request):
    content_id = request.data.get('article_id') or request.data.get('content_id')
    try:
        article = Article.objects.get(pk=content_id, status='published')
    except (Article.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Published article not found.'}, status=404)
    obj, created = Bookmark.objects.get_or_create(
        user=request.user, target_id=article.id, target_type='article')
    if not created:
        obj.delete()
    return Response({'bookmarked': created})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def bookmarks(request):
    marks = list(Bookmark.objects.filter(
        user=request.user, target_type='article').order_by('-created_at'))
    ids = [m.target_id for m in marks]
    articles = {
        a.id: a for a in Article.objects.filter(
            id__in=ids, status='published').select_related('author').prefetch_related('tags')
    }
    ordered = [articles[i] for i in ids if i in articles]
    return Response({'results': [_article_json(a, request.user) for a in ordered]})
