"""End-to-end check of every signup / registration flow.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_signup_flows.py

Django test Client against the *live* configured database (needs
featherflow_schema.sql + postgres_backend_extension.sql applied). Creates
throw-away accounts prefixed ``signuptest+`` and cleans its own rows on entry
and exit. Idempotent.

Covers, for farmer / doctor / pharmacy / delivery / researcher / admin:
valid signup, per-field validation (name, email, phone, password strength,
password confirmation, terms consent, role-specific required fields),
duplicate email / phone, invalid role, admin-role escalation attempt,
document upload validation, transaction rollback, duplicate submission,
account-status + profile-row correctness, the pending -> admin-approve ->
login lifecycle, rejected-application behaviour, and role-based access.
"""
import os
import sys

# Throttling would block a test that makes dozens of register calls.
os.environ.setdefault('THROTTLE_AUTH_REGISTER', '100000/hour')
os.environ.setdefault('THROTTLE_AUTH_LOGIN', '100000/min')
os.environ.setdefault('THROTTLE_AUTH_UPLOAD', '100000/hour')
os.environ.setdefault('THROTTLE_OTP_REQUEST', '100000/hour')
os.environ.setdefault('THROTTLE_OTP_CONFIRM', '100000/hour')
os.environ.setdefault('THROTTLE_PASSWORD_RESET', '100000/hour')
os.environ.setdefault('THROTTLE_DOCUMENT_FETCH', '100000/hour')
os.environ.setdefault('OTP_EXPOSE_CODES', 'True')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')

import django  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402

from profiles.models import (  # noqa: E402
    AdminProfile, DeliveryProfile, DoctorProfile, FarmerProfile,
    PharmacyOrganization, ResearcherProfile,
)
from farms.models import Farm  # noqa: E402
from notifications.models import Notification  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'signuptest+'
JSON = 'application/json'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def cleanup():
    users = list(User.objects.filter(email__startswith=PREFIX))
    for u in users:
        Farm.objects.filter(farmer__user=u).delete()
        FarmerProfile.objects.filter(user=u).delete()
        DoctorProfile.objects.filter(user=u).delete()
        DeliveryProfile.objects.filter(user=u).delete()
        PharmacyOrganization.objects.filter(user=u).delete()
        ResearcherProfile.objects.filter(user=u).delete()
        AdminProfile.objects.filter(user=u).delete()
        Notification.objects.filter(user=u).delete()
    User.objects.filter(email__startswith=PREFIX).delete()


_phone_seq = [0]


def phone():
    _phone_seq[0] += 1
    return f'+88017{_phone_seq[0]:08d}'


def base_payload(role, **over):
    pw = over.pop('password', 'Str0ngPass!42')
    body = {
        'email': over.pop('email', f'{PREFIX}{role}{_phone_seq[0]}@example.com'),
        'password': pw,
        'password2': over.pop('password2', pw),
        'phone': over.pop('phone', phone()),
        'full_name': over.pop('full_name', f'Test {role.title()}'),
        'present_address': over.pop('present_address', 'House 1, Road 2, Dhaka'),
        'date_of_birth': '1990-05-05',
        'consent_terms': over.pop('consent_terms', True),
        'role': role,
        'role_data': over.pop('role_data', dict(ROLE_DATA.get(role, {}))),
    }
    body.update(over)
    return body


ROLE_DATA = {
    'farmer': {'farm_name': 'Sunrise Poultry', 'farm_owner': 'Test Farmer',
               'farm_location': 'Savar, Dhaka', 'farm_type': 'Broiler',
               'bird_count': '1200', 'years_in_farming': '4',
               'experience_level': 'Intermediate', 'active_workers': '3'},
    'doctor': {'clinic_name': 'Dhaka Avian Clinic', 'practice_address': 'Mirpur, Dhaka',
               'district': 'Dhaka', 'workplace': 'Dhaka Avian Clinic',
               'degree': 'DVM', 'university': 'BAU', 'graduation_year': '2014',
               'license_number': None,  # set per-call to stay unique
               'issuing_authority': 'Bangladesh Veterinary Council',
               'license_expiry': '2030-01-01', 'specialty': 'Poultry medicine',
               'years_experience': '9', 'consult_mode': 'Both', 'fees': '800'},
    'pharmacy': {'business_name': 'VetMeds Ltd', 'contact_person': 'Test Pharmacy',
                 'business_reg_number': None, 'tax_number': 'TIN-99120',
                 'trade_license': 'TL-5521', 'business_address': 'Dhanmondi, Dhaka',
                 'warehouse_address': 'Tejgaon, Dhaka', 'number_of_pharmacists': '2',
                 'responsible_pharmacist': 'R. Karim'},
    'delivery': {'license_number': None, 'license_class': 'B',
                 'license_expiry': '2031-06-01', 'vehicle_type': 'Motorcycle',
                 'vehicle_registration': None, 'insurance_details': 'INS-11',
                 'proof_of_right_to_work': 'NID-123', 'area_coverage': 'Dhaka North',
                 'availability': 'Weekdays 9-6', 'banking_details': 'bKash 017...'},
    'researcher': {'institution': 'BLRI', 'institutional_email': 'r@blri.gov.bd',
                   'department': 'Poultry Science', 'degree': 'PhD',
                   'field_of_study': 'Avian pathology', 'university': 'BAU',
                   'graduation_year': '2016', 'areas_of_expertise': 'Pathology, Vaccines',
                   'years_experience': '7', 'research_role': 'Disease'},
    'admin': {'job_title': 'Ops Coordinator', 'department': 'Operations',
              'start_date': '2026-01-10', 'access_level': 'Operations Admin',
              'tech_skills': 'intermediate', 'confidentiality_agreement': True,
              'background_consent': True},
}


def unique_role_data(role):
    rd = dict(ROLE_DATA.get(role, {}))
    n = _phone_seq[0]
    if role in ('doctor',):
        rd['license_number'] = f'BVC-{n}-{PREFIX[-4:]}'
    if role == 'pharmacy':
        rd['business_reg_number'] = f'BRN-{n}'
    if role == 'delivery':
        rd['license_number'] = f'DL-{n}'
        rd['vehicle_registration'] = f'DHK-{n}'
    return rd


def reg(client, role, **over):
    if 'role_data' not in over:
        over['role_data'] = unique_role_data(role)
    return client.post('/api/auth/register/', base_payload(role, **over),
                       content_type=JSON)


def verify_signup_email(client, reg_response):
    """Complete the email-OTP step for a just-registered account using the
    debug_code the signup response returns in dev mode. Returns the confirm
    response (a session for active accounts, a 403 pending body otherwise)."""
    data = reg_response.json()
    return client.post('/api/auth/verify/confirm/',
                       {'email': data['email'], 'channel': 'email',
                        'code': data['debug_code']}, content_type=JSON)


# ── tests ────────────────────────────────────────────────────────────────
def test_validation(c):
    print('\n-- field validation --')
    r = reg(c, 'farmer', full_name='  ')
    check('blank name -> 400', r.status_code == 400 and 'full_name' in r.json(), r.content[:200])

    r = reg(c, 'farmer', full_name='x' * 200)
    check('over-long name -> 400', r.status_code == 400, r.content[:150])

    r = reg(c, 'farmer', email='not-an-email')
    check('invalid email -> 400', r.status_code == 400 and 'email' in r.json(), r.content[:200])

    r = reg(c, 'farmer', phone='12345')
    check('invalid phone -> 400', r.status_code == 400 and 'phone' in r.json(), r.content[:200])

    r = reg(c, 'farmer', password='short', password2='short')
    check('weak password -> 400', r.status_code == 400 and 'password' in r.json(), r.content[:200])

    r = reg(c, 'farmer', password='Str0ngPass!42', password2='different')
    check('password mismatch -> 400', r.status_code == 400 and 'password2' in r.json(), r.content[:200])

    r = reg(c, 'farmer', consent_terms=False)
    check('terms not accepted -> 400', r.status_code == 400 and 'consent_terms' in r.json(), r.content[:200])

    r = reg(c, 'farmer', password='12345678', password2='12345678')
    check('all-numeric password -> 400', r.status_code == 400, r.content[:150])

    r = c.post('/api/auth/register/', base_payload('supergod', role_data={}),
               content_type=JSON)
    check('invalid role -> 400', r.status_code == 400 and 'role' in r.json(), r.content[:200])

    r = reg(c, 'doctor', role_data={'clinic_name': 'X'})
    check('doctor missing required role fields -> 400',
          r.status_code == 400 and 'role_data' in r.json(), r.content[:250])
    body = r.json().get('role_data', {})
    check('  ...names the missing fields',
          isinstance(body, dict) and 'license_number' in body, body)

    r = reg(c, 'doctor', role_data=dict(unique_role_data('doctor'), graduation_year='abc'))
    check('non-numeric graduation_year -> 400', r.status_code == 400, r.content[:200])

    # whitespace-only role field must not pass as "present"
    rd = unique_role_data('pharmacy')
    rd['business_name'] = '   '
    r = reg(c, 'pharmacy', role_data=rd)
    check('whitespace-only required field -> 400', r.status_code == 400, r.content[:200])

    # email normalisation (case + spaces)
    email = f'{PREFIX}NormCase{_phone_seq[0]}@Example.com  '
    r = reg(c, 'farmer', email=email)
    check('mixed-case email accepted', r.status_code == 201, r.content[:200])
    if r.status_code == 201:
        uid = r.json()['user']['id']
        check('  ...stored lowercased + trimmed',
              User.objects.get(pk=uid).email == email.strip().lower())


def test_duplicates(c):
    print('\n-- duplicates --')
    p = base_payload('farmer', role_data=unique_role_data('farmer'))
    r1 = c.post('/api/auth/register/', p, content_type=JSON)
    check('first signup -> 201', r1.status_code == 201, r1.content[:200])

    r2 = c.post('/api/auth/register/', p, content_type=JSON)
    check('duplicate email -> 409', r2.status_code == 409, r2.content[:200])
    check('  ...single user created',
          User.objects.filter(email=p['email']).count() == 1)

    p2 = base_payload('farmer', phone=p['phone'], role_data=unique_role_data('farmer'))
    r3 = c.post('/api/auth/register/', p2, content_type=JSON)
    check('duplicate phone -> 409', r3.status_code == 409, r3.content[:200])

    # idempotent double-submit of an identical *doctor* payload
    dp = base_payload('doctor', role_data=unique_role_data('doctor'))
    a = c.post('/api/auth/register/', dp, content_type=JSON)
    b = c.post('/api/auth/register/', dp, content_type=JSON)
    check('doctor double-submit -> 201 then 409',
          a.status_code == 201 and b.status_code == 409, f'{a.status_code}/{b.status_code}')
    check('  ...one user, one profile',
          User.objects.filter(email=dp['email']).count() == 1
          and DoctorProfile.objects.filter(user__email=dp['email']).count() == 1)


def test_role_creation(c):
    print('\n-- role + profile + status --')
    expect = {
        'farmer': ('active', FarmerProfile, 'farmer_profile'),
        'doctor': ('pending', DoctorProfile, 'doctor_profile'),
        'pharmacy': ('pending', PharmacyOrganization, 'pharmacy_organization'),
        'delivery': ('pending', DeliveryProfile, 'delivery_profile'),
        'researcher': ('pending', ResearcherProfile, 'researcher_profile'),
        'admin': ('pending', AdminProfile, 'admin_profile'),
    }
    created = {}
    for role, (status_want, model, rel) in expect.items():
        r = reg(c, role)
        ok = r.status_code == 201
        check(f'{role} signup -> 201', ok, r.content[:250])
        if not ok:
            continue
        data = r.json()
        uid = data['user']['id']
        user = User.objects.get(pk=uid)
        created[role] = user
        check(f'  {role} account_status == {status_want}',
              user.account_status == status_want, user.account_status)
        check(f'  {role} profile row exists',
              model.objects.filter(user=user).exists())
        check(f'  {role} signup asks for email verification (no tokens yet)',
              data.get('next') == 'verify_email' and data.get('debug_code')
              and not data.get('access'), data.get('next'))

        vr = verify_signup_email(c, r)
        vdata = vr.json()
        if status_want == 'active':
            check(f'  {role} after email verify -> 200 + tokens + dashboard',
                  vr.status_code == 200 and vdata.get('access')
                  and vdata.get('next') == 'dashboard', vr.content[:200])
        else:
            check(f'  {role} after email verify -> 403 pending, tokens withheld',
                  vr.status_code == 403 and not vdata.get('access')
                  and vdata.get('next') == 'pending_approval', vr.content[:200])
        user.refresh_from_db()
        check(f'  {role} email marked verified', user.email_verified is True)

        if role == 'farmer':
            check('  farmer primary Farm created',
                  Farm.objects.filter(farmer__user=user).exists())
        if role == 'admin':
            prof = AdminProfile.objects.get(user=user)
            check('  admin approval_status pending', prof.approval_status == 'pending')
            check('  admin not is_active', prof.is_active is False)
    return created


def test_admin_escalation(c):
    print('\n-- admin role escalation --')
    r = reg(c, 'admin', role_data=dict(ROLE_DATA['admin'], access_level='super'))
    check('admin requesting super -> 201 (not blocked, but downgraded)', r.status_code == 201, r.content[:200])
    if r.status_code == 201:
        user = User.objects.get(pk=r.json()['user']['id'])
        prof = AdminProfile.objects.get(user=user)
        check('  self-registered admin is NOT admin_super',
              prof.admin_sub_role != 'super'
              and not user.roles.filter(name='admin_super').exists(),
              prof.admin_sub_role)
        check('  ...and lands pending + inactive',
              user.account_status == 'pending' and prof.is_active is False)


def test_uploads(c):
    print('\n-- document upload validation --')
    png = SimpleUploadedFile(
        'x.png', b'\x89PNG\r\n\x1a\n' + b'0' * 32, content_type='image/png')
    r = c.post('/api/auth/registration-upload/', {'kind': 'license_photo', 'file': png})
    check('valid png upload -> 201 + url', r.status_code == 201 and r.json().get('url'), r.content[:200])

    pdf = SimpleUploadedFile('doc.pdf', b'%PDF-1.4 test', content_type='application/pdf')
    r = c.post('/api/auth/registration-upload/', {'kind': 'cv', 'file': pdf})
    check('valid pdf upload -> 201', r.status_code == 201, r.content[:200])

    exe = SimpleUploadedFile('bad.exe', b'MZ' + b'0' * 10, content_type='application/octet-stream')
    r = c.post('/api/auth/registration-upload/', {'kind': 'cv', 'file': exe})
    check('disallowed file type -> 400', r.status_code == 400, r.content[:200])

    big = SimpleUploadedFile('big.png', b'0' * (6 * 1024 * 1024), content_type='image/png')
    r = c.post('/api/auth/registration-upload/', {'kind': 'license_photo', 'file': big})
    check('oversized upload -> 400', r.status_code == 400, r.content[:200])

    r = c.post('/api/auth/registration-upload/', {'kind': 'license_photo'})
    check('missing file -> 400', r.status_code == 400, r.content[:200])

    pdf2 = SimpleUploadedFile('p.pdf', b'%PDF-1.4', content_type='application/pdf')
    r = c.post('/api/auth/registration-upload/', {'kind': 'profile_photo', 'file': pdf2})
    check('pdf as profile photo -> 400', r.status_code == 400, r.content[:200])

    r = c.post('/api/auth/registration-upload/',
               {'kind': 'nonsense', 'file': SimpleUploadedFile('a.png', b'x', content_type='image/png')})
    check('unknown kind -> 400', r.status_code == 400, r.content[:200])

    # the uploaded url can then be used in role_data
    png2 = SimpleUploadedFile('lic.png', b'\x89PNG\r\n\x1a\n' + b'0' * 16, content_type='image/png')
    up = c.post('/api/auth/registration-upload/', {'kind': 'license_photo', 'file': png2})
    url = up.json()['url']
    rd = unique_role_data('delivery')
    rd['license_photo_url'] = url
    r = reg(c, 'delivery', role_data=rd)
    check('delivery signup carries uploaded license photo url', r.status_code == 201, r.content[:250])
    if r.status_code == 201:
        prof = DeliveryProfile.objects.get(user__email=r.json()['user']['email'])
        check('  ...persisted on the profile', prof.license_photo_url == url, prof.license_photo_url)


def test_rollback(c):
    print('\n-- transaction rollback --')
    from unittest.mock import patch
    email = f'{PREFIX}rollback{_phone_seq[0]}@example.com'
    p = base_payload('researcher', email=email, role_data=unique_role_data('researcher'))
    with patch('users.serializers.ResearcherProfile.objects.update_or_create',
               side_effect=RuntimeError('boom')):
        try:
            r = c.post('/api/auth/register/', p, content_type=JSON)
            code = r.status_code
        except RuntimeError:
            code = 500
    check('profile failure aborts signup (no 201)', code != 201, code)
    check('  ...user row rolled back', not User.objects.filter(email=email).exists())
    check('  ...role profile rolled back',
          not ResearcherProfile.objects.filter(user__email=email).exists())


def test_lifecycle(c, admins):
    print('\n-- verify -> pending -> approve -> login lifecycle --')
    dp = base_payload('doctor', role_data=unique_role_data('doctor'))
    rr = c.post('/api/auth/register/', dp, content_type=JSON)

    # before verifying the email, login is gated on verification (not approval)
    lr0 = c.post('/api/auth/login/', {'email': dp['email'], 'password': dp['password']},
                 content_type=JSON)
    check('login before email verify -> 403 verify_email',
          lr0.status_code == 403 and lr0.json().get('next') == 'verify_email',
          lr0.content[:200])

    vr = verify_signup_email(c, rr)
    check('email verify -> 403 pending (tokens withheld)',
          vr.status_code == 403 and vr.json().get('next') == 'pending_approval'
          and not vr.json().get('access'), vr.content[:200])

    # now login is blocked on *approval* with a clear message
    lr = c.post('/api/auth/login/', {'email': dp['email'], 'password': dp['password']},
                content_type=JSON)
    check('login before approval -> 403', lr.status_code == 403, lr.content[:200])
    check('  ...message explains pending',
          'pending' in lr.json().get('detail', '').lower()
          or lr.json().get('next') == 'pending_approval', lr.json())

    lr_bad = c.post('/api/auth/login/', {'email': dp['email'], 'password': 'wrong-Pass9'},
                    content_type=JSON)
    check('wrong password -> 401 (distinct from pending)', lr_bad.status_code == 401, lr_bad.content[:150])

    # an admin approves the doctor via the admin panel
    doctor = User.objects.get(email=dp['email'])
    prof = DoctorProfile.objects.get(user=doctor)
    admin_client = admins['super_client']
    ar = admin_client.patch(f'/api/admin-panel/doctors/{prof.id}/',
                            {'status': 'Verified'}, content_type=JSON)
    check('admin verifies doctor -> 200', ar.status_code == 200, ar.content[:250])
    doctor.refresh_from_db()
    prof.refresh_from_db()
    check('  doctor account_status now active', doctor.account_status == 'active', doctor.account_status)
    check('  doctor profile is_verified', prof.is_verified is True)

    lr2 = c.post('/api/auth/login/', {'email': dp['email'], 'password': dp['password']},
                 content_type=JSON)
    check('login after approval -> 200 + tokens',
          lr2.status_code == 200 and lr2.json().get('access'), lr2.content[:200])

    # rejected application (verify the email first so the reject message shows)
    rp = base_payload('researcher', role_data=unique_role_data('researcher'))
    rpr = c.post('/api/auth/register/', rp, content_type=JSON)
    verify_signup_email(c, rpr)
    researcher = User.objects.get(email=rp['email'])
    rej = admin_client.patch(f'/api/admin-panel/users/{researcher.id}/',
                             {'status': 'Suspended'}, content_type=JSON)
    researcher.refresh_from_db()
    check('admin can reject/suspend a researcher application',
          rej.status_code == 200 and researcher.account_status == 'suspended',
          f'{rej.status_code} {researcher.account_status}')
    lr3 = c.post('/api/auth/login/', {'email': rp['email'], 'password': rp['password']},
                 content_type=JSON)
    check('rejected applicant login -> 403 with reason',
          lr3.status_code == 403 and 'suspended' in lr3.json().get('detail', '').lower(),
          lr3.content[:200])


def test_access_control(c, admins):
    print('\n-- role-based access --')
    fp = base_payload('farmer', role_data=unique_role_data('farmer'))
    r = c.post('/api/auth/register/', fp, content_type=JSON)
    token = verify_signup_email(c, r).json()['access']
    fc = Client()
    fc.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    dash = fc.get('/api/admin-panel/dashboard/')
    check('farmer cannot open admin dashboard', dash.status_code in (401, 403), dash.status_code)
    me = fc.get('/api/auth/me/')
    check('farmer can read own profile', me.status_code == 200 and me.json()['roles'] == ['farmer'],
          me.content[:150])


def get_admin_clients():
    """A Super Admin client for driving the approval endpoints."""
    sup = User.objects.filter(roles__name='admin_super', account_status='active').first()
    if not sup:
        return None
    from rest_framework_simplejwt.tokens import RefreshToken
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(sup).access_token}'
    return {'super_client': c, 'super': sup}


def run():
    print('\n== Signup / Registration E2E ==')
    cleanup()
    c = Client()
    admins = get_admin_clients()

    test_validation(c)
    test_duplicates(c)
    test_role_creation(c)
    test_admin_escalation(c)
    test_uploads(c)
    test_rollback(c)
    if admins:
        test_lifecycle(c, admins)
        test_access_control(c, admins)
    else:
        print('  SKIP lifecycle/access tests — no active admin_super account. '
              'Run: manage.py seed_platform_demo')

    cleanup()
    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
