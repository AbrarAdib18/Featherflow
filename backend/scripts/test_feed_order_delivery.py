"""Priority 7/8 — feed order -> Feed Admin queue -> rider assignment ->
delivery status chain regression.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_feed_order_delivery.py

Live DB, `feeddelivtest+` prefixed throw-away accounts. Idempotent.

Covers: order appears in the Feed Admin queue with location data, only
approved riders are assignable, rider sees the assigned order + map location,
status transitions notify both sides, delivery completion is recorded, and
riders only see their own assigned feed deliveries (least-privilege).
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

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import AdminPanelRecord  # noqa: E402
from delivery.models import DeliveryEarning, DeliveryOrder  # noqa: E402
from feed_catalogue.models import FeedCompany, FeedProduct  # noqa: E402
from profiles.models import DeliveryProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'feeddelivtest+'
JSON = 'application/json'

# Minimal valid PNG (matches scripts/test_profile_photo.py's fixture) — a
# proof-of-delivery photo is now required before a delivery can be marked
# delivered (see DELIVERY_PROOF_AND_STATS_FIX.md).
PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
    '0000000d4944415478da6364f8cf000000030101002718d6a40000000049454e44ae426082')


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
    users.delete()


_n = [0]


def mk_user(role_name, panel_type=None):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel_type or role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{role_name}{n}@example.com', password='Test1234!',
        phone=f'0196{n:07d}', full_name=f'{role_name} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Priority 7/8: Feed order -> delivery chain regression ==\n')
    cleanup()

    feed_admin = mk_user('feed_admin', panel_type='admin')
    fac = client_for(feed_admin)
    farmer = mk_user('farmer')
    fc = client_for(farmer)
    rider = mk_user('delivery')
    rc = client_for(rider)
    unapproved_rider = mk_user('delivery')

    rider_profile = DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-{rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='pending-upload',
        approved_by_admin=feed_admin)
    unapproved_profile = DeliveryProfile.objects.create(
        user=unapproved_rider, drivers_license_number=f'DL-{unapproved_rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='pending-upload', approved_by_admin=None)

    company = FeedCompany.objects.create(name=f'{PREFIX}Co', status='active')
    product = FeedProduct.objects.create(
        company=company, product_name='Layer Feed', price=1000, stock_quantity=50,
        approval_status='approved')

    # ── Place the order ──────────────────────────────────────────────────
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': str(product.id), 'quantity': 2}],
        'delivery_address': 'Village Road 5', 'latitude': 23.81, 'longitude': 90.41,
        'payment_method': 'cod', 'contact_phone': '01711111111',
    }, content_type=JSON)
    check('farmer places feed order -> 201', r.status_code == 201, r.content[:300])
    order_id = r.json()['id']

    # ── Feed Admin queue ─────────────────────────────────────────────────
    r = fac.get('/api/admin-panel/feed-catalogue/orders/')
    check('order appears in Feed Admin queue',
          any(o['id'] == order_id for o in r.json()['results']), r.content[:300])
    r = fac.get(f'/api/admin-panel/feed-catalogue/orders/{order_id}/')
    check('order detail carries delivery location for the map',
          r.status_code == 200 and r.json()['latitude'] == 23.81 and r.json()['longitude'] == 90.41,
          r.content[:300])

    # ── Only approved riders are assignable ──────────────────────────────
    r = fac.get('/api/admin-panel/feed-catalogue/riders/available/')
    ids = [x['id'] for x in r.json()['results']]
    check('unapproved rider is not in the assignable list', str(unapproved_profile.id) not in ids, ids)
    check('approved rider is in the assignable list', str(rider_profile.id) in ids, ids)

    r = fac.post(f'/api/admin-panel/feed-catalogue/orders/{order_id}/assign/',
                {'rider_id': str(unapproved_profile.id)}, content_type=JSON)
    check('assigning an unapproved rider is rejected', r.status_code == 409, r.content[:300])

    r = fac.post(f'/api/admin-panel/feed-catalogue/orders/{order_id}/assign/',
                {'rider_id': str(rider_profile.id)}, content_type=JSON)
    check('assigning an approved rider succeeds -> 201', r.status_code == 201, r.content[:300])
    delivery_order_id = r.json()['delivery_order_id']

    # ── Rider sees the pending offer with map location, least-privilege ──
    r = rc.get('/api/delivery/requests/')
    check('rider sees the pending assignment in their requests', r.status_code == 200 and
          any(o['id'] == delivery_order_id for o in r.json()['results']), r.content[:300])
    mine = next(o for o in r.json()['results'] if o['id'] == delivery_order_id)
    check('rider sees the delivery lat/lng for the map',
          mine.get('delivery_lat') == 23.81 and mine.get('delivery_lng') == 90.41, mine)
    check('rider sees a farmer contact number and no extra PII (least privilege)',
          bool(mine.get('customer_phone')) and 'national_id_number' not in mine
          and 'present_address' not in mine, mine)

    other_rider = mk_user('delivery')
    other_profile = DeliveryProfile.objects.create(
        user=other_rider, drivers_license_number=f'DL-{other_rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='pending-upload', approved_by_admin=feed_admin)
    orc = client_for(other_rider)
    r2 = orc.get('/api/delivery/requests/')
    check("a different rider does not see this rider's assigned feed order",
          all(o['id'] != delivery_order_id for o in r2.json()['results']), r2.content[:300])

    # ── Delivery progresses; farmer/admin notified; completion recorded ──
    r = rc.patch(f'/api/delivery/requests/{delivery_order_id}/respond/', {'action': 'accept'}, content_type=JSON)
    check('rider accepts -> 200', r.status_code == 200, r.content[:300])
    r = rc.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'picked_up'}, content_type=JSON)
    check('rider marks picked_up -> 200', r.status_code == 200, r.content[:300])
    r = rc.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    check('rider marks on_the_way -> 200', r.status_code == 200, r.content[:300])
    r = rc.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'delivered'}, content_type=JSON)
    check('delivered without a proof photo is rejected -> 400',
          r.status_code == 400 and 'proof' in r.json().get('detail', '').lower(), r.content[:300])
    r = rc.post('/api/delivery/proof-upload/', {'file': SimpleUploadedFile('proof.png', PNG, content_type='image/png')})
    check('proof photo upload -> 201', r.status_code == 201, r.content[:300])
    proof_url = r.json()['url']
    r = rc.patch(f'/api/delivery/orders/{delivery_order_id}/status/',
                 {'status': 'delivered', 'proof_of_delivery_url': proof_url}, content_type=JSON)
    check('rider marks delivered with proof -> 200', r.status_code == 200, r.content[:300])
    r = rc.patch(f'/api/delivery/orders/{delivery_order_id}/status/',
                 {'status': 'delivered', 'proof_of_delivery_url': proof_url}, content_type=JSON)
    check('repeat delivered confirmation is idempotent (200, same order)',
          r.status_code == 200 and r.json()['id'] == delivery_order_id, r.content[:300])
    check('idempotent retry did not create a second earning row',
          DeliveryEarning.objects.filter(delivery_order_id=delivery_order_id).count() == 1)

    order = AdminPanelRecord.objects.get(module='feed-orders', payload__id=order_id)
    check("farmer's feed-order record reflects delivered status", order.payload.get('status') == 'delivered', order.payload)

    r = fc.get(f'/api/farmers/feed-catalogue/orders/{order_id}/')
    check('farmer sees delivered status via their own order endpoint',
          r.status_code == 200 and r.json()['status'] == 'delivered', r.content[:300])

    # ── A rejected/expired assignment can be reassigned (bug found live) ──
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': str(product.id), 'quantity': 1}],
        'delivery_address': 'Village Road 9', 'payment_method': 'cod',
    }, content_type=JSON)
    order2_id = r.json()['id']
    r = fac.post(f'/api/admin-panel/feed-catalogue/orders/{order2_id}/assign/',
                {'rider_id': str(rider_profile.id)}, content_type=JSON)
    check('second order assigned to rider -> 201', r.status_code == 201, r.content[:300])
    delivery_order2_id = r.json()['delivery_order_id']
    r = rc.patch(f'/api/delivery/requests/{delivery_order2_id}/respond/', {'action': 'reject'}, content_type=JSON)
    check('rider rejects the offer -> 200', r.status_code == 200, r.content[:300])

    r = fac.get(f'/api/admin-panel/feed-catalogue/orders/{order2_id}/')
    detail = r.json()
    check('feed_admin sees the rejection via delivery_status (not stuck at "assigned")',
          detail.get('delivery_status') == 'rejected' and detail.get('can_assign_rider') is True, detail)

    r = fac.post(f'/api/admin-panel/feed-catalogue/orders/{order2_id}/assign/',
                {'rider_id': str(other_profile.id)}, content_type=JSON)
    check('feed_admin can reassign a rejected order to a different rider -> 201',
          r.status_code == 201, r.content[:300])
    check('reassignment produced a new delivery_order_id',
          r.json()['delivery_order_id'] != delivery_order2_id, r.json())

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
