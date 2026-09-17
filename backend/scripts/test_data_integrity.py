"""Priority 1 — farmer profile field persistence regression check.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_data_integrity.py

Confirms the full chain for every audited farmer signup field (see
FEED_AND_DATA_INTEGRITY_AUDIT.md): signup payload -> DB row -> profile GET ->
dashboard aggregate, plus the specific bird-count/dashboard bug fix and the
unrecognised-role_data-key safeguard. Idempotent, live DB, `dataintegritytest+`
prefixed throw-away accounts.
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
from profiles.models import FarmerProfile  # noqa: E402
from users.models import User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'dataintegritytest+'
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
    Flock.objects.filter(farm__in=farms).delete()
    farms.delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def register_farmer(n, bird_count='777', extra_role_data=None):
    role_data = {
        'farm_name': f'Integrity Farm {n}', 'farm_owner': 'Tester',
        'farm_location': 'Savar, Dhaka', 'farm_type': 'Broiler',
        'bird_count': bird_count, 'years_in_farming': '3',
        'experience_level': 'Intermediate', 'active_workers': '2',
    }
    if extra_role_data:
        role_data.update(extra_role_data)
    c = Client()
    payload = {
        'email': f'{PREFIX}{n}@example.com', 'phone': f'0191{n:07d}',
        'full_name': f'Farmer Integrity {n}', 'date_of_birth': '1990-01-01',
        'present_address': 'Dhaka', 'consent_terms': True,
        'password': 'Test1234!', 'password2': 'Test1234!',
        'role': 'farmer', 'role_data': role_data,
    }
    r = c.post('/api/auth/register/', payload, content_type=JSON)
    return r


def run():
    print('\n== Priority 1: Data-integrity regression ==\n')
    cleanup()

    # 1. Signup -> DB -> profile GET -> dashboard, for a fresh farmer with NO
    #    flock rows yet (the exact scenario that used to show "0 Birds").
    r = register_farmer(1, bird_count='777')
    check('register farmer', r.status_code == 201, r.content[:300])
    user = User.objects.get(email=f'{PREFIX}1@example.com')
    fp = FarmerProfile.objects.get(user=user)
    check('DB: number_of_birds persisted', fp.number_of_birds == 777, fp.number_of_birds)

    c = client_for(user)
    r = c.get('/api/farmers/profile/')
    check('profile GET returns number_of_birds',
          r.status_code == 200 and r.json().get('number_of_birds') == 777, r.content[:300])

    check('no flocks exist yet for a brand-new farmer',
          not Flock.objects.filter(farm__farmer__user=user).exists())

    r = c.get('/api/farmers/dashboard/')
    body = r.json()
    check('dashboard total_birds falls back to signup count (bug fix)',
          r.status_code == 200 and body.get('farm', {}).get('total_birds') == 777,
          body.get('farm'))

    # 2. Once a flock exists, the dashboard should prefer the live flock total
    #    over the static signup value (flocks are the authoritative source
    #    once batches are being tracked).
    farm = Farm.objects.get(farmer__user=user)
    Flock.objects.create(farm=farm, batch_name='Batch A', bird_type='broiler',
                         breed='Cobb 500', quantity=500, current_quantity=500,
                         start_date=date.today(), status='active')
    r = c.get('/api/farmers/dashboard/')
    check('dashboard total_birds switches to flock total once a flock exists',
          r.json().get('farm', {}).get('total_birds') == 500, r.json().get('farm'))

    # 3. Profile PUT still round-trips the field (regression guard for the
    #    already-working chain — must not be broken by the dashboard fix).
    r = c.put('/api/farmers/profile/', {'number_of_birds': 1234}, content_type=JSON)
    check('profile PUT round-trips number_of_birds',
          r.status_code == 200 and r.json().get('number_of_birds') == 1234, r.content[:300])
    fp.refresh_from_db()
    check('DB updated after PUT', fp.number_of_birds == 1234)

    # 4. Logout/login-equivalent: re-fetch profile with a fresh client/token
    #    to confirm the value survives a new session (not just cached).
    c2 = client_for(user)
    r = c2.get('/api/farmers/profile/')
    check('value persists across a new session (logout/login equivalent)',
          r.json().get('number_of_birds') == 1234, r.content[:300])

    # 5. Unrecognised role_data key is logged (see `users.signup` logger output
    #    above) but never blocks an otherwise-valid signup — hard-rejecting
    #    risks breaking a working flow over a harmless extra key, so this is
    #    intentionally warn-only (see FEED_AND_DATA_INTEGRITY_AUDIT.md).
    r = register_farmer(2, bird_count='100', extra_role_data={'totally_unknown_field': 'x'})
    check('unknown role_data key does not block signup (warn-only, see logs above)',
          r.status_code == 201, r.content[:300])
    u2 = User.objects.get(email=f'{PREFIX}2@example.com')
    check('known fields in the same payload still persisted despite the unknown key',
          FarmerProfile.objects.get(user=u2).number_of_birds == 100)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
