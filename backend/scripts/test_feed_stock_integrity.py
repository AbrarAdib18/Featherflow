"""Feed stock update/integrity regression suite — see
FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_feed_stock_integrity.py

Live DB, `feedstocktest+` prefixed throw-away accounts. Idempotent.

Root cause covered by this suite's centerpiece test ("repeating the same
purchase with different casing/whitespace accumulates onto the same stock
row"): `feed/views.py`'s POST handler used to look up FeedType via an exact
`(name, brand, unit)` string match, so retyping the same feed with different
casing/whitespace created a brand-new FeedType + FeedStock row instead of
incrementing the existing one — the row the farmer was looking at never
moved. Fixed with a case/whitespace-insensitive lookup.
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from farms.models import Farm, Flock  # noqa: E402
from feed.models import FeedConsumption, FeedStock, FeedStockMovement, FeedType  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'feedstocktest+'
JSON = 'application/json'


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
    farms = Farm.objects.filter(farmer__user__in=users)
    FeedStockMovement.objects.filter(farm__in=farms).delete()
    FeedConsumption.objects.filter(flock__farm__in=farms).delete()
    FeedStock.objects.filter(farm__in=farms).delete()
    Flock.objects.filter(farm__in=farms).delete()
    Notification.objects.filter(user__in=users).delete()
    farms.delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()
    FeedType.objects.filter(name__istartswith=PREFIX).delete()


_n = [0]


def mk_farmer():
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u = User.objects.create_user(
        email=f'{PREFIX}{n}@example.com', password='Test1234!',
        phone=f'0195{n:07d}', full_name=f'Farmer {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    fp, _ = FarmerProfile.objects.get_or_create(
        user=u, defaults={'farm_name': f'Farm {n}', 'owner_name': f'Farmer {n}',
                          'farm_location': 'L', 'farm_address': 'A'})
    farm = Farm.objects.create(farmer=fp, farm_name=f'Farm {n}', farm_type='mixed',
                                location='L', address='A')
    return u, farm


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def main():
    cleanup()
    feed_name = f'{PREFIX}Layer Starter'

    farmer, farm = mk_farmer()
    farmer2, farm2 = mk_farmer()
    c, c2 = client_for(farmer), client_for(farmer2)

    print('\n== adding feed increases current stock ==')
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'brand': 'ACI', 'unit': 'kg', 'quantity': '100', 'cost_per_unit': '50',
    }, content_type=JSON)
    check('add feed -> 201', r.status_code == 201, r.content[:200])
    check('response echoes the new quantity_available', r.json()['quantity_available'] == 100.0, r.json())
    stock_id = r.json()['id']

    r = c.get('/api/farmers/feed/inventory/')
    stock_row = next(s for s in r.json()['stock'] if s['id'] == stock_id)
    check('GET reflects the persisted stock (100)', stock_row['quantity_available'] == 100.0, stock_row)

    print("\n== repeating the 'same' purchase with different casing/whitespace "
          "accumulates onto the SAME row (the actual bug fix) ==")
    r = c.post('/api/farmers/feed/inventory/', {
        # Different case, extra whitespace, same feed as far as any farmer is concerned.
        'name': f'  {feed_name.upper()}  ', 'brand': ' aci ', 'unit': 'kg',
        'quantity': '25', 'cost_per_unit': '52',
    }, content_type=JSON)
    check('second purchase -> 201', r.status_code == 201, r.content[:200])
    check('second purchase targeted the SAME stock row', r.json()['id'] == stock_id, r.json())
    check('quantity accumulated to 125, not reset to 25 on a new row',
          r.json()['quantity_available'] == 125.0, r.json())
    check('exactly one FeedStock row exists for this farm (no duplicate row)',
          FeedStock.objects.filter(farm=farm, feed_type__name__iexact=feed_name).count() == 1)

    print('\n== a different unit for "the same" feed IS a separate line (by design; no unit conversion) ==')
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'brand': 'ACI', 'unit': 'bag', 'quantity': '10', 'cost_per_unit': '500',
    }, content_type=JSON)
    check('purchase in a different unit -> 201', r.status_code == 201, r.content[:200])
    check('creates a distinct stock line (different unit)', r.json()['id'] != stock_id, r.json())

    print('\n== validation ==')
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'unit': 'kg', 'quantity': '0', 'cost_per_unit': '10',
    }, content_type=JSON)
    check('zero quantity rejected -> 400', r.status_code == 400, r.content[:200])
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'unit': 'kg', 'quantity': '-5', 'cost_per_unit': '10',
    }, content_type=JSON)
    check('negative quantity rejected -> 400', r.status_code == 400, r.content[:200])
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'unit': 'kg', 'quantity': '5', 'cost_per_unit': '-1',
    }, content_type=JSON)
    check('negative cost rejected -> 400', r.status_code == 400, r.content[:200])
    r = c.post('/api/farmers/feed/inventory/', {
        'name': feed_name, 'unit': 'kg', 'quantity': 'abc', 'cost_per_unit': '10',
    }, content_type=JSON)
    check('non-numeric quantity rejected -> 400', r.status_code == 400, r.content[:200])

    print('\n== real purchase history (not the old fake current-stock redisplay) ==')
    r = c.get('/api/farmers/feed/inventory/')
    history = r.json()['history']
    purchases = [h for h in history if h['feed_type'].lower() == feed_name.lower()
                 and h['unit'] == 'kg' and h['movement_type'] == 'purchase']
    check('history has one entry per purchase (2 for the kg line), not one per stock row',
          len(purchases) == 2, [h['quantity'] for h in purchases])
    check('history entries carry the actual quantity of that purchase (100 then 25), '
          'not the running total', {p['quantity'] for p in purchases} == {100.0, 25.0}, purchases)

    print('\n== feed consumption reduces stock and cannot go negative ==')
    flock = Flock.objects.create(
        farm=farm, batch_name='Test Flock', bird_type='layer', breed='ISA Brown',
        quantity=500, current_quantity=500, start_date=date.today())
    feed_type_id = FeedStock.objects.get(id=stock_id).feed_type_id
    r = c.post('/api/farmers/feed/consumption/', {
        'flock_id': str(flock.id), 'feed_type_id': str(feed_type_id), 'quantity_consumed': '40',
    }, content_type=JSON)
    check('log consumption -> 201', r.status_code == 201, r.content[:200])
    consumption_id = r.json()['id']
    stock = FeedStock.objects.get(id=stock_id)
    check('stock reduced by the consumed amount (125 - 40 = 85)',
          float(stock.quantity_available) == 85.0, stock.quantity_available)
    check('a consumption movement was logged', FeedStockMovement.objects.filter(
        farm=farm, feed_type_id=feed_type_id, movement_type='consumption', quantity_delta=-40).exists())

    r = c.post('/api/farmers/feed/consumption/', {
        'flock_id': str(flock.id), 'feed_type_id': str(feed_type_id), 'quantity_consumed': '999999',
    }, content_type=JSON)
    check('over-consuming does not error, clamps at 0 instead', r.status_code == 201, r.content[:200])
    stock.refresh_from_db()
    check('stock floors at 0, never negative', float(stock.quantity_available) == 0.0, stock.quantity_available)
    big_consumption_id = r.json()['id']

    print('\n== deleting a consumption record restores the stock it drew down ==')
    r = c.delete(f'/api/farmers/feed/consumption/{big_consumption_id}/')
    check('delete consumption -> 204', r.status_code == 204, r.status_code)
    stock.refresh_from_db()
    check('stock restored by the deleted (clamped) consumption amount (0 + 85 = 85, not 999999)',
          float(stock.quantity_available) == 85.0, stock.quantity_available)
    r = c.delete(f'/api/farmers/feed/consumption/{consumption_id}/')
    check('delete the original 40-unit consumption -> 204', r.status_code == 204, r.status_code)
    stock.refresh_from_db()
    check('stock fully restored (85 + 40 = 125)', float(stock.quantity_available) == 125.0, stock.quantity_available)

    print('\n== ownership isolation ==')
    r = c2.get('/api/farmers/feed/inventory/')
    check("another farmer's inventory list never includes this farm's stock",
          all(s['id'] != stock_id for s in r.json()['stock']), r.json())
    r = c2.delete(f'/api/farmers/feed/inventory/{stock_id}/')
    check("another farmer can't delete this farm's stock line (404)", r.status_code == 404, r.status_code)
    r = c2.post('/api/farmers/feed/consumption/', {
        'flock_id': str(flock.id), 'feed_type_id': str(feed_type_id), 'quantity_consumed': '1',
    }, content_type=JSON)
    check("another farmer can't log consumption against this farm's flock (400/404, not 201)",
          r.status_code != 201, r.status_code)

    print('\n== deleting a stock line logs a removal movement ==')
    r = c.delete(f'/api/farmers/feed/inventory/{stock_id}/')
    check('delete stock line -> 204', r.status_code == 204, r.status_code)
    check('a removal movement was logged with the full remaining quantity', FeedStockMovement.objects.filter(
        farm=farm, feed_type_id=feed_type_id, movement_type='removal', quantity_delta=-125).exists())

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
