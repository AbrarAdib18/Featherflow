"""Operations Admin dashboard metrics regression suite — see
OPERATIONS_ADMIN_DASHBOARD_AUDIT.md.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_admin_dashboard_metrics.py

Live DB, `admindashtest+` prefixed throw-away accounts. Idempotent.

This endpoint (`GET /api/admin-panel/dashboard/`) had zero test coverage
before this pass. Centerpiece: `active_users` used to be `User.objects.count()`
— every row regardless of status — mislabeled "Active Users" in the UI. Since
this dev database already has many pre-existing rows from other seed/test
scripts, every assertion here is a before/after DELTA over a controlled set
of newly-created accounts, not an absolute count.
"""
import os
import sys
from datetime import date, datetime

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from profiles.models import AdminProfile, DeliveryProfile, DoctorProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'admindashtest+'
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
    DeliveryProfile.objects.filter(user__in=users).delete()
    AdminProfile.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_user(role_name, account_status='active', **extra):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{role_name}{n}@example.com', password='Test1234!',
        phone=f'0196{n:07d}', full_name=f'{role_name.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status=account_status, is_verified=extra.get('is_verified', True))
    u.roles.add(role)
    return u


def ensure_ops_admin():
    role, _ = Role.objects.get_or_create(name='admin_operations', defaults={'panel_type': 'admin'})
    user, _ = User.objects.get_or_create(
        email=f'{PREFIX}ops@example.com', defaults=dict(
            full_name='Ops Tester', phone='+8801999900001',
            date_of_birth=date(1990, 1, 1), present_address='Dhaka',
            consent_terms=True, account_status='active'))
    user.set_password('Test1234!')
    user.account_status = 'active'
    user.save()
    user.roles.clear()
    user.roles.add(role)
    AdminProfile.objects.update_or_create(user=user, defaults=dict(
        admin_role=role, job_title='Ops Tester', department='Operations',
        start_date=date(2024, 1, 1), admin_sub_role='operations',
        approval_status='approved', is_active=True, is_suspended=False,
        internal_approval_by_founder_hr=True))
    return user


def auth(client, user):
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'


def main():
    cleanup()
    ops = ensure_ops_admin()
    c = Client()
    auth(c, ops)

    print('\n== RBAC: only admin accounts may read the dashboard ==')
    farmer = mk_user('farmer')
    fc = Client()
    auth(fc, farmer)
    r = fc.get('/api/admin-panel/dashboard/')
    check("a non-admin role is refused (403)", r.status_code == 403, r.status_code)
    r = Client().get('/api/admin-panel/dashboard/')
    check('an anonymous request is refused (401/403)', r.status_code in (401, 403), r.status_code)

    print('\n== baseline read ==')
    r = c.get('/api/admin-panel/dashboard/')
    check('ops admin can read the dashboard (200)', r.status_code == 200, r.content[:200])
    before = r.json()['stats']
    check("'generated_at' is present and parseable", bool(
        datetime.fromisoformat(r.json()['generated_at'].replace('Z', '+00:00'))))

    print('\n== active_users / pending_users / suspended_users are correctly '
          'defined (delta over known-status accounts) ==')
    active_users = [mk_user('farmer', account_status='active') for _ in range(3)]
    pending_users = [mk_user('farmer', account_status='pending') for _ in range(2)]
    suspended_users = [mk_user('farmer', account_status='suspended') for _ in range(1)]

    r = c.get('/api/admin-panel/dashboard/')
    after = r.json()['stats']
    check('active_users increased by exactly 3',
          after['active_users'] - before['active_users'] == 3,
          (before['active_users'], after['active_users']))
    check('pending_users increased by exactly 2',
          after['pending_users'] - before['pending_users'] == 2,
          (before['pending_users'], after['pending_users']))
    check('suspended_users increased by exactly 1',
          after['suspended_users'] - before['suspended_users'] == 1,
          (before['suspended_users'], after['suspended_users']))
    check('total_users increased by exactly 6 (3+2+1), confirming it is the '
          'honest all-rows figure active_users used to be mislabeled as',
          after['total_users'] - before['total_users'] == 6,
          (before['total_users'], after['total_users']))

    print('\n== active_doctors ==')
    verified_doc = mk_user('doctor')
    DoctorProfile.objects.create(
        user=verified_doc, clinic_hospital_name='C', practice_address='A',
        veterinary_degree='DVM', university_name='U', graduation_year=2015,
        license_number=f'DASH-{verified_doc.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today().replace(year=date.today().year + 2),
        specialty='Poultry', years_of_experience=5, consultation_mode='online',
        council_registration_proof_url='x', service_fee=500,
        consent_platform_guidelines=True, is_verified=True)
    unverified_doc = mk_user('doctor')
    DoctorProfile.objects.create(
        user=unverified_doc, clinic_hospital_name='C', practice_address='A',
        veterinary_degree='DVM', university_name='U', graduation_year=2015,
        license_number=f'DASH-{unverified_doc.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today().replace(year=date.today().year + 2),
        specialty='Poultry', years_of_experience=5, consultation_mode='online',
        council_registration_proof_url='x', service_fee=500,
        consent_platform_guidelines=True, is_verified=False)
    r = c.get('/api/admin-panel/dashboard/')
    after2 = r.json()['stats']
    check('active_doctors increased by exactly 1 (only the verified one)',
          after2['active_doctors'] - after['active_doctors'] == 1,
          (after['active_doctors'], after2['active_doctors']))

    print('\n== pending_delivery ==')
    rider = mk_user('delivery')
    DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-DASH-{rider.id.hex[:8]}',
        license_class='B', license_expiry_date=date.today().replace(year=date.today().year + 2),
        license_photo_url='x', approved_by_admin=None)
    r = c.get('/api/admin-panel/dashboard/')
    after3 = r.json()['stats']
    check('pending_delivery increased by exactly 1 (approved_by_admin is null)',
          after3['pending_delivery'] - after2['pending_delivery'] == 1,
          (after2['pending_delivery'], after3['pending_delivery']))

    print('\n== metrics update after a real status change ==')
    pending_users[0].account_status = 'active'
    pending_users[0].save(update_fields=['account_status'])
    r = c.get('/api/admin-panel/dashboard/')
    after4 = r.json()['stats']
    check('active_users increased by 1 after approving a pending user',
          after4['active_users'] - after3['active_users'] == 1,
          (after3['active_users'], after4['active_users']))
    check('pending_users decreased by 1 after approving a pending user',
          after3['pending_users'] - after4['pending_users'] == 1,
          (after3['pending_users'], after4['pending_users']))

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
