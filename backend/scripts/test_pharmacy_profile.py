"""Pharmacy full profile (GET/PATCH /api/pharmacy/profile/) — every field
collected at pharmacy signup should be visible and editable afterward, not
just the small subset the dashboard/order views use.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_profile.py

Live DB, `pharmprof+` prefixed throw-away accounts. Idempotent.
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

from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'pharmprof+'
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
    User.objects.filter(email__startswith=PREFIX).delete()


def mk_user(role_name, tag, **profile):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0194{n:07d}', full_name=f'{tag.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    if profile:
        u.profile_data = profile
        u.save()
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Pharmacy full profile (signup fields, GET+PATCH) ==\n')
    cleanup()

    # Seed with a realistic slice of what the signup form actually collects.
    pharmacy = mk_user('pharmacy', 'pharm',
                        business_name='Test Pharmacy Ltd.',
                        contact_person='Karim Uddin',
                        business_reg_number='BRN-1001',
                        trade_license_number='TL-2002',
                        tax_number='TAX-3003',
                        business_address='House 12, Road 5, Dhanmondi',
                        warehouse_address='Warehouse 9, Tejgaon',
                        number_of_pharmacists='3',
                        responsible_pharmacist='Dr. Nasima Begum',
                        pharmacy_license_number='PL-4004',
                        council_registration='CR-5005',
                        permitted_products='Antibiotics, Vaccines, Vitamins',
                        storage_requirements='Cold chain 2-8C for vaccines',
                        delivery_coverage='Dhaka Metro',
                        returns_policy='7-day return on unopened stock',
                        bank_account='1234567890',
                        signatory='Karim Uddin',
                        license_expiry='2028-01-01',
                        trade_license='http://example.com/tl.pdf')
    pc = client_for(pharmacy)

    # 1. GET returns every signup field, not just the dashboard's subset.
    r_get = pc.get('/api/pharmacy/profile/')
    check('GET profile -> 200', r_get.status_code == 200, r_get.content[:300])
    body = r_get.json()
    for field in ['business_name', 'contact_person', 'business_reg_number', 'trade_license_number',
                  'tax_number', 'business_address', 'warehouse_address', 'number_of_pharmacists',
                  'responsible_pharmacist', 'pharmacy_license_number', 'council_registration',
                  'permitted_products', 'storage_requirements', 'delivery_coverage', 'returns_policy',
                  'bank_account', 'signatory', 'license_expiry', 'trade_license']:
        check(f'GET includes {field}', field in body and body[field] != '', {field: body.get(field)})
    check('GET includes account fields too (full_name/phone/email)',
          body.get('full_name') and body.get('phone') and body.get('email'), body)

    # 2. PATCH updates a subset of fields and preserves the rest.
    r_patch = pc.patch('/api/pharmacy/profile/', {
        'business_address': 'New Address, Gulshan',
        'delivery_coverage': 'Dhaka + Narayanganj',
        'phone': '01999888777',
    }, content_type=JSON)
    check('PATCH -> 200', r_patch.status_code == 200, r_patch.content[:300])
    patched = r_patch.json()
    check('business_address updated', patched.get('business_address') == 'New Address, Gulshan', patched)
    check('delivery_coverage updated', patched.get('delivery_coverage') == 'Dhaka + Narayanganj', patched)
    check('phone updated', patched.get('phone') == '01999888777', patched)
    check('untouched field (bank_account) preserved', patched.get('bank_account') == '1234567890', patched)
    check('untouched field (business_name) preserved', patched.get('business_name') == 'Test Pharmacy Ltd.', patched)

    # 3. Re-GET confirms the PATCH actually persisted, not just echoed.
    r_get2 = pc.get('/api/pharmacy/profile/')
    check('re-GET reflects the PATCH', r_get2.json().get('business_address') == 'New Address, Gulshan',
          r_get2.json())

    # 4. Validation: empty full_name/phone rejected; bad expiry date rejected.
    r_bad_name = pc.patch('/api/pharmacy/profile/', {'full_name': '  '}, content_type=JSON)
    check('empty full_name is rejected', r_bad_name.status_code == 400, r_bad_name.content[:300])
    r_bad_date = pc.patch('/api/pharmacy/profile/', {'license_expiry': 'not-a-date'}, content_type=JSON)
    check('invalid license_expiry is rejected', r_bad_date.status_code == 400, r_bad_date.content[:300])

    # 5. Authorization — a farmer cannot read/edit a pharmacy's profile.
    farmer = mk_user('farmer', 'farmer')
    fc = client_for(farmer)
    r_farmer_get = fc.get('/api/pharmacy/profile/')
    check('a farmer cannot GET the pharmacy profile endpoint (403/401)',
          r_farmer_get.status_code in (401, 403), r_farmer_get.content[:300])

    # 6. It's actually THIS pharmacy's own data — a second pharmacy sees only
    #    its own (empty) profile, never the first one's.
    other_pharmacy = mk_user('pharmacy', 'otherpharm')
    opc = client_for(other_pharmacy)
    r_other = opc.get('/api/pharmacy/profile/')
    check("a different pharmacy's profile GET returns its own (empty) data, not the first pharmacy's",
          r_other.json().get('business_name', '') == '', r_other.json())

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
