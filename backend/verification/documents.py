"""Private storage + access control for documents uploaded during signup.

Files are written under ``PRIVATE_MEDIA_ROOT`` (``backend/private_media/``),
which is NOT on ``MEDIA_URL`` and is never served by the static handler — so a
file cannot be reached by guessing a ``/media/...`` path.

Each stored file is handed back as an opaque, signed URL:
``/api/auth/registration-documents/<token>/``. The token is a
``django.core.signing`` blob carrying the relative path, kind, content-type and
upload time. Access rules (see ``can_access``):

  * During the signup session — while the file is still unclaimed and younger
    than GRACE_SECONDS — anyone holding the (unguessable) signed token may fetch
    it. This lets the signup screen preview an upload before the account exists.
  * After that, the file is readable only by the account that referenced it in
    its profile (resolved by reverse lookup — no ownership table) and by any
    admin-panel user.
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
# Everything else (CV, licences, ID, certificates) stays owner + admin only.
_PUBLIC_TO_AUTHED = {'profile_photo'}


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
