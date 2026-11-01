"""Route + ETA lookup for riders (fault F-003).

Provider: Google **Routes API** (`routes.googleapis.com/directions/v2:computeRoutes`).
The legacy Directions API (`maps.googleapis.com/maps/api/directions/json`) is not
enabled for new Google Cloud projects and answered `REQUEST_DENIED`; it is no
longer used.

The rest of the app talks only to `get_route()` and `RoutingError`, so another
provider can be swapped in by replacing `_fetch_google` — nothing outside this
module knows about Google's request/response shapes.

Error mapping (never a misleading 404 for a provider problem):
    location_missing            422  order has neither coordinates nor an address
    no_route                    422  provider answered but found no drivable route
    routing_not_configured      503  no server API key configured
    routing_configuration_error 503  key invalid / API not enabled / key restricted
    routing_quota_exceeded      503  provider quota or rate limit hit
    routing_unreachable         502  network failure / unexpected provider answer
    routing_timeout             504  provider did not answer in time
"""
import json
import urllib.error
import urllib.request

from django.conf import settings
from django.core.cache import cache

PROVIDER = 'google_routes'
ROUTES_URL = 'https://routes.googleapis.com/directions/v2:computeRoutes'
TIMEOUT_SECONDS = 6
CACHE_SECONDS = 300
FIELD_MASK = 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline'


class RoutingError(Exception):
    def __init__(self, code, detail, status):
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.status = status


def _api_key():
    # a dedicated server key only: the browser/Android key is referrer/app restricted and public by design
    return (getattr(settings, 'GOOGLE_ROUTES_API_KEY', '') or '').strip()


def _waypoint(lat, lng, address):
    if lat is not None and lng is not None:
        return {'location': {'latLng': {'latitude': float(lat), 'longitude': float(lng)}}}
    if (address or '').strip():
        return {'address': address.strip()}
    return None


def _classify_http_error(status, body):
    """Map a non-200 provider answer onto an application error."""
    try:
        err = json.loads(body).get('error', {})
    except (ValueError, AttributeError):
        err = {}
    reason = ' '.join(
        str(d.get('reason', '')) for d in err.get('details', []) if isinstance(d, dict)
    ).upper()
    provider_status = str(err.get('status', '')).upper()
    if status == 429 or provider_status == 'RESOURCE_EXHAUSTED':
        return RoutingError('routing_quota_exceeded',
                            'The routing service quota was exceeded. Try again shortly.', 503)
    if status in (400, 401, 403) and (
            'API_KEY' in reason or 'SERVICE_DISABLED' in reason or 'ACCESS_NOT_CONFIGURED' in reason
            or provider_status in ('PERMISSION_DENIED', 'UNAUTHENTICATED')):
        return RoutingError(
            'routing_configuration_error',
            'The routing service is not configured correctly (API key rejected or Routes API not enabled).', 503)
    if status == 400 and provider_status in ('INVALID_ARGUMENT', 'NOT_FOUND'):
        return RoutingError('no_route', 'No route could be found between these locations.', 422)
    if status == 404:
        return RoutingError('no_route', 'No route could be found between these locations.', 422)
    return RoutingError('routing_unreachable', 'The routing service returned an unexpected error.', 502)


def _fetch_google(origin, destination, key):
    body = json.dumps({
        'origin': origin, 'destination': destination,
        'travelMode': 'DRIVE', 'routingPreference': 'TRAFFIC_UNAWARE',
    }).encode()
    req = urllib.request.Request(ROUTES_URL, data=body, method='POST', headers={
        'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': FIELD_MASK,
    })
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        raise _classify_http_error(exc.code, exc.read().decode(errors='replace'))
    except TimeoutError:
        raise RoutingError('routing_timeout', 'The routing service took too long to answer.', 504)
    except urllib.error.URLError as exc:
        if isinstance(getattr(exc, 'reason', None), TimeoutError):
            raise RoutingError('routing_timeout', 'The routing service took too long to answer.', 504)
        raise RoutingError('routing_unreachable', 'Could not reach the routing service.', 502)
    except ValueError:
        raise RoutingError('routing_unreachable', 'The routing service returned an unreadable answer.', 502)
    routes = data.get('routes') or []
    if not routes:
        raise RoutingError('no_route', 'No route could be found between these locations.', 422)
    r = routes[0]
    try:
        seconds = int(str(r.get('duration', '0s')).rstrip('s') or 0)
        return {
            'polyline': r['polyline']['encodedPolyline'],
            'distance_km': round(int(r['distanceMeters']) / 1000, 2),
            'duration_min': max(1, round(seconds / 60)),
        }
    except (KeyError, TypeError, ValueError):
        raise RoutingError('routing_unreachable', 'The routing service returned an unreadable answer.', 502)


def get_route(pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address):
    """Return {polyline, distance_km, duration_min, provider} or raise RoutingError."""
    origin = _waypoint(pickup_lat, pickup_lng, pickup_address)
    destination = _waypoint(drop_lat, drop_lng, drop_address)
    if origin is None or destination is None:
        raise RoutingError('location_missing',
                           'This order has no pickup/drop location to route between.', 422)
    key = _api_key()
    if not key:
        raise RoutingError('routing_not_configured', 'Routing is not configured on the server.', 503)
    cache_key = 'route:' + json.dumps([origin, destination], sort_keys=True)
    cached = cache.get(cache_key)
    if cached:
        return {**cached, 'provider': PROVIDER, 'cached': True}
    result = _fetch_google(origin, destination, key)
    cache.set(cache_key, result, CACHE_SECONDS)
    return {**result, 'provider': PROVIDER, 'cached': False}
