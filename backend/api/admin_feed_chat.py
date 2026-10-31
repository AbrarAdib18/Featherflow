"""Feed Marketplace Admin — Feed Inventory Owner chat inbox.

Mirrors api/admin_pharmacy_chat.py file-for-file: any admin holding
feed-catalogue view/edit permission can see and reply to every feed owner's
conversation (a team inbox), gated by RBAC (can_perform_action), not by
conversation participant identity. Reuses doctor.Conversation/Message +
pharmacy_chat_status/assigned_admin, filtered by roles__name='feed_owner'.
"""
from django.db.models import Q
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from doctor.models import Conversation, Message
from doctor.serializers import MessageSerializer
from messaging.realtime import emit_to_conversation
from notifications.models import Notification
from users.models import User

from api.admin_rbac import IsAdminUser, can_perform_action


def _deny(user, action):
    # 'feed-orders' already grants feed_admin view/edit/assign (feed_marketplace
    # _extension.sql) — reused here rather than adding a new permission module
    # just for chat.
    if not can_perform_action(user, 'feed-orders', action):
        return Response(
            {'detail': f'Your admin role cannot "{action}" in the feed-orders module.',
             'code': 'forbidden_module_action'}, status=403)
    return None


def _feed_owner_conversations_qs():
    return Conversation.objects.filter(consultation__isnull=True).filter(
        Q(participant_one__roles__name='feed_owner') | Q(participant_two__roles__name='feed_owner'),
    ).distinct()


def _owner_participant(conversation):
    if conversation.participant_one.roles.filter(name='feed_owner').exists():
        return conversation.participant_one
    return conversation.participant_two


def _row_json(conversation):
    owner = _owner_participant(conversation)
    messages = conversation.messages.order_by('sent_at')
    last = messages.last()
    last_at = conversation.last_message_at or conversation.created_at
    return {
        'id': str(conversation.id),
        'owner_id': str(owner.id),
        'owner_name': owner.full_name or owner.email,
        'status': conversation.pharmacy_chat_status or 'open',
        'assigned_admin_id': str(conversation.assigned_admin_id) if conversation.assigned_admin_id else None,
        'unread_count': messages.filter(is_read=False).exclude(sender=owner).count(),
        'last_message': (last.content or last.file_url or '') if last else '',
        'last_message_at': last_at.isoformat() if last_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_feed_chats(request):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    qs = _feed_owner_conversations_qs().select_related(
        'participant_one', 'participant_two', 'assigned_admin').order_by('-last_message_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(pharmacy_chat_status=status_filter)
    rows = [_row_json(c) for c in qs]
    search = (request.query_params.get('search') or '').strip().lower()
    if search:
        rows = [r for r in rows if search in r['owner_name'].lower()]
    if request.query_params.get('unread') == 'true':
        rows = [r for r in rows if r['unread_count'] > 0]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_feed_chat_detail(request, conversation_id):
    denied = _deny(request.user, 'view')
    if denied:
        return denied
    conversation = _feed_owner_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    owner = _owner_participant(conversation)
    messages = conversation.messages.order_by('sent_at')
    return Response({
        **_row_json(conversation),
        'messages': [{
            'id': str(m.id), 'sender_id': str(m.sender_id), 'from_owner': m.sender_id == owner.id,
            'content': m.content or m.file_url or '', 'message_type': m.message_type,
            'file_url': m.file_url, 'is_read': m.is_read, 'sent_at': m.sent_at.isoformat(),
        } for m in messages],
    })


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_feed_chat_reply(request, conversation_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    conversation = _feed_owner_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    serializer = MessageSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    message = Message.objects.create(conversation=conversation, sender=request.user, **serializer.validated_data)
    conversation.last_message_at = message.sent_at
    conversation.pharmacy_chat_status = 'waiting_for_pharmacy'
    conversation.save(update_fields=['last_message_at', 'pharmacy_chat_status'])
    owner = _owner_participant(conversation)
    Notification.objects.create(
        user=owner, title='New message from Feed Marketplace Admin',
        body=(message.content or message.file_url or '')[:200],
        notification_type='message', reference_type='feed_owner_conversation')
    payload = {
        'id': str(message.id), 'conversation_id': str(conversation.id), 'sender_id': str(request.user.id),
        'content': message.content or message.file_url or '', 'message_type': message.message_type,
        'file_url': message.file_url, 'is_read': False, 'sent_at': message.sent_at.isoformat(),
    }
    emit_to_conversation(conversation.id, 'message_created', payload)
    return Response(payload, status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_feed_chat_status(request, conversation_id):
    denied = _deny(request.user, 'edit')
    if denied:
        return denied
    conversation = _feed_owner_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    new_status = request.data.get('status')
    valid = {'open', 'waiting_for_pharmacy', 'waiting_for_admin', 'resolved', 'reopened'}
    if new_status not in valid:
        return Response({'detail': f'status must be one of {sorted(valid)}.'}, status=400)
    conversation.pharmacy_chat_status = new_status
    conversation.save(update_fields=['pharmacy_chat_status'])
    return Response(_row_json(conversation))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_feed_chat_assign(request, conversation_id):
    denied = _deny(request.user, 'assign')
    if denied:
        return denied
    conversation = _feed_owner_conversations_qs().filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    admin_id = request.data.get('admin_id')
    admin_user = User.objects.filter(pk=admin_id, roles__panel_type='admin').first() if admin_id else None
    if admin_id and admin_user is None:
        return Response({'detail': 'Admin not found.'}, status=404)
    conversation.assigned_admin = admin_user
    conversation.save(update_fields=['assigned_admin'])
    return Response(_row_json(conversation))
