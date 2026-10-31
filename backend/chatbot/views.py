"""Poultry & Featherflow assistant.

    POST /api/chatbot/chat/   {"message": str, "history": [{"role","text"}]}
      200     {"reply": str, "in_scope": bool, "error": null}
      4xx/5xx {"reply": "", "in_scope": false, "error": {"code": str, "message": str}}

Authenticated users only, throttled per user. Conversation history is supplied
by the client (max 6 turns) and never stored. The audit log records user id,
outcome and message length only, never message or reply text.
"""
import logging
import time

from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle

from . import providers, service

audit = logging.getLogger('chatbot.audit')

_STATUS = {
    'not_configured': 503,
    'provider_rate_limited': 503,
    'provider_rejected': 502,
    'provider_unavailable': 503,
    'invalid_response': 502,
    'timeout': 504,
}


class ChatBurstThrottle(UserRateThrottle):
    scope = 'chatbot_burst'


class ChatHourlyThrottle(UserRateThrottle):
    scope = 'chatbot'


def _error(status, code, message):
    return Response({'reply': '', 'in_scope': False,
                    'error': {'code': code, 'message': message}}, status=status)


def _audit(request, outcome, length, started):
    audit.info('chatbot user=%s outcome=%s chars=%s ms=%d', request.user.pk, outcome, length,
               int((time.monotonic() - started) * 1000))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([ChatBurstThrottle, ChatHourlyThrottle])
def chat(request):
    started = time.monotonic()
    message, history, errors = service.validate_payload(request.data)
    if errors:
        _audit(request, 'invalid', 0, started)
        return _error(400, 'invalid_request', ' '.join(errors.values()))
    try:
        provider = providers.get_provider()
        in_scope, reply = service.ask(provider, message, history)
    except providers.ProviderError as exc:
        _audit(request, exc.code, len(message), started)
        return _error(_STATUS.get(exc.code, 502), exc.code, exc.message)
    except Exception:  # never leak internals (or a key) to the client
        audit.error('chatbot unexpected failure user=%s', request.user.pk)
        return _error(502, 'internal_error', 'The assistant hit an unexpected problem. Please retry.')
    _audit(request, 'ok' if in_scope else 'refused', len(message), started)
    return Response({'reply': reply, 'in_scope': in_scope, 'error': None})
