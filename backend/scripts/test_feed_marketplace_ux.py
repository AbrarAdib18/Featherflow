"""Feed marketplace UX-correction regression suite.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_feed_marketplace_ux.py

Live DB, `feedmktuxtest+` prefixed throw-away accounts. Idempotent.

Covers what's new/changed in this pass (see FEED_MARKETPLACE_UX_AUDIT.md):
product/company image upload + persistence, client (company) creation with
the new district/upazila/description fields, product price snapshot
preservation across a later edit, pagination on products/companies/orders,
image upload validation (rejects a non-image file), and the new demo seed
command's idempotency.
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
from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import AdminPanelRecord  # noqa: E402
from feed_catalogue.models import FeedCompany, FeedProduct  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'feedmktuxtest+'
JSON = 'application/json'

# A minimal valid 1x1 PNG (real magic bytes) for upload tests.
_PNG_BYTES = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108020000009077'
    '53de000000097048597300000ec300000ec301c76fa8640000000c49444154'
    '789c626060606000000500010d0a2db40000000049454e44ae426082')


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
        phone=f'0199{n:07d}', full_name=f'{role_name} {n}',
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
    print('\n== Feed marketplace UX-correction regression ==\n')
    cleanup()

    feed_admin = mk_user('feed_admin', panel_type='admin')
    fac = client_for(feed_admin)
    farmer = mk_user('farmer')
    fc = client_for(farmer)

    # ── Client (company) creation with new fields ────────────────────────
    r = fac.post('/api/admin-panel/feed-catalogue/companies/', {
        'name': f'{PREFIX}Client Co', 'contact_person': 'Test Contact',
        'contact_phone': '01711111111', 'district': 'Dhaka', 'upazila': 'Savar',
        'description': 'A test client.',
    }, content_type=JSON)
    check('feed_admin creates a client with district/upazila/description -> 201',
          r.status_code == 201 and r.json()['district'] == 'Dhaka' and r.json()['description'] == 'A test client.',
          r.content[:300])
    company_id = r.json()['id']

    # ── Company status vocabulary widened to pending/active/suspended/rejected
    r = fac.patch(f'/api/admin-panel/feed-catalogue/companies/{company_id}/',
                 {'status': 'pending'}, content_type=JSON)
    check('company status can be set to "pending" (widened vocabulary) -> 200',
          r.status_code == 200 and r.json()['status'] == 'pending', r.content[:300])
    fac.patch(f'/api/admin-panel/feed-catalogue/companies/{company_id}/',
             {'status': 'active'}, content_type=JSON)

    # ── Company logo/cover image upload + persistence ────────────────────
    r = fac.post(f'/api/admin-panel/feed-catalogue/companies/{company_id}/logo/',
                 {'file': SimpleUploadedFile('logo.png', _PNG_BYTES, content_type='image/png')})
    check('company logo upload -> 201 with a logo_url', r.status_code == 201 and r.json().get('logo_url'), r.content[:300])
    logo_url = r.json().get('logo_url')

    r = fac.get(f'/api/admin-panel/feed-catalogue/companies/{company_id}/')
    check('logo_url persists across a fresh GET', r.json().get('logo_url') == logo_url, r.content[:300])

    r = fac.post(f'/api/admin-panel/feed-catalogue/companies/{company_id}/logo/',
                 {'file': SimpleUploadedFile('logo.txt', b'not a real image', content_type='text/plain')})
    check('uploading a non-image file for the logo is rejected (magic-byte check)',
          r.status_code == 400, r.content[:300])

    # ── Product creation + image upload + persistence ────────────────────
    r = fac.post('/api/admin-panel/feed-catalogue/products/', {
        'company_id': company_id, 'product_name': f'{PREFIX}Product', 'bird_type': 'broiler',
        'feed_type': 'starter', 'price': 1000, 'stock_quantity': 50, 'min_order_quantity': 2,
    }, content_type=JSON)
    check('feed_admin creates a product -> 201 pending_review',
          r.status_code == 201 and r.json()['approval_status'] == 'pending_review', r.content[:300])
    product_id = r.json()['id']

    r = fac.post(f'/api/admin-panel/feed-catalogue/products/{product_id}/image/',
                 {'file': SimpleUploadedFile('product.png', _PNG_BYTES, content_type='image/png')})
    check('product primary image upload -> 201 with an image_url', r.status_code == 201 and r.json().get('image_url'), r.content[:300])
    image_url = r.json().get('image_url')

    r = fac.post(f'/api/admin-panel/feed-catalogue/products/{product_id}/image/',
                 {'file': SimpleUploadedFile('gallery1.png', _PNG_BYTES, content_type='image/png'), 'gallery': '1'})
    check('product gallery image upload -> 201, appended to gallery_urls',
          r.status_code == 201 and len(r.json().get('gallery_urls', [])) == 1, r.content[:300])

    r = fac.get(f'/api/admin-panel/feed-catalogue/products/{product_id}/')
    check('image_url and gallery_urls both persist across a fresh GET',
          r.json().get('image_url') == image_url and len(r.json().get('gallery_urls', [])) == 1, r.content[:300])

    r = fac.post(f'/api/admin-panel/feed-catalogue/products/{product_id}/image/',
                 {'file': SimpleUploadedFile('bad.gif', b'GIF87a not allowed', content_type='image/gif')})
    check('uploading an unsupported file type for a product image is rejected',
          r.status_code == 400, r.content[:300])

    # approve so it can be ordered
    fac.patch(f'/api/admin-panel/feed-catalogue/products/{product_id}/', {'action': 'approve'}, content_type=JSON)

    r = fc.get('/api/farmers/feed-catalogue/products/')
    matched = next((p for p in r.json()['results'] if p['id'] == product_id), None)
    check('farmer sees the product with image_url and company_logo_url',
          matched is not None and matched.get('image_url') == image_url and 'company_logo_url' in matched, matched)

    # ── Product snapshot preservation across a later price edit ──────────
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 2}],
        'delivery_address': 'Snapshot Test Farm', 'payment_method': 'cod',
    }, content_type=JSON)
    check('farmer places an order at the original price -> 201', r.status_code == 201, r.content[:300])
    order_id = r.json()['id']
    original_unit_price = r.json()['items'][0]['unit_price']
    check('order captured the original unit price (1000)', original_unit_price == 1000.0, r.json())

    fac.patch(f'/api/admin-panel/feed-catalogue/products/{product_id}/',
             {'price': 5000}, content_type=JSON)

    r = fc.get(f'/api/farmers/feed-catalogue/orders/{order_id}/')
    check("editing the product's price afterwards does not rewrite the existing order's snapshot",
          r.json()['items'][0]['unit_price'] == original_unit_price, r.json())

    # ── Pagination on products/companies/orders ──────────────────────────
    r = fac.get('/api/admin-panel/feed-catalogue/products/?limit=1&offset=0')
    body = r.json()
    check('products list is paginated (limit respected, total/offset present)',
          len(body['results']) <= 1 and 'total' in body and 'offset' in body, body)

    r = fac.get('/api/admin-panel/feed-catalogue/companies/?limit=1&offset=0')
    body = r.json()
    check('companies list is paginated', len(body['results']) <= 1 and 'total' in body, body)

    r = fac.get('/api/admin-panel/feed-catalogue/orders/?limit=1&offset=0')
    body = r.json()
    check('feed orders list is paginated', len(body['results']) <= 1 and 'total' in body, body)

    r = fc.get('/api/farmers/feed-catalogue/products/?limit=1&offset=0')
    body = r.json()
    check("farmer's own product browse endpoint is paginated too",
          len(body['results']) <= 1 and 'total' in body, body)

    # ── Seed command idempotency ──────────────────────────────────────────
    call_command('seed_feed_marketplace_demo')
    before = FeedProduct.objects.filter(company__name__startswith='Demo ').count()
    call_command('seed_feed_marketplace_demo')
    after = FeedProduct.objects.filter(company__name__startswith='Demo ').count()
    check('re-running seed_feed_marketplace_demo does not create duplicate products',
          before == after and before >= 20, (before, after))
    demo_orders = AdminPanelRecord.objects.filter(module='feed-orders', record_id__startswith='feed:FEEDMKT-').count()
    check('seed command produced at least 6 demo orders', demo_orders >= 6, demo_orders)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
