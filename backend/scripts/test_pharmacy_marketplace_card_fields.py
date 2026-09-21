"""Pharmacy marketplace product-card fields — previous_price, min_order_quantity,
is_top_seller.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_marketplace_card_fields.py

Live DB, `pharmcard+` prefixed throw-away accounts. Idempotent.

Covers: previous_price is only meaningful (and only ever set) when higher
than price, min_order_quantity is validated and actually enforced when a
farmer places an order (not just displayed), and is_top_seller is a derived
read-only signal based on real orders_count, not something a client can set.
"""
import os
import sys
from datetime import date, timedelta

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

from pharmacy.models import PharmacyMedicine  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'pharmcard+'
JSON = 'application/json'
_n = [0]


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
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0196{n:07d}', full_name=f'{tag.title()} {n}',
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
    print('\n== Pharmacy marketplace card fields ==\n')
    cleanup()

    pharmacy = mk_user('pharmacy', 'pharm')
    farmer = mk_user('farmer', 'farmer')
    pc = client_for(pharmacy)
    fc = client_for(farmer)

    # 1. previous_price is optional and only renders as a discount when
    #    actually higher than price — verified here at the serialization
    #    level; the Flutter card only draws the strikethrough when this holds.
    r = pc.post('/api/pharmacy/medicines/', {
        'name': 'Discounted Vitamin Mix', 'category': 'vitamin', 'unit': 'bottle',
        'price': 150, 'previous_price': 200, 'stock_quantity': 20, 'min_order_quantity': 2,
        'expiry_date': (date.today() + timedelta(days=365)).isoformat(),
    }, content_type=JSON)
    check('create with previous_price + min_order_quantity -> 201', r.status_code == 201, r.content[:300])
    med = r.json()
    check('previous_price round-trips', med['previous_price'] == 200.0, med)
    check('min_order_quantity round-trips', med['min_order_quantity'] == 2, med)
    check('is_top_seller is false for a brand-new medicine', med['is_top_seller'] is False, med)
    medicine_id = med['id']

    # 2. Rejections.
    r_neg = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', {'previous_price': -5}, content_type=JSON)
    check('negative previous_price is rejected', r_neg.status_code == 400, r_neg.content[:300])
    r_zero_moq = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', {'min_order_quantity': 0}, content_type=JSON)
    check('min_order_quantity below 1 is rejected', r_zero_moq.status_code == 400, r_zero_moq.content[:300])
    r_null_prev = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', {'previous_price': None}, content_type=JSON)
    check('previous_price can be cleared back to null', r_null_prev.status_code == 200 and r_null_prev.json()['previous_price'] is None,
          r_null_prev.content[:300])

    # 3. Farmer sees the same fields (marketplace card needs them too).
    r_search = fc.get('/api/farmers/medicines/search/', {'query': 'Discounted Vitamin Mix'})
    hit = next((m for m in r_search.json()['results'] if m['id'] == medicine_id), None)
    check('farmer search result includes min_order_quantity', hit is not None and hit['min_order_quantity'] == 2, hit)
    check('farmer search result includes is_top_seller', hit is not None and 'is_top_seller' in hit, hit)

    # 4. min_order_quantity is actually enforced when ordering, not just shown.
    r_under = fc.post('/api/farmers/orders/', {
        'pharmacy_id': str(pharmacy.id),
        'items': [{'medicine_id': medicine_id, 'quantity': 1}],
        'delivery_method': 'pickup', 'payment_method': 'cod',
    }, content_type=JSON)
    check('ordering below min_order_quantity is rejected', r_under.status_code == 409, r_under.content[:300])

    r_ok = fc.post('/api/farmers/orders/', {
        'pharmacy_id': str(pharmacy.id),
        'items': [{'medicine_id': medicine_id, 'quantity': 2}],
        'delivery_method': 'pickup', 'payment_method': 'cod',
    }, content_type=JSON)
    check('ordering at exactly min_order_quantity succeeds', r_ok.status_code == 201, r_ok.content[:300])

    # 5. is_top_seller becomes true once orders_count crosses the threshold —
    #    a real derived signal, not a client-settable flag.
    from pharmacy.models import TOP_SELLER_ORDERS_THRESHOLD
    PharmacyMedicine.objects.filter(pk=medicine_id).update(orders_count=TOP_SELLER_ORDERS_THRESHOLD)
    r_detail = pc.get(f'/api/pharmacy/medicines/{medicine_id}/')
    check('is_top_seller flips on once orders_count crosses the threshold',
          r_detail.json()['is_top_seller'] is True, r_detail.json())
    r_client_set = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', {'is_top_seller': False}, content_type=JSON)
    check("a client can't override is_top_seller directly (ignored, still derived)",
          r_client_set.status_code == 200 and r_client_set.json()['is_top_seller'] is True, r_client_set.json())

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
