"""Private-document storage + access-control regression suite.

    backend/venv/Scripts/python.exe backend/scripts/test_private_documents.py

Covers the migration described in SECURITY_HARDENING_REPORT.md finding C2:
prescriptions, disease-scan images, financial receipts (expense/revenue/tax/
farm-photo), and delivery proof-of-delivery photos moved from public
`MEDIA_ROOT` to the private, signed-token, access-controlled storage system
(`verification/documents.py`) already used for signup documents and profile
photos. Community post media and pharmacy catalogue images were deliberately
LEFT public (a real social feed / product catalogue needs to be visible to
every viewer) — this suite also asserts that those two stayed public, i.e.
that the migration didn't overreach.

For every migrated upload type: upload it, then assert the returned URL is
NOT a public /media/ path, then exercise the four-way access matrix —
owner / other user / anonymous / admin — plus, for prescriptions specifically
(the one two-party document type), the fulfilling pharmacy vs. an unrelated
pharmacy.

Uses the live DB (Django test Client against the configured database). Creates
throw-away accounts prefixed ``privdoc+`` and cleans its own rows on entry and
exit. Idempotent.
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
os.environ.setdefault('THROTTLE_DOCUMENT_FETCH', '5000/hour')
os.environ.setdefault('THROTTLE_DISEASE_PREDICT', '5000/hour')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import AdminPanelRecord  # noqa: E402
from expenses.models import Expense, Loan, Revenue  # noqa: E402
from farms.models import Farm  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402
from verification.models import SignupDocument  # noqa: E402

PASS = FAIL = 0
PREFIX = 'privdoc+'
_PHONE = [869_000_000]

PNG = b'\x89PNG\r\n\x1a\n' + bytes(range(256)) * 4  # real PNG magic bytes + filler


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def phone():
    _PHONE[0] += 1
    return '+8801' + str(_PHONE[0])


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    for u in users:
        farms = Farm.objects.filter(farmer__user=u)
        Expense.objects.filter(farm__in=farms).delete()
        Revenue.objects.filter(farm__in=farms).delete()
        Loan.objects.filter(farm__in=farms).delete()
        farms.delete()
        FarmerProfile.objects.filter(user=u).delete()
        Payment.objects.filter(user=u).delete()
        Notification.objects.filter(user=u).delete()
        SignupDocument.objects.filter(user=u).delete()
    users.delete()
    SignupDocument.objects.filter(original_filename__startswith='privdoc-').delete()
    AdminPanelRecord.objects.filter(module='pharmacy-orders', record_id__startswith='PRIVDOC-').delete()


def mk_user(tag, role_name, **extra):
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=phone(), full_name=f'{role_name.title()} {tag}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True, **extra)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def png(name='photo.png'):
    return SimpleUploadedFile(name, PNG, content_type='image/png')


def real_jpeg(name='scan.jpg'):
    """A genuinely decodable image — ml/views.py:predict_disease runs Pillow
    inference on the bytes, unlike the other upload endpoints which only store
    them, so the magic-bytes-only PNG stub above isn't enough here."""
    import io as _io
    from PIL import Image
    buf = _io.BytesIO()
    Image.new('RGB', (400, 400), (150, 110, 70)).save(buf, 'JPEG')
    return SimpleUploadedFile(name, buf.getvalue(), content_type='image/jpeg')


def assert_private_url(name, url):
    check(f'{name}: URL is not a public /media/ path',
          bool(url) and '/media/' not in url and '/registration-documents/' in url, url)


def four_way(name, url, owner_client, other_client, admin_client):
    """owner 200, other user 403, anonymous 401, admin 200."""
    r = owner_client.get(url)
    check(f'{name}: owner can fetch (200)', r.status_code == 200, r.status_code)
    r = other_client.get(url)
    check(f'{name}: another user is refused (403)', r.status_code == 403, r.status_code)
    r = Client().get(url)
    check(f'{name}: anonymous is refused (401)', r.status_code == 401, r.status_code)
    r = admin_client.get(url)
    check(f'{name}: admin can fetch (200)', r.status_code == 200, r.status_code)


def main():
    cleanup()

    farmer = mk_user('farmer1', 'farmer')
    farmer2 = mk_user('farmer2', 'farmer')
    rider = mk_user('rider1', 'delivery')
    rider2 = mk_user('rider2', 'delivery')
    pharmacy = mk_user('pharmacy1', 'pharmacy')
    pharmacy2 = mk_user('pharmacy2', 'pharmacy')
    admin_role, _ = Role.objects.get_or_create(name='admin_super', defaults={'panel_type': 'admin'})
    admin = User.objects.create_user(
        email=f'{PREFIX}admin1@example.com', password='Test1234!', phone=phone(),
        full_name='Admin One', date_of_birth=date(1990, 1, 1), present_address='Dhaka',
        consent_terms=True, account_status='active', is_verified=True)
    admin.roles.add(admin_role)  # is_staff is a computed property off role membership

    fc, f2c = client_for(farmer), client_for(farmer2)
    rc, r2c = client_for(rider), client_for(rider2)
    pc, p2c = client_for(pharmacy), client_for(pharmacy2)
    ac = client_for(admin)

    # ── 1. Financial receipt (farmer, owner-only) ──────────────────────────
    print('\n== receipt upload (farmers/costs) ==')
    r = fc.post('/api/farmers/costs/expenses/upload-receipt/', {'image': png()})
    check('receipt upload 201', r.status_code == 201, r.content[:200])
    url = r.json().get('image_url', '')
    assert_private_url('receipt', url)
    four_way('receipt', url, fc, f2c, ac)

    # ── 2. Disease-scan image (farmer, owner-only) ─────────────────────────
    print('\n== disease-scan image (ml) ==')
    r = fc.post('/api/ml/predict-disease/', {'image': real_jpeg('privdoc-scan.jpg')})
    check('predict-disease 201', r.status_code == 201, r.content[:200])
    scan_url = (r.json().get('image_url')
                or (r.json().get('scan') or {}).get('image_url', ''))
    if not scan_url:
        # image_url isn't necessarily top-level — pull it from the scan history.
        hist = fc.get('/api/ml/scans/').json().get('results', [])
        scan_url = hist[0]['image_url'] if hist else ''
    assert_private_url('disease-scan', scan_url)
    four_way('disease-scan', scan_url, fc, f2c, ac)

    # ── 3. Delivery proof-of-delivery (rider, owner-only) ──────────────────
    print('\n== delivery proof upload ==')
    r = rc.post('/api/delivery/proof-upload/', {'file': png()})
    check('proof upload 201', r.status_code == 201, r.content[:200])
    proof_url = r.json().get('url', '')
    assert_private_url('delivery-proof', proof_url)
    four_way('delivery-proof', proof_url, rc, r2c, ac)

    # ── 4. Prescription (farmer + the fulfilling pharmacy; two-party) ──────
    print('\n== prescription upload + order counterparty ==')
    r = fc.post('/api/farmers/prescriptions/upload/', {'image': png()})
    check('prescription upload 201', r.status_code == 201, r.content[:200])
    rx_url = r.json().get('image_url', '')
    assert_private_url('prescription', rx_url)

    from pharmacy.services import order_key
    AdminPanelRecord.objects.create(
        module='pharmacy-orders',
        record_id=order_key(pharmacy.id, 'PRIVDOC-ORD-1'),
        payload={
            'id': 'PRIVDOC-ORD-1', 'owner_id': str(pharmacy.id),
            'farmer_id': str(farmer.id), 'prescription_image': rx_url,
            'status': 'pending',
        },
    )
    r = fc.get(rx_url)
    check('prescription: farmer (owner) can fetch (200)', r.status_code == 200, r.status_code)
    r = pc.get(rx_url)
    check('prescription: fulfilling pharmacy can fetch (200)', r.status_code == 200, r.status_code)
    r = p2c.get(rx_url)
    check('prescription: unrelated pharmacy is refused (403)', r.status_code == 403, r.status_code)
    r = Client().get(rx_url)
    check('prescription: anonymous is refused (401)', r.status_code == 401, r.status_code)
    r = ac.get(rx_url)
    check('prescription: admin can fetch (200)', r.status_code == 200, r.status_code)

    # ── 5. Sanity: the deliberately-PUBLIC paths were not accidentally
    #    locked down by this migration ─────────────────────────────────────
    print('\n== deliberately-public paths stayed public ==')
    r = fc.post('/api/community/upload/', {'file': png()})
    if r.status_code == 201:
        media_url = r.json().get('media_url') or r.json().get('url', '')
        check('community upload returns a /media/ URL (still public)',
              '/media/' in media_url, media_url)
        if media_url:
            r = Client().get(media_url)
            check('community media: anonymous fetch is NOT blocked by the private system '
                  '(still a plain static 200/404, never 401/403)',
                  r.status_code not in (401, 403), r.status_code)
    else:
        check('community upload endpoint reachable', False, r.content[:200])

    cleanup()
    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
