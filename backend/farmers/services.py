"""Shared helpers for the farmer panel views.

Reuses the established plumbing: ``workers.views.farm_for`` for farm resolution,
the private-document storage + access-control system for uploaded images, the
immutable ``activity_logs`` table for a financial audit trail, and
``notifications`` for in-app toasts.
"""
from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from django.utils import timezone

from audit.models import ActivityLog
from notifications.models import Notification
from verification import documents as docs
from verification.uploads import UploadError, validate_upload
from workers.views import farm_for  # noqa: F401  (re-exported)

from consultations.permissions import IsFarmer  # noqa: F401  (re-exported)


# ── money / dates ──────────────────────────────────────────────────────────

def money(value, field='amount'):
    """Parse a user-supplied amount into a positive Decimal or raise ValueError."""
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, TypeError):
        raise ValueError(f'{field} must be a number.')
    if amount <= 0:
        raise ValueError(f'{field} must be greater than zero.')
    return amount.quantize(Decimal('0.01'))


def parse_date(value, fallback=None):
    if not value:
        return fallback
    if isinstance(value, date):
        return value
    return datetime.strptime(str(value)[:10], '%Y-%m-%d').date()


def period_range(params):
    """Resolve ?period=lifetime|monthly|yearly|custom (+ ?from=&to=) to a
    (start, end) date tuple. ``None`` bounds mean unbounded."""
    period = (params.get('period') or 'lifetime').lower()
    today = date.today()
    if period == 'monthly':
        return today.replace(day=1), today
    if period == 'yearly':
        return today.replace(month=1, day=1), today
    if period == 'custom':
        return parse_date(params.get('from')), parse_date(params.get('to'))
    return None, None


def in_range(qs, field, start, end):
    if start:
        qs = qs.filter(**{f'{field}__gte': start})
    if end:
        qs = qs.filter(**{f'{field}__lte': end})
    return qs


# ── images ─────────────────────────────────────────────────────────────────

def store_image(request, prefix):
    """Validate + persist one uploaded image PRIVATELY, returning (absolute_url, error).

    ``prefix`` (``receipts`` / ``tax-receipts`` / ``farm-photos``) doubles as the
    document "kind" for the private-storage access-control system — see
    verification/documents.py. Financial receipts and farm photos are personal
    records; only the uploading farmer (and admin staff) can view the resulting
    URL, which now serves through the signed-token endpoint used for signup
    documents/profile photos rather than the public media tree. Callers that
    need to display the URL to another user (Flutter side) must fetch it with
    the JWT attached — see ``AuthedNetworkImage``.
    """
    file = request.FILES.get('image') or request.FILES.get('file')
    if not file:
        return None, 'An image file is required.'
    try:
        ext, mime = validate_upload(file, images_only=True)
    except UploadError as exc:
        return None, exc.detail
    rel, token = docs.store(file.read(), ext, prefix, mime, file.name)
    docs.claim(token, request.user, document_type=prefix)
    return request.build_absolute_uri(f'/api/auth/registration-documents/{token}/'), None


# ── notifications + audit ─────────────────────────────────────────────────

def notify(user, title, body, notification_type='system', reference_id=None, reference_type='farm'):
    Notification.objects.create(
        user=user, title=title, body=body, notification_type=notification_type,
        reference_id=reference_id, reference_type=reference_type)


def log_finance(user, action, action_type, entity_type, entity_id, new_values=None, old_values=None):
    """Append an immutable row to activity_logs for every financial write."""
    try:
        ActivityLog.objects.create(
            user=user, module='cost_management', action=action, action_type=action_type,
            entity_type=entity_type, entity_id=entity_id,
            new_values=new_values, old_values=old_values)
    except Exception:  # audit must never break the primary write
        pass


def f(value):
    return float(value or 0)
