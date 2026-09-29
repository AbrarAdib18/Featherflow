"""Find Vet discovery regression suite — the gap that let the "farmer sees no
doctors" bug ship unnoticed.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_find_vet_discovery.py

There was no test asserting that an eligible doctor is actually *discoverable*
by a farmer, so when a shared admin suite de-verified the seeded demo doctor
(see FIND_VET_DISCOVERY_FIX.md) every consultation suite kept passing — they
each build their own doctor — while the real farmer-facing Find Vet list went
silently empty.

Live DB, `findvettest+`-prefixed throw-away accounts. Idempotent.
"""
import hashlib
import os
import sys
from datetime import date, time, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from doctor.models import AvailabilitySlot  # noqa: E402
from farms.models import Farm  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'findvettest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    ids = list(User.objects.filter(email__startswith=PREFIX).values_list('id', flat=True))
    AvailabilitySlot.objects.filter(doctor_id__in=ids).delete()
    Farm.objects.filter(farmer__user_id__in=ids).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    User.objects.filter(id__in=ids).delete()


def _user(tag, role_name, account_status='active'):
    email = f'{PREFIX}{tag}@example.com'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    u, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'FindVet {tag.title()}', phone=phone, date_of_birth=date(1988, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status=account_status,
        is_verified=True))
    u.set_password('Test1234!')
    u.account_status = account_status
    u.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': None})
    u.roles.add(role)
    return u


def _doctor(tag, *, is_verified, account_status='active', name=None,
            specialty='Avian Medicine', mode='both', fee='900.00', with_availability=True):
    u = _user(tag, 'doctor', account_status=account_status)
    if name:
        u.full_name = name
        u.save(update_fields=['full_name'])
    p, _ = DoctorProfile.objects.update_or_create(user=u, defaults=dict(
        clinic_hospital_name=f'{tag} Clinic', practice_address='Dhaka',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'FV-{u.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=900),
        specialty=specialty, years_of_experience=7, consultation_mode=mode,
        council_registration_proof_url='x', service_fee=Decimal(fee),
        consent_platform_guidelines=True, is_verified=is_verified,
        is_available=True, availability_status='available'))
    if with_availability:
        # Availability on a FUTURE weekday only — deliberately not "right now".
        AvailabilitySlot.objects.get_or_create(
            doctor=u, weekday=(date.today().weekday() + 2) % 7,
            start_time=time(9, 0), end_time=time(17, 0), mode='online')
    return p


def auth(c, u):
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(u).access_token}'


def names(resp):
    return [d['name'] for d in resp.json().get('doctors', [])]


def main():
    cleanup()

    eligible = _doctor('eligible', is_verified=True, name='Dr Findable Eligible')
    _doctor('unverified', is_verified=False, name='Dr Unverified Hidden')
    _doctor('suspended', is_verified=True, account_status='suspended', name='Dr Suspended Hidden')
    _doctor('cheap', is_verified=True, name='Dr Cheap Online', mode='online',
            specialty='Nutrition', fee='200.00')

    farmer = _user('farmer', 'farmer')
    c = Client()
    auth(c, farmer)

    print('\n== eligibility: who is discoverable ==')
    r = c.get('/api/consultations/vets/')
    check('farmer can call Find Vet (200)', r.status_code == 200, r.content[:200])
    listed = names(r)
    check('an eligible verified+active doctor IS listed',
          'Dr Findable Eligible' in listed, listed)
    check('an UNVERIFIED doctor is NOT listed',
          'Dr Unverified Hidden' not in listed, listed)
    check('a SUSPENDED doctor is NOT listed',
          'Dr Suspended Hidden' not in listed, listed)
    check('the default list is non-empty when eligible doctors exist',
          len(listed) >= 2, listed)

    print('\n== the actual regression: future-only availability still lists ==')
    # The eligible doctor's only availability is a future weekday, never "now".
    check('a doctor with only FUTURE availability still appears by default '
          '(default list must not require a slot at this exact minute)',
          'Dr Findable Eligible' in names(c.get('/api/consultations/vets/')))

    print('\n== search ==')
    check('search by name finds the doctor',
          'Dr Findable Eligible' in names(c.get('/api/consultations/vets/?search=Findable')))
    check('search is case-insensitive',
          'Dr Findable Eligible' in names(c.get('/api/consultations/vets/?search=findable')))
    check('search by specialty works',
          'Dr Cheap Online' in names(c.get('/api/consultations/vets/?search=Nutrition')))
    check('a non-matching search returns an empty list, not an error',
          names(c.get('/api/consultations/vets/?search=zzzznomatchzzz')) == [])

    print('\n== filters, independently and combined ==')
    check('mode=online includes an online-only doctor',
          'Dr Cheap Online' in names(c.get('/api/consultations/vets/?mode=online')))
    check('mode=offline excludes the online-only doctor',
          'Dr Cheap Online' not in names(c.get('/api/consultations/vets/?mode=offline')))
    check('max_fee excludes the pricier doctor',
          'Dr Findable Eligible' not in names(c.get('/api/consultations/vets/?max_fee=300')))
    check('max_fee keeps the cheaper doctor',
          'Dr Cheap Online' in names(c.get('/api/consultations/vets/?max_fee=300')))
    check('specialty filter narrows correctly',
          'Dr Cheap Online' in names(c.get('/api/consultations/vets/?specialty=Nutrition'))
          and 'Dr Findable Eligible' not in names(c.get('/api/consultations/vets/?specialty=Nutrition')))
    combined = names(c.get('/api/consultations/vets/?mode=online&max_fee=300&search=Cheap'))
    check('combined filters still return the matching doctor', 'Dr Cheap Online' in combined, combined)
    check('empty filter values do not change the result',
          names(c.get('/api/consultations/vets/?search=&specialty=&mode=')) == names(c.get('/api/consultations/vets/')))

    print('\n== doctor card / detail payload ==')
    r = c.get('/api/consultations/vets/')
    card = next(d for d in r.json()['doctors'] if d['name'] == 'Dr Findable Eligible')
    for field in ('id', 'name', 'specialty', 'fee', 'mode', 'rating', 'verified', 'available'):
        check(f'card exposes "{field}"', field in card, sorted(card))
    for leaked in ('license_number', 'council_registration_proof_url', 'cv_url', 'email'):
        check(f'card does NOT leak "{leaked}"', leaked not in card)

    r = c.get(f'/api/consultations/vets/{eligible.id}/')
    check('vet detail 200', r.status_code == 200, r.content[:160])
    detail = r.json()
    check('detail includes availability_slots', 'availability_slots' in detail, sorted(detail)[:15])
    for leaked in ('license_number', 'council_registration_proof_url', 'cv_url'):
        check(f'detail does NOT leak "{leaked}"', leaked not in detail)

    print('\n== seeded demo data is actually usable (guards the real regression) ==')
    # The suites above each build their own doctor, so they stayed green while
    # the *seeded* demo doctor was silently de-verified and the real Find Vet
    # screen went empty. This check is the one that would have caught it.
    demo = DoctorProfile.objects.select_related('user').filter(
        user__email='dr.samira.rahman@example.com').first()
    if demo is None:
        print('  --   seeded demo doctor absent (run: manage.py seed_platform_demo) — skipped')
    else:
        demo_farmer = User.objects.filter(email='farmer.rashed@example.com').first()
        if demo_farmer is None:
            print('  --   seeded demo farmer absent — skipped')
        else:
            dc = Client()
            auth(dc, demo_farmer)
            demo_names = names(dc.get('/api/consultations/vets/'))
            check('the seeded demo doctor is discoverable by the seeded demo farmer '
                  '(this is what silently broke: another suite de-verified her)',
                  demo.user.full_name in demo_names, demo_names)
            check('seeded demo doctor is verified + active',
                  demo.is_verified and demo.user.account_status == 'active',
                  (demo.is_verified, demo.user.account_status))

    print('\n== access control ==')
    check('an unauthenticated caller is refused (401/403)',
          Client().get('/api/consultations/vets/').status_code in (401, 403))
    doc_client = Client()
    auth(doc_client, eligible.user)
    check('a non-farmer role is refused the farmer discovery feed (403)',
          doc_client.get('/api/consultations/vets/').status_code == 403,
          doc_client.get('/api/consultations/vets/').status_code)

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
