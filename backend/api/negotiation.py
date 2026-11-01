"""Content negotiation for endpoints that return a file themselves.

DRF negotiates a *renderer* before the view runs. A file endpoint returns its
bytes as a plain ``HttpResponse`` and never uses a renderer, but a client that
honestly asks for the file (``Accept: application/pdf``) still failed
negotiation, since only JSON / browsable renderers exist, and got
``406 "Could not satisfy the request Accept header."`` before the view, its
access checks or the file were even reached. That was the prescription PDF
viewer bug (PRESCRIPTION_PDF_VIEWER_AUDIT.md).

With this class the file is still served as-is, and any error (401 / 403 /
404 / 503) is rendered as JSON with its real status, whatever the client's
Accept header asked for (RFC 9110 lets a server answer with a representation
outside Accept rather than 406).
"""
from rest_framework.exceptions import NotAcceptable
from rest_framework.negotiation import DefaultContentNegotiation
from rest_framework.renderers import JSONRenderer


class FileDownloadNegotiation(DefaultContentNegotiation):
    def select_renderer(self, request, renderers, format_suffix=None):
        try:
            return super().select_renderer(request, renderers, format_suffix)
        except NotAcceptable:
            renderer = next((r for r in renderers if isinstance(r, JSONRenderer)), JSONRenderer())
            return renderer, renderer.media_type
