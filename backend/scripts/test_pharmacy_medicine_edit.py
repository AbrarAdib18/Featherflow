"""Pharmacy medicine full-field edit — regression for a real 500 found via
live browser testing (Playwright), not caught by any prior automated test.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_medicine_edit.py

Live DB, `pharmedit+` prefixed throw-away accounts. Idempotent.

Root cause: the Flutter Add/Edit Medicine dialog's "Save" button always PATCHes
every field, including `expiry_date` — unlike every previous automated test of
this endpoint, which only ever PATCHed a subset (e.g. `{'price': 260}` or
`{'images': [...]}`). `clean_medicine_payload` parses `expiry_date` into a real
`datetime.date` object, and `medicine_detail`'s PATCH handler used to hand that
raw `cleaned` dict straight to `log_action` -> `ActivityLog.objects.create(...,
new_values=cleaned)`. psycopg2's own JSON adapter for that column calls plain
`json.dumps` under the hood regardless of the JSONField's `encoder=` kwarg (that
only covers Django's own serialization path, not psycopg2's), so saving a raw
`date` 500'd with "Object of type date is not JSON serializable" on every
single medicine edit that touched every field at once - i.e. every real save
from the actual UI, every time.
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

from audit.models import ActivityLog  # noqa: E402
from pharmacy.models import PharmacyMedicine  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'pharmedit+'
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
    # activity_logs is append-only (a DB trigger rejects DELETE/UPDATE on it —
    # see ActivityLog's docstring), so test-run rows are left in place; the
    # FK is on_delete=SET_NULL, so deleting the throwaway user is still fine.
    users = User.objects.filter(email__startswith=PREFIX)
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0195{n:07d}', full_name=f'{tag.title()} {n}',
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
    print('\n== Pharmacy medicine full-field edit (Save button) ==\n')
    cleanup()

    pharmacy = mk_user('pharmacy', 'pharm')
    pc = client_for(pharmacy)

    r = pc.post('/api/pharmacy/medicines/', {
        'name': 'Edit Regression Medicine', 'category': 'antibiotic', 'unit': 'bottle',
        'price': 50, 'stock_quantity': 10,
        'expiry_date': (date.today() + timedelta(days=365)).isoformat(),
    }, content_type=JSON)
    check('create medicine -> 201', r.status_code == 201, r.content[:300])
    medicine_id = r.json()['id']

    # This is exactly the payload shape AddMedicineDialog._fieldPayload sends
    # on every "Save" click in edit mode — every field, always, including
    # expiry_date as a plain 'YYYY-MM-DD' string.
    full_payload = {
        'name': 'Edit Regression Medicine', 'generic_name': '', 'manufacturer': '',
        'category': 'antibiotic', 'unit': 'bottle', 'price': 65, 'stock_quantity': 12,
        'pack_size': '', 'batch_number': '', 'description': '', 'dosage_instructions': '',
        'storage_instructions': '', 'prescription_required': False, 'cold_chain_required': False,
        'expiry_date': (date.today() + timedelta(days=400)).isoformat(),
    }
    r_edit = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', full_payload, content_type=JSON)
    check('full-field edit (the real Save button payload) -> 200, not 500',
          r_edit.status_code == 200, r_edit.content[:500])
    if r_edit.status_code == 200:
        check('price actually updated', r_edit.json()['price'] == 65.0, r_edit.json())
        check('stock actually updated', r_edit.json()['stock_quantity'] == 12, r_edit.json())

    # A second edit, changing the expiry date again, must also succeed
    # (exactly-once isn't the concern here — repeatability of the same code
    # path is).
    full_payload['expiry_date'] = (date.today() + timedelta(days=500)).isoformat()
    full_payload['price'] = 70
    r_edit2 = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', full_payload, content_type=JSON)
    check('a second full-field edit also succeeds', r_edit2.status_code == 200, r_edit2.content[:500])

    # The activity log entry itself must be readable back (proves the JSON
    # round-tripped through storage correctly, not just that the response
    # didn't crash).
    log = ActivityLog.objects.filter(user=pharmacy, action='Update medicine').order_by('-created_at').first()
    check('an ActivityLog row was actually written', log is not None)
    if log is not None:
        check('the logged new_values are readable and JSON-safe',
              isinstance(log.new_values, dict) and log.new_values.get('price') == 70.0,
              log.new_values)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
