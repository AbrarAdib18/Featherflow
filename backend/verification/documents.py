"""Private storage + access control for sensitive uploaded files.

Originally built for signup documents; now the shared private-storage system
for every sensitive upload in the app — signup documents, profile photos,
disease-scan images, farm/expense/tax receipts, prescriptions, and delivery
proof-of-delivery photos (see SECURITY_HARDENING_REPORT.md finding C2). Files
are written under ``PRIVATE_MEDIA_ROOT`` (``backend/private_media/``), which is
NOT on ``MEDIA_URL`` and is never served by the static handler — so a file
cannot be reached by guessing a ``/media/...`` path.

Each stored file is handed back as an opaque, signed URL:
``/api/auth/registration-documents/<token>/``. The token is a
``django.core.signing`` blob carrying the relative path, kind, content-type and
upload time — permanent once minted (no expiry), since callers persist this
URL (e.g. ``Expense.receipt_url``) and re-mint-on-access isn't how any caller
uses it. Access rules (see ``can_access``):

  * During the signup session — while the file is still unclaimed and younger
    than GRACE_SECONDS — anyone holding the (unguessable) signed token may fetch
    it. This lets the signup screen preview an upload before the account exists.
    Any authenticated upload (post-signup) should ``claim()`` immediately, so
    this branch is never actually reached for those.
  * After that, the file is readable only by: the account that claimed it
    (``document_owner``), any admin-panel user, any signed-in user for a
    ``kind`` in ``_PUBLIC_TO_AUTHED`` (currently just ``profile_photo``), or
    one of the deliberate two-party exceptions — the pharmacy fulfilling the
    order a ``prescription`` is attached to, or the farmer/customer whose
    order a ``delivery_proof`` photo is attached to.

Flutter must fetch these URLs with the JWT attached (a plain ``Image.network``
sends no auth header and will 401) — use ``AuthedNetworkImage``
(``lib/core/network/authed_image.dart``).
"""
import time
import uuid
from datetime import datetime, timezone as dt_timezone
from functools import reduce
from operator import or_

from django.conf import settings
from django.core import signing
from django.core.files.base import ContentFile
from django.core.files.storage import FileSystemStorage
from django.db.models import Q
from django.utils import timezone

_SALT = 'featherflow.registration-document.v1'
GRACE_SECONDS = 2 * 60 * 60  # unclaimed-document read window (one signup session)

PRIVATE_ROOT = getattr(
    settings, 'PRIVATE_MEDIA_ROOT', settings.BASE_DIR / 'private_media')
private_storage = FileSystemStorage(location=str(PRIVATE_ROOT))

# Profile fields that can hold a registration-document URL, used for the
# reverse ownership lookup.
_OWNER_FIELDS = [
    ('users.User', ['profile_photo_url', 'national_id_photo_url', 'selfie_verification_url'], None),
    ('profiles.DoctorProfile', ['cv_url', 'council_registration_proof_url'], 'user'),
    ('profiles.DeliveryProfile', ['license_photo_url', 'proof_of_work_url'], 'user'),
    ('profiles.PharmacyOrganization', ['trade_license_url'], 'user'),
    ('profiles.ResearcherProfile',
     ['cv_url', 'ethics_certificate_url', 'publications_portfolio_url'], 'user'),
    ('profiles.AdminProfile', ['cv_url'], 'user'),
]


def store(file_bytes, ext, kind, content_type='', original_filename=''):
    """Persist bytes privately, return ``(relative_path, token)``.

    Also records an **unclaimed** ``SignupDocument`` row so every upload is
    tracked from the moment it lands (no orphaned-on-disk files). The row is
    linked to an account later by :func:`claim`; rows never claimed are removed
    by the ``purge_orphan_signup_documents`` command.
    """
    rel = f'registration/{kind}/{uuid.uuid4().hex}.{ext}'
    private_storage.save(rel, ContentFile(file_bytes))
    now = int(time.time())
    token = signing.dumps(
        {'p': rel, 'k': kind, 'ct': content_type, 't': now}, salt=_SALT)

    try:
        from verification.models import SignupDocument
        SignupDocument.objects.get_or_create(
            token=token,
            defaults={
                'document_type': _doc_type(kind),
                'file_path': rel,
                'content_type': content_type,
                'original_filename': (original_filename or '')[:255],
                'uploaded_at': datetime.fromtimestamp(now, tz=dt_timezone.utc),
            },
        )
    except Exception:  # a tracking-row failure must not break the upload
        pass
    return rel, token


def resolve(token):
    """Return the token payload dict, or raise ``signing.BadSignature``."""
    return signing.loads(token, salt=_SALT)


# Upload ``kind`` -> SignupDocument.document_type (mostly identical; a few aliases).
_KIND_TO_DOC_TYPE = {
    'license_photo': 'license_photo', 'council_proof': 'council_proof',
    'trade_license': 'trade_license', 'vehicle_photo': 'vehicle_photo',
    'id_document': 'id_document', 'farm_photo': 'farm_photo',
    'profile_photo': 'profile_photo', 'cv': 'cv', 'certificate': 'certificate',
    'prescription': 'prescription', 'disease_scan': 'disease_scan',
    'delivery_proof': 'delivery_proof', 'receipts': 'receipt',
    'tax-receipts': 'tax_receipt', 'farm-photos': 'farm_photo',
}


def _doc_type(kind):
    return _KIND_TO_DOC_TYPE.get((kind or '').lower(), 'other')


def token_from(url_or_token):
    """Accept either a bare token or the full ``/registration-documents/<token>/`` URL."""
    value = (url_or_token or '').strip().rstrip('/')
    if '/registration-documents/' in value:
        return value.rsplit('/', 1)[-1]
    return value


def claim(url_or_token, user, document_type=''):
    """Link an uploaded file to ``user``. Idempotent.

    Returns the ``SignupDocument`` row, or ``None`` if the token is missing /
    unparseable (a bad token must not abort signup — the field is simply skipped).
    A genuine DB error propagates so the surrounding atomic block rolls back.
    """
    if not url_or_token:
        return None
    from verification.models import SignupDocument

    token = token_from(url_or_token)
    try:
        payload = resolve(token)
    except signing.BadSignature:
        return None

    doc, _ = SignupDocument.objects.get_or_create(
        token=token,
        defaults={
            'file_path': payload.get('p', ''),
            'content_type': payload.get('ct', ''),
            'document_type': document_type or _doc_type(payload.get('k', '')),
            'uploaded_at': datetime.fromtimestamp(
                int(payload.get('t', time.time())), tz=dt_timezone.utc),
        },
    )
    fields = []
    if doc.user_id is None:
        doc.user = user
        doc.claimed_at = timezone.now()
        fields += ['user', 'claimed_at']
    if document_type and doc.document_type != document_type:
        doc.document_type = document_type
        fields.append('document_type')
    if fields:
        doc.save(update_fields=fields)
    return doc


def delete_document(url_or_token, *, only_owner=None):
    """Remove a stored file and its ``SignupDocument`` row. Best-effort — a
    missing file or row is fine. ``only_owner`` guards against deleting a
    document that belongs to someone else (or is still unclaimed but shared).

    Returns True if anything was removed.
    """
    if not url_or_token:
        return False
    token = token_from(url_or_token)
    from verification.models import SignupDocument

    row = SignupDocument.objects.filter(token=token).first()
    if row is not None and only_owner is not None and row.user_id not in (None, only_owner.pk):
        return False

    rel = ''
    if row is not None:
        rel = row.file_path
    else:
        try:
            rel = resolve(token).get('p', '')
        except signing.BadSignature:
            rel = ''

    removed = False
    if rel and private_storage.exists(rel):
        try:
            private_storage.delete(rel)
            removed = True
        except OSError:
            pass
    if row is not None:
        row.delete()
        removed = True
    return removed


def document_owner(token):
    """The User who claimed / whose profile references this token, or None."""
    # Fast path: an explicit claim row (covers every role, incl. documents that
    # only live in a JSON column — delivery vehicle photo, pharmacy certs).
    try:
        from verification.models import SignupDocument
        claimed = (SignupDocument.objects
                   .filter(token=token, user__isnull=False)
                   .select_related('user').first())
        if claimed is not None:
            return claimed.user
    except Exception:
        pass

    # Legacy fallback: reverse lookup across profile URL columns (pre-migration
    # accounts, and belt-and-braces if a claim row was never written).
    from django.apps import apps
    for label, fields, rel in _OWNER_FIELDS:
        model = apps.get_model(label)
        query = reduce(or_, (Q(**{f'{f}__contains': token}) for f in fields))
        row = model.objects.filter(query).first()
        if row is not None:
            return row if rel is None else getattr(row, rel, None)
    # Farmer photos live in a JSON array.
    FarmerProfile = apps.get_model('profiles.FarmerProfile')
    for fp in FarmerProfile.objects.exclude(farm_photos=None).iterator():
        if any(token in str(p) for p in (fp.farm_photos or [])):
            return fp.user
    return None


# Document kinds that are low-sensitivity "avatars" — any signed-in user may
# view them (so a profile photo shows on any screen, not just the owner's own).
# Everything else (CV, licences, ID, certificates, prescriptions, disease scans,
# receipts, delivery-proof photos) stays owner + admin only, except the single
# two-party case handled explicitly below (prescriptions <-> the fulfilling
# pharmacy).
_PUBLIC_TO_AUTHED = {'profile_photo'}


def _prescription_order_pharmacy(token):
    """The pharmacy user id fulfilling the order this prescription token is
    attached to, or None if no order references it (yet, or ever).

    Orders store the full prescription URL (not just the token) in
    ``AdminPanelRecord.payload['prescription_image']`` — see
    ``pharmacy/farmer_views.py:orders()``. This is a narrow, single-purpose
    lookup for the one two-party document type today, not a generic
    relationship system — extend deliberately, don't generalise speculatively.
    """
    from audit.models import AdminPanelRecord
    record = (AdminPanelRecord.objects
              .filter(module='pharmacy-orders', payload__prescription_image__icontains=token)
              .only('payload').first())
    return record.payload.get('owner_id') if record is not None else None


def _delivery_proof_order_farmer(token):
    """The farmer/customer id whose order this delivery-proof-photo token is
    attached to, or None if no delivery order references it (yet, or ever).

    Mirrors `_prescription_order_pharmacy` — a delivery proof is attached to
    a `DeliveryOrder.proof_of_delivery_url`, which in turn points at either a
    pharmacy or feed-marketplace order (`AdminPanelRecord.payload`) carrying
    the `farmer_id`. Narrow, single-purpose lookup for this one two-party
    case, same design as the prescription one above — extend deliberately."""
    from delivery.models import DeliveryOrder
    order = (DeliveryOrder.objects
             .filter(proof_of_delivery_url__icontains=token)
             .only('order_reference_id', 'is_pharmacy_delivery', 'order_type').first())
    if order is None:
        return None
    from audit.models import AdminPanelRecord
    module = 'pharmacy-orders' if order.is_pharmacy_delivery else 'feed-orders'
    record = (AdminPanelRecord.objects
              .filter(module=module, id=order.order_reference_id)
              .only('payload').first())
    return record.payload.get('farmer_id') if record is not None else None


def can_access(token, payload, request):
    """(allowed: bool, http_status_if_denied: int)."""
    age = time.time() - payload.get('t', 0)
    owner = document_owner(token)
    kind = _doc_kind(token, payload)

    if owner is None and age < GRACE_SECONDS:
        return True, None                       # mid-signup, capability token

    user = getattr(request, 'user', None)
    if not (user and user.is_authenticated):
        return False, 401
    if user.is_staff:
        return True, None                       # admin review
    if owner is not None and owner.pk == user.pk:
        return True, None                       # the account owner
    if kind in _PUBLIC_TO_AUTHED:
        return True, None                       # profile photo — visible to any signed-in user
    if kind == 'prescription' and str(_prescription_order_pharmacy(token)) == str(user.pk):
        return True, None                       # the pharmacy fulfilling the order
    if kind == 'delivery_proof' and str(_delivery_proof_order_farmer(token)) == str(user.pk):
        return True, None                       # the farmer/customer this delivery belongs to
    return False, 403


def _doc_kind(token, payload):
    """Best-effort document kind: the token payload's ``k``, or the claimed row's
    ``document_type`` (covers old tokens minted before ``k`` was always set)."""
    kind = (payload or {}).get('k')
    if kind:
        return kind
    try:
        from verification.models import SignupDocument
        row = SignupDocument.objects.filter(token=token).only('document_type').first()
        return row.document_type if row else None
    except Exception:
        return None
