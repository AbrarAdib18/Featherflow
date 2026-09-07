"""Checks for GET /api/vets/nearby/ (farmer vet-map "find nearby vets").

Run:  backend/venv/Scripts/python.exe backend/scripts/test_vets_nearby.py

Uses Django's test Client against the live configured DB. Creates throw-away
accounts prefixed ``vetneartest+`` and cleans its own rows. Idempotent.
"""
import os
import sys
from datetime import date, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')

from django.test import Client
from rest_framework_simplejwt.tokens import RefreshToken
from profiles.models import DoctorProfile, FarmerProfile
from users.models import Role, User

PREFIX = 'vetneartest+'


def mk(handle, role):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    u, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'VN {handle}', phone=phone, date_of_birth=date(1988, 3, 3),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    u.account_status = 'active'; u.set_password('Testpass!2026'); u.save()
    r, _ = Role.objects.get_or_create(name=role, defaults={'panel_type': role})
    u.roles.clear(); u.roles.add(r)
    return u


def cleanup(users):
    ids = [u.id for u in users]
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()


farmer = mk('farmer', 'farmer')
near = mk('near', 'doctor')
far = mk('far', 'doctor')
cleanup([farmer, near, far])

# Farmer at Dhaka 23.8103, 90.4125
common = dict(veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
             license_issuing_authority='BVC', license_expiry_date=date.today() + timedelta(days=800),
             specialty='Poultry medicine', years_of_experience=8, consultation_mode='both',
             council_registration_proof_url='x', consent_platform_guidelines=True,
             is_verified=True, is_available=True, availability_status='available')
DoctorProfile.objects.create(user=near, clinic_hospital_name='Near Clinic',
    practice_address='Banani, Dhaka', latitude=Decimal('23.7940'), longitude=Decimal('90.4043'),
    license_number=f'VN-{near.id.hex[:8]}', service_fee=Decimal('1500'), rating=Decimal('4.30'), **common)
DoctorProfile.objects.create(user=far, clinic_hospital_name='Far Clinic',
    practice_address='Chittagong', latitude=Decimal('22.3569'), longitude=Decimal('91.7832'),
    license_number=f'VF-{far.id.hex[:8]}', service_fee=Decimal('1200'), rating=Decimal('0'), **common)

c = Client()
c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(farmer).access_token}'

ok = 0; fail = 0
def check(name, cond, extra=''):
    global ok, fail
    if cond: ok += 1; print(f'  ok   {name}')
    else: fail += 1; print(f'  FAIL {name}  {extra}')

r = c.get('/api/vets/nearby/', {'lat': '23.8103', 'lng': '90.4125', 'radius': '50'})
check('200', r.status_code == 200, r.content[:300])
j = r.json()
names = [v['clinic_name'] for v in j['vets']]
check('near clinic in radius', 'Near Clinic' in names, names)
check('far clinic excluded (>50km)', 'Far Clinic' not in names, names)
nearrow = next((v for v in j['vets'] if v['clinic_name'] == 'Near Clinic'), None)
check('fields present', nearrow and all(k in nearrow for k in
    ('name', 'clinic_name', 'address', 'latitude', 'longitude', 'phone', 'rating', 'distance_km')), nearrow)
check('phone populated', nearrow and nearrow['phone'], nearrow)
check('rating populated', nearrow and nearrow['rating'] == 4.3, nearrow)
check('distance ~2-3km', nearrow and nearrow['distance_km'] < 5, nearrow)

r = c.get('/api/vets/nearby/', {'lat': '23.8103', 'lng': '90.4125', 'radius': '600'})
check('big radius includes far clinic', 'Far Clinic' in [v['clinic_name'] for v in r.json()['vets']], r.content[:200])
check('sorted by distance', [v['distance_km'] for v in r.json()['vets']] ==
      sorted(v['distance_km'] for v in r.json()['vets']))

r = c.get('/api/vets/nearby/', {'lat': 'abc', 'lng': '90'})
check('bad coords -> 400', r.status_code == 400, r.content[:200])

r = c.get('/api/vets/nearby/', {'lat': '1.0', 'lng': '1.0'})
check('empty result ok', r.status_code == 200 and r.json()['vets'] == [], r.content[:200])

r = c.get('/api/consultations/vets/nearby/', {'lat': '23.8103', 'lng': '90.4125'})
check('consultations alias works', r.status_code == 200 and 'vets' in r.json(), r.content[:200])

cleanup([farmer, near, far])
print(f'\n{ok} passed, {fail} failed')
sys.exit(1 if fail else 0)
