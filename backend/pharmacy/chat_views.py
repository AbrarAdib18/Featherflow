"""Pharmacy <-> Pharmacy Admin support chat.

Reuses doctor.Conversation/Message verbatim (see PHARMACY_ADMIN_AUDIT.md
§1.6) — those models have zero doctor-specific logic (`consultation` is
nullable, participants are plain User FKs), so no new chat schema was needed,
only the two additive columns on `conversations`
(pharmacy_chat_status/assigned_admin_id, pharmacy_admin_portal_extension.sql).

A pharmacy support thread is a Conversation with consultation=NULL. The admin
side (api/admin_pharmacy_chat.py) is a team inbox gated by RBAC, not by which
admin happens to be `participant_two` — any admin with pharmacy permission can
view and reply, so `participant_two` here is structurally required but
otherwise incidental.
"""
from django.db.models import Q
from django.utils import timezone
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from doctor.models import Conversation, Message
from doctor.serializers import MessageSerializer
from messaging.realtime import emit_to_conversation
from users.models import User

from pharmacy.auth import PharmacyAlwaysOnAuthentication
from pharmacy.permissions import IsPharmacyAccount
from pharmacy.services import log_pharmacy_action, notify_pharmacy_admins


def _pharmacy_conversation_qs(user):
    return Conversation.objects.filter(
        Q(participant_one=user) | Q(participant_two=user), consultation__isnull=True)


def _any_admin():
    return User.objects.filter(
        roles__name__in=['admin_pharmacy', 'admin_operations', 'admin_super']).order_by('id').first()


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
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def support_conversation(request):
    """GET returns the pharmacy's one admin-support thread (`exists: False`
    if none yet); POST get-or-creates it. Reachable at every lifecycle stage
    — PENDING_REVIEW, SUSPENDED, etc. — per spec §1/§8."""
    existing = _pharmacy_conversation_qs(request.user).first()
    if request.method == 'GET':
        if existing is None:
            return Response({'exists': False})
        return Response({'exists': True, **_conversation_json(existing, request.user)})

    if existing is not None:
        return Response({'exists': True, **_conversation_json(existing, request.user)})
    admin = _any_admin()
    if admin is None:
        return Response(
            {'detail': 'No Pharmacy Admin is currently available. Please try again shortly.'}, status=503)
    conversation = Conversation.objects.create(
        participant_one=request.user, participant_two=admin,
        pharmacy_chat_status='open', created_at=timezone.now())
    log_pharmacy_action(request.user, 'Pharmacy opened support conversation', 'create',
                        'pharmacy_conversation', conversation.id)
    notify_pharmacy_admins(
        'New pharmacy support conversation',
        f'{request.user.full_name or request.user.email} started a support conversation.',
        reference_type='pharmacy_conversation')
    return Response({'exists': True, **_conversation_json(conversation, request.user)}, status=201)


@api_view(['POST', 'PATCH'])
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def support_conversation_detail(request, conversation_id):
    conversation = _pharmacy_conversation_qs(request.user).filter(id=conversation_id).first()
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
    notify_pharmacy_admins(
        'New pharmacy support message',
        f'{request.user.full_name or request.user.email}: {(message.content or "")[:120]}',
        reference_type='pharmacy_conversation')
    payload = {
        'id': str(message.id), 'conversation_id': str(conversation.id), 'sender_id': str(request.user.id),
        'content': message.content or message.file_url or '', 'message_type': message.message_type,
        'file_url': message.file_url, 'is_read': False, 'sent_at': message.sent_at.isoformat(),
    }
    emit_to_conversation(conversation.id, 'message_created', payload)
    return Response(payload, status=201)
