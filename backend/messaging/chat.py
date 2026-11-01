"""The one place chat messages are created and serialized.

Every send path — doctor REST (`/api/doctor/conversations/<id>/`), farmer REST
(`/api/consultations/chats/<id>/`) and the Socket.IO `send_message` event —
goes through :func:`deliver_message`, and every list/echo payload is built by
:func:`message_payload`. See CHAT_MESSAGE_STATE_FIX.md.

Idempotency: a client sends a ``client_message_id`` (UUID) with each new
message and reuses it on retry. ``(sender_id, client_message_id)`` is unique in
the database (partial index in postgres_backend_extension.sql), so a retry or
a concurrent double submit returns the original message instead of creating a
second row.

Time: ``messages.sent_at`` is ``timestamp without time zone`` holding UTC
wall-clock (Django writes UTC; the DB session runs in UTC). Rows read back are
*naive*, and ``naive.isoformat()`` has no offset, which clients then read as
their own local time — the cause of every chat time showing 6 hours early in
Dhaka. All chat timestamps leave the API through :func:`iso_utc` instead.
"""
from datetime import timezone as dt_timezone

from django.db import IntegrityError, transaction
from django.utils import timezone

from doctor.models import Conversation, Message
from notifications.models import Notification


class ClientMessageIdConflict(Exception):
    """The sender already used this client_message_id in another conversation."""


def aware_utc(value):
    if value is None:
        return None
    if timezone.is_naive(value):
        return value.replace(tzinfo=dt_timezone.utc)
    return value.astimezone(dt_timezone.utc)


def iso_utc(value):
    """ISO 8601 with an explicit UTC offset, e.g. ``2026-10-30T10:48:20.203851+00:00``."""
    value = aware_utc(value)
    return value.isoformat() if value else None


def message_payload(message, viewer_id=None):
    """Wire format of one message. ``from_me`` only when a viewer is known —
    a Socket.IO broadcast goes to both participants, who compare
    ``sender_id`` to their own id instead."""
    data = {
        'id': str(message.id),
        'client_message_id': str(message.client_message_id) if message.client_message_id else None,
        'conversation_id': str(message.conversation_id),
        'sender_id': str(message.sender_id),
        'content': message.content or message.file_url or '',
        'message_type': message.message_type,
        'type': message.message_type,
        'file_url': message.file_url,
        'is_read': bool(message.is_read),
        'sent_at': iso_utc(message.sent_at),
    }
    if viewer_id is not None:
        data['from_me'] = str(message.sender_id) == str(viewer_id)
    return data


def ordered_messages(conversation):
    # `id` breaks ties so two messages in the same microsecond keep a stable order.
    return conversation.messages.order_by('sent_at', 'id')


def deliver_message(conversation, sender, *, content=None, message_type='text',
                    file_url=None, client_message_id=None):
    """Create a message (or return the one this client already created).

    Returns ``(message, created)``. Side effects — ``last_message_at`` and the
    recipient's notification — happen only when a row is actually created, so
    a retried send never notifies twice. Callers broadcast only when
    ``created`` is true for the same reason.
    """
    if client_message_id:
        existing = Message.objects.filter(sender=sender, client_message_id=client_message_id).first()
        if existing:
            if existing.conversation_id != conversation.id:
                raise ClientMessageIdConflict()
            return existing, False
    try:
        with transaction.atomic():
            message = Message.objects.create(
                conversation=conversation, sender=sender, content=content or None,
                message_type=message_type, file_url=file_url or None,
                client_message_id=client_message_id or None,
            )
    except IntegrityError:
        # A concurrent submit of the same client_message_id won the unique index.
        if not client_message_id:
            raise
        existing = Message.objects.get(sender=sender, client_message_id=client_message_id)
        if existing.conversation_id != conversation.id:
            raise ClientMessageIdConflict()
        return existing, False

    Conversation.objects.filter(id=conversation.id).update(last_message_at=message.sent_at)
    recipient_id = (conversation.participant_two_id
                    if conversation.participant_one_id == sender.id else conversation.participant_one_id)
    Notification.objects.create(
        user_id=recipient_id, title='New message',
        body=f'New message from {sender.full_name or sender.email}.',
        notification_type='message', reference_id=conversation.id, reference_type='conversation',
    )
    return message, True
