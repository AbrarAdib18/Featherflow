import socketio
from asgiref.sync import sync_to_async
from django.db.models import Q
from rest_framework_simplejwt.tokens import AccessToken

from doctor.models import Conversation, Message
from notifications.models import Notification
from users.models import User
from django.conf import settings


sio = socketio.AsyncServer(
    async_mode='asgi', cors_allowed_origins=settings.SOCKET_IO_ALLOWED_ORIGINS,
)


def room_name(conversation_id):
    return f'conversation:{conversation_id}'


@sync_to_async
def authenticated_user(token):
    try:
        payload = AccessToken(token)
        return User.objects.filter(id=payload['user_id'], account_status='active').first()
    except Exception:
        return None


@sync_to_async
def participant_conversation(user_id, conversation_id):
    return Conversation.objects.filter(id=conversation_id).filter(
        Q(participant_one_id=user_id) | Q(participant_two_id=user_id)
    ).first()


@sync_to_async
def persist_message(user_id, conversation_id, data):
    conversation = Conversation.objects.filter(id=conversation_id).filter(
        Q(participant_one_id=user_id) | Q(participant_two_id=user_id)
    ).select_related('participant_one', 'participant_two').first()
    if not conversation:
        return None
    content = str(data.get('content', '')).strip()
    file_url = str(data.get('file_url', '')).strip() or None
    message_type = data.get('message_type', 'text')
    if message_type not in ('text', 'image', 'file') or (not content and not file_url):
        return None
    message = Message.objects.create(
        conversation=conversation, sender_id=user_id, content=content or None,
        file_url=file_url, message_type=message_type,
    )
    conversation.last_message_at = message.sent_at
    conversation.save(update_fields=['last_message_at'])
    recipient = conversation.participant_two if conversation.participant_one_id == user_id else conversation.participant_one
    Notification.objects.create(
        user=recipient, title='New private message', body=content[:160] or 'New attachment',
        notification_type='message', reference_id=conversation.id, reference_type='conversation',
    )
    return {
        'id': str(message.id), 'conversation_id': str(conversation.id),
        'sender_id': str(user_id), 'content': message.content or message.file_url or '',
        'message_type': message.message_type, 'file_url': message.file_url,
        'sent_at': message.sent_at.isoformat(), 'is_read': False,
    }


@sync_to_async
def mark_conversation_read(user_id, conversation_id):
    conversation = Conversation.objects.filter(id=conversation_id).filter(
        Q(participant_one_id=user_id) | Q(participant_two_id=user_id)
    ).first()
    if not conversation:
        return False
    Message.objects.filter(conversation=conversation, is_read=False).exclude(sender_id=user_id).update(is_read=True)
    return True


@sio.event
async def connect(sid, environ, auth):
    token = (auth or {}).get('token', '')
    user = await authenticated_user(token)
    if not user:
        raise socketio.exceptions.ConnectionRefusedError('Authentication failed')
    await sio.save_session(sid, {'user_id': str(user.id)})


@sio.event
async def join_conversation(sid, data):
    session = await sio.get_session(sid)
    conversation_id = str((data or {}).get('conversation_id', ''))
    conversation = await participant_conversation(session['user_id'], conversation_id)
    if not conversation:
        return {'ok': False, 'error': 'Conversation access denied.'}
    await sio.enter_room(sid, room_name(conversation_id))
    return {'ok': True, 'conversation_id': conversation_id}


@sio.event
async def send_message(sid, data):
    session = await sio.get_session(sid)
    conversation_id = str((data or {}).get('conversation_id', ''))
    message = await persist_message(session['user_id'], conversation_id, data or {})
    if not message:
        return {'ok': False, 'error': 'Message rejected or access denied.'}
    await sio.emit('message_created', message, room=room_name(conversation_id))
    return {'ok': True, 'message': message}


@sio.event
async def mark_read(sid, data):
    session = await sio.get_session(sid)
    conversation_id = str((data or {}).get('conversation_id', ''))
    ok = await mark_conversation_read(session['user_id'], conversation_id)
    if ok:
        await sio.emit('conversation_read', {'conversation_id': conversation_id, 'reader_id': session['user_id']}, room=room_name(conversation_id))
    return {'ok': ok}
