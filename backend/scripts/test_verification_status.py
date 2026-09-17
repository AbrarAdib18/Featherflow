"""Priority 2 — verification-status consistency regression check.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_verification_status.py

Needs a live DB with an active ``admin_super`` account (``manage.py seed_platform_demo``).
Creates throw-away accounts prefixed ``verifytest+``. Idempotent.

Covers the 7 desync bugs documented in FEED_AND_DATA_INTEGRITY_AUDIT.md Priority 2:
doctor approval -> User.is_verified cascade, pharmacy approval via the generic
Users screen -> PharmacyOrganization cascade, pharmacy suspend-via-DELETE
persisting org.is_verified, rider suspend not showing as still-approved,
users-module status-vocabulary validation, the community-badge/professional-
approval desync guard, and the farmer dashboard/profile dead-field fix — plus
the unified `compute_verification_status()` payload for every role/state.
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

from profiles.models import (  # noqa: E402
    DeliveryProfile, DoctorProfile, FarmerProfile, PharmacyOrganization, ResearcherProfile,
)
from users.models import Role, User  # noqa: E402
from verification.status import compute_verification_status  # noqa: E402

PASS = FAIL = 0
PREFIX = 'verifytest+'
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
    DoctorProfile.objects.filter(user__in=users).delete()
    PharmacyOrganization.objects.filter(user__in=users).delete()
    ResearcherProfile.objects.filter(user__in=users).delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_user(role_name, panel_type=None, **extra):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel_type or role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{role_name}{n}@example.com', password='Test1234!',
        phone=f'0192{n:07d}', full_name=f'{role_name.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status=extra.pop('account_status', 'pending'),
        is_verified=extra.pop('is_verified', False))
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def get_admin_client():
    sup = User.objects.filter(roles__name='admin_super', account_status='active').first()
    if not sup:
        return None
    return client_for(sup)


def run():
    print('\n== Priority 2: Verification-status regression ==\n')
    cleanup()
    admin_c = get_admin_client()
    if not admin_c:
        print('  SKIP — no active admin_super account. Run: manage.py seed_platform_demo')
        cleanup()
        sys.exit(0)

    # ── Bug 1: doctor approval cascades to User.is_verified ────────────────
    doctor = mk_user('doctor')
    DoctorProfile.objects.create(
        user=doctor, is_verified=False, is_available=False,
        clinic_hospital_name='Clinic', practice_address='Addr',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'LIC-{doctor.id}', license_issuing_authority='BVC',
        license_expiry_date=date(2030, 1, 1), specialty='Poultry',
        years_of_experience=5, council_registration_proof_url='pending-upload')
    prof = doctor.doctor_profile
    r = admin_c.patch(f'/api/admin-panel/doctors/{prof.id}/', {'status': 'Verified'}, content_type=JSON)
    check('doctor approve -> 200', r.status_code == 200, r.content[:200])
    doctor.refresh_from_db()
    check('doctor approve cascades to User.is_verified (bug 1)', doctor.is_verified is True)

    # ── Bug 2: pharmacy approved via generic Users screen cascades to org ──
    pharmacy = mk_user('pharmacy')
    PharmacyOrganization.objects.create(
        user=pharmacy, business_name='X', is_verified=False,
        authorized_contact_person='Contact', business_registration_number=f'BRN-{pharmacy.id}',
        trade_license_url='pending-upload', tax_vat_tin_number='TIN', business_address='Addr')
    r = admin_c.patch(f'/api/admin-panel/users/{pharmacy.id}/', {'status': 'Approved'}, content_type=JSON)
    check('pharmacy approve via Users screen -> 200', r.status_code == 200, r.content[:200])
    pharmacy.pharmacy_organization.refresh_from_db()
    check('...cascades to PharmacyOrganization.is_verified (bug 2)',
          pharmacy.pharmacy_organization.is_verified is True)

    # ── Bug 3: pharmacy suspend-via-DELETE persists org.is_verified=False ──
    pharmacy2 = mk_user('pharmacy', account_status='active', is_verified=True)
    PharmacyOrganization.objects.create(
        user=pharmacy2, business_name='Y', is_verified=True,
        authorized_contact_person='Contact', business_registration_number=f'BRN-{pharmacy2.id}',
        trade_license_url='pending-upload', tax_vat_tin_number='TIN', business_address='Addr')
    r = admin_c.delete(f'/api/admin-panel/pharmacies/{pharmacy2.id}/')
    check('pharmacy suspend-via-DELETE -> 200/204', r.status_code in (200, 204), r.content[:200])
    pharmacy2.pharmacy_organization.refresh_from_db()
    check('...org.is_verified persisted False (bug 3)',
          pharmacy2.pharmacy_organization.is_verified is False)

    # ── Bug 5: suspended rider no longer reads as "approved" ───────────────
    rider = mk_user('delivery', account_status='active')
    dp = DeliveryProfile.objects.create(
        user=rider, approved_by_admin=None,
        drivers_license_number=f'DL-{rider.id}', license_class='B',
        license_expiry_date=date(2031, 1, 1), license_photo_url='pending-upload')
    r = admin_c.patch(f'/api/admin-panel/riders/{dp.id}/', {'action': 'approve'}, content_type=JSON)
    check('rider approve -> 200', r.status_code == 200, r.content[:200])
    check('...approved badge true', r.json().get('approved') is True, r.content[:200])
    r2 = admin_c.patch(f'/api/admin-panel/riders/{dp.id}/', {'action': 'suspend'}, content_type=JSON)
    check('rider suspend -> 200', r2.status_code == 200, r2.content[:200])
    check('...approved badge now false despite approved_by_admin staying set (bug 5)',
          r2.json().get('approved') is False, r2.content[:200])
    dp.refresh_from_db()
    check('...approval history preserved (approved_by_admin still set)', dp.approved_by_admin_id is not None)

    # ── Bug 6: users-module status vocabulary is validated ─────────────────
    stray = mk_user('farmer', account_status='active')
    r = admin_c.patch(f'/api/admin-panel/users/{stray.id}/', {'status': 'Verified'}, content_type=JSON)
    check('invalid status vocabulary for users module -> 400 (bug 6)', r.status_code == 400, r.content[:200])

    # ── Bug 4: community verified-badge toggle blocked for accounts with a
    #    dedicated professional-approval workflow ───────────────────────────
    doctor2 = mk_user('doctor', account_status='active', is_verified=True)
    DoctorProfile.objects.create(
        user=doctor2, is_verified=True, is_available=True,
        clinic_hospital_name='Clinic', practice_address='Addr',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'LIC-{doctor2.id}', license_issuing_authority='BVC',
        license_expiry_date=date(2030, 1, 1), specialty='Poultry',
        years_of_experience=5, council_registration_proof_url='pending-upload')
    r = admin_c.patch(f'/api/admin-panel/community-users/{doctor2.id}/', {'verified': False}, content_type=JSON)
    check('community-badge toggle blocked for a doctor account (bug 4)', r.status_code == 409, r.content[:200])
    doctor2.refresh_from_db()
    check('...doctor is_verified untouched', doctor2.is_verified is True)

    plain = mk_user('farmer', account_status='active')
    r = admin_c.patch(f'/api/admin-panel/community-users/{plain.id}/', {'verified': True}, content_type=JSON)
    check('community-badge toggle still works for a plain account', r.status_code == 200, r.content[:200])

    # ── Bug 7 / dashboard+profile dead-field fix, via compute_verification_status ──
    farmer = mk_user('farmer', account_status='active')
    FarmerProfile.objects.create(user=farmer, farm_name='F', owner_name='O',
                                 farm_location='L', farm_address='A')
    vs = compute_verification_status(farmer)
    check('farmer professional_approval = not_required', vs['professional_approval']['status'] == 'not_required', vs)
    check('farmer account_active true', vs['account_active'] is True)

    pending_doctor = mk_user('doctor', account_status='pending')
    DoctorProfile.objects.create(
        user=pending_doctor, is_verified=False,
        clinic_hospital_name='Clinic', practice_address='Addr',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'LIC-{pending_doctor.id}', license_issuing_authority='BVC',
        license_expiry_date=date(2030, 1, 1), specialty='Poultry',
        years_of_experience=5, council_registration_proof_url='pending-upload')
    vs2 = compute_verification_status(pending_doctor)
    check('pending doctor professional_approval = pending', vs2['professional_approval']['status'] == 'pending', vs2)

    suspended_researcher = mk_user('researcher', account_status='suspended')
    ResearcherProfile.objects.create(
        user=suspended_researcher, is_verified=False,
        institution_name='Inst', institutional_email=suspended_researcher.email,
        department='Dept', highest_degree='PhD', field_of_study='Avian',
        university_name='BAU', graduation_year=2016, cv_url='pending-upload',
        years_of_research_experience=5)
    vs3 = compute_verification_status(suspended_researcher)
    check('suspended researcher professional_approval = suspended', vs3['professional_approval']['status'] == 'suspended', vs3)

    approved_pharmacy = mk_user('pharmacy', account_status='active')
    PharmacyOrganization.objects.create(
        user=approved_pharmacy, business_name='Z', is_verified=True,
        authorized_contact_person='Contact', business_registration_number=f'BRN-{approved_pharmacy.id}',
        trade_license_url='pending-upload', tax_vat_tin_number='TIN', business_address='Addr')
    vs4 = compute_verification_status(approved_pharmacy)
    check('approved pharmacy professional_approval = approved', vs4['professional_approval']['status'] == 'approved', vs4)
    check('messages are human-readable strings', all(isinstance(m, str) and m for m in vs4['messages']), vs4['messages'])

    # ── farmer profile GET reflects the fix (no longer stuck on "pending") ──
    fc = client_for(farmer)
    r = fc.get('/api/farmers/profile/')
    check('farmer profile GET is_verified reflects active account (bug 7)',
          r.status_code == 200 and r.json().get('is_verified') is True, r.content[:300])
    check('...verification payload included', 'verification' in r.json())

    # ── /api/me/updates/ exposes the unified payload ────────────────────────
    r = fc.get('/api/me/updates/')
    check('/api/me/updates/ includes verification_status', r.status_code == 200 and 'verification_status' in r.json(), r.content[:300])

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
