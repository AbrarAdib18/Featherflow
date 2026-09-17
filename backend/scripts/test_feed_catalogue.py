"""Priority 5/6 — feed catalogue enforcement + Feed Admin RBAC regression.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_feed_catalogue.py

Live DB, `feedcattest+` prefixed throw-away accounts. Idempotent.

Covers: only admin-approved products can be ordered; server computes
price/total; stock cannot go negative; negative/excessive/unknown/rejected/
suspended/inactive products are all rejected; feed_admin can manage the
catalogue but not unrelated admin modules; farmers cannot reach feed_admin
routes.
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

from audit.models import AdminPanelRecord  # noqa: E402
from feed_catalogue.models import FeedCompany, FeedProduct  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'feedcattest+'
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
    AdminPanelRecord.objects.filter(module='feed-orders', payload__farmer_id__in=[
        str(u.id) for u in users]).delete()
    users.delete()


_n = [0]


def mk_user(role_name):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin' if role_name.startswith(('admin', 'feed_admin')) else role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{role_name}{n}@example.com', password='Test1234!',
        phone=f'0195{n:07d}', full_name=f'{role_name} {n}',
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
    print('\n== Priority 5/6: Feed catalogue + Feed Admin RBAC regression ==\n')
    cleanup()

    feed_admin = mk_user('feed_admin')
    fac = client_for(feed_admin)
    farmer = mk_user('farmer')
    fc = client_for(farmer)

    # ── Feed Admin: create company + product ────────────────────────────
    r = fac.post('/api/admin-panel/feed-catalogue/companies/', {
        'name': f'{PREFIX}Nourish Feeds', 'contact_phone': '01700000000',
    }, content_type=JSON)
    check('feed_admin creates company -> 201', r.status_code == 201, r.content[:300])
    company_id = r.json()['id']

    r = fac.post('/api/admin-panel/feed-catalogue/products/', {
        'company_id': company_id, 'product_name': 'Starter Crumble', 'brand': 'Nourish',
        'feed_type': 'starter', 'bird_type': 'broiler', 'unit': 'bag_25kg',
        'price': 1500, 'stock_quantity': 100, 'min_order_quantity': 1,
    }, content_type=JSON)
    check('feed_admin creates product -> 201 (pending_review)',
          r.status_code == 201 and r.json()['approval_status'] == 'pending_review', r.content[:300])
    product_id = r.json()['id']

    # Not yet approved -> invisible to farmers.
    r = fc.get('/api/farmers/feed-catalogue/products/')
    check('unapproved product not visible to farmers', all(p['id'] != product_id for p in r.json()['results']))

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 2}], 'delivery_address': 'Farm Rd 1',
    }, content_type=JSON)
    check('ordering a pending_review product is rejected', r.status_code == 409, r.content[:300])

    # Approve it.
    r = fac.patch(f'/api/admin-panel/feed-catalogue/products/{product_id}/', {'action': 'approve'}, content_type=JSON)
    check('feed_admin approves product -> 200 approved',
          r.status_code == 200 and r.json()['approval_status'] == 'approved', r.content[:300])

    # ── Farmer: browse + order ───────────────────────────────────────────
    r = fc.get('/api/farmers/feed-catalogue/products/')
    check('approved product now visible', any(p['id'] == product_id for p in r.json()['results']))

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 3}],
        'delivery_address': 'Farm Rd 1', 'payment_method': 'cod',
    }, content_type=JSON)
    check('valid order -> 201', r.status_code == 201, r.content[:300])
    order = r.json()
    check('server-computed unit price (client sent nothing) matches catalogue price',
          order['items'][0]['unit_price'] == 1500.0, order)
    check('server-computed subtotal = 3 * 1500', order['subtotal'] == 4500.0, order)
    product = FeedProduct.objects.get(pk=product_id)
    check('stock decremented by ordered quantity', product.stock_quantity == 97, product.stock_quantity)

    # ── Negative paths ───────────────────────────────────────────────────
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': '00000000-0000-0000-0000-000000000000', 'quantity': 1}],
        'delivery_address': 'X',
    }, content_type=JSON)
    check('unknown product id rejected', r.status_code == 409, r.content[:200])

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': -5}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('negative quantity rejected', r.status_code == 409, r.content[:200])

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 999999}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('excessive quantity (exceeds stock) rejected', r.status_code == 409, r.content[:200])

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 1, 'unit_price': 1}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('client-supplied altered unit_price is ignored, not trusted',
          r.status_code == 201 and r.json()['items'][0]['unit_price'] == 1500.0, r.content[:300])

    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'free_text_name': 'Some Random Feed', 'quantity': 1}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('arbitrary free-text product (no product_id) is rejected', r.status_code == 409, r.content[:200])

    # Reject a second product; suspend it; both must stay unorderable.
    r = fac.post('/api/admin-panel/feed-catalogue/products/', {
        'company_id': company_id, 'product_name': 'Bad Batch', 'price': 500, 'stock_quantity': 10,
    }, content_type=JSON)
    rejected_id = r.json()['id']
    r = fac.patch(f'/api/admin-panel/feed-catalogue/products/{rejected_id}/',
                 {'action': 'reject', 'reason': 'Failed quality check'}, content_type=JSON)
    check('feed_admin rejects a product with a reason -> 200', r.status_code == 200, r.content[:300])
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': rejected_id, 'quantity': 1}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('rejected product cannot be ordered', r.status_code == 409, r.content[:200])

    r = fac.patch(f'/api/admin-panel/feed-catalogue/products/{product_id}/', {'action': 'suspend'}, content_type=JSON)
    check('feed_admin suspends a previously-approved product', r.status_code == 200, r.content[:300])
    r = fc.post('/api/farmers/feed-catalogue/orders/', {
        'items': [{'product_id': product_id, 'quantity': 1}], 'delivery_address': 'X',
    }, content_type=JSON)
    check('suspended product cannot be ordered', r.status_code == 409, r.content[:200])

    # ── RBAC isolation ───────────────────────────────────────────────────
    r = fc.get('/api/admin-panel/feed-catalogue/companies/')
    check('farmer cannot reach feed_admin admin routes', r.status_code in (401, 403), r.status_code)

    r = fac.get('/api/admin-panel/users/')
    check('feed_admin cannot reach unrelated admin modules (users)', r.status_code in (401, 403), r.status_code)
    r = fac.patch('/api/admin-panel/pharmacies/00000000-0000-0000-0000-000000000000/',
                 {'status': 'Verified'}, content_type=JSON)
    check('feed_admin cannot reach unrelated admin modules (pharmacies)', r.status_code == 403, r.status_code)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
