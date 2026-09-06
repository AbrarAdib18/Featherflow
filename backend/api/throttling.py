"""One throttle class, applied as the project-wide default, that only rate-limits
the admin-panel / polling / support surface and leaves every other endpoint
untouched. Rates come from ``REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']``.
"""

from rest_framework.throttling import SimpleRateThrottle

_THROTTLED_PREFIXES = ('/api/admin-panel/', '/api/me/updates', '/api/support/')


class ScopedApiThrottle(SimpleRateThrottle):
    scope = 'admin_read'  # placeholder; real scope chosen per-request below

    def get_cache_key(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return None
        path = request.path
        if not any(path.startswith(p) for p in _THROTTLED_PREFIXES):
            return None  # untracked → never throttled

        if '/export/' in path:
            self.scope = 'admin_export'
        elif 'updates' in path:
            self.scope = 'admin_poll'
        elif request.method in ('POST', 'PATCH', 'PUT', 'DELETE'):
            self.scope = 'admin_write'
        else:
            self.scope = 'admin_read'

        self.rate = self.get_rate()
        self.num_requests, self.duration = self.parse_rate(self.rate)
        return f'{self.scope}:{user.pk}'
