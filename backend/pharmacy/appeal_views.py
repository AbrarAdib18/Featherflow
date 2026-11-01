"""Pharmacy suspension appeals (spec §9). New ground — no appeal/dispute
workflow existed anywhere in the codebase before this build; modeled as its
own table (PharmacyAppeal) rather than overloading the generic
AdminEscalation/SupportTicket models, since an appeal needs a strict
lifecycle tied to one specific suspension event."""
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from pharmacy.auth import PharmacyAlwaysOnAuthentication
from pharmacy.models import PharmacyAppeal
from pharmacy.permissions import IsPharmacyAccount
from pharmacy.services import SUSPENSION_REASONS, log_pharmacy_action, notify_pharmacy_admins


def _appeal_json(appeal):
    return {
        'id': str(appeal.id), 'reason': appeal.reason, 'explanation': appeal.explanation,
        'attachments': appeal.attachments or [], 'status': appeal.status,
        'admin_response': appeal.admin_response or '',
        'resolved_at': appeal.resolved_at.isoformat() if appeal.resolved_at else None,
        'created_at': appeal.created_at.isoformat() if appeal.created_at else None,
    }


@api_view(['GET', 'POST'])
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def appeals(request):
    if request.method == 'GET':
        qs = PharmacyAppeal.objects.filter(pharmacy_user=request.user).order_by('-created_at')
        return Response({'results': [_appeal_json(a) for a in qs], 'reasons': SUSPENSION_REASONS})

    if request.user.account_status != 'suspended':
        return Response({'detail': 'Only a suspended account can file an appeal.'}, status=409)
    existing_open = PharmacyAppeal.objects.filter(
        pharmacy_user=request.user, status__in=PharmacyAppeal.OPEN_STATUSES).first()
    if existing_open and existing_open.status != 'more_info_required':
        return Response({'detail': 'You already have an appeal under review.'}, status=409)

    reason = str(request.data.get('reason', '')).strip()
    explanation = str(request.data.get('explanation', '')).strip()
    if not reason or reason not in SUSPENSION_REASONS:
        return Response({'detail': f'reason must be one of {SUSPENSION_REASONS}.'}, status=400)
    if not explanation:
        return Response({'detail': 'An explanation is required.'}, status=400)
    attachments = request.data.get('attachments') or []
    if not isinstance(attachments, list):
        attachments = []
    attachments = [str(a) for a in attachments][:10]

    if existing_open is not None:
        # Resubmission after "more information required" — update in place
        # rather than creating a second row, per spec §9's resubmission flow.
        existing_open.reason = reason
        existing_open.explanation = explanation
        existing_open.attachments = attachments
        existing_open.status = 'submitted'
        existing_open.updated_at = timezone.now()
        existing_open.save(update_fields=['reason', 'explanation', 'attachments', 'status', 'updated_at'])
        log_pharmacy_action(request.user, 'Pharmacy resubmitted appeal', 'edit',
                            'pharmacy_appeal', existing_open.id)
        notify_pharmacy_admins(
            'Pharmacy appeal resubmitted',
            f'{request.user.full_name or request.user.email} resubmitted their suspension appeal.',
            reference_type='pharmacy_appeal')
        return Response(_appeal_json(existing_open))

    last_suspend = ActivityLog.objects.filter(
        entity_type='pharmacy_account', entity_id=request.user.id, action_type='suspend',
    ).order_by('-created_at').first()
    appeal = PharmacyAppeal.objects.create(
        pharmacy_user=request.user, suspension_log_id=last_suspend.id if last_suspend else None,
        reason=reason, explanation=explanation, attachments=attachments, status='submitted',
        created_at=timezone.now(), updated_at=timezone.now(),
    )
    log_pharmacy_action(request.user, 'Pharmacy submitted appeal', 'create', 'pharmacy_appeal', appeal.id)
    notify_pharmacy_admins(
        'New pharmacy appeal',
        f'{request.user.full_name or request.user.email} submitted a suspension appeal.',
        reference_type='pharmacy_appeal')
    return Response(_appeal_json(appeal), status=201)
