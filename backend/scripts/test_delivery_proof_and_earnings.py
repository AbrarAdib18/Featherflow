"""Proof-of-delivery requirement, rider stats accuracy, and per-delivery
earnings regression suite — see DELIVERY_PROOF_AND_STATS_FIX.md.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_delivery_proof_and_earnings.py

Live DB, `delivproof+` prefixed throw-away accounts. Idempotent.

Complements (does not duplicate):
- scripts/test_feed_order_delivery.py — the full feed-order -> delivery ->
  proof -> delivered chain through the real order-assignment flow.
- scripts/test_private_documents.py — the four-way (owner/other/anon/admin)
  + farmer-two-party access matrix for the proof photo itself.

This file creates DeliveryOrder rows directly via the ORM (skipping the
order-assignment flow, already covered above) to focus on: upload
validation, proof-token ownership, rider-ownership on the completion
endpoint, RBAC for non-delivery accounts, stats accuracy (delivered/pending
counts, both live-queried), and earnings (flat 60 BDT base at zero distance,
idempotency, and cross-endpoint consistency between the dashboard and
earnings-summary delivered counts).
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
from profiles.models import DeliveryProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'delivproof+'
JSON = 'application/json'

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
    DeliveryEarning.objects.filter(delivery_person__user__in=users).delete()
    DeliveryOrder.objects.filter(delivery_person__user__in=users).delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()
    AdminPanelRecord.objects.filter(module='feed-orders', record_id__startswith='DELIVPROOF-').delete()


def mk_user(tag, role_name):
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone='+8802' + str(abs(hash(f'{PREFIX}{tag}')) % 100_000_000).zfill(8),
        full_name=tag.title(), date_of_birth=date(1990, 1, 1), present_address='Dhaka',
        consent_terms=True, account_status='active', is_verified=True,
    )
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def make_order(rider_profile, farmer, *, same_point=True, record_tag='ord'):
    """A DeliveryOrder ready to walk through accepted->picked_up->on_the_way,
    linked to a real feed-order AdminPanelRecord so `_order_json`/proof
    two-party access resolve correctly. `same_point=True` puts pickup and
    drop at the identical coordinate (distance 0) so the earning is exactly
    the flat BASE_DELIVERY_PAY with no distance bonus — needed to test the
    "delivered_count × 60 BDT" relationship exactly, per the brief."""
    record = AdminPanelRecord.objects.create(
        module='feed-orders', record_id=f'DELIVPROOF-{record_tag}-{rider_profile.user_id}',
        payload={'id': f'DELIVPROOF-{record_tag}', 'farmer_id': str(farmer.id),
                 'status': 'processing', 'items': []},
    )
    lat, lng = ('23.81', '90.41')
    return DeliveryOrder.objects.create(
        delivery_person=rider_profile, order_reference_id=record.id, order_type='marketplace',
        pickup_address='Warehouse', delivery_address='Farm', status='accepted',
        pickup_lat=lat, pickup_lng=lng,
        delivery_lat=lat if same_point else '23.90', delivery_lng=lng if same_point else '90.50',
    )


def upload_proof(client):
    r = client.post('/api/delivery/proof-upload/',
                     {'file': SimpleUploadedFile('proof.png', PNG, content_type='image/png')})
    return r


def main():
    cleanup()
    rider = mk_user('rider1', 'delivery')
    rider2 = mk_user('rider2', 'delivery')
    farmer = mk_user('farmer1', 'farmer')
    rider_profile = DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-{rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=None)
    rider2_profile = DeliveryProfile.objects.create(
        user=rider2, drivers_license_number=f'DL-{rider2.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='x', approved_by_admin=None)

    rc, r2c, fc = client_for(rider), client_for(rider2), client_for(farmer)

    print('\n== proof-upload validation ==')
    r = rc.post('/api/delivery/proof-upload/', {'file': SimpleUploadedFile('n.txt', b'hello', content_type='text/plain')})
    check('non-image file rejected -> 400', r.status_code == 400, r.content[:200])
    big = SimpleUploadedFile('big.png', PNG + b'0' * (6 * 1024 * 1024), content_type='image/png')
    r = rc.post('/api/delivery/proof-upload/', {'file': big})
    check('oversized (>5MB) file rejected -> 400', r.status_code == 400, r.content[:200])
    r = rc.post('/api/delivery/proof-upload/', {'file': SimpleUploadedFile('fake.png', b'not really a png', content_type='image/png')})
    check('fake extension (bad magic bytes) rejected -> 400', r.status_code == 400, r.content[:200])
    r = rc.post('/api/delivery/proof-upload/', {})
    check('no file -> 400', r.status_code == 400, r.content[:200])

    print('\n== RBAC: non-delivery accounts are refused on every delivery endpoint ==')
    for path, method in [
        ('/api/delivery/dashboard/', 'get'), ('/api/delivery/earnings/', 'get'),
        ('/api/delivery/proof-upload/', 'post'),
    ]:
        r = getattr(fc, method)(path)
        check(f'farmer account refused on {path} (403)', r.status_code == 403, r.status_code)

    order1 = make_order(rider_profile, farmer, record_tag='ord1')
    r = rc.patch(f'/api/delivery/orders/{order1.id}/status/', {'status': 'picked_up'}, content_type=JSON)
    check('rider1 owns order1, can progress it', r.status_code == 200, r.content[:200])
    r = r2c.patch(f'/api/delivery/orders/{order1.id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    check("only the assigned rider can act on a delivery — rider2 gets 404", r.status_code == 404, r.status_code)
    r = fc.patch(f'/api/delivery/orders/{order1.id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    check('a farmer account cannot modify delivery status at all (403)', r.status_code == 403, r.status_code)
    r = rc.patch(f'/api/delivery/orders/{order1.id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    check('rider1 progresses to on_the_way', r.status_code == 200, r.content[:200])

    print('\n== proof-token ownership: a rider cannot attach another rider\'s photo ==')
    order2 = make_order(rider2_profile, farmer, record_tag='ord2')
    rc.patch(f'/api/delivery/orders/{order2.id}/status/', {'status': 'picked_up'}, content_type=JSON)
    rc2_progress = r2c.patch(f'/api/delivery/orders/{order2.id}/status/', {'status': 'picked_up'}, content_type=JSON)
    check('setup: rider2 owns order2', rc2_progress.status_code == 200, rc2_progress.content[:200])
    r2c.patch(f'/api/delivery/orders/{order2.id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    rider1_photo = upload_proof(rc).json()['url']
    r = r2c.patch(f'/api/delivery/orders/{order2.id}/status/',
                  {'status': 'delivered', 'proof_of_delivery_url': rider1_photo}, content_type=JSON)
    check("rider2 can't complete their delivery with rider1's photo token (400)",
          r.status_code == 400 and 'verified' in r.json().get('detail', '').lower(), r.content[:200])

    print('\n== stats are live-queried from the database, not stale/hardcoded ==')
    r = rc.get('/api/delivery/dashboard/')
    before = r.json()['delivered_count']
    check('delivered_count starts at 0 for this fresh rider', before == 0, before)
    photo = upload_proof(rc).json()['url']
    r = rc.patch(f'/api/delivery/orders/{order1.id}/status/',
                 {'status': 'delivered', 'proof_of_delivery_url': photo}, content_type=JSON)
    check('rider1 completes order1 with a valid, own photo -> 200', r.status_code == 200, r.content[:200])
    r = rc.get('/api/delivery/dashboard/')
    dash = r.json()
    check('dashboard delivered_count is exactly 1 after one completed delivery, matching a '
          'direct DeliveryOrder.objects.filter(status="delivered").count()',
          dash['delivered_count'] == 1 ==
          DeliveryOrder.objects.filter(delivery_person=rider_profile, status='delivered').count(),
          dash['delivered_count'])
    r = r2c.get('/api/delivery/dashboard/')
    check("rider2's dashboard is unaffected by rider1's delivery (isolation)",
          r.json()['delivered_count'] == 0, r.json())

    print('\n== earnings: flat 60 BDT base at zero distance, idempotent ==')
    earning = DeliveryEarning.objects.get(delivery_order=order1)
    check('earning created with base_pay == 60.00 (pickup == drop, no distance bonus)',
          float(earning.base_pay) == 60.0 and float(earning.total_earned) == 60.0, earning.base_pay)
    r = rc.patch(f'/api/delivery/orders/{order1.id}/status/',
                 {'status': 'delivered', 'proof_of_delivery_url': photo}, content_type=JSON)
    check('repeat delivered confirmation is idempotent (200, not an error)', r.status_code == 200, r.content[:200])
    check('repeat confirmation did not create a second earning row',
          DeliveryEarning.objects.filter(delivery_order=order1).count() == 1)

    # A second, independent delivery for the same rider — checks the
    # "total earnings == delivered_count × 60 BDT" relationship holds across
    # more than one order, not just as a single-row coincidence.
    order3 = make_order(rider_profile, farmer, record_tag='ord3')
    rc.patch(f'/api/delivery/orders/{order3.id}/status/', {'status': 'picked_up'}, content_type=JSON)
    rc.patch(f'/api/delivery/orders/{order3.id}/status/', {'status': 'on_the_way'}, content_type=JSON)
    photo3 = upload_proof(rc).json()['url']
    rc.patch(f'/api/delivery/orders/{order3.id}/status/',
             {'status': 'delivered', 'proof_of_delivery_url': photo3}, content_type=JSON)
    r = rc.get('/api/delivery/earnings/')
    summary = r.json()
    check('total_earnings == delivered_count × 60 BDT for two zero-distance deliveries',
          summary['delivered_count'] == 2 and summary['total_earnings'] == 120.0, summary)
    check('earnings-summary delivered_count matches dashboard delivered_count '
          '(single source of truth, not two independently-drifting numbers)',
          summary['delivered_count'] == rc.get('/api/delivery/dashboard/').json()['delivered_count'])
    check('per_delivery_rate is exposed and equals the actual base rate',
          summary['per_delivery_rate'] == 60.0, summary.get('per_delivery_rate'))
    check('paid_deliveries_count is 0 — nothing has been paid out yet',
          summary['paid_deliveries_count'] == 0, summary.get('paid_deliveries_count'))

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
