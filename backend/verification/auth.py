"""Password-version-aware JWT.

Every token minted through ``tokens_for`` carries a ``pv`` claim derived from
the user's current password hash. When the password changes (self-service
reset, or an admin-forced reset) the hash changes, so every previously issued
token fails the check on its next request — old sessions are invalidated without
a token-blacklist table.

Tokens without a ``pv`` claim (e.g. minted directly in a test helper, or issued
before this was deployed) are left alone for backward compatibility; only a
present-but-stale ``pv`` is rejected.
"""
import hashlib

from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed
from rest_framework_simplejwt.tokens import RefreshToken


def password_version(user):
    return hashlib.sha256((user.password or '').encode()).hexdigest()[:12]


def tokens_for(user):
    """Return ``(access_str, refresh_str)`` with the password-version claim."""
    refresh = RefreshToken.for_user(user)
    refresh['pv'] = password_version(user)
    access = refresh.access_token
    access['pv'] = password_version(user)
    return str(access), str(refresh)


class VersionedJWTAuthentication(JWTAuthentication):
    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        claimed = validated_token.get('pv')
        if claimed is not None and claimed != password_version(user):
            raise AuthenticationFailed(
                'Your session has expired because the password was changed. '
                'Please sign in again.',
                code='password_changed',
            )
        return user
