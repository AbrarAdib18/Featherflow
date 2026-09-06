"""Approval queue: park a sensitive admin action until a higher tier decides.

``enqueue_approval`` is called from the admin views when
``admin_rbac.requires_approval`` says the caller's tier is too low. When an
approver (or Super Admin override) approves the entry, ``execute_approved`` runs
the parked action with the approver as the actor and writes an audit row.

Only the bounded set of sensitive actions is executable here
(suspend / refund / soft-delete admin / team role change); anything else is
recorded and surfaced but must be re-issued by an authorised admin.
"""

from django.db import transaction
from django.utils import timezone

from audit.models import ActivityLog, AdminApprovalQueue
from notifications.models import Notification
from profiles.models import DeliveryProfile, DoctorProfile, ResearcherProfile
from users.models import Role, User

from api.admin_rbac import canonical_module


def _client_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
    return forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR')


def _audit(actor, module, action, action_type, target_id=None, reason='', old=None, new=None, request=None):
    ActivityLog.objects.create(
        user=actor, module=module, action=action, action_type=action_type,
        entity_type=canonical_module(module), entity_id=target_id,
        old_values=old, new_values=new, reason=reason or None,
        ip_address=_client_ip(request) if request else None,
        user_agent=((request.META.get('HTTP_USER_AGENT') or '')[:1000] or None) if request else None,
    )


def enqueue_approval(request, action_type, module, target_id, target_type,
                     request_data, required_tier, reason=''):
    entry = AdminApprovalQueue.objects.create(
        requested_by=request.user,
        action_type=action_type,
        module_affected=module,
        target_id=_uuid(target_id),
        target_type=target_type,
        request_data=_jsonable(request_data),
        required_tier=required_tier,
        reason=reason or str(request.data.get('reason', '')) or None,
    )
    _audit(request.user, module, f'Queued {action_type} for approval', 'edit',
           target_id=_uuid(target_id), reason=entry.reason or '', request=request)
    # Notify eligible approvers (tier <= required_tier).
    approvers = [
        u for u in User.objects.filter(roles__panel_type='admin').distinct()
        if _tier(u) is not None and _tier(u) <= required_tier and u.id != request.user.id
    ]
    for approver in approvers:
        Notification.objects.create(
            user=approver, title='Admin action needs your approval',
            body=f'{request.user.full_name or request.user.email} requested '
                 f'"{action_type}" on {canonical_module(module)}.',
            notification_type='approval', reference_id=entry.id,
            reference_type='admin_approval_queue',
        )
    return entry


def decide(entry, approver, request, approve, rejection_reason=''):
    if entry.status != 'pending':
        return False, f'This request was already {entry.status}.'
    with transaction.atomic():
        entry = AdminApprovalQueue.objects.select_for_update().get(pk=entry.pk)
        if entry.status != 'pending':
            return False, f'This request was already {entry.status}.'
        if approve:
            ok, message, ref = execute_approved(entry, approver, request)
            if not ok:
                return False, message
            entry.status = 'approved'
            entry.result_ref_id = _uuid(ref)
        else:
            if not rejection_reason:
                return False, 'A rejection reason is required.'
            entry.status = 'rejected'
            entry.rejection_reason = rejection_reason
        entry.approved_by = approver
        entry.decided_at = timezone.now()
        entry.save(update_fields=['status', 'approved_by', 'decided_at',
                                  'rejection_reason', 'result_ref_id'])
    Notification.objects.create(
        user=entry.requested_by,
        title=f'Your admin request was {entry.status}',
        body=f'"{entry.action_type}" on {canonical_module(entry.module_affected)} '
             f'was {entry.status} by {approver.full_name or approver.email}.'
             + (f' Reason: {rejection_reason}' if rejection_reason else ''),
        notification_type='approval', reference_id=entry.id,
        reference_type='admin_approval_queue',
    )
    _audit(approver, entry.module_affected,
           f'{"Approved" if approve else "Rejected"} {entry.action_type} request',
           'approve' if approve else 'reject',
           target_id=entry.target_id, reason=rejection_reason, request=request)
    return True, 'approved' if approve else 'rejected'


def execute_approved(entry, approver, request):
    """Run the parked action. Returns (ok, message, result_ref_id)."""
    module = canonical_module(entry.module_affected)
    action = entry.action_type
    data = entry.request_data or {}
    target = entry.target_id

    if action == 'suspend':
        return _do_suspend(entry.module_affected, target, approver, request, data)
    if action == 'refund':
        return _do_refund(entry.module_affected, target, approver, request, data)
    if action == 'delete' and module in ('team', 'users'):
        return _do_soft_delete_admin(target, approver, request, data)
    if action == 'assign' and module == 'team':
        return _do_team_role_change(target, approver, request, data)
    # Recorded but not auto-executable — the approver must re-issue it.
    return True, 'approved (manual follow-up required)', None


def _do_suspend(module, target, approver, request, data):
    reason = str(data.get('reason', '')) or 'Suspended via approval queue.'
    try:
        user = None
        if module in ('users', 'pharmacies'):
            user = User.objects.get(pk=target)
        elif module == 'doctors':
            profile = DoctorProfile.objects.select_related('user').get(pk=target)
            profile.is_verified = False
            profile.is_available = False
            profile.save(update_fields=['is_verified', 'is_available', 'updated_at'])
            user = profile.user
        elif module == 'researchers':
            profile = ResearcherProfile.objects.select_related('user').get(pk=target)
            user = profile.user
        elif module == 'riders':
            profile = DeliveryProfile.objects.select_related('user').get(pk=target)
            user = profile.user
        if user is None:
            return False, 'Target not found.', None
        user.account_status = 'suspended'
        user.save(update_fields=['account_status', 'updated_at'])
    except (User.DoesNotExist, DoctorProfile.DoesNotExist,
            ResearcherProfile.DoesNotExist, DeliveryProfile.DoesNotExist, ValueError):
        return False, 'Target not found.', None
    Notification.objects.create(
        user=user, title='Your account has been suspended',
        body=f'An administrator suspended your account. Reason: {reason}',
        notification_type='system',
    )
    _audit(approver, module, 'Suspend (via approval)', 'suspend',
           target_id=target, reason=reason, request=request)
    return True, 'suspended', target


def _do_refund(module, target, approver, request, data):
    from delivery.models import DeliveryEarning
    if module == 'payouts':
        try:
            earning = DeliveryEarning.objects.select_related('delivery_person__user').get(pk=target)
        except (DeliveryEarning.DoesNotExist, ValueError):
            return False, 'Payout not found.', None
        if earning.payout_status == 'paid':
            return False, 'Already paid.', None
        earning.payout_status = 'paid'
        earning.payout_date = timezone.now().date()
        earning.save(update_fields=['payout_status', 'payout_date'])
        Notification.objects.create(
            user=earning.delivery_person.user, title='Payout processed',
            body=f'Your payout of ৳{earning.total_earned} has been approved and processed.',
            notification_type='system', reference_id=earning.id, reference_type='delivery_payout',
        )
        _audit(approver, 'payouts', 'Mark paid (via approval)', 'refund',
               target_id=target, request=request)
        return True, 'paid', target
    # payments (JSON-backed) — mark refunded
    from audit.models import AdminPanelRecord
    rec = AdminPanelRecord.objects.filter(module='payments', record_id=str(target)).first()
    if not rec:
        return False, 'Payment not found.', None
    rec.payload = {**rec.payload, 'status': 'Refunded'}
    rec.save(update_fields=['payload', 'updated_at'])
    _audit(approver, 'payments', 'Refund (via approval)', 'refund', request=request)
    return True, 'refunded', target


def _do_soft_delete_admin(target, approver, request, data):
    try:
        user = User.objects.get(pk=target)
    except (User.DoesNotExist, ValueError):
        return False, 'Admin not found.', None
    user.account_status = 'suspended'
    user.save(update_fields=['account_status', 'updated_at'])
    profile = getattr(user, 'admin_profile', None)
    if profile is not None:
        profile.is_active = False
        profile.is_suspended = True
        profile.suspended_at = timezone.now()
        profile.suspended_by = approver
        profile.save(update_fields=['is_active', 'is_suspended', 'suspended_at',
                                    'suspended_by', 'updated_at'])
    _audit(approver, 'team', 'Deactivate admin (via approval)', 'delete',
           target_id=target, request=request)
    return True, 'deactivated', target


def _do_team_role_change(target, approver, request, data):
    new_role = data.get('role')
    if not new_role:
        return False, 'No target role in the request.', None
    role_name = new_role if new_role.startswith('admin_') else (
        'admin_' + new_role.lower().replace(' admin', '').replace(' agent', '').replace(' ', '_'))
    try:
        user = User.objects.get(pk=target)
        role = Role.objects.get(name=role_name)
    except (User.DoesNotExist, Role.DoesNotExist, ValueError):
        return False, 'User or role not found.', None
    user.roles.remove(*user.roles.filter(panel_type='admin'))
    user.roles.add(role)
    profile = getattr(user, 'admin_profile', None)
    if profile is not None:
        profile.admin_role = role
        profile.save(update_fields=['admin_role', 'updated_at'])
    Notification.objects.create(
        user=user, title='Your admin role changed',
        body=f'Your role is now {role.display_name} (approved by '
             f'{approver.full_name or approver.email}).',
        notification_type='approval',
    )
    _audit(approver, 'team', f'Role change to {role_name} (via approval)', 'assign',
           target_id=target, request=request)
    return True, 'role_changed', target


# ── small utils ─────────────────────────────────────────────────────────────

def _uuid(value):
    import uuid
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError, AttributeError):
        return None


def _tier(user):
    from api.admin_rbac import admin_tier
    return admin_tier(user)


def _jsonable(data):
    out = {}
    for key, value in dict(data).items():
        try:
            import json
            json.dumps(value)
            out[key] = value
        except (TypeError, ValueError):
            out[key] = str(value)
    return out
