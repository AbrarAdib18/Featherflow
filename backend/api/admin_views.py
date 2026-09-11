import uuid
from datetime import date, datetime, timedelta

from django.contrib.auth import update_session_auth_hash
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from api.admin_rbac import (
    IsAdminUser, can_perform_action, canonical_module, requires_approval,
)
from api.admin_approvals import enqueue_approval

from articles.models import Article
from audit.models import ActivityLog, AdminPanelRecord
from community.models import Comment as CommunityComment
from community.models import CommunityMute, Post as CommunityPost, Reaction as CommunityReaction, Report
from community.permissions import active_mute as community_active_mute
from community.permissions import verified_badge as community_badge
from consultations.models import Consultation
from delivery.models import DeliveryEarning, DeliveryOrder
from notifications.models import Notification
from profiles.models import DeliveryProfile, DoctorProfile, ResearcherProfile
from research.models import ProfileChangeApplication, ResearchTag
from research.validation import check_length, check_url
from research.views import _application_json, _snapshot
from users.models import Role, User, UserRole


SEEDS = {
    'subscription-plans': [
        {'id': 'PLAN-FREE', 'name': 'Free', 'price': 0, 'currency': 'BDT', 'duration_days': None, 'scan_limit': 3, 'status': 'Active'},
        {'id': 'PLAN-BASIC', 'name': 'Monthly Basic', 'price': 299, 'currency': 'BDT', 'duration_days': 30, 'scan_limit': 50, 'status': 'Active'},
        {'id': 'PLAN-PREMIUM', 'name': 'Monthly Premium', 'price': 599, 'currency': 'BDT', 'duration_days': 30, 'scan_limit': None, 'status': 'Active'},
        {'id': 'PLAN-YEARLY', 'name': 'Yearly', 'price': 4999, 'currency': 'BDT', 'duration_days': 365, 'scan_limit': None, 'status': 'Active'},
    ],
    'diseases': [
        {'id': 'DIS-NEWCASTLE', 'name': 'Newcastle Disease', 'severity': 'Critical', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['Sudden death', 'Twisted neck', 'Breathing difficulty', 'Green diarrhea']},
        {'id': 'DIS-FOWL-POX', 'name': 'Fowl Pox', 'severity': 'Medium', 'requires_immediate_vet': False, 'status': 'Active', 'symptoms': ['Wart-like lesions', 'Reduced feed intake']},
        {'id': 'DIS-COCCIDIOSIS', 'name': 'Coccidiosis', 'severity': 'High', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['Bloody diarrhea', 'Lethargy', 'Weight loss']},
        {'id': 'DIS-AVIAN-FLU', 'name': 'Avian Influenza', 'severity': 'Critical', 'requires_immediate_vet': True, 'status': 'Active', 'symptoms': ['High mortality', 'Respiratory distress', 'Swollen head']},
        {'id': 'DIS-MAREK', 'name': "Marek Disease", 'severity': 'High', 'requires_immediate_vet': False, 'status': 'Active', 'symptoms': ['Progressive paralysis', 'Weight loss', 'Eye lesions']},
    ],
    'pharmacies': [
        {'id': 'P001', 'name': 'MedPlus Veterinary Rx', 'location': 'Rajshahi', 'status': 'Verified', 'product_count': 142, 'monthly_orders': 380, 'rating': 4.7},
        {'id': 'P002', 'name': 'AgroVet Supplies', 'location': 'Dhaka', 'status': 'Pending', 'product_count': 78, 'monthly_orders': 0, 'rating': 0.0},
        {'id': 'P003', 'name': 'PoultryMed Store', 'location': 'Chittagong', 'status': 'Verified', 'product_count': 94, 'monthly_orders': 210, 'rating': 4.4},
    ],
    'medicines': [
        {'id': 'M001', 'name': 'Oxytetracycline 20%', 'pharmacy': 'MedPlus Veterinary Rx', 'status': 'Approved', 'price': 420, 'expires_in_days': 90},
        {'id': 'M002', 'name': 'Newcastle Vaccine', 'pharmacy': 'MedPlus Veterinary Rx', 'status': 'Pending', 'price': 680, 'expires_in_days': 25},
        {'id': 'M003', 'name': 'Vitamin AD3E Supplement', 'pharmacy': 'PoultryMed Store', 'status': 'Approved', 'price': 290, 'expires_in_days': 180},
        {'id': 'M004', 'name': 'Coccidiostat Premix', 'pharmacy': 'PoultryMed Store', 'status': 'Approved', 'price': 550, 'expires_in_days': 18},
    ],
}


_ACTION_TYPE_HINTS = {
    'create': 'create', 'add': 'create', 'update': 'edit', 'edit': 'edit',
    'delete': 'delete', 'remove': 'delete', 'approve': 'approve', 'verify': 'approve',
    'publish': 'approve', 'reject': 'reject', 'request_revision': 'reject',
    'hide': 'reject', 'suspend': 'suspend', 'deactivate': 'suspend',
    'assign': 'assign', 'reassign': 'assign', 'export': 'export',
    'refund': 'refund', 'mark_paid': 'refund', 'override': 'override',
}


def _infer_action_type(action):
    lowered = (action or '').lower()
    for needle, kind in _ACTION_TYPE_HINTS.items():
        if needle in lowered:
            return kind
    return 'edit'


# Action verb the RBAC layer should check for a given request. Callers may pass
# an explicit ``action`` in the body ("approve"/"reject"/"suspend"/...).
_REQUEST_ACTION = {'GET': 'view', 'POST': 'create', 'PATCH': 'edit', 'DELETE': 'delete'}
_BODY_ACTION_TO_PERMISSION = {
    'approve': 'approve', 'verify': 'approve', 'publish': 'approve',
    'mark_paid': 'refund', 'reject': 'reject', 'dismiss': 'reject',
    'request_revision': 'reject', 'remove': 'delete', 'hide': 'edit', 'unhide': 'edit',
    'mute': 'suspend', 'unmute': 'edit',
    'suspend': 'suspend', 'deactivate': 'suspend', 'assign': 'assign',
    'reassign': 'assign', 'cancel': 'edit', 'adjust_stock': 'edit', 'refund': 'refund',
    # Support-desk verbs are day-to-day "edit" work, not an approval gate.
    'resolve': 'edit', 'reply': 'edit', 'escalate': 'edit',
}


def _resolve_action(request):
    body_action = request.data.get('action') if request.method in ('POST', 'PATCH') else None
    if body_action and body_action in _BODY_ACTION_TO_PERMISSION:
        return _BODY_ACTION_TO_PERMISSION[body_action]
    status_value = str(request.data.get('status', '')).lower() if request.method == 'PATCH' else ''
    if status_value in ('suspended', 'inactive'):
        return 'suspend'
    if status_value in ('approved', 'verified', 'published'):
        return 'approve'
    if status_value == 'refunded' or body_action == 'refund':
        return 'refund'
    return _REQUEST_ACTION.get(request.method, 'view')


def _gate(request, module):
    """RBAC chokepoint for the generic collection/record endpoints. Returns a
    403 ``Response`` when the caller lacks the permission, otherwise ``None``."""
    action = _resolve_action(request)
    if not can_perform_action(request.user, module, action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the '
                       f'"{canonical_module(module)}" module.',
             'code': 'forbidden_module_action'},
            status=403,
        )
    return None


def _target_is_verified(module, record_id):
    key = canonical_module(module)
    try:
        if key in ('users',) or module == 'pharmacies':
            return User.objects.filter(pk=record_id, is_verified=True).exists()
        if module == 'doctors':
            return DoctorProfile.objects.filter(pk=record_id, is_verified=True).exists()
        if module == 'researchers':
            return ResearcherProfile.objects.filter(pk=record_id, is_verified=True).exists()
        if module == 'riders':
            return DeliveryProfile.objects.filter(pk=record_id, approved_by_admin__isnull=False).exists()
    except (ValueError, TypeError):
        return False
    return False


def _lookup_amount(module, record_id):
    rid = str(record_id)
    if module == 'payouts' or rid.startswith('payout:'):
        earning = DeliveryEarning.objects.filter(pk=rid.split(':', 1)[-1]).first()
        return float(earning.total_earned) if earning else 0
    if rid.startswith('sub:'):
        from subscriptions.models import Subscription
        sub = Subscription.objects.select_related('plan').filter(pk=rid.split(':', 1)[1]).first()
        return float(sub.plan.price) if sub and sub.plan_id else 0
    if module == 'payments':
        try:
            from payments.models import Payment
            payment = Payment.objects.filter(pk=rid).first()
            return float(payment.amount) if payment else 0
        except Exception:
            return 0
    record = AdminPanelRecord.objects.filter(module=module, record_id=rid).first()
    return float(record.payload.get('amount', 0)) if record else 0


def _maybe_enqueue(request, module, record_id):
    """When a sensitive action outranks the caller's tier, park it in the
    approval queue and return a 202 response; otherwise return ``None``."""
    action = _resolve_action(request)
    if action not in ('suspend', 'refund', 'delete', 'assign', 'override'):
        return None
    key = canonical_module(module)
    context = {}
    if action == 'suspend':
        context['target_verified'] = _target_is_verified(module, record_id)
    elif action == 'refund':
        context['amount'] = request.data.get('amount') or _lookup_amount(module, record_id)
    elif action == 'delete' and key in ('team', 'users'):
        context['target_is_admin'] = User.objects.filter(
            pk=record_id, roles__panel_type='admin').exists() if _uuid_or_none(record_id) else False
    elif action == 'assign' and key == 'team':
        context['is_role_change'] = 'role' in request.data
    needed = requires_approval(request.user, module, action, context)
    if needed is None:
        return None
    entry = enqueue_approval(
        request, action_type=action, module=module, target_id=record_id,
        target_type=key, request_data=dict(request.data), required_tier=needed,
    )
    return Response({
        'detail': 'This action needs approval from a higher-tier admin. It has been queued.',
        'code': 'approval_required', 'approval_id': str(entry.id),
        'required_tier': needed, 'status': 'pending',
    }, status=202)


def _client_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    return (forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR'))


def _uuid_or_none(value):
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        return None


def _log(request, module, action, record_id='', old=None, new=None,
         action_type=None, reason=''):
    if not reason:
        try:
            reason = str(request.data.get('reason', '')) if request.method != 'GET' else ''
        except (AttributeError, TypeError):
            reason = ''
    ActivityLog.objects.create(
        user=request.user,
        module=module,
        action=action,
        action_type=action_type or _infer_action_type(action),
        entity_type=module,
        entity_id=_uuid_or_none(record_id),
        old_values=old,
        new_values=new,
        reason=reason or None,
        ip_address=_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


def _seed(module):
    if module not in SEEDS:
        return
    with transaction.atomic():
        for item in SEEDS[module]:
            record, created = AdminPanelRecord.objects.get_or_create(
                module=module, record_id=item['id'], defaults={'payload': item}
            )
            if not created:
                merged = {**item, **record.payload}
                if merged != record.payload:
                    record.payload = merged
                    record.save(update_fields=['payload', 'updated_at'])


def _records(module):
    _seed(module)
    return [record.payload for record in AdminPanelRecord.objects.filter(module=module)]


def _user_json(user):
    roles = list(user.roles.values_list('name', flat=True))
    role = roles[0].replace('_', ' ').title() if roles else ('Staff' if user.is_staff else 'Farmer')
    if role.startswith('Admin'):
        role = 'Staff'
    status = {'active': 'Approved', 'pending': 'Pending', 'suspended': 'Suspended'}.get(user.account_status.lower(), user.account_status.title())
    return {
        'id': str(user.id), 'name': user.full_name or user.email.split('@')[0],
        'email': user.email, 'phone': user.phone or '', 'role': role,
        'status': status, 'location': user.present_address or user.location_service_area or 'Bangladesh',
        'joined': user.date_joined.strftime('%b %d, %Y') if user.date_joined else '',
        'last_active': user.last_login.strftime('%b %d, %Y %H:%M') if user.last_login else 'Never',
        'verified': user.is_verified, 'bio': user.profile_data.get('bio', '') if isinstance(user.profile_data, dict) else '',
        'two_factor_enabled': user.two_factor_enabled,
    }


def _doctor_json(profile):
    from consultations.metrics import dispute_counts, response_time_stats

    status = (
        profile.user.account_status.title()
        if profile.user.account_status in ['suspended', 'rejected']
        else ('Verified' if profile.is_verified else 'Pending')
    )
    rt = response_time_stats(profile.user)
    disputes = dispute_counts(profile.user)
    return {
        'id': str(profile.id), 'name': profile.user.full_name or profile.user.email,
        'specialty': profile.specialty, 'status': status,
        'rating': float(profile.rating), 'consultations': profile.user.doctor_consultations.count(),
        'response_time': f"~{rt['avg_minutes']:.0f} min" if rt['avg_minutes'] is not None else (
            'No data yet' if profile.is_available else 'Unavailable'),
        'avg_response_minutes': rt['avg_minutes'],
        'pending_requests': rt['pending_requests'],
        'open_disputes': disputes['open'],
        'total_disputes': disputes['total'],
        'license_doc': profile.license_number,
        'clinic_name': profile.clinic_hospital_name,
        'practice_address': profile.practice_address,
        'district': profile.practice_address,
        'degree': profile.veterinary_degree,
        'university': profile.university_name,
        'graduation_year': profile.graduation_year,
        'license_authority': profile.license_issuing_authority,
        'license_expiry': profile.license_expiry_date.isoformat(),
        'focus_area': profile.poultry_focus_area,
        'years_experience': profile.years_of_experience,
        'consultation_mode': profile.consultation_mode,
        'service_fee': float(profile.service_fee or 0),
    }


def _team_json(user):
    role = user.roles.filter(name__startswith='admin_').first()
    profile = user.profile_data if isinstance(user.profile_data, dict) else {}
    return {
        'id': str(user.id),
        'name': user.full_name or user.email,
        'email': user.email,
        'role': (role.display_name or role.name.replace('_', ' ').title()) if role else 'Support Agent',
        'department': profile.get('department', 'Operations'),
        'status': 'Active' if user.account_status == 'active' else 'Inactive',
        'joined_date': user.date_joined.strftime('%b %Y') if user.date_joined else '',
        'last_active': user.last_login.strftime('%b %d, %H:%M') if user.last_login else 'Never',
        'pending_approval': profile.get('pending_approval', False),
    }


def _pharmacy_json(user):
    profile = user.profile_data if isinstance(user.profile_data, dict) else {}
    owner = str(user.id)
    products = AdminPanelRecord.objects.filter(module='pharmacy-products', payload__owner_id=owner).count()
    orders = AdminPanelRecord.objects.filter(module='pharmacy-orders', payload__owner_id=owner).count()
    status = {'active': 'Verified', 'pending': 'Pending', 'suspended': 'Suspended'}.get(user.account_status, user.account_status.title())
    return {
        'id': owner,
        'name': profile.get('business_name') or profile.get('organization_name') or user.full_name or user.email,
        'location': profile.get('business_address') or profile.get('service_area') or user.present_address or 'Bangladesh',
        'status': status, 'product_count': products, 'monthly_orders': orders,
        'rating': float(profile.get('rating', 0)),
    }


def _is_delivery_ops_admin(user):
    # Anyone the RBAC matrix lets manage the delivery module. Kept as a helper
    # so the delivery sub-branches read cleanly; no hard-coded role names (that
    # mismatch is what previously 403'd a delivery admin trying to assign).
    return can_perform_action(user, 'delivery', 'assign') or \
        can_perform_action(user, 'delivery', 'edit')


def parse_admin_date(value):
    """Parses the 'Jun 10, 2024' style date the admin content editor sends
    back (matches the format _article_admin_json emits)."""
    try:
        parsed = datetime.strptime(str(value).strip(), '%b %d, %Y')
        return timezone.make_aware(parsed)
    except (ValueError, TypeError):
        return None


def _is_research_content_admin(user):
    return any(
        can_perform_action(user, module, action)
        for module in ('research', 'articles')
        for action in ('edit', 'approve', 'create')
    )


_ARTICLE_MODULE_TO_TYPE = {
    'research-papers': 'research_paper', 'disease-updates': 'disease_study', 'innovations': 'innovation',
    'team-updates': 'team_update',
}
_ARTICLE_STATUS_TO_LABEL = {
    'draft': 'Draft', 'pending_review': 'Pending', 'needs_revision': 'Hidden',
    'published': 'Published', 'archived': 'Removed',
}
_ARTICLE_LABEL_TO_STATUS = {label: status for status, label in _ARTICLE_STATUS_TO_LABEL.items()}
_ARTICLE_TYPE_TO_LABEL = {
    'research_paper': 'Research', 'news': 'News', 'innovation': 'Innovation',
    'disease_study': 'Disease Study', 'feed_study': 'Feed Study',
    'market_report': 'Market Report', 'team_update': 'Team Update',
}
_ARTICLE_LABEL_TO_TYPE = {label: value for value, label in _ARTICLE_TYPE_TO_LABEL.items()}


def _article_admin_json(article):
    when = article.published_at or article.created_at
    return {
        'id': str(article.id),
        'title': article.title,
        'author': article.author.full_name or article.author.email,
        'author_id': str(article.author_id),
        'type': _ARTICLE_TYPE_TO_LABEL.get(article.content_type, 'Article'),
        'status': _ARTICLE_STATUS_TO_LABEL.get(article.status, article.status.title()),
        'date': when.strftime('%b %d, %Y') if when else '',
        'summary': article.abstract,
        'featured': article.is_featured,
        'review_notes': article.review_notes or '',
        'views_count': article.read_count,
    }


def _researcher_admin_json(profile):
    user = profile.user
    status = (
        'Suspended' if user.account_status == 'suspended'
        else ('Verified' if profile.is_verified else 'Pending')
    )
    return {
        'id': str(profile.id), 'user_id': str(user.id),
        'name': user.full_name or user.email, 'email': user.email,
        'institution': profile.institution_name, 'department': profile.department,
        'field_of_study': profile.field_of_study, 'research_role_type': profile.research_role_type,
        'years_of_research_experience': profile.years_of_research_experience,
        'cv_url': profile.cv_url, 'status': status,
        'publications': Article.objects.filter(author=user, status='published').count(),
        'joined': user.date_joined.strftime('%b %d, %Y') if user.date_joined else '',
    }


def _consultation_dispute_json(d):
    c = d.consultation
    return {
        'id': str(d.id),
        'consultation_id': str(d.consultation_id),
        'raised_by': d.raised_by.full_name or d.raised_by.email,
        'raised_by_role': d.raised_role,
        'farmer': c.farmer.full_name or c.farmer.email,
        'doctor': c.doctor.full_name or c.doctor.email,
        'doctor_id': str(c.doctor_id),
        'consultation_status': c.status,
        'appointment': f'{c.appointment_date} {c.appointment_time:%H:%M}',
        'category': d.category,
        'description': d.description,
        'status': d.status,
        'resolution': d.resolution,
        'reviewed_by': (d.reviewed_by.full_name or d.reviewed_by.email) if d.reviewed_by else None,
        'created_at': d.created_at.isoformat() if d.created_at else None,
        'resolved_at': d.resolved_at.isoformat() if d.resolved_at else None,
    }


def _report_admin_json(report):
    article = Article.objects.filter(pk=report.target_id).first() if report.target_type == 'article' else None
    return {
        'id': str(report.id),
        'reporter': report.reporter.full_name or report.reporter.email,
        'target_id': str(report.target_id), 'target_type': report.target_type,
        'article_title': article.title if article else None,
        'reason': report.reason, 'status': report.status,
        'reviewed_by': (report.reviewed_by.full_name or report.reviewed_by.email) if report.reviewed_by else None,
        'created_at': report.created_at.isoformat() if report.created_at else None,
    }


_COMMUNITY_REPORT_STATUS = {'pending': 'Open', 'reviewed': 'Dismissed', 'resolved': 'Resolved'}


def _community_target(report):
    model = CommunityPost if report.target_type == 'post' else CommunityComment
    return model.objects.select_related('author').filter(pk=report.target_id).first()


def _community_report_json(report):
    target = _community_target(report)
    author = target.author if target else None
    post_id = None
    if target is not None:
        post_id = target.id if report.target_type == 'post' else target.post_id
    text = ''
    if target is not None:
        text = (target.title or target.content) if report.target_type == 'post' else target.content
    pending = Report.objects.filter(
        target_id=report.target_id, target_type=report.target_type, status='pending').count()
    return {
        'id': str(report.id),
        'target_type': report.target_type,
        'target_id': str(report.target_id),
        'post_id': str(post_id) if post_id else None,
        'post_title': (text or '')[:120],
        'excerpt': (text or '')[:240],
        'author': 'Anonymous Farmer' if (target and target.is_anonymous) else (
            (author.full_name or author.email) if author else 'Unknown'),
        'author_id': str(author.id) if author else None,
        'is_anonymous': bool(target.is_anonymous) if target is not None else False,
        'reason': report.reason,
        'type': report.reason,
        'reporter': report.reporter.full_name or report.reporter.email,
        'status': _COMMUNITY_REPORT_STATUS.get(report.status, report.status.title()),
        'report_count': pending,
        'content_status': target.status if target is not None else 'removed',
        'reviewed_by': (report.reviewed_by.full_name or report.reviewed_by.email) if report.reviewed_by else None,
        'date': report.created_at.strftime('%b %d, %Y') if report.created_at else '',
        'created_at': report.created_at.isoformat() if report.created_at else None,
    }


def _community_user_json(user):
    posts = CommunityPost.objects.filter(author=user).exclude(status='removed')
    helpful = CommunityReaction.objects.filter(
        target_type='post', target_id__in=posts.values('id')).count()
    reports_against = Report.objects.filter(
        target_type='post', target_id__in=posts.values('id')).count()
    mute = community_active_mute(user)
    badge = community_badge(user)
    return {
        'id': str(user.id),
        'name': user.full_name or user.email,
        'role': user.role_names[0].replace('_', ' ').title() if user.role_names else 'Farmer',
        'posts': posts.count(),
        'helpful': helpful,
        'reports_against': reports_against,
        'muted': mute is not None,
        'mute_reason': mute.reason if mute else None,
        'verified': bool(user.is_verified),
        'badge': badge['label'] if badge else None,
    }


def _rider_json(profile):
    active = DeliveryOrder.objects.filter(
        delivery_person=profile, status__in=['pending', 'accepted', 'picked_up', 'on_the_way'],
    ).count()
    return {
        'id': str(profile.id),
        'name': profile.user.full_name or profile.user.email,
        'phone': profile.user.phone or '',
        'zone': profile.area_coverage or '',
        'status': 'Online' if profile.is_online else (profile.current_status or 'offline').replace('_', ' ').title(),
        'rating': float(profile.rating or 0),
        'active_orders': active,
        'completed_orders': profile.total_deliveries or 0,
        'approved': profile.approved_by_admin_id is not None,
        'current_lat': float(profile.current_lat) if profile.current_lat is not None else None,
        'current_lng': float(profile.current_lng) if profile.current_lng is not None else None,
        'location_updated_at': profile.location_updated_at.isoformat() if profile.location_updated_at else None,
    }


def _queue_admin_json(record):
    payload = record.payload
    return {
        'id': record.record_id,
        'customer': payload.get('customer', ''),
        'destination': payload.get('delivery_address', ''),
        'items': f"{len(payload.get('items', []))} item(s)",
        'status': 'Pending', 'eta': 'Awaiting assignment',
        'assigned_rider': None, 'assigned_rider_id': None, 'is_queue': True,
    }


_ADMIN_STATUS_LABELS = {
    'pending': 'Assigned', 'accepted': 'Accepted', 'picked_up': 'Picked Up',
    'on_the_way': 'In Transit', 'delivered': 'Delivered',
    'failed': 'Failed', 'rejected': 'Failed', 'cancelled': 'Cancelled',
}


def _order_admin_json(order):
    source = AdminPanelRecord.objects.filter(module='pharmacy-orders', id=order.order_reference_id).first()
    payload = source.payload if source else {}
    history = [{
        'rider': h.delivery_person.user.full_name or h.delivery_person.user.email,
        'status': _ADMIN_STATUS_LABELS.get(h.status, h.status.title()),
        'at': h.assigned_at.isoformat() if h.assigned_at else None,
    } for h in DeliveryOrder.objects.select_related('delivery_person__user').filter(
        order_reference_id=order.order_reference_id,
    ).exclude(pk=order.pk).order_by('-assigned_at')]
    return {
        'id': str(order.id),
        'customer': payload.get('farmer_name', ''),
        'destination': order.delivery_address,
        'items': f"{len(payload.get('items', []))} item(s)",
        'status': _ADMIN_STATUS_LABELS.get(order.status, order.status.title()),
        'eta': '—',
        'assigned_rider': order.delivery_person.user.full_name or order.delivery_person.user.email,
        'assigned_rider_id': str(order.delivery_person_id),
        'is_queue': False,
        'notes': order.notes or '',
        'is_cold_chain': order.is_cold_chain,
        'is_prescription_required': order.is_prescription_required,
        'history': history,
    }


def _payout_json(earning):
    return {
        'id': str(earning.id),
        'rider_id': str(earning.delivery_person_id),
        'rider_name': earning.delivery_person.user.full_name or earning.delivery_person.user.email,
        'amount': float(earning.total_earned),
        'payout_status': earning.payout_status,
        'payout_date': earning.payout_date.isoformat() if earning.payout_date else None,
        'created_at': earning.created_at.isoformat() if earning.created_at else None,
    }


def _assign_from_queue(request, queue_record_id, rider_id, notes=''):
    with transaction.atomic():
        try:
            queue_entry = AdminPanelRecord.objects.select_for_update().get(
                module='delivery-queue', record_id=queue_record_id)
        except AdminPanelRecord.DoesNotExist:
            return Response({'detail': 'This delivery request is no longer available.'}, status=404)
        try:
            rider = DeliveryProfile.objects.select_related('user').get(pk=rider_id)
        except (DeliveryProfile.DoesNotExist, ValueError, TypeError):
            return Response({'detail': 'Rider not found.'}, status=404)
        if rider.approved_by_admin_id is None:
            return Response({'detail': 'This rider has not been approved yet.'}, status=409)
        payload = queue_entry.payload
        default_notes = f"Order for {payload.get('customer', 'customer')}"
        order = DeliveryOrder.objects.create(
            delivery_person=rider,
            order_reference_id=uuid.UUID(payload['pharmacy_order_record_id']),
            order_type='medicine',
            pickup_address=payload.get('pickup_address', ''),
            delivery_address=payload.get('delivery_address', ''),
            status='pending',
            otp_code=payload.get('otp_code'),
            is_pharmacy_delivery=True,
            is_cold_chain=bool(payload.get('is_cold_chain', False)),
            is_prescription_required=bool(payload.get('is_prescription_required', False)),
            notes=f'{default_notes} — {notes}' if notes else default_notes,
            assigned_at=timezone.now(),
            created_at=timezone.now(),
        )
        queue_entry.delete()
        source = AdminPanelRecord.objects.filter(
            module='pharmacy-orders', id=uuid.UUID(payload['pharmacy_order_record_id'])).first()
        if source:
            source.payload = {**source.payload, 'delivery_order_id': str(order.id)}
            source.save(update_fields=['payload', 'updated_at'])
        Notification.objects.create(
            user=rider.user, title='New delivery assignment',
            body=f'You were assigned a delivery for {payload.get("customer", "a customer")}.',
            notification_type='alert', reference_id=order.id, reference_type='delivery_order',
        )
    _log(request, 'delivery-orders', 'Assign', str(order.id), new=_order_admin_json(order))
    return Response(_order_admin_json(order), status=201)


def _reassign_order(request, order_id, rider_id, reason, notes=''):
    with transaction.atomic():
        try:
            current = DeliveryOrder.objects.select_for_update().get(pk=order_id)
        except (DeliveryOrder.DoesNotExist, ValueError):
            return Response({'detail': 'Delivery order not found.'}, status=404)
        if current.status in ('delivered', 'cancelled'):
            return Response({'detail': f'Cannot reassign a delivery that is already {current.status}.'}, status=409)
        try:
            rider = DeliveryProfile.objects.select_related('user').get(pk=rider_id)
        except (DeliveryProfile.DoesNotExist, ValueError, TypeError):
            return Response({'detail': 'Rider not found.'}, status=404)
        if rider.approved_by_admin_id is None:
            return Response({'detail': 'This rider has not been approved yet.'}, status=409)
        previous_rider = current.delivery_person
        current.status = 'cancelled'
        current.failure_reason = f'Reassigned by admin: {reason}' if reason else 'Reassigned by admin.'
        current.save(update_fields=['status', 'failure_reason'])
        new_order = DeliveryOrder.objects.create(
            delivery_person=rider, order_reference_id=current.order_reference_id,
            order_type=current.order_type, pickup_address=current.pickup_address,
            delivery_address=current.delivery_address, pickup_lat=current.pickup_lat,
            pickup_lng=current.pickup_lng, delivery_lat=current.delivery_lat,
            delivery_lng=current.delivery_lng, status='pending', otp_code=current.otp_code,
            is_pharmacy_delivery=current.is_pharmacy_delivery, is_cold_chain=current.is_cold_chain,
            is_prescription_required=current.is_prescription_required,
            notes=f'{current.notes} — {notes}' if notes else current.notes,
            assigned_at=timezone.now(), created_at=timezone.now(),
        )
        Notification.objects.create(
            user=rider.user, title='New delivery assignment',
            body='You were assigned a delivery reassigned from another rider.',
            notification_type='alert', reference_id=new_order.id, reference_type='delivery_order',
        )
        if previous_rider_id := previous_rider.user_id:
            Notification.objects.create(
                user_id=previous_rider_id, title='Delivery reassigned',
                body='A delivery you had was reassigned to another rider.',
                notification_type='system', reference_id=current.id, reference_type='delivery_order',
            )
    _log(request, 'delivery-orders', 'Reassign', str(new_order.id), old={'previous_order': str(current.id)}, new=_order_admin_json(new_order))
    return Response(_order_admin_json(new_order))


def _cancel_order(request, order_id, reason):
    with transaction.atomic():
        try:
            order = DeliveryOrder.objects.select_for_update().get(pk=order_id)
        except (DeliveryOrder.DoesNotExist, ValueError):
            return Response({'detail': 'Delivery order not found.'}, status=404)
        if order.status in ('delivered', 'cancelled'):
            return Response({'detail': f'Cannot cancel a delivery that is already {order.status}.'}, status=409)
        order.status = 'cancelled'
        order.failure_reason = reason or 'Cancelled by admin.'
        order.save(update_fields=['status', 'failure_reason'])
        Notification.objects.create(
            user_id=order.delivery_person.user_id, title='Delivery cancelled',
            body='An assignment was cancelled by an administrator.',
            notification_type='system', reference_id=order.id, reference_type='delivery_order',
        )
        source = AdminPanelRecord.objects.filter(module='pharmacy-orders', id=order.order_reference_id).first()
        if source and source.payload.get('farmer_id'):
            try:
                Notification.objects.create(
                    user_id=source.payload['farmer_id'], title='Delivery cancelled',
                    body=f'{source.payload.get("order_number", "Your delivery")} was cancelled by an administrator.',
                    notification_type='system', reference_type='pharmacy_order',
                )
            except (ValueError, TypeError):
                pass
    _log(request, 'delivery-orders', 'Cancel', str(order.id), new=_order_admin_json(order))
    return Response(_order_admin_json(order))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_dashboard(request):
    from audit.models import AdminApprovalQueue, AdminEscalation, SupportTicket
    from profiles.models import AdminProfile

    pending_users = User.objects.filter(account_status='pending').count()
    pending_doctors = DoctorProfile.objects.filter(is_verified=False).count()
    pending_researchers = ResearcherProfile.objects.filter(is_verified=False).count()
    pending_content = Article.objects.filter(status='pending_review').count()
    open_tickets = SupportTicket.objects.filter(status__in=['open', 'in_progress', 'escalated']).count()
    pending_approvals_queue = AdminApprovalQueue.objects.filter(status='pending').count()
    open_escalations = AdminEscalation.objects.exclude(status='resolved').count()
    pending_admin_regs = AdminProfile.objects.filter(approval_status='pending').count()

    from subscriptions.models import Subscription
    monthly_revenue = float(
        Subscription.objects.filter(status='active')
        .aggregate(v=Sum('plan__price'))['v'] or 0
    )

    stats = {
        'total_users': User.objects.count(),
        'active_doctors': DoctorProfile.objects.filter(is_verified=True).count(),
        'pending_approvals': pending_users + pending_doctors + pending_researchers,
        'open_tickets': open_tickets,
        'monthly_revenue': monthly_revenue,
        'flagged_content': Report.objects.filter(
            target_type__in=['post', 'comment'], status='pending').count() + pending_content,
        'deliveries_in_progress': DeliveryOrder.objects.filter(status__in=['pending', 'accepted', 'picked_up', 'on_the_way']).count(),
        'active_pharmacies': sum(1 for x in _records('pharmacies') if x['status'] == 'Verified'),
        'pending_pharmacies': sum(1 for x in _records('pharmacies') if x['status'] == 'Pending'),
        'urgent_consultations': Consultation.objects.filter(urgency_level__in=['urgent', 'emergency']).exclude(status__in=['completed', 'cancelled']).count(),
        'active_researchers': ResearcherProfile.objects.filter(is_verified=True).count(),
        'pending_researchers': pending_researchers,
        'pending_content_review': pending_content,
        'pending_approval_requests': pending_approvals_queue,
        'open_escalations': open_escalations,
        'pending_admin_registrations': pending_admin_regs,
    }
    tasks = [
        {'title': 'User approvals', 'count': pending_users, 'module': 'User Management'},
        {'title': 'Doctor verification', 'count': pending_doctors, 'module': 'Doctor & Patient'},
        {'title': 'Researcher verification', 'count': pending_researchers, 'module': 'Research & Articles'},
        {'title': 'Content pending review', 'count': pending_content, 'module': 'Research & Articles'},
        {'title': 'Open support tickets', 'count': open_tickets, 'module': 'Support & Safety'},
        {'title': 'Actions awaiting approval', 'count': pending_approvals_queue, 'module': 'Approvals'},
        {'title': 'Open escalations', 'count': open_escalations, 'module': 'Escalations'},
    ]
    return Response({
        'stats': stats,
        'tasks': [t for t in tasks if t['count'] or t['module'] in ('Approvals', 'Escalations')],
        'activity': list(ActivityLog.objects.values(
            'module', 'action', 'action_type', 'entity_id', 'created_at')[:12]),
    })


def _collection_rows(request, module):
    """The list payload for an admin module (also reused by CSV export)."""
    if module == 'users':
        return [_user_json(u) for u in User.objects.prefetch_related('roles').all()]
    if module == 'doctors':
        return [_doctor_json(p) for p in DoctorProfile.objects.select_related('user').all()]
    if module == 'team':
        members = User.objects.filter(roles__name__startswith='admin_').prefetch_related('roles').distinct()
        return [_team_json(user) for user in members]
    if module == 'pharmacies':
        return [_pharmacy_json(user) for user in User.objects.filter(roles__name='pharmacy').distinct()]
    if module == 'consultations':
        return [{
            'id': str(c.id), 'patient': c.farmer.full_name or c.farmer.email,
            'doctor': c.doctor.full_name or c.doctor.email,
            'topic': c.review_text or c.urgency_level.title(),
            'time': f'{c.appointment_date} {c.appointment_time:%H:%M}',
            'urgent': c.urgency_level in ['urgent', 'emergency'], 'status': c.status,
        } for c in Consultation.objects.select_related('farmer', 'doctor')]
    if module == 'access-logs':
        return list(ActivityLog.objects.values(
            'id', 'module', 'action', 'action_type', 'entity_id', 'created_at')[:100])
    if module == 'riders':
        return [_rider_json(p) for p in DeliveryProfile.objects.select_related('user').order_by('-created_at')]
    if module == 'delivery-orders':
        queue_rows = [_queue_admin_json(r) for r in AdminPanelRecord.objects.filter(module='delivery-queue').order_by('-created_at')]
        order_rows = [_order_admin_json(o) for o in DeliveryOrder.objects.select_related('delivery_person__user').order_by('-created_at')]
        return queue_rows + order_rows
    if module == 'payouts':
        earnings = DeliveryEarning.objects.select_related('delivery_person__user').filter(
            payout_status='pending').order_by('delivery_person', '-created_at')
        return [_payout_json(e) for e in earnings]
    if module == 'researchers':
        return [_researcher_admin_json(p) for p in ResearcherProfile.objects.select_related('user').order_by('-created_at')]
    if module in ('articles', 'research-papers', 'disease-updates', 'innovations', 'team-updates'):
        articles = Article.objects.select_related('author').exclude(status='draft')
        content_type = _ARTICLE_MODULE_TO_TYPE.get(module)
        if content_type:
            articles = articles.filter(content_type=content_type)
        return [_article_admin_json(a) for a in articles.order_by('-created_at')]
    if module == 'profile-change-applications':
        apps = ProfileChangeApplication.objects.select_related('user', 'reviewed_by').order_by(
            request.query_params.get('order', '-created_at'))
        status_filter = request.query_params.get('status')
        if status_filter:
            apps = apps.filter(status=status_filter)
        return [_application_json(a) for a in apps]
    if module == 'content-reports':
        reports = Report.objects.select_related('reporter', 'reviewed_by').filter(
            target_type='article').order_by('-created_at')
        status_filter = request.query_params.get('status')
        if status_filter:
            reports = reports.filter(status=status_filter)
        return [_report_admin_json(r) for r in reports]
    if module == 'consultation-disputes':
        from consultations.models import ConsultationDispute

        rows = ConsultationDispute.objects.select_related(
            'consultation__farmer', 'consultation__doctor', 'raised_by', 'reviewed_by',
        ).order_by('-created_at')
        status_filter = request.query_params.get('status')
        if status_filter:
            rows = rows.filter(status=status_filter)
        return [_consultation_dispute_json(d) for d in rows]
    if module == 'community-reports':
        reports = Report.objects.select_related('reporter', 'reviewed_by').filter(
            target_type__in=['post', 'comment']).order_by('-created_at')
        status_filter = request.query_params.get('status')
        if status_filter in _COMMUNITY_REPORT_STATUS:
            reports = reports.filter(status=status_filter)
        return [_community_report_json(r) for r in reports]
    if module == 'community-users':
        reported_post_ids = Report.objects.filter(
            target_type='post').values_list('target_id', flat=True)
        author_ids = set(CommunityPost.objects.filter(
            id__in=list(reported_post_ids)).values_list('author_id', flat=True))
        author_ids |= set(CommunityMute.objects.values_list('user_id', flat=True))
        author_ids |= set(CommunityPost.objects.order_by('-created_at').values_list(
            'author_id', flat=True)[:100])
        users = User.objects.filter(id__in=author_ids).prefetch_related('roles')
        return sorted(
            [_community_user_json(u) for u in users],
            key=lambda r: (not r['muted'], -r['reports_against'], -r['posts']),
        )
    if module == 'research-tags':
        return [{'id': str(t.id), 'name': t.name, 'slug': t.slug, 'category': t.category}
                for t in ResearchTag.objects.order_by('category', 'name')]
    if module == 'support-tickets':
        from api.admin_support import ticket_rows
        return ticket_rows(request)
    if module == 'payments':
        from api.admin_finance import finance_rows
        return finance_rows(request)
    if module == 'security-flags':
        from api.admin_security import security_rows
        return security_rows(request)
    if module == 'subscriptions':
        from subscriptions.models import Subscription
        return [{
            'id': str(s.id),
            'user': (s.user.full_name or s.user.email) if s.user_id else 'Unknown',
            'plan': s.plan.name if s.plan_id else '',
            'price': float(s.plan.price) if s.plan_id else 0,
            'status': s.status.title(),
            'started': s.started_at.strftime('%b %d, %Y') if s.started_at else '',
            'expires': s.expires_at.strftime('%b %d, %Y') if s.expires_at else '',
            'auto_renew': s.auto_renew,
        } for s in Subscription.objects.select_related('user', 'plan').order_by('-created_at')[:300]]
    return _records(module)


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_collection(request, module):
    denied = _gate(request, module)
    if denied is not None:
        return denied
    if request.method == 'GET':
        return Response({'results': _collection_rows(request, module)})

    if module == 'support-tickets':
        from api.admin_support import admin_create_ticket
        return admin_create_ticket(request)

    if module == 'team':
        email = request.data.get('email', '').strip().lower()
        if not email:
            return Response({'detail': 'Email is required.'}, status=400)
        role_label = request.data.get('role', 'Support Agent')
        role_name = 'admin_' + role_label.lower().replace(' admin', '').replace(' agent', '').replace(' ', '_')
        role, _ = Role.objects.get_or_create(
            name=role_name, defaults={'panel_type': 'admin'})
        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                'full_name': request.data.get('name', ''),
                'phone': request.data.get('phone') or f'pending-{uuid.uuid4().hex[:12]}',
                'date_of_birth': request.data.get('date_of_birth') or date(1970, 1, 1),
                'present_address': request.data.get('present_address') or 'Not provided',
                'consent_terms': True,
                'account_status': 'active',
                'profile_data': {'department': request.data.get('department', 'Operations')},
            },
        )
        if not created:
            return Response({'detail': 'A user with this email already exists.'}, status=400)
        user.set_password(request.data.get('temporary_password', 'FeatherflowTeam@2026'))
        user.save()
        UserRole.objects.create(user=user, role=role)
        result = _team_json(user)
        _log(request, module, 'Create', str(user.id), new=result)
        return Response(result, status=201)

    if module == 'team-updates':
        if not _is_research_content_admin(request.user):
            return Response({'detail': 'You are not authorized to post Team Featherflow updates.'}, status=403)
        title = str(request.data.get('title', '')).strip()
        body = str(request.data.get('body', '')).strip()
        if error := (check_length('title', title) or check_length('body', body)):
            return Response({'detail': error}, status=400)
        abstract = str(request.data.get('summary') or body[:280])
        tag_ids = request.data.get('tag_ids') or []
        tags = list(ResearchTag.objects.filter(id__in=tag_ids)) if tag_ids else []
        now = timezone.now()
        with transaction.atomic():
            article = Article.objects.create(
                author=request.user, content_type='team_update', status='published',
                title=title, abstract=abstract, body=body,
                category=request.data.get('category') or None,
                keywords=request.data.get('keywords') or [],
                is_featured=bool(request.data.get('is_featured', True)),
                published_at=now, created_at=now, updated_at=now,
            )
            if tags:
                article.tags.set(tags)
        result = _article_admin_json(article)
        _log(request, module, 'Create', str(article.id), new=result)
        return Response(result, status=201)

    if module in ('riders', 'delivery-orders', 'payouts'):
        return Response({'detail': 'Riders, delivery orders, and payouts are created automatically, not through this endpoint.'}, status=405)
    if module in ('researchers', 'articles', 'research-papers', 'disease-updates', 'innovations',
                   'profile-change-applications', 'content-reports', 'research-tags'):
        return Response({'detail': 'Researchers and their content are created through signup and the Researchers Panel, not this endpoint.'}, status=405)
    if module in ('community-reports', 'community-users'):
        return Response({'detail': 'Community reports and members come from the community feed, not this endpoint.'}, status=405)
    if module == 'consultation-disputes':
        return Response({'detail': 'Disputes are raised by farmers/doctors from a consultation, not this endpoint.'}, status=405)

    payload = dict(request.data)
    record_id = str(payload.get('id') or f'{module[:3].upper()}-{AdminPanelRecord.objects.filter(module=module).count() + 1:03d}')
    payload['id'] = record_id
    record = AdminPanelRecord.objects.create(module=module, record_id=record_id, payload=payload)
    _log(request, module, 'Create', record_id, new=record.payload)
    return Response(record.payload, status=201)


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsAdminUser])
def admin_record(request, module, record_id):
    denied = _gate(request, module)
    if denied is not None:
        return denied
    queued = _maybe_enqueue(request, module, record_id)
    if queued is not None:
        return queued
    if module == 'support-tickets':
        from api.admin_support import admin_update_ticket
        return admin_update_ticket(request, record_id)
    if module == 'payments':
        if request.method == 'DELETE':
            return Response({'detail': 'Financial records cannot be deleted.'}, status=405)
        from api.admin_finance import finance_action
        return finance_action(request, record_id)
    if module == 'security-flags':
        from api.admin_security import clear_flag
        result = clear_flag(request, record_id)
        _log(request, module, 'Clear security flag', record_id, action_type='edit')
        return Response(result)
    if module == 'pharmacies':
        try:
            user = User.objects.get(pk=record_id, roles__name='pharmacy')
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'Pharmacy not found.'}, status=404)
        old = _pharmacy_json(user)
        status_value = request.data.get('status')
        org = getattr(user, 'pharmacy_organization', None)
        if request.method == 'DELETE' or status_value == 'Suspended':
            user.account_status = 'suspended'
            user.is_verified = False
            if org is not None:
                org.is_verified = False
        elif status_value == 'Verified':
            user.account_status = 'active'
            user.is_verified = True
            if org is not None:
                org.is_verified = True
                org.approved_by_admin = request.user
        user.save(update_fields=['account_status', 'is_verified', 'updated_at'])
        if org is not None and status_value in ('Verified', 'Suspended'):
            org.save(update_fields=['is_verified', 'approved_by_admin', 'updated_at'])
        result = _pharmacy_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'users':
        try:
            user = User.objects.get(pk=record_id)
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'User not found.'}, status=404)
        old = _user_json(user)
        if request.method == 'DELETE':
            user.account_status = 'suspended'
        else:
            status_value = request.data.get('status')
            if status_value:
                user.account_status = {'Approved': 'active', 'Pending': 'pending', 'Suspended': 'suspended'}.get(status_value, status_value.lower())
                user.is_verified = status_value == 'Approved'
                try:
                    doctor_profile = user.doctor_profile
                except DoctorProfile.DoesNotExist:
                    doctor_profile = None
                if doctor_profile is not None:
                    doctor_profile.is_verified = status_value == 'Approved'
                    doctor_profile.is_available = status_value == 'Approved'
                    doctor_profile.save(update_fields=['is_verified', 'is_available', 'updated_at'])
                try:
                    researcher_profile = user.researcher_profile
                except ResearcherProfile.DoesNotExist:
                    researcher_profile = None
                if researcher_profile is not None:
                    researcher_profile.is_verified = status_value == 'Approved'
                    researcher_profile.save(update_fields=['is_verified', 'updated_at'])
            for field in ['full_name', 'phone', 'present_address', 'two_factor_enabled']:
                if field in request.data:
                    setattr(user, field, request.data[field])
            if 'bio' in request.data:
                profile_data = dict(user.profile_data or {})
                profile_data['bio'] = request.data['bio']
                user.profile_data = profile_data
        user.save()
        result = _user_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'doctors':
        try:
            profile = DoctorProfile.objects.get(pk=record_id)
        except (DoctorProfile.DoesNotExist, ValueError):
            return Response({'detail': 'Doctor not found.'}, status=404)
        old = _doctor_json(profile)
        status_value = request.data.get('status')
        if status_value:
            profile.is_verified = status_value == 'Verified'
            profile.is_available = status_value == 'Verified'
            profile.save()
            profile.user.account_status = {
                'Suspended': 'suspended',
                'Rejected': 'suspended',
                'Verified': 'active',
            }.get(status_value, 'pending')
            profile.user.save(update_fields=['account_status'])
        profile_fields = {
            'specialty': 'specialty',
            'clinic_name': 'clinic_hospital_name',
            'practice_address': 'practice_address',
            'district': 'practice_address',
            'degree': 'veterinary_degree',
            'university': 'university_name',
            'license_doc': 'license_number',
            'license_authority': 'license_issuing_authority',
            'focus_area': 'poultry_focus_area',
            'consultation_mode': 'consultation_mode',
            'service_fee': 'service_fee',
            'years_experience': 'years_of_experience',
        }
        changed = []
        for api_field, model_field in profile_fields.items():
            if api_field in request.data:
                setattr(profile, model_field, request.data[api_field])
                changed.append(model_field)
        if changed:
            profile.save(update_fields=changed + ['updated_at'])
        result = _doctor_json(profile)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'team':
        try:
            user = User.objects.prefetch_related('roles').get(pk=record_id)
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'Team member not found.'}, status=404)
        old = _team_json(user)
        if 'status' in request.data:
            user.account_status = 'active' if request.data['status'] == 'Active' else 'suspended'
        if 'name' in request.data:
            user.full_name = request.data['name']
        if 'email' in request.data:
            user.email = request.data['email']
        profile = dict(user.profile_data or {})
        for key in ['department', 'pending_approval']:
            if key in request.data:
                profile[key] = request.data[key]
        user.profile_data = profile
        if 'role' in request.data:
            role_label = request.data['role']
            role_name = 'admin_' + role_label.lower().replace(' admin', '').replace(' agent', '').replace(' ', '_')
            role, _ = Role.objects.get_or_create(
                name=role_name, defaults={'panel_type': 'admin'})
            user.roles.remove(*user.roles.filter(name__startswith='admin_'))
            user.roles.add(role)
        user.save()
        result = _team_json(user)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'riders':
        if request.method == 'DELETE':
            return Response({'detail': 'Riders cannot be deleted, only suspended.'}, status=405)
        if not _is_delivery_ops_admin(request.user):
            return Response({'detail': 'You are not authorized to manage delivery riders.'}, status=403)
        try:
            profile = DeliveryProfile.objects.select_related('user').get(pk=record_id)
        except (DeliveryProfile.DoesNotExist, ValueError):
            return Response({'detail': 'Rider not found.'}, status=404)
        old = _rider_json(profile)
        action = request.data.get('action')
        if action == 'approve':
            profile.approved_by_admin = request.user
            profile.save(update_fields=['approved_by_admin', 'updated_at'])
            # A rider registers as ``pending`` — approval also unlocks sign-in.
            if profile.user.account_status != 'active':
                profile.user.account_status = 'active'
                profile.user.save(update_fields=['account_status', 'updated_at'])
            Notification.objects.create(
                user=profile.user, title='You are approved',
                body='Your delivery rider account has been approved. You can now go online and accept deliveries.',
                notification_type='approval',
            )
        elif action == 'suspend':
            profile.user.account_status = 'suspended'
            profile.user.save(update_fields=['account_status'])
        else:
            return Response({'detail': 'action must be "approve" or "suspend".'}, status=400)
        result = _rider_json(profile)
        _log(request, module, f'Rider {action}', record_id, old=old, new=result)
        return Response(result)

    if module == 'delivery-orders':
        if request.method == 'DELETE':
            return Response({'detail': 'Use an action-based PATCH for delivery orders.'}, status=405)
        if not _is_delivery_ops_admin(request.user):
            return Response({'detail': 'You are not authorized to manage delivery assignments.'}, status=403)
        action = request.data.get('action')
        rider_id = request.data.get('rider_id')
        reason = request.data.get('reason', '')
        notes = request.data.get('notes', '')
        if record_id.startswith('DQ-'):
            if action == 'assign':
                return _assign_from_queue(request, record_id, rider_id, notes)
            if action == 'cancel':
                deleted, _n = AdminPanelRecord.objects.filter(module='delivery-queue', record_id=record_id).delete()
                if not deleted:
                    return Response({'detail': 'This delivery request is no longer available.'}, status=404)
                _log(request, module, 'Cancel queued request', record_id)
                return Response(status=204)
            return Response({'detail': 'A queued delivery request can only be assigned or cancelled.'}, status=400)
        if action == 'reassign':
            return _reassign_order(request, record_id, rider_id, reason, notes)
        if action == 'cancel':
            return _cancel_order(request, record_id, reason)
        return Response({'detail': 'action must be "reassign" or "cancel".'}, status=400)

    if module == 'payouts':
        if request.method == 'DELETE':
            return Response({'detail': 'Payouts cannot be deleted.'}, status=405)
        if not _is_delivery_ops_admin(request.user):
            return Response({'detail': 'You are not authorized to process payouts.'}, status=403)
        try:
            earning = DeliveryEarning.objects.select_related('delivery_person__user').get(pk=record_id)
        except (DeliveryEarning.DoesNotExist, ValueError):
            return Response({'detail': 'Payout record not found.'}, status=404)
        if request.data.get('action') != 'mark_paid':
            return Response({'detail': 'action must be "mark_paid".'}, status=400)
        if earning.payout_status == 'paid':
            return Response({'detail': 'This payout was already processed.'}, status=409)
        earning.payout_status = 'paid'
        earning.payout_date = timezone.now().date()
        earning.save(update_fields=['payout_status', 'payout_date'])
        Notification.objects.create(
            user=earning.delivery_person.user, title='Payout processed',
            body=f'Your payout of ৳{earning.total_earned} has been processed.',
            notification_type='system', reference_id=earning.id, reference_type='delivery_payout',
        )
        result = _payout_json(earning)
        _log(request, module, 'Mark paid', record_id, new=result)
        return Response(result)

    if module == 'researchers':
        if request.method == 'DELETE':
            return Response({'detail': 'Researchers cannot be deleted, only suspended.'}, status=405)
        if not _is_research_content_admin(request.user):
            return Response({'detail': 'You are not authorized to manage researchers.'}, status=403)
        try:
            profile = ResearcherProfile.objects.select_related('user').get(pk=record_id)
        except (ResearcherProfile.DoesNotExist, ValueError):
            return Response({'detail': 'Researcher not found.'}, status=404)
        old = _researcher_admin_json(profile)
        action = request.data.get('action')
        if action == 'verify':
            profile.is_verified = True
            profile.approved_by_admin = request.user
            profile.save(update_fields=['is_verified', 'approved_by_admin', 'updated_at'])
            if profile.user.account_status != 'active':
                profile.user.account_status = 'active'
                profile.user.save(update_fields=['account_status', 'updated_at'])
            Notification.objects.create(
                user=profile.user, title='You are verified',
                body='Your researcher account has been verified. You can now request a premium subscription to publish content.',
                notification_type='approval',
            )
        elif action == 'suspend':
            profile.user.account_status = 'suspended'
            profile.user.save(update_fields=['account_status', 'updated_at'])
        elif action == 'reject':
            profile.is_verified = False
            profile.save(update_fields=['is_verified', 'updated_at'])
            profile.user.account_status = 'suspended'
            profile.user.save(update_fields=['account_status', 'updated_at'])
        else:
            return Response({'detail': 'action must be "verify", "suspend", or "reject".'}, status=400)
        result = _researcher_admin_json(profile)
        _log(request, module, f'Researcher {action}', record_id, old=old, new=result)
        return Response(result)

    if module in ('articles', 'research-papers', 'disease-updates', 'innovations', 'team-updates'):
        if request.method == 'DELETE':
            return Response({'detail': 'Use a PATCH action to hide, remove, or approve content.'}, status=405)
        if not _is_research_content_admin(request.user):
            return Response({'detail': 'You are not authorized to moderate research content.'}, status=403)
        try:
            article = Article.objects.select_related('author').get(pk=record_id)
        except (Article.DoesNotExist, ValueError):
            return Response({'detail': 'Content not found.'}, status=404)
        old = _article_admin_json(article)
        changed = ['updated_at']
        if 'featured' in request.data:
            article.is_featured = bool(request.data['featured'])
            changed.append('is_featured')
        for api_field, model_field in [('title', 'title'), ('summary', 'abstract')]:
            if api_field in request.data:
                setattr(article, model_field, request.data[api_field])
                changed.append(model_field)
        if 'type' in request.data:
            new_type = _ARTICLE_LABEL_TO_TYPE.get(request.data['type'])
            if new_type:
                article.content_type = new_type
                changed.append('content_type')
        if 'date' in request.data:
            parsed_date = parse_admin_date(request.data['date'])
            if parsed_date:
                article.published_at = parsed_date
                changed.append('published_at')
        new_status_label = request.data.get('status')
        action = request.data.get('action')
        if action == 'approve' or new_status_label == 'Published':
            if article.status not in ('pending_review', 'needs_revision', 'published'):
                return Response({'detail': f'Cannot publish content from "{article.status}".'}, status=409)
            article.status = 'published'
            if not article.published_at:
                article.published_at = timezone.now()
            article.review_notes = ''
            changed += ['status', 'published_at', 'review_notes']
            _snapshot(article, request.user, 'Published by admin')
        elif action == 'request_revision':
            notes = str(request.data.get('review_notes', '')).strip()
            if not notes:
                return Response({'detail': 'Review notes are required when requesting revision.'}, status=400)
            article.status = 'needs_revision'
            article.review_notes = notes
            changed += ['status', 'review_notes']
        elif new_status_label == 'Hidden':
            # One-click "Hide" from the admin content list — a lighter-weight
            # unpublish than the explicit request_revision flow, which is why
            # it doesn't require a typed reason.
            article.status = 'needs_revision'
            article.review_notes = str(request.data.get('review_notes', '')).strip()
            changed += ['status', 'review_notes']
        elif action in ('reject', 'remove') or new_status_label == 'Removed':
            article.status = 'archived'
            article.review_notes = str(request.data.get('review_notes', '')).strip()
            changed += ['status', 'review_notes']
        elif new_status_label and new_status_label not in _ARTICLE_LABEL_TO_STATUS:
            return Response({'detail': f'Unknown status "{new_status_label}".'}, status=400)
        article.save(update_fields=list(dict.fromkeys(changed)))
        if 'status' in changed:
            readable = _ARTICLE_STATUS_TO_LABEL.get(article.status, article.status.title())
            Notification.objects.create(
                user=article.author, title=f'Your content is now {readable.lower()}',
                body=f'"{article.title}" — {article.review_notes or "no additional notes."}',
                notification_type='approval', reference_id=article.id, reference_type='article',
            )
        result = _article_admin_json(article)
        _log(request, module, 'Update', record_id, old=old, new=result)
        return Response(result)

    if module == 'profile-change-applications':
        if request.method == 'DELETE':
            return Response({'detail': 'Applications cannot be deleted, only approved or rejected.'}, status=405)
        if not _is_research_content_admin(request.user):
            return Response({'detail': 'You are not authorized to review profile change applications.'}, status=403)
        try:
            application = ProfileChangeApplication.objects.select_related('user').get(pk=record_id)
        except (ProfileChangeApplication.DoesNotExist, ValueError):
            return Response({'detail': 'Application not found.'}, status=404)
        if application.status != 'pending':
            return Response({'detail': f'This application was already {application.status}.'}, status=409)
        action = request.data.get('action')
        if action not in ('approve', 'reject'):
            return Response({'detail': 'action must be "approve" or "reject".'}, status=400)
        review_note = str(request.data.get('review_note', '')).strip()
        if action == 'reject' and not review_note:
            return Response({'detail': 'A review note is required when rejecting an application.'}, status=400)
        with transaction.atomic():
            application = ProfileChangeApplication.objects.select_for_update().get(pk=record_id)
            if application.status != 'pending':
                return Response({'detail': f'This application was already {application.status}.'}, status=409)
            if action == 'approve':
                try:
                    researcher_profile = application.user.researcher_profile
                except ResearcherProfile.DoesNotExist:
                    return Response({'detail': 'Researcher profile no longer exists.'}, status=404)
                old_value = getattr(researcher_profile, application.field_name)
                setattr(researcher_profile, application.field_name, application.new_value)
                researcher_profile.save(update_fields=[application.field_name, 'updated_at'])
                _log(request, module, 'Approve profile change', record_id, old={'value': str(old_value)},
                     new={'field_name': application.field_name, 'value': application.new_value})
            application.status = 'approved' if action == 'approve' else 'rejected'
            application.reviewed_by = request.user
            application.review_note = review_note
            application.decided_at = timezone.now()
            application.save(update_fields=['status', 'reviewed_by', 'review_note', 'decided_at', 'updated_at'])
        Notification.objects.create(
            user=application.user,
            title=f'Profile change application {application.status}',
            body=(
                f'Your request to change "{application.field_name}" was {application.status}.'
                + (f' Note: {review_note}' if review_note else '')
            ),
            notification_type='approval', reference_id=application.id, reference_type='profile_change_application',
        )
        return Response(_application_json(application))

    if module == 'content-reports':
        if request.method == 'DELETE':
            return Response({'detail': 'Reports cannot be deleted, only resolved or dismissed.'}, status=405)
        if not _is_research_content_admin(request.user):
            return Response({'detail': 'You are not authorized to review content reports.'}, status=403)
        try:
            report = Report.objects.select_related('reporter').get(pk=record_id)
        except (Report.DoesNotExist, ValueError):
            return Response({'detail': 'Report not found.'}, status=404)
        action = request.data.get('action')
        if action not in ('resolve', 'dismiss'):
            return Response({'detail': 'action must be "resolve" or "dismiss".'}, status=400)
        report.status = 'resolved' if action == 'resolve' else 'reviewed'
        report.reviewed_by = request.user
        report.save(update_fields=['status', 'reviewed_by', 'updated_at'])
        _log(request, module, f'Report {action}', record_id)
        return Response(_report_admin_json(report))

    if module == 'consultation-disputes':
        from consultations.models import ConsultationDispute

        if request.method == 'DELETE':
            return Response({'detail': 'Disputes are resolved or dismissed, not deleted.'}, status=405)
        if not can_perform_action(request.user, 'doctors', 'edit'):
            return Response({'detail': 'You are not authorized to review consultation disputes.'}, status=403)
        try:
            dispute = ConsultationDispute.objects.select_related(
                'consultation__farmer', 'consultation__doctor', 'raised_by').get(pk=record_id)
        except (ConsultationDispute.DoesNotExist, ValueError):
            return Response({'detail': 'Dispute not found.'}, status=404)
        action = request.data.get('action')
        if action not in ('review', 'resolve', 'dismiss'):
            return Response({'detail': 'action must be "review", "resolve", or "dismiss".'}, status=400)
        resolution = str(request.data.get('resolution', '')).strip()
        if action in ('resolve', 'dismiss') and not resolution:
            return Response({'detail': 'A resolution note is required to close a dispute.'}, status=400)
        old = _consultation_dispute_json(dispute)
        dispute.status = {'review': 'under_review', 'resolve': 'resolved', 'dismiss': 'dismissed'}[action]
        dispute.reviewed_by = request.user
        if action in ('resolve', 'dismiss'):
            dispute.resolution = resolution
            dispute.resolved_at = timezone.now()
        dispute.save(update_fields=['status', 'reviewed_by', 'resolution', 'resolved_at', 'updated_at'])
        for party in {dispute.consultation.farmer_id, dispute.consultation.doctor_id, dispute.raised_by_id}:
            Notification.objects.create(
                user_id=party, title=f'Consultation dispute {dispute.status.replace("_", " ")}',
                body=resolution or 'A moderator is now reviewing your consultation dispute.',
                notification_type='system', reference_id=dispute.id, reference_type='consultation_dispute')
        result = _consultation_dispute_json(dispute)
        _log(request, module, f'Dispute {action}', record_id, old=old, new=result,
             action_type='reject' if action == 'dismiss' else 'edit')
        return Response(result)

    if module == 'community-reports':
        if request.method == 'DELETE':
            return Response({'detail': 'Reports are resolved or dismissed, not deleted.'}, status=405)
        if not can_perform_action(request.user, 'community', 'edit'):
            return Response({'detail': 'You are not authorized to moderate the community.'}, status=403)
        try:
            report = Report.objects.select_related('reporter').get(
                pk=record_id, target_type__in=['post', 'comment'])
        except (Report.DoesNotExist, ValueError):
            return Response({'detail': 'Report not found.'}, status=404)
        target = _community_target(report)
        action = request.data.get('action') or {
            'Removed': 'remove', 'Hidden': 'hide', 'Dismissed': 'dismiss', 'Resolved': 'hide',
        }.get(request.data.get('status'), '')
        reason = str(request.data.get('reason') or request.data.get('review_notes') or '').strip()
        old = _community_report_json(report)

        if action in ('hide', 'remove') and target is not None:
            target.status = 'removed' if action == 'remove' else 'hidden'
            target.hidden_reason = reason or f'{action.title()} by moderator'
            target.save(update_fields=['status', 'hidden_reason', 'updated_at'])
            Report.objects.filter(
                target_id=report.target_id, target_type=report.target_type, status='pending',
            ).update(status='resolved', reviewed_by=request.user)
            Notification.objects.create(
                user=target.author, title=f'Your {report.target_type} was {action}d',
                body=reason or 'A moderator actioned your content after a community report.',
                notification_type='system', reference_type='community_moderation')
        elif action == 'unhide' and target is not None:
            target.status = 'active'
            target.hidden_reason = None
            target.save(update_fields=['status', 'hidden_reason', 'updated_at'])
            Report.objects.filter(
                target_id=report.target_id, target_type=report.target_type, status='pending',
            ).update(status='reviewed', reviewed_by=request.user)
        elif action == 'dismiss':
            report.status = 'reviewed'
            report.reviewed_by = request.user
            report.save(update_fields=['status', 'reviewed_by', 'updated_at'])
        else:
            return Response({'detail': 'action must be hide, unhide, remove, or dismiss.'}, status=400)

        result = _community_report_json(report)
        _log(request, module, f'Community report {action}', record_id, old=old, new=result,
             action_type='reject' if action == 'dismiss' else 'edit')
        return Response(result)

    if module == 'community-users':
        if request.method == 'DELETE':
            return Response({'detail': 'Community members are muted, not deleted.'}, status=405)
        if not can_perform_action(request.user, 'community', 'edit'):
            return Response({'detail': 'You are not authorized to moderate the community.'}, status=403)
        try:
            member = User.objects.prefetch_related('roles').get(pk=record_id)
        except (User.DoesNotExist, ValueError):
            return Response({'detail': 'Member not found.'}, status=404)
        old = _community_user_json(member)
        action = request.data.get('action')
        wants_mute = action == 'mute' or request.data.get('muted') is True
        wants_unmute = action == 'unmute' or request.data.get('muted') is False
        reason = str(request.data.get('reason', '')).strip()

        if wants_mute:
            if not can_perform_action(request.user, 'community', 'suspend'):
                return Response({'detail': 'Muting a member needs the community "suspend" permission.'}, status=403)
            CommunityMute.objects.filter(user=member, is_active=True).update(is_active=False)
            CommunityMute.objects.create(
                user=member, muted_by=request.user, reason=reason or None,
                is_active=True, created_at=timezone.now(), updated_at=timezone.now())
            Notification.objects.create(
                user=member, title='Your community access was muted',
                body=reason or 'A moderator has muted your community access.',
                notification_type='system', reference_type='community_moderation')
        elif wants_unmute:
            CommunityMute.objects.filter(user=member, is_active=True).update(
                is_active=False, updated_at=timezone.now())
        elif request.data.get('verified') is True:
            member.is_verified = True
            member.save(update_fields=['is_verified', 'updated_at'])
        elif request.data.get('verified') is False:
            member.is_verified = False
            member.save(update_fields=['is_verified', 'updated_at'])
        else:
            return Response({'detail': 'Pass action=mute/unmute or verified=true/false.'}, status=400)

        result = _community_user_json(member)
        _log(request, module, f'Community member {action or "update"}', record_id,
             old=old, new=result, action_type='suspend' if wants_mute else 'edit')
        return Response(result)

    _seed(module)
    try:
        record = AdminPanelRecord.objects.get(module=module, record_id=record_id)
    except AdminPanelRecord.DoesNotExist:
        return Response({'detail': 'Record not found.'}, status=404)
    old = dict(record.payload)
    if request.method == 'DELETE':
        record.delete()
        _log(request, module, 'Delete', record_id, old=old)
        return Response(status=204)
    updated = {**old, **dict(request.data)}
    record.payload = updated
    record.save(update_fields=['payload', 'updated_at'])
    if module == 'medicines' and updated.get('pharmacy_user_id'):
        try:
            pharmacy_user = User.objects.get(pk=updated['pharmacy_user_id'])
            Notification.objects.create(
                user=pharmacy_user,
                title=f'Medicine {updated.get("status", "updated").lower()}',
                body=f'{updated.get("name", "Your medicine")} was {updated.get("status", "updated").lower()} by an administrator.',
                notification_type='approval', reference_type='pharmacy_medicine',
            )
        except (User.DoesNotExist, ValueError, TypeError):
            pass
    _log(request, module, 'Update', record_id, old=old, new=updated)
    return Response(updated)


@api_view(['GET', 'PATCH', 'POST'])
@permission_classes([IsAdminUser])
def admin_profile(request):
    user = request.user
    if request.method == 'GET':
        return Response(_user_json(user) | {
            'department': user.profile_data.get('department', 'IT & Operations'),
            'notification_preferences': user.profile_data.get('notification_preferences', {
                'user_activity': True, 'system_alerts': True, 'weekly_report': False,
            }),
        })
    if request.method == 'POST':
        current_password = request.data.get('current_password')
        password = request.data.get('password')
        if not password:
            return Response({'detail': 'Password is required.'}, status=400)
        if not current_password or not user.check_password(current_password):
            return Response({'detail': 'Current password is incorrect.'}, status=400)
        user.set_password(password)
        user.save(update_fields=['password'])
        update_session_auth_hash(request, user)
        _log(request, 'Profile', 'Change Password', str(user.id))
        return Response({'detail': 'Password updated.'})
    old = _user_json(user)
    for field in ['full_name', 'phone', 'present_address', 'two_factor_enabled']:
        if field in request.data:
            setattr(user, field, request.data[field])
    profile_data = dict(user.profile_data or {})
    for field in ['department', 'bio', 'notification_preferences']:
        if field in request.data:
            profile_data[field] = request.data[field]
    user.profile_data = profile_data
    user.save()
    result = _user_json(user) | {'department': profile_data.get('department', 'IT & Operations'), 'notification_preferences': profile_data.get('notification_preferences', {})}
    _log(request, 'Profile', 'Update', str(user.id), old=old, new=result)
    return Response(result)
