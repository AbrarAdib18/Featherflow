"""Structured error responses for every DRF view.

Before this, error shapes were inconsistent across apps: some views returned
``{"detail": "..."}`` (DRF's default), some ``{"detail": str(exception)}``
(leaking raw exception text — see SECURITY_HARDENING_REPORT.md), and unhandled
exceptions fell through to Django's HTML error page.

Every response now ADDS a structured ``error`` block::

    {"error": {"code": "VALIDATION_ERROR", "message": "...",
                "fields": {"amount": ["Amount must be greater than zero."]},
                "request_id": "..."},
     "amount": ["Amount must be greater than zero."]}   # <- unchanged, kept

Deliberately additive, not a replacement: the existing DRF-default top-level
keys (``detail``, or the flat ``{field: [messages]}`` shape) are preserved
byte-for-byte alongside the new ``error`` key. `lib/core/network/auth_service.dart`
(`_errorFrom`) and other existing parsers read those top-level keys directly for
the signup wizard's field-level error display — an earlier version of this
handler *replaced* the body with only the nested shape, which silently broke
every field-validation message across all 6 signup flows (caught by
`scripts/test_signup_flows.py` field-validation checks). New/future callers
can read the nested, typed `error.code` / `error.request_id` instead of
sniffing status codes and message text.
"""
import logging

from django.conf import settings
from rest_framework import exceptions as drf_exceptions
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_default_handler

from api.request_id import get_request_id

logger = logging.getLogger('api')

_CODE_BY_EXCEPTION = {
    drf_exceptions.ValidationError: 'VALIDATION_ERROR',
    drf_exceptions.NotAuthenticated: 'NOT_AUTHENTICATED',
    drf_exceptions.AuthenticationFailed: 'AUTHENTICATION_FAILED',
    drf_exceptions.PermissionDenied: 'PERMISSION_DENIED',
    drf_exceptions.NotFound: 'NOT_FOUND',
    drf_exceptions.MethodNotAllowed: 'METHOD_NOT_ALLOWED',
    drf_exceptions.NotAcceptable: 'NOT_ACCEPTABLE',
    drf_exceptions.UnsupportedMediaType: 'UNSUPPORTED_MEDIA_TYPE',
    drf_exceptions.Throttled: 'THROTTLED',
    drf_exceptions.ParseError: 'PARSE_ERROR',
}


def _code_for(exc):
    for exc_type, code in _CODE_BY_EXCEPTION.items():
        if isinstance(exc, exc_type):
            return code
    return 'ERROR'


def _split_fields_and_message(data, top_level_code):
    """DRF's default ``exception_handler`` produces either a flat list/string
    (non-field errors) or a dict of ``{field: [messages]}`` (field errors, or
    a mix via ``non_field_errors``/``detail``). Separate the two.
    """
    if isinstance(data, dict):
        fields = {}
        messages = []
        for key, value in data.items():
            values = value if isinstance(value, list) else [value]
            values = [str(v) for v in values]
            if key in ('detail', 'non_field_errors', '__all__'):
                messages.extend(values)
            else:
                fields[key] = values
        message = ' '.join(messages) if messages else None
        return fields or None, message
    if isinstance(data, list):
        return None, ' '.join(str(v) for v in data)
    return None, str(data)


_DEFAULT_MESSAGES = {
    'VALIDATION_ERROR': 'Please correct the highlighted fields.',
    'NOT_AUTHENTICATED': 'Please sign in to continue.',
    'AUTHENTICATION_FAILED': 'Your session has expired. Please sign in again.',
    'PERMISSION_DENIED': "You don't have permission to do that.",
    'NOT_FOUND': 'That item could not be found.',
    'METHOD_NOT_ALLOWED': 'That action is not supported here.',
    'THROTTLED': "You're doing that too much — please slow down and try again shortly.",
    'PARSE_ERROR': 'The request could not be understood.',
    'SERVER_ERROR': 'Something went wrong on our end. Please try again in a moment.',
}


def structured_exception_handler(exc, context):
    response = drf_default_handler(exc, context)
    request_id = get_request_id()

    if response is not None:
        original = response.data
        code = _code_for(exc)
        fields, message = _split_fields_and_message(original, code)
        error_block = {
            'code': code,
            'message': message or _DEFAULT_MESSAGES.get(code, 'An error occurred.'),
            'request_id': request_id,
        }
        if fields:
            error_block['fields'] = fields
        # Merge rather than replace — see module docstring.
        response.data = {**original, 'error': error_block} if isinstance(original, dict) \
            else {'detail': original, 'error': error_block}
        return response

    # DRF returned None: an exception type it doesn't recognise (not an
    # APIException/Http404/PermissionDenied) — previously this fell straight
    # through to Django's own error handling (an HTML page, or a raw
    # traceback in DEBUG). Log it with the request id for correlation and,
    # in production only, return the same structured JSON shape instead of
    # letting an unstyled/HTML 500 reach an API client. DEBUG keeps Django's
    # normal debug page (re-raise) since that's more useful locally.
    logger.error('Unhandled exception [request_id=%s]', request_id, exc_info=exc)
    if settings.DEBUG:
        return None
    return Response(
        {
            'detail': _DEFAULT_MESSAGES['SERVER_ERROR'],
            'error': {
                'code': 'SERVER_ERROR',
                'message': _DEFAULT_MESSAGES['SERVER_ERROR'],
                'request_id': request_id,
            },
        },
        status=500,
    )
