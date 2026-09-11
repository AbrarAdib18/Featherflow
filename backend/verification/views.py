"""Endpoints for contact verification, password reset, and private document
delivery. All mounted under /api/auth/ (see verification/urls.py)."""
import logging
import os

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core import signing
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.http import FileResponse
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from api.throttling import (
    DocumentFetchRateThrottle, OTPConfirmRateThrottle, OTPRequestRateThrottle,
    PasswordResetRateThrottle, ProfilePhotoRateThrottle,
)
from users.models import User
from users.serializers import normalize_bd_phone, normalize_email
from users.views import _record_login_attempt, resume_response
from verification import documents as docs
from verification import otp
from verification.auth import password_version
from verification.delivery import send_code
from verification.uploads import UploadError, validate_upload

logger = logging.getLogger('verification')

# Human copy for otp.verify() error codes.
_CONFIRM_ERRORS = {
    'no_code': (400, 'Request a code first.'),
    'expired': (400, 'That code has expired. Request a new one.'),
    'wrong': (400, 'That code is not correct. Check it and try again.'),
    'locked': (429, 'Too many incorrect attempts. Try again in about 15 minutes.'),
}
_ISSUE_ERRORS = {
    'cooldown': (429, 'Please wait a moment before requesting another code.'),
    'max_resends': (429, 'You have requested too many codes. Try again later.'),
    'locked': (429, 'Too many attempts. Try again in about 15 minutes.'),
}


def _maybe_debug(code):
    return {'debug_code': code} if (code and settings.OTP_EXPOSE_CODES) else {}


def _delivery_meta():
    """Tell the client whether codes are only observable in the server terminal
    (console email backend / console SMS stub) so the OTP screen can say so."""
    return {'dev_delivery': getattr(settings, 'OTP_DEV_DELIVERY', False)}


# ── contact verification ────────────────────────────────────────────────────
@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OTPRequestRateThrottle])
def verify_request(request):
    """Send (or resend) a verification code for the account's email or phone."""
    channel = str(request.data.get('channel', 'email')).strip().lower()
    if channel not in ('email', 'phone'):
        return Response({'detail': 'channel must be "email" or "phone".'}, status=400)

    email = normalize_email(request.data.get('email', ''))
    user = User.objects.filter(email__iexact=email).first() if email else None
    generic = Response({
        'detail': 'If that account exists and is unverified, a code has been sent.',
        'channel': channel, 'resend_cooldown': otp.RESEND_COOLDOWN,
        'expires_in': otp.CODE_TTL,
    })
    if user is None:
        return generic

    already = user.phone_verified if channel == 'phone' else user.email_verified
    if already:
        return Response({'detail': f'Your {channel} is already verified.',
                         'channel': channel, 'verified': True})

    ident = user.phone if channel == 'phone' else user.email
    purpose = 'phone_verify' if channel == 'phone' else 'email_verify'
    code, retry_after, error = otp.issue(purpose, channel, ident)
    if error:
        code_status, msg = _ISSUE_ERRORS.get(error, (429, 'Try again later.'))
        return Response({'detail': msg, 'retry_after': retry_after}, status=code_status)
    try:
        delivered = send_code(channel, ident, code, purpose)
    except NotImplementedError as exc:
        return Response({'detail': str(exc)}, status=503)
    return Response({**generic.data, **_delivery_meta(),
                     'delivered': bool(delivered), **_maybe_debug(code)})


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([OTPConfirmRateThrottle])
def verify_confirm(request):
    """Confirm an email/phone verification code. On success returns a session
    (active account) or a pending-approval explanation, mirroring login."""
    channel = str(request.data.get('channel', 'email')).strip().lower()
    if channel not in ('email', 'phone'):
        return Response({'detail': 'channel must be "email" or "phone".'}, status=400)
    email = normalize_email(request.data.get('email', ''))
    code = str(request.data.get('code', '')).strip()
    user = User.objects.filter(email__iexact=email).first() if email else None
    if user is None or not code:
        return Response({'detail': 'That code is not correct.'}, status=400)

    ident = user.phone if channel == 'phone' else user.email
    purpose = 'phone_verify' if channel == 'phone' else 'email_verify'
    ok, error = otp.verify(purpose, channel, ident, code)
    if not ok:
        code_status, msg = _CONFIRM_ERRORS.get(error, (400, 'That code is not correct.'))
        return Response({'detail': msg, 'code': error}, status=code_status)

    if channel == 'phone':
        user.mark_phone_verified()
    else:
        user.mark_email_verified()
    _record_login_attempt(request, user.email, success=True, user=user)
    return resume_response(request, user)


# ── password reset ──────────────────────────────────────────────────────────
@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetRateThrottle])
def password_reset_request(request):
    """Send a password-reset code to the account's email (or phone)."""
    channel = str(request.data.get('channel', 'email')).strip().lower()
    if channel not in ('email', 'phone'):
        return Response({'detail': 'channel must be "email" or "phone".'}, status=400)
    email = normalize_email(request.data.get('email', ''))
    user = User.objects.filter(email__iexact=email).first() if email else None
    generic = Response({
        'detail': 'If that account exists, a reset code has been sent.',
        'channel': channel, 'resend_cooldown': otp.RESEND_COOLDOWN,
        'expires_in': otp.CODE_TTL,
    })
    if user is None:
        return generic
    ident = user.phone if channel == 'phone' else user.email
    code, retry_after, error = otp.issue('password_reset', channel, ident)
    if error:
        # Don't reveal existence via a 429 vs 200; stay generic but hint timing.
        return Response({**generic.data, 'retry_after': retry_after})
    try:
        send_code(channel, ident, code, 'password_reset')
    except NotImplementedError as exc:
        return Response({'detail': str(exc)}, status=503)
    return Response({**generic.data, **_delivery_meta(), **_maybe_debug(code)})


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetRateThrottle])
def password_reset_confirm(request):
    """Verify a reset code and set a new password. Invalidates existing tokens."""
    channel = str(request.data.get('channel', 'email')).strip().lower()
    if channel not in ('email', 'phone'):
        return Response({'detail': 'channel must be "email" or "phone".'}, status=400)
    email = normalize_email(request.data.get('email', ''))
    code = str(request.data.get('code', '')).strip()
    new_password = request.data.get('new_password') or request.data.get('password') or ''
    user = User.objects.filter(email__iexact=email).first() if email else None
    if user is None or not code:
        return Response({'detail': 'That code is not correct.'}, status=400)

    ident = user.phone if channel == 'phone' else user.email
    ok, error = otp.verify('password_reset', channel, ident, code)
    if not ok:
        code_status, msg = _CONFIRM_ERRORS.get(error, (400, 'That code is not correct.'))
        return Response({'detail': msg, 'code': error}, status=code_status)

    try:
        validate_password(new_password, user=user)
    except DjangoValidationError as exc:
        # Re-issue a short-lived code so the user isn't forced to restart.
        again, _r, _e = otp.issue('password_reset', channel, ident)
        if again:
            try:
                send_code(channel, ident, again, 'password_reset')
            except NotImplementedError:
                pass
        payload = {'password': list(exc.messages),
                   'detail': 'Password does not meet the requirements. '
                             'We sent a new code.'}
        payload.update(_maybe_debug(again))
        return Response(payload, status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save(update_fields=['password', 'updated_at'])
    # A successful reset also proves control of the email inbox.
    if channel == 'email' and not user.email_verified:
        user.mark_email_verified()
    _record_login_attempt(request, user.email, success=True, user=user)
    return Response({
        'detail': 'Your password has been updated and you have been signed out '
                  'of other devices. Please sign in with your new password.',
        'next': 'login',
    })


# ── profile photo (authenticated, any role) ─────────────────────────────────
@api_view(['POST', 'DELETE'])
@permission_classes([IsAuthenticated])
@throttle_classes([ProfilePhotoRateThrottle])
def profile_photo(request):
    """Replace or clear the signed-in user's profile photo.

    POST  multipart ``file`` (JPG/PNG/WebP, <=5 MB) — validated by extension,
    advisory MIME and real magic bytes, stored privately, tracked as a claimed
    ``SignupDocument`` and referenced from ``User.profile_photo_url``. The whole
    DB update is one transaction; a newly-stored file is removed if it fails.
    The previous photo's file + row are cleaned up after a successful swap.

    DELETE — clear the photo (initials fall back in the UI).

    Works for every role because ``profile_photo_url`` lives on ``users.User``.
    Access to the served file: any signed-in user may view a ``profile_photo``
    (see ``documents._PUBLIC_TO_AUTHED``); licences / IDs / certs stay private.
    """
    user = request.user
    old_url = user.profile_photo_url or ''

    if request.method == 'DELETE':
        with transaction.atomic():
            user.profile_photo_url = ''
            user.save(update_fields=['profile_photo_url'])
        if old_url:
            docs.delete_document(old_url, only_owner=user)
        logger.info('profile photo cleared for %s', user.email)
        return Response({'profile_photo_url': ''})

    file = request.FILES.get('file') or request.FILES.get('image')
    try:
        ext, mime = validate_upload(file, images_only=True)
    except UploadError as exc:
        return Response({'detail': exc.detail}, status=exc.status)

    try:
        rel, token = docs.store(file.read(), ext, 'profile_photo', mime, file.name)
    except Exception as exc:  # disk / storage failure
        logger.exception('profile photo failed to persist for %s: %s', user.email, exc)
        return Response(
            {'detail': 'The server could not save the photo. Please try again.'},
            status=status.HTTP_503_SERVICE_UNAVAILABLE)

    new_url = request.build_absolute_uri(f'/api/auth/registration-documents/{token}/')
    try:
        with transaction.atomic():
            docs.claim(token, user, document_type='profile_photo')
            user.profile_photo_url = new_url
            user.save(update_fields=['profile_photo_url'])
    except Exception as exc:
        docs.delete_document(token)          # roll the orphaned file + row back
        logger.exception('profile photo DB update failed for %s: %s', user.email, exc)
        return Response(
            {'detail': 'Could not update your profile. The photo was not changed.'},
            status=status.HTTP_400_BAD_REQUEST)

    # Old photo is safe to drop only now that the new one is committed.
    if old_url and docs.token_from(old_url) != token:
        docs.delete_document(old_url, only_owner=user)

    logger.info('profile photo updated for %s (%s, %s bytes)',
                user.email, file.name, file.size)
    return Response({
        'profile_photo_url': new_url,
        'document': {
            'document_type': 'profile_photo',
            'filename': file.name,
            'content_type': mime or f'image/{ext}',
        },
    }, status=status.HTTP_200_OK)


# ── private document delivery ───────────────────────────────────────────────
@api_view(['GET'])
@permission_classes([AllowAny])
@throttle_classes([DocumentFetchRateThrottle])
def serve_registration_document(request, token):
    try:
        payload = docs.resolve(token)
    except signing.BadSignature:
        return Response({'detail': 'Invalid or expired document link.'}, status=404)

    rel = payload.get('p', '')
    if not rel or not docs.private_storage.exists(rel):
        return Response({'detail': 'Document not found.'}, status=404)

    allowed, deny_status = docs.can_access(token, payload, request)
    if not allowed:
        return Response(
            {'detail': 'You are not allowed to view this document.'},
            status=deny_status or status.HTTP_403_FORBIDDEN)

    response = FileResponse(
        docs.private_storage.open(rel, 'rb'),
        content_type=payload.get('ct') or 'application/octet-stream')
    response['Content-Disposition'] = (
        f'inline; filename="{os.path.basename(rel)}"')
    response['X-Content-Type-Options'] = 'nosniff'
    response['Cache-Control'] = 'private, no-store'
    return response
