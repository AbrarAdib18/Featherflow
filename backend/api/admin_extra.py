"""Admin Panel — RBAC-aware endpoints beyond the generic collection/record pair:

  * ``admin_me``              — the caller's role, tier, permission matrix
  * ``admin_admins`` / ``admin_admin_detail`` / ``admin_admin_action``
                              — Super Admin manages admin accounts
  * ``admin_roles``           — the role catalogue (+ Super edits permissions)
  * ``admin_audit_logs`` / ``admin_audit_override``
                              — immutable audit trail + reversal
  * ``admin_approval_queue`` / ``admin_approval_decide``
  * ``admin_oversight``       — Operations: platform-wide module activity
  * ``admin_escalations`` / ``admin_escalation_resolve``
  * ``admin_module_export``   — CSV of any module the caller can view
  * ``me_updates``            — user-facing "what changed since <ts>" poll
"""

import csv
import io
from datetime import date, datetime

from django.db import transaction
from django.db.models import Count
from django.http import HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from audit.models import (
    ActivityLog, AdminApprovalQueue, AdminEscalation, AdminPanelRecord,
)
from notifications.models import Notification
from profiles.models import (
    AdminProfile, DeliveryProfile, DoctorProfile, PharmacyOrganization, ResearcherProfile,
)
from users.models import Role, User

from api.admin_approvals import decide as decide_approval
from api.admin_rbac import (
    IsAdminUser, ROLE_SUPER, accessible_modules, admin_roles, admin_tier,
    can_perform_action, effective_permissions, is_operations_admin, is_super_admin,
)


def _client_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    return forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR')


def _audit(request, module, action, action_type, target_id=None, old=None, new=None, reason=''):
    ActivityLog.objects.create(
        user=request.user, module=module, action=action, action_type=action_type,
        entity_type=module, entity_id=_uuid(target_id), old_values=old, new_values=new,
        reason=reason or str(request.data.get('reason', '')) or None,
        ip_address=_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


def _uuid(value):
    import uuid
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        return None


# ── /admin-panel/me/ ────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_me(request):
    user = request.user
    roles = admin_roles(user)
    primary = min(roles, key=lambda r: r.tier_level or 3) if roles else None
    profile = getattr(user, 'admin_profile', None)
    tier = admin_tier(user)
    payload = {
        'id': str(user.id),
        'name': user.full_name or user.email,
        'email': user.email,
        'roles': [r.name for r in roles],
        'role': primary.name if primary else None,
        'role_display': primary.display_name if primary else 'Admin',
        'tier': tier,
        'is_super_admin': is_super_admin(user),
        'is_operations_admin': is_operations_admin(user),
        'permissions': effective_permissions(user),
        'accessible_modules': accessible_modules(user),
        'department': (profile.department if profile else None)
                      or user.profile_data.get('department', 'Operations'),
        'job_title': profile.job_title if profile else None,
        'approval_status': profile.approval_status if profile else 'approved',
        'two_factor_enabled': bool(user.two_factor_enabled),
        # Shift timer: hourly admins (tier 2-4) clock in; Super Admin does not.
        'tracks_shifts': tier is not None and tier > 1 and profile is not None,
    }
    if payload['tracks_shifts']:
        from api.admin_shifts import _status_payload
        payload['shift'] = _status_payload(profile)
    return Response(payload)


# ── /admin-panel/admins/ (Super Admin) ──────────────────────────────────────

def _admin_json(profile):
    user = profile.user
    roles = [r for r in user.roles.all() if r.panel_type == 'admin']
    role = min(roles, key=lambda r: r.tier_level or 3) if roles else None
    return {
        'id': str(profile.id),
        'user_id': str(user.id),
        'name': user.full_name or user.email,
        'email': user.email,
        'phone': user.phone or '',
        'role': role.name if role else None,
        'role_display': role.display_name if role else 'Admin',
        'tier': role.tier_level if role else None,
        'job_title': profile.job_title,
        'department': profile.department,
        'account_id_number': profile.account_id_number or '',
        'employment_type': profile.employment_type or '',
        'work_location': profile.work_location or '',
        'start_date': profile.start_date.isoformat() if profile.start_date else None,
        'approval_status': profile.approval_status,
        'is_active': profile.is_active and not profile.is_suspended,
        'is_suspended': profile.is_suspended,
        'two_factor_enabled': bool(user.two_factor_enabled),
        'internal_approval_by_founder_hr': profile.internal_approval_by_founder_hr,
        'reporting_manager': (profile.reporting_manager.full_name or profile.reporting_manager.email)
                             if profile.reporting_manager_id else None,
        'approved_by': (profile.approved_by_admin.full_name or profile.approved_by_admin.email)
                       if profile.approved_by_admin_id else None,
        'created': user.date_joined.strftime('%b %d, %Y') if user.date_joined else '',
        'last_active': user.last_login.strftime('%b %d, %Y') if user.last_login else 'Never',
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_admins(request):
    if not can_perform_action(request.user, 'team', 'view'):
        return Response({'detail': 'You cannot view admin accounts.'}, status=403)
    if request.method == 'GET':
        profiles = AdminProfile.objects.select_related(
            'user', 'reporting_manager', 'approved_by_admin').prefetch_related('user__roles')
        status_filter = request.query_params.get('status')
        rows = [_admin_json(p) for p in profiles]
        if status_filter:
            rows = [r for r in rows if r['approval_status'] == status_filter]
        return Response({'results': rows})

    # POST — create an admin account (Super Admin only)
    if not is_super_admin(request.user):
        return Response({'detail': 'Only a Super Admin can create admin accounts.'}, status=403)
    data = request.data
    email = str(data.get('email', '')).strip().lower()
    role_name = str(data.get('role', '')).strip()
    if not email or not role_name:
        return Response({'detail': 'email and role are required.'}, status=400)
    try:
        role = Role.objects.get(name=role_name, panel_type='admin')
    except Role.DoesNotExist:
        return Response({'detail': f'Unknown admin role "{role_name}".'}, status=400)
    if role.name == ROLE_SUPER and User.objects.filter(roles__name=ROLE_SUPER).exists():
        return Response({'detail': 'A Super Admin already exists; there can be only one.'}, status=409)
    if User.objects.filter(email=email).exists():
        return Response({'detail': 'A user with this email already exists.'}, status=400)

    with transaction.atomic():
        user = User.objects.create_user(
            email=email,
            password=data.get('temporary_password') or 'Featherflow@Admin2026',
            full_name=data.get('name', ''),
            phone=data.get('phone') or f'pending-{_uuid4hex()}',
            date_of_birth=_parse_date(data.get('date_of_birth')) or date(1980, 1, 1),
            present_address=data.get('work_location') or 'Not provided',
            consent_terms=True,
            account_status='active',
        )
        user.roles.add(role)
        profile = AdminProfile.objects.create(
            user=user,
            admin_role=role,
            job_title=data.get('job_title') or role.display_name,
            department=data.get('department') or 'Operations',
            work_location=data.get('work_location') or None,
            employment_type=str(data.get('employment_type', 'full_time')).lower().replace(' ', '_'),
            start_date=_parse_date(data.get('start_date')) or timezone.now().date(),
            admin_sub_role=_sub_role(role.name),
            account_id_number=data.get('account_id_number') or None,
            confidentiality_agreement_accepted=bool(data.get('confidentiality_agreement', True)),
            background_check_consent=bool(data.get('background_check_consent', True)),
            internal_approval_by_founder_hr=True,
            approval_status='approved',
            approved_by_admin=request.user,
            reporting_manager=request.user,
        )
    Notification.objects.create(
        user=user, title='Your admin account is ready',
        body=f'You have been added as {role.display_name}. Sign in to get started.',
        notification_type='approval',
    )
    _audit(request, 'team', f'Created admin {email} ({role.name})', 'create', profile.id, new=_admin_json(profile))
    return Response(_admin_json(profile), status=201)


@api_view(['GET', 'PATCH', 'DELETE'])
@permission_classes([IsAdminUser])
def admin_admin_detail(request, admin_id):
    try:
        profile = AdminProfile.objects.select_related('user').prefetch_related('user__roles').get(pk=admin_id)
    except (AdminProfile.DoesNotExist, ValueError):
        return Response({'detail': 'Admin not found.'}, status=404)

    if request.method == 'GET':
        if not can_perform_action(request.user, 'team', 'view'):
            return Response({'detail': 'Not permitted.'}, status=403)
        return Response(_admin_json(profile))

    if not is_super_admin(request.user):
        return Response({'detail': 'Only a Super Admin can modify admin accounts.'}, status=403)
    if profile.user_id == request.user.id:
        return Response({'detail': 'You cannot modify your own admin account here.'}, status=400)

    old = _admin_json(profile)

    if request.method == 'DELETE':
        # Soft-delete: never hard-remove an admin (audit continuity).
        profile.is_active = False
        profile.is_suspended = True
        profile.suspended_at = timezone.now()
        profile.suspended_by = request.user
        profile.save(update_fields=['is_active', 'is_suspended', 'suspended_at', 'suspended_by', 'updated_at'])
        profile.user.account_status = 'suspended'
        profile.user.save(update_fields=['account_status', 'updated_at'])
        _audit(request, 'team', f'Deactivated admin {profile.user.email}', 'delete', profile.id, old=old)
        return Response(_admin_json(profile))

    data = request.data
    if 'role' in data:
        try:
            role = Role.objects.get(name=data['role'], panel_type='admin')
        except Role.DoesNotExist:
            return Response({'detail': 'Unknown admin role.'}, status=400)
        if role.name == ROLE_SUPER:
            return Response({'detail': 'The Super Admin role cannot be assigned here.'}, status=403)
        profile.user.roles.remove(*profile.user.roles.filter(panel_type='admin'))
        profile.user.roles.add(role)
        profile.admin_role = role
        profile.admin_sub_role = _sub_role(role.name)
    for field in ('job_title', 'department', 'work_location', 'account_id_number', 'employment_type'):
        if field in data:
            setattr(profile, field, data[field])
    if 'name' in data:
        profile.user.full_name = data['name']
        profile.user.save(update_fields=['full_name', 'updated_at'])
    profile.save()
    _audit(request, 'team', f'Updated admin {profile.user.email}', 'edit', profile.id, old=old, new=_admin_json(profile))
    return Response(_admin_json(profile))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_admin_action(request, admin_id):
    """suspend / recover / approve / reject a pending admin registration."""
    if not is_operations_admin(request.user):
        return Response({'detail': 'Operations or Super Admin only.'}, status=403)
    try:
        profile = AdminProfile.objects.select_related('user').get(pk=admin_id)
    except (AdminProfile.DoesNotExist, ValueError):
        return Response({'detail': 'Admin not found.'}, status=404)
    if profile.user_id == request.user.id:
        return Response({'detail': 'You cannot action your own account.'}, status=400)

    action = request.data.get('action')
    reason = str(request.data.get('reason', ''))
    user = profile.user

    if action == 'suspend':
        profile.is_suspended = True
        profile.suspended_at = timezone.now()
        profile.suspended_by = request.user
        user.account_status = 'suspended'
    elif action == 'recover':
        profile.is_suspended = False
        profile.is_active = True
        profile.suspended_at = None
        user.account_status = 'active'
    elif action in ('approve', 'reject'):
        if not is_super_admin(request.user) and profile.admin_role and (profile.admin_role.tier_level or 3) <= 2:
            return Response({'detail': 'Approving Operations/Super admins requires a Super Admin.'}, status=403)
        profile.approval_status = 'approved' if action == 'approve' else 'rejected'
        profile.approved_by_admin = request.user
        profile.internal_approval_by_founder_hr = action == 'approve'
        user.account_status = 'active' if action == 'approve' else 'suspended'
    else:
        return Response({'detail': 'action must be suspend / recover / approve / reject.'}, status=400)

    profile.save()
    user.save(update_fields=['account_status', 'updated_at'])
    Notification.objects.create(
        user=user, title=f'Your admin account was {action}d'.replace('recoverd', 'recovered'),
        body=reason or f'An administrator {action}d your admin account.',
        notification_type='approval',
    )
    _audit(request, 'team', f'{action.title()} admin {user.email}',
           'suspend' if action == 'suspend' else ('approve' if action in ('approve', 'recover') else 'reject'),
           profile.id, reason=reason)
    return Response(_admin_json(profile))


# ── /admin-panel/roles/ ─────────────────────────────────────────────────────

@api_view(['GET', 'PATCH'])
@permission_classes([IsAdminUser])
def admin_roles_view(request):
    if request.method == 'GET':
        rows = [{
            'id': r.id, 'name': r.name, 'display_name': r.display_name,
            'description': r.description or '', 'tier_level': r.tier_level,
            'is_system': r.is_system, 'permissions': r.permissions,
            'member_count': r.users.count(),
        } for r in Role.objects.filter(panel_type='admin').order_by('tier_level', 'name')]
        return Response({'results': rows})

    if not is_super_admin(request.user):
        return Response({'detail': 'Only a Super Admin can edit role permissions.'}, status=403)
    name = request.data.get('name')
    try:
        role = Role.objects.get(name=name, panel_type='admin')
    except Role.DoesNotExist:
        return Response({'detail': 'Role not found.'}, status=404)
    if role.name == ROLE_SUPER:
        return Response({'detail': 'The Super Admin role is fixed.'}, status=403)
    new_permissions = request.data.get('permissions')
    if not isinstance(new_permissions, dict):
        return Response({'detail': 'permissions must be an object of {module: [actions]}.'}, status=400)
    old = dict(role.permissions)
    role.permissions = new_permissions
    role.save(update_fields=['permissions', 'updated_at'])
    _audit(request, 'team', f'Edited permissions for {role.name}', 'edit', reason='',
           old={'permissions': old}, new={'permissions': new_permissions})
    return Response({'name': role.name, 'permissions': role.permissions})


# ── /admin-panel/audit-logs/ ────────────────────────────────────────────────

def _log_json(log):
    return {
        'id': str(log.id),
        'admin': (log.user.full_name or log.user.email) if log.user_id else 'System',
        'admin_id': str(log.user_id) if log.user_id else None,
        'module': log.module,
        'action': log.action,
        'action_type': log.action_type or '',
        'target_id': str(log.entity_id) if log.entity_id else None,
        'target_type': log.entity_type or '',
        'reason': log.reason or '',
        'old_value': log.old_values,
        'new_value': log.new_values,
        'ip_address': log.ip_address or '',
        'created_at': log.created_at.isoformat() if log.created_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_audit_logs(request):
    if not can_perform_action(request.user, 'audit', 'view'):
        return Response({'detail': 'You cannot view the audit trail.'}, status=403)
    qs = ActivityLog.objects.select_related('user').all()
    p = request.query_params
    if p.get('admin_id'):
        qs = qs.filter(user_id=p['admin_id'])
    if p.get('module'):
        qs = qs.filter(module=p['module'])
    if p.get('action_type'):
        qs = qs.filter(action_type=p['action_type'])
    if p.get('target_id'):
        qs = qs.filter(entity_id=p['target_id'])
    if p.get('since'):
        since = parse_datetime(p['since'])
        if since:
            qs = qs.filter(created_at__gte=since)
    if p.get('until'):
        until = parse_datetime(p['until'])
        if until:
            qs = qs.filter(created_at__lte=until)
    try:
        limit = min(int(p.get('limit', 100)), 500)
        offset = max(int(p.get('offset', 0)), 0)
    except ValueError:
        limit, offset = 100, 0
    total = qs.count()
    rows = [_log_json(x) for x in qs[offset:offset + limit]]
    return Response({'results': rows, 'total': total, 'limit': limit, 'offset': offset})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_audit_override(request, log_id):
    if not is_super_admin(request.user):
        return Response({'detail': 'Only a Super Admin can override a logged action.'}, status=403)
    try:
        original = ActivityLog.objects.get(pk=log_id)
    except (ActivityLog.DoesNotExist, ValueError):
        return Response({'detail': 'Log entry not found.'}, status=404)
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A reason is required to override an action.'}, status=400)
    # Overriding does not mutate the immutable original; it appends a new row and
    # (best-effort) restores the recorded "old_value" snapshot where we can.
    restored = _attempt_restore(original)
    ActivityLog.objects.create(
        user=request.user, module=original.module,
        action=f'Override of {original.action_type or original.action} ({original.id})',
        action_type='override', entity_type=original.entity_type, entity_id=original.entity_id,
        old_values=original.new_values, new_values=original.old_values,
        reason=reason, ip_address=_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )
    return Response({
        'detail': 'Override recorded.' + ('' if restored else
                  ' The affected record could not be auto-restored — reverse it manually.'),
        'auto_restored': restored,
    })


def _attempt_restore(log):
    """Best-effort restore of a user/doctor/researcher status from log.old_values."""
    old = log.old_values or {}
    if not log.entity_id or not isinstance(old, dict):
        return False
    try:
        if log.module == 'users' and 'status' in old:
            user = User.objects.get(pk=log.entity_id)
            mapping = {'Approved': 'active', 'Pending': 'pending', 'Suspended': 'suspended'}
            user.account_status = mapping.get(old['status'], user.account_status)
            user.save(update_fields=['account_status', 'updated_at'])
            return True
        if log.module == 'doctors' and 'status' in old:
            profile = DoctorProfile.objects.get(pk=log.entity_id)
            profile.is_verified = old['status'] == 'Verified'
            profile.save(update_fields=['is_verified', 'updated_at'])
            return True
    except Exception:
        return False
    return False


# ── /admin-panel/approval-queue/ ────────────────────────────────────────────

def _queue_json(entry):
    return {
        'id': str(entry.id),
        'requested_by': (entry.requested_by.full_name or entry.requested_by.email),
        'requested_by_id': str(entry.requested_by_id),
        'approved_by': (entry.approved_by.full_name or entry.approved_by.email) if entry.approved_by_id else None,
        'action_type': entry.action_type,
        'module': entry.module_affected,
        'target_id': str(entry.target_id) if entry.target_id else None,
        'target_type': entry.target_type or '',
        'request_data': entry.request_data,
        'status': entry.status,
        'required_tier': entry.required_tier,
        'reason': entry.reason or '',
        'rejection_reason': entry.rejection_reason or '',
        'created_at': entry.created_at.isoformat() if entry.created_at else None,
        'decided_at': entry.decided_at.isoformat() if entry.decided_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_approval_queue(request):
    if not can_perform_action(request.user, 'approvals', 'view'):
        return Response({'detail': 'You cannot view the approval queue.'}, status=403)
    qs = AdminApprovalQueue.objects.select_related('requested_by', 'approved_by')
    status_filter = request.query_params.get('status', 'pending')
    if status_filter != 'all':
        qs = qs.filter(status=status_filter)
    mine = request.query_params.get('mine')
    if mine:
        qs = qs.filter(requested_by=request.user)
    return Response({'results': [_queue_json(e) for e in qs[:200]]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_approval_decide(request, queue_id):
    try:
        entry = AdminApprovalQueue.objects.get(pk=queue_id)
    except (AdminApprovalQueue.DoesNotExist, ValueError):
        return Response({'detail': 'Request not found.'}, status=404)
    decision = request.data.get('decision')
    tier = admin_tier(request.user) or 4
    override = decision == 'override'
    if override and not is_super_admin(request.user):
        return Response({'detail': 'Only a Super Admin can override.'}, status=403)
    if not override and tier > entry.required_tier:
        return Response({'detail': 'Your tier is not high enough to decide this request.'}, status=403)
    if entry.requested_by_id == request.user.id and not override:
        return Response({'detail': 'You cannot approve your own request.'}, status=400)
    if decision not in ('approve', 'reject', 'override'):
        return Response({'detail': 'decision must be approve / reject / override.'}, status=400)

    ok, message = decide_approval(
        entry, request.user, request,
        approve=decision in ('approve', 'override'),
        rejection_reason=str(request.data.get('rejection_reason', '')),
    )
    if not ok:
        return Response({'detail': message}, status=409)
    entry.refresh_from_db()
    return Response(_queue_json(entry))


# ── /admin-panel/oversight/ (Operations) ────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_oversight(request):
    if not is_operations_admin(request.user):
        return Response({'detail': 'Operations or Super Admin only.'}, status=403)
    since = timezone.now() - timezone.timedelta(days=7)
    by_admin = (ActivityLog.objects.filter(created_at__gte=since)
                .values('user__email', 'user__full_name')
                .annotate(actions=Count('id')).order_by('-actions')[:20])
    by_module = (ActivityLog.objects.filter(created_at__gte=since)
                 .values('module').annotate(actions=Count('id')).order_by('-actions'))
    return Response({
        'window_days': 7,
        'pending_approvals': AdminApprovalQueue.objects.filter(status='pending').count(),
        'open_escalations': AdminEscalation.objects.exclude(status='resolved').count(),
        'pending_admin_registrations': AdminProfile.objects.filter(approval_status='pending').count(),
        'activity_by_admin': [
            {'admin': r['user__full_name'] or r['user__email'] or 'System', 'actions': r['actions']}
            for r in by_admin
        ],
        'activity_by_module': [
            {'module': r['module'], 'actions': r['actions']} for r in by_module
        ],
        'module_backlog': {
            'user_approvals': User.objects.filter(account_status='pending').count(),
            'doctor_verifications': DoctorProfile.objects.filter(is_verified=False).count(),
            'researcher_verifications': ResearcherProfile.objects.filter(is_verified=False).count(),
            'pharmacy_verifications': PharmacyOrganization.objects.filter(is_verified=False).count(),
            'unassigned_riders': DeliveryProfile.objects.filter(approved_by_admin__isnull=True).count(),
        },
    })


# ── /admin-panel/escalations/ ───────────────────────────────────────────────

def _escalation_json(e):
    return {
        'id': str(e.id),
        'raised_by': (e.raised_by.full_name or e.raised_by.email),
        'assigned_to': (e.assigned_to.full_name or e.assigned_to.email) if e.assigned_to_id else None,
        'module': e.module, 'subject': e.subject, 'detail': e.detail or '',
        'priority': e.priority, 'status': e.status,
        'target_id': str(e.target_id) if e.target_id else None,
        'target_type': e.target_type or '',
        'resolution': e.resolution or '',
        'created_at': e.created_at.isoformat() if e.created_at else None,
        'resolved_at': e.resolved_at.isoformat() if e.resolved_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_escalations(request):
    if not can_perform_action(request.user, 'escalations', 'view'):
        return Response({'detail': 'You cannot view escalations.'}, status=403)
    if request.method == 'POST':
        if not can_perform_action(request.user, 'escalations', 'create'):
            return Response({'detail': 'You cannot raise escalations.'}, status=403)
        subject = str(request.data.get('subject', '')).strip()
        if not subject:
            return Response({'detail': 'A subject is required.'}, status=400)
        e = AdminEscalation.objects.create(
            raised_by=request.user, module=request.data.get('module', 'support'),
            target_id=_uuid(request.data.get('target_id')),
            target_type=request.data.get('target_type') or None,
            priority=str(request.data.get('priority', 'medium')).lower(),
            subject=subject, detail=request.data.get('detail', ''),
        )
        for admin in User.objects.filter(roles__name__in=['admin_super', 'admin_operations']).distinct():
            Notification.objects.create(
                user=admin, title='New escalation', body=subject,
                notification_type='alert', reference_id=e.id, reference_type='admin_escalation',
            )
        _audit(request, 'escalations', f'Raised escalation: {subject}', 'create', e.id)
        return Response(_escalation_json(e), status=201)

    qs = AdminEscalation.objects.select_related('raised_by', 'assigned_to')
    status_filter = request.query_params.get('status', 'open')
    if status_filter == 'active':
        qs = qs.exclude(status='resolved')
    elif status_filter != 'all':
        qs = qs.filter(status=status_filter)
    return Response({'results': [_escalation_json(e) for e in qs[:200]]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_escalation_resolve(request, escalation_id):
    if not is_operations_admin(request.user):
        return Response({'detail': 'Operations or Super Admin only.'}, status=403)
    try:
        e = AdminEscalation.objects.select_related('raised_by').get(pk=escalation_id)
    except (AdminEscalation.DoesNotExist, ValueError):
        return Response({'detail': 'Escalation not found.'}, status=404)
    if e.status == 'resolved':
        return Response({'detail': 'Already resolved.'}, status=409)
    action = request.data.get('action', 'resolve')
    if action == 'claim':
        e.assigned_to = request.user
        e.status = 'in_progress'
        e.save(update_fields=['assigned_to', 'status'])
    else:
        resolution = str(request.data.get('resolution', '')).strip()
        if not resolution:
            return Response({'detail': 'A resolution note is required.'}, status=400)
        e.status = 'resolved'
        e.resolution = resolution
        e.resolved_at = timezone.now()
        e.resolved_by = request.user
        e.save(update_fields=['status', 'resolution', 'resolved_at', 'resolved_by'])
        from audit.models import SupportTicket
        SupportTicket.objects.filter(escalation=e).update(status='in_progress', is_escalated=False)
        Notification.objects.create(
            user=e.raised_by, title='Your escalation was resolved', body=resolution,
            notification_type='system', reference_id=e.id, reference_type='admin_escalation',
        )
    _audit(request, 'escalations', f'{action.title()} escalation', 'approve', e.id)
    return Response(_escalation_json(e))


# ── /admin-panel/<module>/export/ (CSV) ─────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_module_export(request, module):
    if not can_perform_action(request.user, module, 'export') and not can_perform_action(request.user, module, 'view'):
        return Response({'detail': 'You cannot export this module.'}, status=403)
    from api.admin_views import _collection_rows
    rows = _collection_rows(request, module)
    if not isinstance(rows, list):
        rows = list(rows)
    fields = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=fields or ['id'], extrasaction='ignore')
    writer.writeheader()
    for row in rows:
        writer.writerow({k: _csv_cell(v) for k, v in row.items()})
    _audit(request, module, f'Exported {len(rows)} {module} rows to CSV', 'export')
    response = HttpResponse(buffer.getvalue(), content_type='text/csv')
    stamp = timezone.now().strftime('%Y%m%d-%H%M')
    response['Content-Disposition'] = f'attachment; filename="{module}-{stamp}.csv"'
    return response


def _csv_cell(value):
    if isinstance(value, (dict, list)):
        import json
        return json.dumps(value, ensure_ascii=False)
    if value is None:
        return ''
    return value


# ── /admin-panel/finance/summary/ ──────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_finance_summary(request):
    if not can_perform_action(request.user, 'finance', 'view'):
        return Response({'detail': 'You cannot view finance.'}, status=403)
    from api.admin_finance import finance_summary
    return finance_summary(request)


# ── /api/<module>/updates/?since=  (per-module aliases of me_updates) ────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def module_updates(request, module):
    """Per-module polling endpoint the spec calls for (research / delivery /
    pharmacy / doctors). Same contract as ``me_updates`` — the payload already
    carries this user's profile verification/approval state and notifications;
    ``module`` just scopes which notification types are echoed first."""
    return Response(_me_updates_payload(request, module=module))


# ── /me/updates/?since=<iso>  (user-facing polling) ─────────────────────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def me_updates(request):
    """Lightweight "what changed for me since <ts>" poll used by every role's
    dashboard to reflect admin actions in near-real-time without WebSockets."""
    return Response(_me_updates_payload(request))


def _me_updates_payload(request, module=None):
    user = request.user
    since = parse_datetime(request.query_params.get('since', '') or '')
    notifications = user.notifications.order_by('-created_at')
    if since:
        notifications = notifications.filter(created_at__gt=since)
    notif_rows = [{
        'id': str(n.id), 'type': n.notification_type, 'title': n.title, 'body': n.body,
        'reference_id': str(n.reference_id) if n.reference_id else None,
        'reference_type': n.reference_type,
        'created_at': n.created_at.isoformat() if n.created_at else None,
    } for n in notifications[:50]]

    profile_state = {}
    for relation, model in (
        ('researcher_profile', ResearcherProfile), ('doctor_profile', DoctorProfile),
        ('delivery_profile', DeliveryProfile), ('pharmacy_organization', PharmacyOrganization),
    ):
        try:
            profile = getattr(user, relation)
        except model.DoesNotExist:
            continue
        profile_state = {
            'kind': relation,
            'is_verified': getattr(profile, 'is_verified', None),
            'approved': getattr(profile, 'approved_by_admin_id', None) is not None,
            'updated_at': profile.updated_at.isoformat() if getattr(profile, 'updated_at', None) else None,
        }
        break

    return {
        'server_time': timezone.now().isoformat(),
        'module': module,
        'account_status': user.account_status,
        'is_verified': bool(user.is_verified),
        'access_revoked': user.account_status == 'suspended',
        'unread_count': user.notifications.filter(is_read=False).count(),
        'notifications': notif_rows,
        'profile': profile_state,
    }


# ── helpers ─────────────────────────────────────────────────────────────────

def _uuid4hex():
    import uuid
    return uuid.uuid4().hex[:12]


def _parse_date(value):
    try:
        return date.fromisoformat(str(value)[:10])
    except (TypeError, ValueError):
        return None


def _sub_role(role_name):
    return role_name[len('admin_'):] if role_name.startswith('admin_') else 'operations'
