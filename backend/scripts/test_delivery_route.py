"""Regression suite for F-003: rider route/ETA via the Google Routes API.

Provider calls are mocked (urllib.request.urlopen) so the suite is deterministic
and never spends quota; set ROUTE_LIVE=1 to add one real call with the
configured key.  Runs against the dev DB with throw-away `routetest+` accounts.

    python scripts/test_delivery_route.py
"""
import io
import json
import os
import sys
import urllib.error
from datetime import date
from unittest import mock

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.cache import cache  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import AdminPanelRecord  # noqa: E402
from delivery import routing  # noqa: E402
from delivery.models import DeliveryOrder  # noqa: E402
from profiles.models import DeliveryProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'routetest+'
SECRET = 'AIzaSyTESTKEY-not-real-0123456789abcd'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    DeliveryOrder.objects.filter(delivery_person__user__in=users).delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    users.delete()
    AdminPanelRecord.objects.filter(module='feed-orders', record_id__startswith='ROUTETEST-').delete()


_n = [0]


def mk_user(tag, role_name):
    _n[0] += 1
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=f'0196{os.getpid() % 1000:03d}{_n[0]:04d}', full_name=tag.title(),
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def mk_order(profile, tag, **kw):
    rec = AdminPanelRecord.objects.create(
        module='feed-orders', record_id=f'ROUTETEST-{tag}-{profile.user_id}',
        payload={'id': f'ROUTETEST-{tag}', 'status': 'processing', 'items': []})
    base = dict(delivery_person=profile, order_reference_id=rec.id, order_type='marketplace',
                pickup_address='Warehouse', delivery_address='Farm', status='accepted',
                pickup_lat='23.81', pickup_lng='90.41', delivery_lat='23.78', delivery_lng='90.42')
    base.update(kw)
    return DeliveryOrder.objects.create(**base)


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


GOOD = {'routes': [{'duration': '1189s', 'distanceMeters': 5259,
                    'polyline': {'encodedPolyline': 'mmipCsoyfPbAa@l@]'}}]}


def ok(payload=GOOD):
    return lambda req, timeout=None: _Resp(json.dumps(payload).encode())


def http_error(code, payload):
    def f(req, timeout=None):
        raise urllib.error.HTTPError(req.full_url, code, 'err', {}, io.BytesIO(json.dumps(payload).encode()))
    return f


def raising(exc):
    def f(req, timeout=None):
        raise exc
    return f


def google_err(code, status, reason=None):
    d = {'error': {'code': code, 'status': status, 'message': 'x'}}
    if reason:
        d['error']['details'] = [{'@type': 'type.googleapis.com/google.rpc.ErrorInfo', 'reason': reason}]
    return d


def main():
    cleanup()
    rider = mk_user('rider', 'delivery')
    rider2 = mk_user('rider2', 'delivery')
    farmer = mk_user('farmer', 'farmer')
    prof = DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-{rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=None)
    DeliveryProfile.objects.create(
        user=rider2, drivers_license_number=f'DL-{rider2.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=None)
    rc, r2c, fc = client_for(rider), client_for(rider2), client_for(farmer)
    n = [0]

    def fresh_order(**kw):
        n[0] += 1
        return mk_order(prof, f'o{n[0]}', **kw)

    def call(o, handler, c=rc, key=SECRET):
        cache.clear()
        with mock.patch.object(dj_settings, 'GOOGLE_ROUTES_API_KEY', key), \
                mock.patch('delivery.routing.urllib.request.urlopen', side_effect=handler) as m:
            r = c.get(f'/api/delivery/orders/{o.id}/route/')
        return r, m

    print('\n== successful route ==')
    o = fresh_order()
    r, m = call(o, ok())
    body = r.json()
    check('200 with polyline, distance and duration', r.status_code == 200 and body['polyline']
          and body['distance_km'] == 5.26 and body['duration_min'] == 20, r.content[:300])
    check('provider is reported', body.get('provider') == 'google_routes')
    req = m.call_args[0][0]
    sent = json.loads(req.data)
    check('uses the Routes API endpoint (not legacy Directions)',
          req.full_url == routing.ROUTES_URL and 'directions/json' not in req.full_url, req.full_url)
    check('request is POST with api key + field mask headers, key not in URL',
          req.get_method() == 'POST' and req.get_header('X-goog-api-key') == SECRET
          and 'routes.polyline' in req.get_header('X-goog-fieldmask') and SECRET not in req.full_url)
    check('request body has lat/lng waypoints and DRIVE mode',
          sent['origin']['location']['latLng']['latitude'] == 23.81
          and sent['destination']['location']['latLng']['longitude'] == 90.42 and sent['travelMode'] == 'DRIVE', sent)
    check('server key is never echoed to the client', SECRET not in r.content.decode())
    with mock.patch.object(dj_settings, 'GOOGLE_ROUTES_API_KEY', SECRET), \
            mock.patch('delivery.routing.urllib.request.urlopen', side_effect=raising(AssertionError('provider hit again'))):
        r2 = rc.get(f'/api/delivery/orders/{o.id}/route/')
    check('second identical request is served from cache (no provider call)',
          r2.status_code == 200 and r2.json().get('cached') is True, r2.content[:200])

    print('\n== provider failures map to meaningful statuses (never 404) ==')
    cases = [
        ('invalid key (API_KEY_INVALID) -> 503 routing_configuration_error',
         http_error(400, google_err(400, 'INVALID_ARGUMENT', 'API_KEY_INVALID')), 503, 'routing_configuration_error'),
        ('Routes API not enabled (SERVICE_DISABLED) -> 503 routing_configuration_error',
         http_error(403, google_err(403, 'PERMISSION_DENIED', 'SERVICE_DISABLED')), 503, 'routing_configuration_error'),
        ('key restricted (PERMISSION_DENIED) -> 503 routing_configuration_error',
         http_error(403, google_err(403, 'PERMISSION_DENIED')), 503, 'routing_configuration_error'),
        ('quota exceeded (429) -> 503 routing_quota_exceeded',
         http_error(429, google_err(429, 'RESOURCE_EXHAUSTED')), 503, 'routing_quota_exceeded'),
        ('provider 500 -> 502 routing_unreachable',
         http_error(500, google_err(500, 'INTERNAL')), 502, 'routing_unreachable'),
        ('network failure -> 502 routing_unreachable',
         raising(urllib.error.URLError('dns failure')), 502, 'routing_unreachable'),
        ('timeout -> 504 routing_timeout', raising(TimeoutError()), 504, 'routing_timeout'),
        ('URLError(timeout) -> 504 routing_timeout',
         raising(urllib.error.URLError(TimeoutError())), 504, 'routing_timeout'),
        ('garbage body -> 502 routing_unreachable',
         lambda req, timeout=None: _Resp(b'<html>nope</html>'), 502, 'routing_unreachable'),
        ('no drivable route (empty routes) -> 422 no_route', ok({'routes': []}), 422, 'no_route'),
        ('unroutable points (INVALID_ARGUMENT, no key reason) -> 422 no_route',
         http_error(400, google_err(400, 'INVALID_ARGUMENT')), 422, 'no_route'),
        ('malformed route object -> 502', ok({'routes': [{'duration': '5s'}]}), 502, 'routing_unreachable'),
    ]
    for name, handler, status, code in cases:
        r, _ = call(fresh_order(), handler)
        check(name, r.status_code == status and r.json().get('code') == code and r.status_code != 404,
              (r.status_code, r.content[:200]))

    print('\n== configuration ==')
    r, m = call(fresh_order(), ok(), key='')
    check('no key configured -> 503 routing_not_configured, provider not called',
          r.status_code == 503 and r.json().get('code') == 'routing_not_configured' and m.call_count == 0, r.content[:200])
    cache.clear()
    # the browser/Android Maps key is public by design and must never be used server-side
    with mock.patch.object(dj_settings, 'GOOGLE_MAPS_API_KEY', 'AIzaMAPKEY', create=True),             mock.patch.object(dj_settings, 'GOOGLE_ROUTES_API_KEY', ''),             mock.patch('delivery.routing.urllib.request.urlopen', side_effect=ok()) as m:
        r = rc.get(f'/api/delivery/orders/{fresh_order().id}/route/')
    check('a Maps (browser) key is NOT used as the server key: no Routes key -> 503, provider not called',
          r.status_code == 503 and r.json().get('code') == 'routing_not_configured' and m.call_count == 0, r.content[:160])


    print('\n== missing coordinates ==')
    o = fresh_order(pickup_lat=None, pickup_lng=None, delivery_lat=None, delivery_lng=None)
    r, m = call(o, ok())
    sent = json.loads(m.call_args[0][0].data)
    check('no coordinates but addresses -> routes by address', r.status_code == 200
          and sent['origin'] == {'address': 'Warehouse'} and sent['destination'] == {'address': 'Farm'}, (r.status_code, sent))
    o = fresh_order(pickup_lat=None, pickup_lng=None, delivery_lat=None, delivery_lng=None, pickup_address=' ', delivery_address='')
    r, m = call(o, ok())
    check('no coordinates and no address -> 422 location_missing (not 404), provider not called',
          r.status_code == 422 and r.json().get('code') == 'location_missing' and m.call_count == 0, r.content[:200])

    from django.utils import timezone
    o = fresh_order(pickup_lat=None, pickup_lng=None)
    prof.current_lat, prof.current_lng, prof.location_updated_at = 23.7, 90.3, timezone.now()
    prof.save(update_fields=['current_lat', 'current_lng', 'location_updated_at'])
    r, m = call(o, ok())
    sent = json.loads(m.call_args[0][0].data)
    check('no pickup coordinates + fresh rider location -> routes from the rider position',
          r.status_code == 200 and r.json()['origin_source'] == 'rider_location'
          and sent['origin']['location']['latLng']['latitude'] == 23.7, (r.status_code, sent))
    prof.location_updated_at = timezone.now() - __import__("datetime").timedelta(hours=2)
    prof.save(update_fields=['location_updated_at'])
    r, m = call(o, ok())
    check('stale rider location is ignored -> pickup address used',
          r.json()['origin_source'] == 'pickup_address'
          and json.loads(m.call_args[0][0].data)['origin'] == {'address': 'Warehouse'})

    print('\n== authorization / genuine not-found ==')
    o = fresh_order()
    r, _ = call(o, ok(), c=r2c)
    check("another rider's order -> 404 (a genuine not-found)", r.status_code == 404 and 'code' not in r.json(), r.content[:200])
    r, _ = call(o, ok(), c=fc)
    check('farmer -> 403', r.status_code == 403)
    r = Client().get(f'/api/delivery/orders/{o.id}/route/')
    check('anonymous -> 401', r.status_code == 401)
    import uuid
    r, _ = call(type('O', (), {'id': uuid.uuid4()}), ok())
    check('unknown order id -> 404', r.status_code == 404)

    if os.environ.get('ROUTE_LIVE') == '1':
        print('\n== live provider (ROUTE_LIVE=1) ==')
        cache.clear()
        r = rc.get(f'/api/delivery/orders/{fresh_order().id}/route/')
        check('live Routes API call succeeds', r.status_code == 200 and r.json()['distance_km'] > 0, r.content[:200])

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
