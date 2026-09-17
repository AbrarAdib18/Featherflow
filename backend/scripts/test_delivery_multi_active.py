"""Multi-active-delivery regression suite (delivery/services.py).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_delivery_multi_active.py

Live DB, `multiactvtest+` prefixed throw-away accounts. Idempotent.

Covers the fix for the bug documented in FEED_AND_DATA_INTEGRITY_AUDIT.md /
OPERATIONS_RUNBOOK.md §11: a rider with two concurrent in-progress
deliveries used to have only the most-recently-assigned one exposed by
`GET /api/delivery/dashboard/`, silently hiding the other. This suite
exercises `active_orders`, the deterministic ordering, the per-rider
concurrent-order cap, least-privilege isolation, and that a status update on
one order never touches another — across both feed and pharmacy deliveries,
since both share the same `delivery` app.
"""
import os
import sys
import uuid as _uuid
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

from audit.models import AdminPanelRecord  # noqa: E402
from delivery.models import DeliveryEarning, DeliveryOrder  # noqa: E402
from delivery.services import MAX_CONCURRENT_ORDERS_PER_RIDER  # noqa: E402
from feed_catalogue.models import FeedCompany, FeedProduct  # noqa: E402
from profiles.models import DeliveryProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'multiactvtest+'
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
    companies = FeedCompany.objects.filter(name__startswith=PREFIX)
    FeedProduct.objects.filter(company__in=companies).delete()
    companies.delete()
    DeliveryEarning.objects.filter(delivery_person__user__in=users).delete()
    DeliveryOrder.objects.filter(delivery_person__user__in=users).delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    AdminPanelRecord.objects.filter(module='feed-orders', payload__farmer_id__in=[
        str(u.id) for u in users]).delete()
    AdminPanelRecord.objects.filter(module='pharmacy-orders', record_id__contains=PREFIX).delete()
    AdminPanelRecord.objects.filter(module='delivery-queue', record_id__contains=PREFIX).delete()
    users.delete()


_n = [0]


def mk_user(role_name, panel_type=None):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel_type or role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{role_name}{n}@example.com', password='Test1234!',
        phone=f'0197{n:07d}', full_name=f'{role_name} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def mk_delivery_ops_admin():
    """A real `admin_delivery` role user (seeded role, real permissions) —
    the same role `_assign_from_queue`/`_reassign_order`'s RBAC gate expects,
    so the pharmacy assignment path is exercised for real, not bypassed."""
    _n[0] += 1
    n = _n[0]
    role = Role.objects.get(name='admin_delivery')
    u = User.objects.create_user(
        email=f'{PREFIX}admindelivery{n}@example.com', password='Test1234!',
        phone=f'0198{n:07d}', full_name=f'Delivery Ops {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def mk_rider(feed_admin):
    rider = mk_user('delivery')
    profile = DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-{rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='pending-upload',
        approved_by_admin=feed_admin)
    return rider, profile, client_for(rider)


def place_feed_order(fc, product, address='Village Road', **extra):
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': str(product.id), 'quantity': 1}],
        'delivery_address': address, 'payment_method': 'cod', **extra,
    }, content_type=JSON)
    check(f'farmer places feed order ({address}) -> 201', r.status_code == 201, r.content[:300])
    return r.json()['id']


def assign_feed_order(fac, order_id, rider_profile_id, expect_status=201):
    r = fac.post(f'/api/admin-panel/feed-catalogue/orders/{order_id}/assign/',
                 {'rider_id': str(rider_profile_id)}, content_type=JSON)
    check(f'assign feed order {order_id[:8]} to rider -> {expect_status}',
          r.status_code == expect_status, r.content[:300])
    return r.json() if r.status_code == 201 else r.json()


def place_and_queue_pharmacy_order(delivery_admin_client, rider_profile_id, tag):
    """Mirrors test_admin_panel.py's pharmacy delivery-queue fixture shape —
    the exact structure `_assign_from_queue` expects."""
    pharm_rec = AdminPanelRecord.objects.create(
        module='pharmacy-orders', record_id=f'PO-{PREFIX}{tag}',
        payload={'farmer_name': 'QA Farmer', 'items': [{'name': 'Vitamins'}]})
    # The admin-panel dispatcher routes by a literal 'DQ-' *prefix* on
    # record_id (see api/admin_views.py's admin_record), so the queue id
    # must start with that exact string, not just contain it.
    qid = f'DQ-{PREFIX}{tag}'
    AdminPanelRecord.objects.create(module='delivery-queue', record_id=qid, payload={
        'customer': 'QA Farmer', 'pickup_address': 'Depot', 'delivery_address': 'Farm 1',
        'pharmacy_order_record_id': str(pharm_rec.id), 'otp_code': '1234',
        'is_cold_chain': False, 'is_prescription_required': False})
    r = delivery_admin_client.patch(
        f'/api/admin-panel/delivery-orders/{qid}/',
        data={'action': 'assign', 'rider_id': str(rider_profile_id)}, content_type=JSON)
    return r


def run():
    print('\n== Multi-active-delivery regression (delivery/services.py) ==\n')
    cleanup()

    feed_admin = mk_user('feed_admin', panel_type='admin')
    fac = client_for(feed_admin)
    delivery_admin = mk_delivery_ops_admin()
    dac = client_for(delivery_admin)
    farmer = mk_user('farmer')
    fc = client_for(farmer)

    rider1, rider1_profile, r1c = mk_rider(feed_admin)
    rider2, rider2_profile, r2c = mk_rider(feed_admin)
    rider3, rider3_profile, r3c = mk_rider(feed_admin)

    company = FeedCompany.objects.create(name=f'{PREFIX}Co', status='active')
    product = FeedProduct.objects.create(
        company=company, product_name='Layer Feed', price=1000, stock_quantity=500,
        approval_status='approved')

    # ── One active delivery ──────────────────────────────────────────────
    order1_id = place_feed_order(fc, product, address='Farm A')
    assign1 = assign_feed_order(fac, order1_id, rider1_profile.id)
    do1_id = assign1['delivery_order_id']
    r = r1c.patch(f'/api/delivery/requests/{do1_id}/respond/', {'action': 'accept'}, content_type=JSON)
    check('rider1 accepts order 1 -> 200', r.status_code == 200, r.content[:300])

    r = r1c.get('/api/delivery/dashboard/')
    dash = r.json()
    check('dashboard has exactly 1 active order', len(dash.get('active_orders', [])) == 1, dash.get('active_orders'))
    check('legacy active_order (back-compat) matches the single active order',
          dash.get('active_order', {}).get('id') == do1_id, dash.get('active_order'))

    # ── Two active deliveries (both feed) ────────────────────────────────
    order2_id = place_feed_order(fc, product, address='Farm B')
    assign2 = assign_feed_order(fac, order2_id, rider1_profile.id)
    do2_id = assign2['delivery_order_id']
    r = r1c.patch(f'/api/delivery/requests/{do2_id}/respond/', {'action': 'accept'}, content_type=JSON)
    check('rider1 accepts order 2 -> 200', r.status_code == 200, r.content[:300])

    r = r1c.get('/api/delivery/dashboard/')
    dash = r.json()
    active_ids = [o['id'] for o in dash.get('active_orders', [])]
    check('dashboard now has exactly 2 active orders (the bug this fixes)',
          len(active_ids) == 2, active_ids)
    check('the older order (order 1) is still visible, not hidden by the newer one',
          do1_id in active_ids, active_ids)
    check('deterministic ordering: same status (accepted) -> oldest-assigned first',
          active_ids == [do1_id, do2_id], active_ids)

    # ── Feed plus pharmacy active at the same time ───────────────────────
    r = place_and_queue_pharmacy_order(dac, rider1_profile.id, 'A')
    check('pharmacy order assigned to rider1 (already has 2 active) -> 201', r.status_code == 201, r.content[:300])
    do3_id = r.json()['id']
    r = r1c.patch(f'/api/delivery/requests/{do3_id}/respond/', {'action': 'accept'}, content_type=JSON)
    check('rider1 accepts the pharmacy order -> 200', r.status_code == 200, r.content[:300])

    r = r1c.get('/api/delivery/dashboard/')
    dash = r.json()
    by_id = {o['id']: o for o in dash.get('active_orders', [])}
    check('dashboard has 3 active orders: 2 feed + 1 pharmacy', len(by_id) == 3, list(by_id))
    check('feed orders still marked order_type "regular", pharmacy one marked "pharmacy"',
          by_id.get(do1_id, {}).get('order_type') == 'regular' and
          by_id.get(do3_id, {}).get('order_type') == 'pharmacy', by_id)

    # ── Assignment safety: rider cannot exceed the operational limit ────
    order4_id = place_feed_order(fc, product, address='Farm C')
    r = assign_feed_order(fac, order4_id, rider1_profile.id, expect_status=409)
    check(f'4th assignment blocked once at the {MAX_CONCURRENT_ORDERS_PER_RIDER}-order cap (not silently dropped)',
          isinstance(r, dict) and 'detail' in r and str(MAX_CONCURRENT_ORDERS_PER_RIDER) in r['detail'], r)
    # the order itself must still exist and be assignable to someone else,
    # not silently discarded because rider1 was full
    r2 = assign_feed_order(fac, order4_id, rider2_profile.id)
    check('the same order can immediately go to a different, non-full rider -> 201',
          'delivery_order_id' in r2, r2)

    # ── Status update on one order does not change another ──────────────
    r = r1c.patch(f'/api/delivery/orders/{do1_id}/status/', {'status': 'picked_up'}, content_type=JSON)
    check('rider1 marks order 1 picked_up -> 200', r.status_code == 200, r.content[:300])
    r = r1c.get('/api/delivery/dashboard/')
    dash = r.json()
    by_id = {o['id']: o for o in dash.get('active_orders', [])}
    check('order 1 is now picked_up', by_id.get(do1_id, {}).get('status') == 'picked_up', by_id.get(do1_id))
    check('order 2 is unaffected, still accepted', by_id.get(do2_id, {}).get('status') == 'accepted', by_id.get(do2_id))
    check('order 3 (pharmacy) is unaffected, still accepted', by_id.get(do3_id, {}).get('status') == 'accepted', by_id.get(do3_id))
    check('priority ordering: picked_up sorts ahead of accepted',
          [o['id'] for o in dash['active_orders']][0] == do1_id, dash['active_orders'])

    # ── Refresh / dashboard response contains all active orders ─────────
    r = r1c.get('/api/delivery/dashboard/')
    check('a fresh dashboard fetch still returns all 3 active orders (refresh-safe)',
          len(r.json().get('active_orders', [])) == 3, r.json().get('active_orders'))

    # ── Unauthorized delivery visibility ─────────────────────────────────
    r = r2c.get('/api/delivery/dashboard/')
    r2_active_ids = [o['id'] for o in r.json().get('active_orders', [])]
    check("rider2's dashboard does not include any of rider1's active orders",
          not set(r2_active_ids) & {do1_id, do2_id, do3_id}, r2_active_ids)
    r = r2c.get('/api/delivery/orders/')
    check("rider2's order history does not leak rider1's orders",
          not any(o['id'] in (do1_id, do2_id, do3_id) for o in r.json()['results']), r.json()['results'])

    # ── Reassignment after rejection/expiry still works with the cap ────
    order5_id = place_feed_order(fc, product, address='Farm D')
    assign5 = assign_feed_order(fac, order5_id, rider3_profile.id)
    do5_id = assign5['delivery_order_id']
    r = r3c.patch(f'/api/delivery/requests/{do5_id}/respond/', {'action': 'reject'}, content_type=JSON)
    check('rider3 rejects order 5 -> 200', r.status_code == 200, r.content[:300])
    r = fac.get(f'/api/admin-panel/feed-catalogue/orders/{order5_id}/')
    check('feed_admin sees the rejection (delivery_status=rejected, can_assign_rider=True)',
          r.json().get('delivery_status') == 'rejected' and r.json().get('can_assign_rider') is True, r.json())
    # rider3's open count is back to 0 after rejecting -> capacity check must
    # not still count the rejected offer against them
    reassign = assign_feed_order(fac, order5_id, rider3_profile.id)
    check('reassigning back onto the same (now-idle) rider succeeds -> 201',
          'delivery_order_id' in reassign, reassign)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
