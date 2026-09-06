"""Support desk — real ``support_tickets`` table behind the admin ``support-tickets``
module and the user-facing ``/api/support/`` endpoints.

Replaces the JSON ``backend_admin_records`` seed rows the panel used before.
"""

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from audit.models import ActivityLog, AdminEscalation, SupportTicket, SupportTicketReply
from notifications.models import Notification
from users.models import User


def _ticket_number():
    count = SupportTicket.objects.count() + 1
    return f'SUP-{count:05d}'


def _reply_json(reply):
    return {
        'id': str(reply.id),
        'author': (reply.author.full_name or reply.author.email) if reply.author_id else 'System',
        'author_role': reply.author_role or '',
        'body': reply.body,
        'is_internal': reply.is_internal,
        'created_at': reply.created_at.isoformat() if reply.created_at else None,
    }


def ticket_json(ticket, include_replies=False):
    data = {
        'id': str(ticket.id),
        'ticket_number': ticket.ticket_number,
        'user': ticket.raised_by_name or (
            (ticket.raised_by.full_name or ticket.raised_by.email) if ticket.raised_by_id else 'Guest'),
        'user_id': str(ticket.raised_by_id) if ticket.raised_by_id else None,
        'subject': ticket.subject,
        'description': ticket.description or '',
        'category': ticket.category,
        'type': ticket.category.replace('_', ' ').title(),
        'priority': ticket.priority.title(),
        'status': ticket.status.replace('_', ' ').title(),
        'is_escalated': ticket.is_escalated,
        'assigned_to': (ticket.assigned_to.full_name or ticket.assigned_to.email) if ticket.assigned_to_id else None,
        'assigned_to_id': str(ticket.assigned_to_id) if ticket.assigned_to_id else None,
        'resolution': ticket.resolution or '',
        'date': ticket.created_at.strftime('%b %d, %Y %I:%M %p') if ticket.created_at else '',
        'created_at': ticket.created_at.isoformat() if ticket.created_at else None,
        'updated_at': ticket.updated_at.isoformat() if ticket.updated_at else None,
    }
    if include_replies:
        data['replies'] = [_reply_json(r) for r in ticket.replies.select_related('author')]
    return data


def ticket_rows(request):
    qs = SupportTicket.objects.select_related('raised_by', 'assigned_to').all()
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter.lower().replace(' ', '_'))
    search = request.query_params.get('q')
    if search:
        qs = qs.filter(Q(subject__icontains=search) | Q(ticket_number__icontains=search)
                       | Q(raised_by_name__icontains=search))
    return [ticket_json(t) for t in qs[:300]]


def _audit(request, action, action_type, ticket_id, reason=''):
    ActivityLog.objects.create(
        user=request.user, module='support-tickets', action=action,
        action_type=action_type, entity_type='support', entity_id=ticket_id,
        reason=reason or None,
        ip_address=(request.META.get('HTTP_X_FORWARDED_FOR') or request.META.get('REMOTE_ADDR')),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


def admin_create_ticket(request):
    subject = str(request.data.get('subject', '')).strip()
    if not subject:
        return Response({'detail': 'A subject is required.'}, status=400)
    ticket = SupportTicket.objects.create(
        ticket_number=_ticket_number(),
        raised_by_id=request.data.get('user_id') or None,
        raised_by_name=request.data.get('user') or None,
        assigned_to=request.user,
        category=request.data.get('category', 'general'),
        subject=subject,
        description=request.data.get('description', ''),
        priority=str(request.data.get('priority', 'medium')).lower(),
    )
    _audit(request, 'Create ticket', 'create', ticket.id)
    return Response(ticket_json(ticket, include_replies=True), status=201)


def admin_update_ticket(request, ticket_id):
    try:
        ticket = SupportTicket.objects.select_related('raised_by', 'assigned_to').get(pk=ticket_id)
    except (SupportTicket.DoesNotExist, ValueError):
        return Response({'detail': 'Ticket not found.'}, status=404)

    action = request.data.get('action')
    reason = str(request.data.get('reason', ''))

    if action == 'assign':
        assignee_id = request.data.get('assigned_to_id') or request.user.id
        ticket.assigned_to_id = assignee_id
        ticket.status = 'in_progress'
        ticket.save(update_fields=['assigned_to', 'status', 'updated_at'])
        _audit(request, 'Assign ticket', 'assign', ticket.id, reason)

    elif action == 'reply':
        body = str(request.data.get('body', '')).strip()
        if not body:
            return Response({'detail': 'Reply text is required.'}, status=400)
        SupportTicketReply.objects.create(
            ticket=ticket, author=request.user, author_role='admin',
            body=body, is_internal=bool(request.data.get('is_internal', False)),
        )
        if ticket.status == 'open':
            ticket.status = 'in_progress'
            ticket.save(update_fields=['status', 'updated_at'])
        if ticket.raised_by_id and not request.data.get('is_internal'):
            Notification.objects.create(
                user=ticket.raised_by, title=f'Reply on ticket {ticket.ticket_number}',
                body=body[:200], notification_type='message',
                reference_id=ticket.id, reference_type='support_ticket',
            )
        _audit(request, 'Reply to ticket', 'edit', ticket.id)

    elif action == 'resolve':
        ticket.status = 'resolved'
        ticket.resolution = reason or request.data.get('resolution', '')
        ticket.resolved_at = timezone.now()
        ticket.save(update_fields=['status', 'resolution', 'resolved_at', 'updated_at'])
        if ticket.raised_by_id:
            Notification.objects.create(
                user=ticket.raised_by, title=f'Ticket {ticket.ticket_number} resolved',
                body=ticket.resolution or 'Your support ticket has been resolved.',
                notification_type='system', reference_id=ticket.id, reference_type='support_ticket',
            )
        _audit(request, 'Resolve ticket', 'approve', ticket.id, reason)

    elif action == 'escalate':
        with transaction.atomic():
            escalation = AdminEscalation.objects.create(
                raised_by=request.user, module='support',
                target_id=ticket.id, target_type='support_ticket',
                priority='high' if ticket.priority in ('high', 'critical') else 'medium',
                subject=f'Escalated: {ticket.subject}',
                detail=reason or 'Escalated from the support desk.',
            )
            ticket.is_escalated = True
            ticket.status = 'escalated'
            ticket.escalation = escalation
            ticket.save(update_fields=['is_escalated', 'status', 'escalation', 'updated_at'])
        for admin in User.objects.filter(roles__name__in=['admin_super', 'admin_operations']).distinct():
            Notification.objects.create(
                user=admin, title='Support ticket escalated',
                body=f'{ticket.ticket_number}: {ticket.subject}',
                notification_type='alert', reference_id=escalation.id,
                reference_type='admin_escalation',
            )
        _audit(request, 'Escalate ticket', 'edit', ticket.id, reason)

    else:
        for field in ('priority', 'category', 'status'):
            if field in request.data:
                setattr(ticket, field, str(request.data[field]).lower().replace(' ', '_'))
        ticket.save()
        _audit(request, 'Update ticket', 'edit', ticket.id)

    ticket.refresh_from_db()
    return Response(ticket_json(ticket, include_replies=True))


# ── user-facing: file and track your own tickets ────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def my_tickets(request):
    if request.method == 'POST':
        subject = str(request.data.get('subject', '')).strip()
        if not subject:
            return Response({'detail': 'A subject is required.'}, status=400)
        ticket = SupportTicket.objects.create(
            ticket_number=_ticket_number(),
            raised_by=request.user,
            raised_by_name=request.user.full_name or request.user.email,
            category=request.data.get('category', 'general'),
            subject=subject,
            description=request.data.get('description', ''),
            priority=str(request.data.get('priority', 'medium')).lower(),
        )
        for agent in User.objects.filter(roles__name__in=['admin_support', 'admin_operations']).distinct():
            Notification.objects.create(
                user=agent, title='New support ticket',
                body=f'{ticket.ticket_number}: {subject}',
                notification_type='alert', reference_id=ticket.id, reference_type='support_ticket',
            )
        return Response(ticket_json(ticket, include_replies=True), status=201)
    qs = SupportTicket.objects.filter(raised_by=request.user).select_related('assigned_to')
    return Response({'results': [ticket_json(t, include_replies=True) for t in qs]})
