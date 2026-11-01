"""Pharmacy Admin — support chat inbox.

Any admin holding pharmacy view/edit permission can see and reply to every
pharmacy's support conversation (a team inbox), unlike the strict 1:1
participant model doctor-farmer chat uses — access here is gated by RBAC
(api.admin_rbac.can_perform_action), not by conversation participant
identity. `assigned_admin_id` tracks ownership without ever rewriting
historical message sender attribution (participant_two stays whichever admin
happened to open the thread).
"""
from django.db.models import Q
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from doctor.models import Conversation, Message
from doctor.serializers import MessageSerializer
from messaging.realtime import emit_to_conversation
from users.models import User

from api.admin_rbac import IsAdminUser, can_perform_action
from pharmacy.services import log_pharmacy_action, notify


def _deny(user, action):
    if not can_perform_action(user, 'pharmacy', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the pharmacy module.',
             'code': 'forbidden_module_action'}, status=403)
    return None


def _pharmacy_conversations_qs():
    return Conversation.objects.filter(consultation__isnull=True).filter(
        Q(participant_one__roles__name='pharmacy') | Q(participant_two__roles__name='pharmacy'),
    ).distinct()


def _pharmacy_participant(conversation):
    if conversation.participant_one.roles.filter(name='pharmacy').exists():
        return conversation.participant_one
    return conversation.participant_two


def _row_json(conversation):
    pharmacy = _pharmacy_participant(conversation)
    messages = conversation.messages.order_by('sent_at')
    last = messages.last()
    last_at = conversation.last_message_at or conversation.created_at
    return {
        'id': str(conversation.id),
        'pharmacy_id': str(pharmacy.id),
        'pharmacy_name': pharmacy.full_name or pharmacy.email,
        'status': conversation.pharmacy_chat_status or 'open',
        'assigned_admin_id': str(conversation.assigned_admin_id) if conversation.assigned_admin_id else None,
        'unread_count': messages.filter(is_read=False).exclude(sender=pharmacy).count(),
        'last_message': (last.content or last.file_url or '') if last else '',
        'last_message_at': last_at.isoformat() if last_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_chats(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = _pharmacy_conversations_qs().select_related(
        'participant_one', 'participant_two', 'assigned_admin').order_by('-last_message_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(pharmacy_chat_status=status_filter)
    rows = [_row_json(c) for c in qs]
    search = (request.query_params.get('search') or '').strip().lower()
    if search:
        rows = [r for r in rows if search in r['pharmacy_name'].lower()]
    if request.query_params.get('unread') == 'true':
        rows = [r for r in rows if r['unread_count'] > 0]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_pharmacy_chat_detail(request, conversation_id):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    conversation = _pharmacy_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    pharmacy = _pharmacy_participant(conversation)
    messages = conversation.messages.order_by('sent_at')
    return Response({
        **_row_json(conversation),
        'messages': [{
            'id': str(m.id), 'sender_id': str(m.sender_id), 'from_pharmacy': m.sender_id == pharmacy.id,
            'content': m.content or m.file_url or '', 'message_type': m.message_type,
            'file_url': m.file_url, 'is_read': m.is_read, 'sent_at': m.sent_at.isoformat(),
        } for m in messages],
    })


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_pharmacy_chat_reply(request, conversation_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    conversation = _pharmacy_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    serializer = MessageSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    message = Message.objects.create(conversation=conversation, sender=request.user, **serializer.validated_data)
    conversation.last_message_at = message.sent_at
    conversation.pharmacy_chat_status = 'waiting_for_pharmacy'
    conversation.save(update_fields=['last_message_at', 'pharmacy_chat_status'])
    pharmacy = _pharmacy_participant(conversation)
    notify(pharmacy, 'New message from Pharmacy Admin', (message.content or message.file_url or '')[:200],
          reference_type='pharmacy_conversation', notification_type='message')
    payload = {
        'id': str(message.id), 'conversation_id': str(conversation.id), 'sender_id': str(request.user.id),
        'content': message.content or message.file_url or '', 'message_type': message.message_type,
        'file_url': message.file_url, 'is_read': False, 'sent_at': message.sent_at.isoformat(),
    }
    emit_to_conversation(conversation.id, 'message_created', payload)
    log_pharmacy_action(request.user, 'Admin replied to pharmacy conversation', 'edit',
                        'pharmacy_conversation', conversation.id, request=request)
    return Response(payload, status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_chat_status(request, conversation_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    conversation = _pharmacy_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    new_status = request.data.get('status')
    valid = {'open', 'waiting_for_pharmacy', 'waiting_for_admin', 'resolved', 'reopened'}
    if new_status not in valid:
        return Response({'detail': f'status must be one of {sorted(valid)}.'}, status=400)
    conversation.pharmacy_chat_status = new_status
    conversation.save(update_fields=['pharmacy_chat_status'])
    log_pharmacy_action(request.user, f'Pharmacy conversation marked {new_status}', 'edit',
                        'pharmacy_conversation', conversation.id, request=request)
    return Response(_row_json(conversation))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_pharmacy_chat_assign(request, conversation_id):
    denied = _deny(request.user, 'assign')
    if denied:
        return denied
    conversation = _pharmacy_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    admin_id = request.data.get('admin_id')
    admin_user = User.objects.filter(pk=admin_id, roles__panel_type='admin').first() if admin_id else None
    if admin_id and admin_user is None:
        return Response({'detail': 'Admin not found.'}, status=404)
    conversation.assigned_admin = admin_user
    conversation.save(update_fields=['assigned_admin'])
    log_pharmacy_action(request.user, 'Pharmacy conversation reassigned', 'assign',
                        'pharmacy_conversation', conversation.id, request=request)
    return Response(_row_json(conversation))
