"""Feed Inventory Owner <-> Feed Admin private chat.

Reuses doctor.Conversation/Message verbatim (consultation=NULL) plus the two
generic columns pharmacy_admin_portal_extension.sql already added to
`conversations` (pharmacy_chat_status/assigned_admin) — filtered by
roles__name='feed_owner' instead of 'pharmacy'. This is a private 1:1
owner<->admin-team thread, never a public Community conversation. Mirrors
pharmacy/chat_views.py file-for-file; see api/admin_feed_chat.py for the
Feed Admin team-inbox side.
"""
from django.db.models import Q
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from doctor.models import Conversation, Message
from doctor.serializers import MessageSerializer
from messaging.realtime import emit_to_conversation
from users.models import User

from .owner_permissions import IsFeedOwnerAccount


def _owner_conversation_qs(user):
    return Conversation.objects.filter(
        Q(participant_one=user) | Q(participant_two=user), consultation__isnull=True)


def _any_feed_admin():
    return User.objects.filter(roles__name='feed_admin').order_by('id').first()


def _notify_feed_admins(title, body):
    from notifications.models import Notification
    for admin in User.objects.filter(roles__name='feed_admin').distinct():
        Notification.objects.create(
            user=admin, title=title, body=body,
            notification_type='alert', reference_type='feed_owner_conversation')


def _conversation_json(conversation, viewer):
    messages = conversation.messages.order_by('sent_at')
    last_at = conversation.last_message_at or conversation.created_at
    return {
        'id': str(conversation.id),
        'status': conversation.pharmacy_chat_status or 'open',
        'created_at': conversation.created_at.isoformat() if conversation.created_at else None,
        'last_message_at': last_at.isoformat() if last_at else None,
        'unread_count': messages.exclude(sender=viewer).filter(is_read=False).count(),
        'messages': [{
            'id': str(m.id), 'sender_id': str(m.sender_id), 'is_mine': m.sender_id == viewer.id,
            'content': m.content or m.file_url or '', 'message_type': m.message_type,
            'file_url': m.file_url, 'is_read': m.is_read, 'sent_at': m.sent_at.isoformat(),
        } for m in messages],
    }


@api_view(['GET', 'POST'])
@permission_classes([IsFeedOwnerAccount])
def owner_conversation(request):
    """GET returns the owner's one admin chat thread (`exists: False` if
    none yet); POST get-or-creates it."""
    existing = _owner_conversation_qs(request.user).first()
    if request.method == 'GET':
        if existing is None:
            return Response({'exists': False})
        return Response({'exists': True, **_conversation_json(existing, request.user)})

    if existing is not None:
        return Response({'exists': True, **_conversation_json(existing, request.user)})
    admin = _any_feed_admin()
    if admin is None:
        return Response(
            {'detail': 'No Feed Marketplace Admin is currently available. Please try again shortly.'}, status=503)
    conversation = Conversation.objects.create(
        participant_one=request.user, participant_two=admin,
        pharmacy_chat_status='open', created_at=timezone.now())
    _notify_feed_admins(
        'New feed inventory owner conversation',
        f'{request.user.full_name or request.user.email} started a conversation.')
    return Response({'exists': True, **_conversation_json(conversation, request.user)}, status=201)


@api_view(['POST', 'PATCH'])
@permission_classes([IsFeedOwnerAccount])
def owner_conversation_detail(request, conversation_id):
    conversation = _owner_conversation_qs(request.user).filter(id=conversation_id).first()
    if conversation is None:
        return Response({'detail': 'Conversation not found.'}, status=404)
    if request.method == 'PATCH':
        conversation.messages.exclude(sender=request.user).filter(is_read=False).update(is_read=True)
        return Response({'unread_count': 0})

    serializer = MessageSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    message = Message.objects.create(conversation=conversation, sender=request.user, **serializer.validated_data)
    conversation.last_message_at = message.sent_at
    conversation.pharmacy_chat_status = 'waiting_for_admin'
    conversation.save(update_fields=['last_message_at', 'pharmacy_chat_status'])
    _notify_feed_admins(
        'New feed owner message',
        f'{request.user.full_name or request.user.email}: {(message.content or "")[:120]}')
    payload = {
        'id': str(message.id), 'conversation_id': str(conversation.id), 'sender_id': str(request.user.id),
        'content': message.content or message.file_url or '', 'message_type': message.message_type,
        'file_url': message.file_url, 'is_read': False, 'sent_at': message.sent_at.isoformat(),
    }
    emit_to_conversation(conversation.id, 'message_created', payload)
    return Response(payload, status=201)
