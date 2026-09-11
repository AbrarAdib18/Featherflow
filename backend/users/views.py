import logging
import uuid

from django.conf import settings
from django.contrib.auth import authenticate
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from api.throttling import (
    LoginRateThrottle, RegistrationRateThrottle, RegistrationUploadRateThrottle,
)
from users.models import User
from users.serializers import UserLoginSerializer, UserRegistrationSerializer, UserSerializer
from verification import documents as docs
from verification.auth import tokens_for
from verification.otp import RESEND_COOLDOWN

logger = logging.getLogger('signup')

# Roles that must clear admin review before the account can be used.
PENDING_MESSAGES = {
    'doctor': 'Your veterinarian account is pending admin verification of your '
              'credentials. You will be able to sign in once it is approved.',
    'pharmacy': 'Your pharmacy account is pending admin verification. You will be '
                'able to sign in once it is approved.',
    'delivery': 'Your delivery rider account is pending admin approval. You will be '
                'able to sign in once it is approved.',
    'researcher': 'Your researcher account is pending admin verification. You will '
                  'be able to sign in once it is approved.',
    'admin': 'Your admin application is pending review by Operations / Super Admin.',
}
_DEFAULT_PENDING = 'Your account is pending approval. You will be able to sign in once it is approved.'
_STATE_MESSAGES = {
    'pending': _DEFAULT_PENDING,
    'suspended': 'This account has been suspended. Contact support.',
    'rejected': 'This account application was not approved. Contact support.',
}


def _role_of(user):
    return user.roles.values_list('name', flat=True).first() or 'farmer'


def _session_payload(request, user):
    access, refresh = tokens_for(user)
    return {
        'user': UserSerializer(user).data,
        'user_url': request.build_absolute_uri(f'/api/auth/users/{user.pk}/'),
        'access': access,
        'refresh': refresh,
    }


def resume_response(request, user):
    """The response for a user who has just proved they own the account
    (fresh signup verification, or login): a session if the account is usable,
    otherwise a pending/suspended explanation with no tokens."""
    role = _role_of(user)
    if not user.email_verified and settings.SIGNUP_REQUIRE_EMAIL_VERIFICATION:
        return Response({
            'user': UserSerializer(user).data,
            'detail': 'Please verify your email address to continue.',
            'next': 'verify_email',
            'channel': 'email',
            'email': user.email,
        }, status=status.HTTP_403_FORBIDDEN)
    if settings.SIGNUP_REQUIRE_PHONE_VERIFICATION and not user.phone_verified:
        return Response({
            'user': UserSerializer(user).data,
            'detail': 'Please verify your phone number to continue.',
            'next': 'verify_phone',
            'channel': 'phone',
            'phone': user.phone,
        }, status=status.HTTP_403_FORBIDDEN)
    if user.account_status == 'active':
        return Response({**_session_payload(request, user), 'next': 'dashboard',
                         'detail': 'You are now signed in.'})
    return Response({
        'user': UserSerializer(user).data,
        'detail': PENDING_MESSAGES.get(
            'admin' if role.startswith('admin') else role,
            _STATE_MESSAGES.get(user.account_status, _DEFAULT_PENDING)),
        'next': 'pending_approval',
        'account_status': user.account_status,
    }, status=status.HTTP_403_FORBIDDEN)


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer

    def get_permissions(self):
        if self.action in ['create', 'register', 'login']:
            return [AllowAny()]
        return [IsAuthenticated()]

    def get_throttles(self):
        if self.action in ('create', 'register'):
            return [RegistrationRateThrottle()]
        if self.action == 'login':
            return [LoginRateThrottle()]
        return super().get_throttles()

    def get_serializer_class(self):
        if self.action in ['create', 'register']:
            return UserRegistrationSerializer
        if self.action == 'login':
            return UserLoginSerializer
        return UserSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        role = _role_of(user)

        body = {'user': UserSerializer(user).data}

        if settings.SIGNUP_REQUIRE_EMAIL_VERIFICATION and not user.email_verified:
            sent, debug = _dispatch_signup_code(user, 'email')
            dev = getattr(settings, 'OTP_DEV_DELIVERY', False)
            body['detail'] = (
                'Account created. '
                + ('No email provider is configured on this server, so your '
                   '6-digit code is printed in the backend terminal (and '
                   'filled in below).' if dev
                   else f'We sent a 6-digit code to {user.email}. Enter it '
                        f'to continue.'))
            body['next'] = 'verify_email'
            body['channel'] = 'email'
            body['email'] = user.email
            body['resend_cooldown'] = RESEND_COOLDOWN
            body['account_status'] = user.account_status
            body['dev_delivery'] = dev
            body['delivered'] = sent
            if debug is not None:
                body['debug_code'] = debug
            logger.info('signup: code issued for %s (sent=%s dev_delivery=%s)',
                        user.email, sent, dev)
            return Response(body, status=status.HTTP_201_CREATED)

        # Verification disabled — fall back to the previous behaviour.
        if user.account_status == 'active':
            body.update(_session_payload(request, user))
            body['detail'] = 'Account created. You are now signed in.'
            body['next'] = 'dashboard'
        else:
            body['detail'] = PENDING_MESSAGES.get(
                'admin' if role.startswith('admin') else role, _DEFAULT_PENDING)
            body['next'] = 'pending_approval'
            body['account_status'] = user.account_status
        return Response(body, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['post'])
    def register(self, request):
        return self.create(request)

    @action(detail=False, methods=['post'], permission_classes=[AllowAny])
    def login(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data['email']
        password = serializer.validated_data['password']

        user = authenticate(request, email=email, password=password)
        candidate = user or User.objects.filter(email__iexact=email).first()
        password_ok = bool(user) or bool(candidate and candidate.check_password(password))

        if not password_ok:
            _record_login_attempt(request, email, success=False)
            return Response({'detail': 'Invalid email or password.'},
                            status=status.HTTP_401_UNAUTHORIZED)

        # Password is correct. Contact verification is checked before the
        # account-state gate so a pending professional can still finish it.
        if settings.SIGNUP_REQUIRE_EMAIL_VERIFICATION and not candidate.email_verified:
            _record_login_attempt(request, email, success=False, user=candidate)
            sent, debug = _dispatch_signup_code(candidate, 'email')
            dev = getattr(settings, 'OTP_DEV_DELIVERY', False)
            payload = {
                'detail': 'Please verify your email address before signing in.'
                          + (' The code is in the backend terminal (dev mode).' if dev
                             else ' We just sent you a fresh code.' if sent else
                             ' Enter the code from your signup email, or request a new one.'),
                'next': 'verify_email', 'channel': 'email', 'email': candidate.email,
                'resend_cooldown': RESEND_COOLDOWN, 'dev_delivery': dev,
            }
            if debug is not None:
                payload['debug_code'] = debug
            return Response(payload, status=status.HTTP_403_FORBIDDEN)

        if candidate.account_status != 'active':
            _record_login_attempt(request, email, success=False, user=candidate)
            return Response(
                {'detail': _STATE_MESSAGES.get(candidate.account_status,
                                               'This account is not active.'),
                 'next': 'pending_approval',
                 'account_status': candidate.account_status},
                status=status.HTTP_403_FORBIDDEN,
            )

        _record_login_attempt(request, email, success=True, user=candidate)
        return Response({**_session_payload(request, candidate), 'next': 'dashboard'})

    def retrieve(self, request, *args, **kwargs):
        user = self.get_object()
        if request.user.pk != user.pk and not request.user.is_staff:
            return Response(
                {'detail': 'You may only view your own user record.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(UserSerializer(user).data)

    @action(detail=False, methods=['get'])
    def me(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)


def _dispatch_signup_code(user, channel):
    """Issue + send a verification code. Returns ``(sent, debug_code)`` where
    ``sent`` is False when a cooldown / ceiling suppressed it, and
    ``debug_code`` is the code only when ``OTP_EXPOSE_CODES`` is on (dev)."""
    from verification import otp
    from verification.delivery import send_code
    purpose = 'phone_verify' if channel == 'phone' else 'email_verify'
    ident = user.phone if channel == 'phone' else user.email
    code, _retry, error = otp.issue(purpose, channel, ident)
    if error:
        return False, None
    try:
        send_code(channel, ident, code, purpose)
    except NotImplementedError:
        pass
    return True, (code if settings.OTP_EXPOSE_CODES else None)


def _record_login_attempt(request, email, success, user=None):
    """Append a login attempt to activity_logs so the admin panel's security
    monitor can spot brute-force / suspicious-access patterns from real data."""
    try:
        from audit.models import ActivityLog
        forwarded = request.META.get('HTTP_X_FORWARDED_FOR')
        ip = forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR')
        ActivityLog.objects.create(
            user=user, module='auth',
            action=f'Login {"success" if success else "failed"} for {email}',
            action_type='login',
            new_values={'email': email, 'success': success},
            ip_address=ip,
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
        )
    except Exception:
        pass


# Signup document/photo upload — anonymous but strictly validated + throttled.
_MAX_UPLOAD_BYTES = 5 * 1024 * 1024
_ALLOWED_UPLOAD_EXT = {'jpg', 'jpeg', 'png', 'webp', 'pdf'}
# Canonical MIME types plus the common aliases browsers / file pickers actually
# send. A file whose *extension* is allowed but whose MIME is generic
# ('application/octet-stream' — what Flutter web's MultipartFile sends when no
# content-type is set) or empty is accepted and the bytes are sniffed instead.
_ALLOWED_UPLOAD_MIME = {
    'image/jpeg', 'image/jpg', 'image/pjpeg', 'image/png', 'image/x-png',
    'image/webp', 'application/pdf', 'application/x-pdf',
}
_GENERIC_MIME = {'', 'application/octet-stream', 'binary/octet-stream', None}

# Leading magic bytes for the allowed formats — the real type check.
_MAGIC = {
    'jpg': (b'\xff\xd8\xff',),
    'jpeg': (b'\xff\xd8\xff',),
    'png': (b'\x89PNG\r\n\x1a\n',),
    'webp': (b'RIFF',),          # 'RIFF'....'WEBP'
    'pdf': (b'%PDF-',),
}


def _sniff_ok(head, ext):
    sigs = _MAGIC.get(ext, ())
    if not sigs:
        return False
    if ext == 'webp':
        return head[:4] == b'RIFF' and head[8:12] == b'WEBP'
    return any(head.startswith(sig) for sig in sigs)


_UPLOAD_KINDS = {
    'profile_photo', 'license_photo', 'council_proof', 'trade_license',
    'cv', 'certificate', 'vehicle_photo', 'id_document', 'farm_photo',
}


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([RegistrationUploadRateThrottle])
def registration_upload(request):
    """Store one signup document privately and return a signed URL for
    inclusion in role_data. The file is NOT publicly reachable — it is served
    only through /api/auth/registration-documents/<token>/ with access checks."""
    kind = str(request.data.get('kind', 'certificate')).strip().lower()
    if kind not in _UPLOAD_KINDS:
        return Response({'detail': f'kind must be one of: {", ".join(sorted(_UPLOAD_KINDS))}.'},
                        status=status.HTTP_400_BAD_REQUEST)
    file = request.FILES.get('file') or request.FILES.get('image')
    if not file:
        logger.info('upload rejected: no file (kind=%s)', kind)
        return Response({'detail': 'Choose a file to upload (form field "file").'},
                        status=status.HTTP_400_BAD_REQUEST)

    mime = (file.content_type or '').lower().split(';')[0].strip()
    ext = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''

    if file.size > _MAX_UPLOAD_BYTES:
        mb = file.size / (1024 * 1024)
        logger.info('upload rejected: too large (%.1f MB, name=%s)', mb, file.name)
        return Response(
            {'detail': f'That file is {mb:.1f} MB. The limit is 5 MB — '
                       f'please choose a smaller file.'},
            status=status.HTTP_400_BAD_REQUEST)

    head = file.read(64)
    file.seek(0)

    ext_ok = ext in _ALLOWED_UPLOAD_EXT
    sniff_ok = _sniff_ok(head, ext) if ext_ok else False
    # A non-generic MIME that isn't in the allow-list is a real mismatch
    # (e.g. text/plain); a generic/blank one is what browsers & Flutter web
    # send and is fine as long as the extension + magic bytes agree.
    mime_conflict = bool(mime) and mime not in _ALLOWED_UPLOAD_MIME \
        and mime not in _GENERIC_MIME

    if not ext_ok or not sniff_ok or mime_conflict:
        logger.info(
            'upload rejected: type (name=%s ext=%s mime=%s ext_ok=%s sniff_ok=%s conflict=%s)',
            file.name, ext, mime or '<none>', ext_ok, sniff_ok, mime_conflict)
        detail = ('That file type is not supported. Upload a JPG, PNG, WebP or '
                  'PDF file.')
        if ext_ok and not sniff_ok:
            detail = (f'That file does not look like a valid {ext.upper()} '
                      f'file. Re-export it and try again.')
        return Response({'detail': detail}, status=status.HTTP_400_BAD_REQUEST)

    if kind == 'profile_photo' and ext == 'pdf':
        return Response({'detail': 'The profile photo must be an image (JPG, PNG or WebP).'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        _rel, token = docs.store(file.read(), ext, kind, mime, file.name)
    except Exception as exc:  # disk / storage failure — surface it, don't 500 silently
        logger.exception('upload failed to persist (kind=%s name=%s): %s', kind, file.name, exc)
        return Response(
            {'detail': 'The server could not save the file. Please try again.'},
            status=status.HTTP_503_SERVICE_UNAVAILABLE)

    url = request.build_absolute_uri(f'/api/auth/registration-documents/{token}/')
    logger.info('upload stored: kind=%s name=%s size=%s mime=%s -> %s',
                kind, file.name, file.size, mime or '<none>', _rel)
    return Response({'url': url, 'kind': kind, 'filename': file.name},
                    status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([AllowAny])
def auth_root(request):
    base = request.build_absolute_uri
    return Response({
        'register': base('register/'),
        'login': base('login/'),
        'registration_upload': base('registration-upload/'),
        'verify_request': base('verify/request/'),
        'verify_confirm': base('verify/confirm/'),
        'password_reset_request': base('password-reset/request/'),
        'password_reset_confirm': base('password-reset/confirm/'),
        'current_user': base('me/'),
        'current_user_authentication': 'Send Authorization: Bearer <access_token> from the login response.',
    })
