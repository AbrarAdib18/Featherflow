"""Per-request correlation id — attached to the response, and to every log
record emitted while handling the request, so a user-reported error (or an
entry in an aggregated log stream) can be traced back to one exact request.
"""
import contextvars
import logging
import uuid

_current_request_id = contextvars.ContextVar('request_id', default='-')

HEADER_NAME = 'X-Request-ID'


def get_request_id():
    return _current_request_id.get()


class RequestIDMiddleware:
    """Reuses an inbound X-Request-ID (e.g. from a load balancer / API gateway)
    when present, otherwise mints one. Always echoes it back on the response.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        incoming = request.META.get('HTTP_X_REQUEST_ID', '').strip()
        request_id = incoming or uuid.uuid4().hex
        request.request_id = request_id
        token = _current_request_id.set(request_id)
        try:
            response = self.get_response(request)
        finally:
            _current_request_id.reset(token)
        response[HEADER_NAME] = request_id
        return response


class RequestIDLogFilter(logging.Filter):
    """Adds ``%(request_id)s`` to every log record for LOGGING formatters."""

    def filter(self, record):
        record.request_id = get_request_id()
        return True
