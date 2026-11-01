"""Authentication for the handful of pharmacy endpoints that must stay
reachable at EVERY account lifecycle stage (profile, permissions,
verification-status, dashboard, support chat, appeals).

`User.is_active` (users/models.py) is a COMPUTED property —
`account_status == 'active'` — and the platform's default authentication
class (`verification.auth.VersionedJWTAuthentication`, subclassing SimpleJWT's
`JWTAuthentication`) rejects any inactive user's token outright inside
`get_user()`, before `permission_classes` ever runs. That is correct and
desired everywhere else on the platform (a pending/suspended account of ANY
role should not be able to call arbitrary authenticated endpoints), which is
exactly why loosening `IsPharmacyUser` alone (pharmacy/permissions.py) was not
enough to satisfy the spec's "profile/earnings/chat/appeal stay reachable
while pending/suspended" requirement — the request never reached the
permission check in the first place.

`PharmacyAlwaysOnAuthentication` is identical to `VersionedJWTAuthentication`
except it skips the `is_active` check **only when the token's user holds the
`pharmacy` role** — for every other role it behaves exactly like the base
class (still rejects an inactive user). That role check is what makes it
safe to add as an *additional* authenticator on a few pharmacy-specific
always-on views (profile, permissions, chat, appeals) AND, critically, on
the platform-wide `/api/me/updates/` polling endpoint every logged-in
client calls continuously (`api.admin_extra.me_updates`) — without it, a
pending/suspended pharmacy's very first background poll 401s, and
`UserUpdatesService` (lib/core/network/user_updates_service.dart) treats any
401/403 from that endpoint as "access revoked", clearing the session and
bouncing back to the login screen a few seconds after a successful login.
This was only caught by actually running the app, not by the endpoint-level
backend test suite. Every other endpoint, and every other role, is
unaffected — this is a role-scoped exception, not a platform-wide relaxation
of the inactive-account gate.
"""
from rest_framework_simplejwt.exceptions import AuthenticationFailed, InvalidToken
from rest_framework_simplejwt.settings import api_settings

from verification.auth import VersionedJWTAuthentication, password_version


class PharmacyAlwaysOnAuthentication(VersionedJWTAuthentication):
    def get_user(self, validated_token):
        try:
            user_id = validated_token[api_settings.USER_ID_CLAIM]
        except KeyError:
            raise InvalidToken('Token contained no recognizable user identification')
        try:
            user = self.user_model.objects.get(**{api_settings.USER_ID_FIELD: user_id})
        except self.user_model.DoesNotExist:
            raise AuthenticationFailed('User not found', code='user_not_found')
        if not user.is_active and not user.roles.filter(name='pharmacy').exists():
            # Not a pharmacy account — behave exactly like the base class so
            # this is safe to use as a fallback authenticator on shared
            # endpoints without weakening the inactive-account gate for
            # anyone else.
            raise AuthenticationFailed('User is inactive', code='user_inactive')
        claimed = validated_token.get('pv')
        if claimed is not None and claimed != password_version(user):
            raise AuthenticationFailed(
                'Your session has expired because the password was changed. Please sign in again.',
                code='password_changed')
        return user
