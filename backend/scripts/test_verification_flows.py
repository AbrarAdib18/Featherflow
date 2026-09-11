"""End-to-end check of contact verification (email + phone OTP), self-service
password reset, and private document access control.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_verification_flows.py

Django test Client against the *live* configured database. Creates throw-away
accounts prefixed ``verifytest+`` and cleans up on entry/exit. Idempotent.
"""
import os
import sys
import time

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

from unittest.mock import patch  # noqa: E402

from django.core.cache import cache  # noqa: E402
from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client, override_settings  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from profiles.models import (  # noqa: E402
    AdminProfile, DeliveryProfile, DoctorProfile, FarmerProfile,
    PharmacyOrganization, ResearcherProfile,
)
from farms.models import Farm  # noqa: E402
from notifications.models import Notification  # noqa: E402
from users.models import Role, User  # noqa: E402
from verification import otp as otp_mod  # noqa: E402
from verification.auth import tokens_for  # noqa: E402
from verification.delivery import sms_outbox  # noqa: E402

PASS = FAIL = 0
PREFIX = 'verifytest+'
JSON = 'application/json'
_seq = [0]


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def cleanup():
    for u in list(User.objects.filter(email__startswith=PREFIX)):
        Farm.objects.filter(farmer__user=u).delete()
        for m in (FarmerProfile, DoctorProfile, DeliveryProfile, PharmacyOrganization,
                  ResearcherProfile, AdminProfile):
            m.objects.filter(user=u).delete()
        Notification.objects.filter(user=u).delete()
    User.objects.filter(email__startswith=PREFIX).delete()
    sms_outbox.clear()


def new_email(tag='u'):
    _seq[0] += 1
    return f'{PREFIX}{tag}{_seq[0]}@example.com'


def new_phone():
    _seq[0] += 1
    return f'+88017{_seq[0]:08d}'


def register(c, role='farmer', **over):
    _seq[0] += 1
    rd = {'farmer': {'farm_name': 'F', 'farm_location': 'Savar'},
          'doctor': {'clinic_name': 'C', 'practice_address': 'Rd', 'degree': 'DVM',
                     'university': 'U', 'graduation_year': '2015',
                     'license_number': f'L{_seq[0]}', 'issuing_authority': 'BVC',
                     'license_expiry': '2032-01-01', 'specialty': 'poultry',
                     'years_experience': '5'}}[role]
    body = {
        'email': over.get('email', new_email(role[0])),
        'password': over.get('password', 'Str0ngPass!42'),
        'password2': over.get('password', 'Str0ngPass!42'),
        'phone': over.get('phone', new_phone()),
        'full_name': 'Verify Test', 'present_address': 'House 1, Dhaka',
        'date_of_birth': '1990-01-01', 'consent_terms': True,
        'role': role, 'role_data': rd,
    }
    return c.post('/api/auth/register/', body, content_type=JSON)


def expire_code(purpose, channel, ident):
    key = otp_mod._key(purpose, channel, ident)
    rec = cache.get(key)
    rec['expires_at'] = time.time() - 1
    cache.set(key, rec, timeout=60)


# ── email OTP ───────────────────────────────────────────────────────────────
def test_email_otp(c):
    print('\n-- email verification OTP --')
    r = register(c, 'farmer')
    email = r.json()['email']
    check('signup returns verify_email + debug_code',
          r.json().get('next') == 'verify_email' and r.json().get('debug_code'),
          r.content[:200])
    code = r.json()['debug_code']

    # wrong code
    w = c.post('/api/auth/verify/confirm/',
               {'email': email, 'channel': 'email', 'code': '000000'}, content_type=JSON)
    check('wrong code -> 400 code:wrong', w.status_code == 400 and w.json().get('code') == 'wrong',
          w.content[:150])

    # resend within cooldown -> 429
    rs = c.post('/api/auth/verify/request/', {'email': email, 'channel': 'email'},
                content_type=JSON)
    check('resend within cooldown -> 429', rs.status_code == 429 and 'retry_after' in rs.json(),
          rs.content[:150])

    # unknown email -> generic 200 (no enumeration)
    u = c.post('/api/auth/verify/request/',
               {'email': 'verifytest+ghost@example.com', 'channel': 'email'}, content_type=JSON)
    check('unknown email -> generic 200', u.status_code == 200 and 'debug_code' not in u.json(),
          u.content[:150])

    # correct code -> session (farmer active)
    ok = c.post('/api/auth/verify/confirm/',
                {'email': email, 'channel': 'email', 'code': code}, content_type=JSON)
    check('correct code -> 200 + tokens', ok.status_code == 200 and ok.json().get('access'),
          ok.content[:150])
    check('  user.email_verified is set',
          User.objects.get(email=email).email_verified is True)

    # replay the consumed code -> no_code
    replay = c.post('/api/auth/verify/confirm/',
                    {'email': email, 'channel': 'email', 'code': code}, content_type=JSON)
    check('replay consumed code -> 400 no_code',
          replay.status_code == 400 and replay.json().get('code') == 'no_code', replay.content[:150])

    # already verified -> request says so
    av = c.post('/api/auth/verify/request/', {'email': email, 'channel': 'email'},
                content_type=JSON)
    check('request for verified account -> verified:true',
          av.status_code == 200 and av.json().get('verified') is True, av.content[:150])


def test_email_otp_expiry_and_lockout(c):
    print('\n-- OTP expiry + brute-force lockout --')
    r = register(c, 'farmer')
    email = r.json()['email']
    expire_code('email_verify', 'email', email.lower())
    ex = c.post('/api/auth/verify/confirm/',
                {'email': email, 'channel': 'email', 'code': r.json()['debug_code']},
                content_type=JSON)
    check('expired code -> 400 code:expired',
          ex.status_code == 400 and ex.json().get('code') == 'expired', ex.content[:150])

    # fresh code, then 5 wrong guesses -> lockout
    r2 = register(c, 'farmer')
    email2 = r2.json()['email']
    good = r2.json()['debug_code']
    last = None
    for _ in range(5):
        last = c.post('/api/auth/verify/confirm/',
                      {'email': email2, 'channel': 'email', 'code': '999999'}, content_type=JSON)
    check('5th wrong guess -> 429 locked',
          last.status_code == 429 and last.json().get('code') == 'locked', last.content[:150])
    blocked = c.post('/api/auth/verify/confirm/',
                     {'email': email2, 'channel': 'email', 'code': good}, content_type=JSON)
    check('correct code during lockout -> still 429', blocked.status_code == 429, blocked.content[:150])


def test_phone_otp(c):
    print('\n-- phone verification OTP (SMS console backend) --')
    sms_outbox.clear()
    r = register(c, 'farmer')
    email, phone = r.json()['email'], User.objects.get(email=r.json()['email']).phone
    # verify email first (not the subject of this test)
    c.post('/api/auth/verify/confirm/',
           {'email': email, 'channel': 'email', 'code': r.json()['debug_code']}, content_type=JSON)

    req = c.post('/api/auth/verify/request/', {'email': email, 'channel': 'phone'},
                 content_type=JSON)
    check('phone code requested -> 200', req.status_code == 200, req.content[:150])
    check('  ...SMS console backend recorded it',
          any(m['to'] == phone for m in sms_outbox), sms_outbox)
    code = next(m['code'] for m in sms_outbox if m['to'] == phone)
    ok = c.post('/api/auth/verify/confirm/',
                {'email': email, 'channel': 'phone', 'code': code}, content_type=JSON)
    check('phone code confirmed -> 200', ok.status_code == 200, ok.content[:150])
    check('  user.phone_verified is set',
          User.objects.get(email=email).phone_verified is True)


def test_phone_gate_toggle(c):
    print('\n-- SIGNUP_REQUIRE_PHONE_VERIFICATION toggle --')
    with override_settings(SIGNUP_REQUIRE_PHONE_VERIFICATION=True):
        r = register(c, 'farmer')
        email = r.json()['email']
        vr = c.post('/api/auth/verify/confirm/',
                    {'email': email, 'channel': 'email', 'code': r.json()['debug_code']},
                    content_type=JSON)
        check('email verified but phone required -> 403 verify_phone',
              vr.status_code == 403 and vr.json().get('next') == 'verify_phone', vr.content[:200])
        # supply the phone code
        c.post('/api/auth/verify/request/', {'email': email, 'channel': 'phone'}, content_type=JSON)
        pcode = next(m['code'] for m in sms_outbox if m['to'] == User.objects.get(email=email).phone)
        done = c.post('/api/auth/verify/confirm/',
                      {'email': email, 'channel': 'phone', 'code': pcode}, content_type=JSON)
        check('phone verified -> 200 + tokens', done.status_code == 200 and done.json().get('access'),
              done.content[:200])


# ── password reset ──────────────────────────────────────────────────────────
def make_verified_farmer(c):
    r = register(c, 'farmer')
    email = r.json()['email']
    c.post('/api/auth/verify/confirm/',
           {'email': email, 'channel': 'email', 'code': r.json()['debug_code']}, content_type=JSON)
    return User.objects.get(email=email)


def test_password_reset(c):
    print('\n-- self-service password reset --')
    user = make_verified_farmer(c)
    email = user.email
    old_password = 'Str0ngPass!42'
    new_password = 'BrandNew!Pass77'

    # old session token, to prove it dies on reset
    old_access, _ = tokens_for(user)
    authed = Client()
    authed.defaults['HTTP_AUTHORIZATION'] = f'Bearer {old_access}'
    check('old token works before reset', authed.get('/api/auth/me/').status_code == 200)

    req = c.post('/api/auth/password-reset/request/', {'email': email}, content_type=JSON)
    check('reset request -> generic 200 + debug_code', req.status_code == 200 and req.json().get('debug_code'),
          req.content[:150])
    code = req.json()['debug_code']

    # unknown email -> still generic 200
    g = c.post('/api/auth/password-reset/request/',
               {'email': 'verifytest+nobody@example.com'}, content_type=JSON)
    check('reset request unknown email -> generic 200 (no debug_code)',
          g.status_code == 200 and 'debug_code' not in g.json(), g.content[:150])

    # wrong code
    bad = c.post('/api/auth/password-reset/confirm/',
                 {'email': email, 'code': '111111', 'new_password': new_password}, content_type=JSON)
    check('wrong reset code -> 400', bad.status_code == 400, bad.content[:150])

    # weak new password -> 400 + a fresh code
    weak = c.post('/api/auth/password-reset/confirm/',
                  {'email': email, 'code': code, 'new_password': 'short'}, content_type=JSON)
    check('weak new password -> 400 with password errors',
          weak.status_code == 400 and 'password' in weak.json(), weak.content[:200])
    code = weak.json().get('debug_code', code)

    # valid reset
    ok = c.post('/api/auth/password-reset/confirm/',
                {'email': email, 'code': code, 'new_password': new_password}, content_type=JSON)
    check('valid reset -> 200 next:login', ok.status_code == 200 and ok.json().get('next') == 'login',
          ok.content[:200])

    # replay the reset code
    replay = c.post('/api/auth/password-reset/confirm/',
                    {'email': email, 'code': code, 'new_password': 'Another!Pass88'}, content_type=JSON)
    check('reset code replay -> 400', replay.status_code == 400, replay.content[:150])

    # old password no longer works, new one does
    lo = c.post('/api/auth/login/', {'email': email, 'password': old_password}, content_type=JSON)
    check('login with old password -> 401', lo.status_code == 401, lo.content[:150])
    ln = c.post('/api/auth/login/', {'email': email, 'password': new_password}, content_type=JSON)
    check('login with new password -> 200 + tokens', ln.status_code == 200 and ln.json().get('access'),
          ln.content[:150])

    # the pre-reset token is now rejected (password-version claim stale)
    check('pre-reset JWT is now invalid (401)',
          authed.get('/api/auth/me/').status_code == 401)


def test_password_reset_rate_limit(c):
    print('\n-- password-reset rate limiting --')
    from rest_framework.throttling import SimpleRateThrottle
    user = make_verified_farmer(c)
    cache.clear()
    with patch.dict(SimpleRateThrottle.THROTTLE_RATES, {'password_reset': '3/hour'}):
        codes = [c.post('/api/auth/password-reset/request/', {'email': user.email},
                        content_type=JSON).status_code for _ in range(6)]
    cache.clear()
    check('reset endpoint 429s once the per-IP limit is hit',
          codes[0] == 200 and 429 in codes, codes)


# ── document access control ─────────────────────────────────────────────────
def upload(c, kind='license_photo'):
    png = SimpleUploadedFile('d.png', b'\x89PNG\r\n\x1a\n' + b'0' * 64, content_type='image/png')
    r = c.post('/api/auth/registration-upload/', {'kind': kind, 'file': png})
    return r.json()['url']


def path_of(url):
    return url.split('127.0.0.1:8000')[-1] if '127.0.0.1' in url else url.split('testserver')[-1]


def test_document_access(c):
    print('\n-- private document access control --')
    anon = Client()
    url = upload(anon, 'council_proof')
    check('upload returns a non-/media/ signed URL',
          '/api/auth/registration-documents/' in url and '/media/' not in url, url)

    doc_path = path_of(url)

    # unclaimed + within grace -> anyone with the token can fetch
    g = anon.get(doc_path)
    check('unclaimed doc within grace -> 200', g.status_code == 200, g.status_code)

    # a garbage token -> 404
    bad = anon.get('/api/auth/registration-documents/not-a-real-token/')
    check('tampered token -> 404', bad.status_code == 404, bad.status_code)

    # attach the doc to a doctor account
    r = register(c, 'doctor')
    email = r.json()['email']
    rd_url = url
    dr = c.post('/api/auth/register/', {  # re-register cleanly with the doc in role_data
        'email': new_email('doc'), 'password': 'Str0ngPass!42', 'password2': 'Str0ngPass!42',
        'phone': new_phone(), 'full_name': 'Doc Owner', 'present_address': 'Rd 2, Dhaka',
        'date_of_birth': '1985-01-01', 'consent_terms': True, 'role': 'doctor',
        'role_data': {'clinic_name': 'C', 'practice_address': 'Rd', 'degree': 'DVM',
                      'university': 'U', 'graduation_year': '2015',
                      'license_number': f'DOC{_seq[0]}', 'issuing_authority': 'BVC',
                      'license_expiry': '2032-01-01', 'specialty': 'poultry',
                      'years_experience': '5',
                      'council_registration_proof_url': rd_url},
    }, content_type=JSON)
    owner_email = dr.json()['email']
    owner = User.objects.get(email=owner_email)
    owner.mark_email_verified()
    check('doc URL stored on the doctor profile',
          DoctorProfile.objects.get(user=owner).council_registration_proof_url == rd_url)

    # Approve the doctor so the owner has a usable session (a pending
    # professional cannot authenticate anywhere — the signup grace window
    # covers that period instead).
    admin_for_approve = User.objects.filter(
        roles__name='admin_super', account_status='active').first()
    if admin_for_approve:
        aa2, _ = tokens_for(admin_for_approve)
        ac2 = Client()
        ac2.defaults['HTTP_AUTHORIZATION'] = f'Bearer {aa2}'
        prof_id = DoctorProfile.objects.get(user=owner).id
        ac2.patch(f'/api/admin-panel/doctors/{prof_id}/', {'status': 'Verified'},
                  content_type=JSON)
        owner.refresh_from_db()

    owner_access, _ = tokens_for(owner)
    owner_client = Client()
    owner_client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {owner_access}'

    other = make_verified_farmer(c)
    other_access, _ = tokens_for(other)
    other_client = Client()
    other_client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {other_access}'

    admin = User.objects.filter(roles__name='admin_super', account_status='active').first()
    admin_client = Client()
    if admin:
        aa, _ = tokens_for(admin)
        admin_client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {aa}'

    # Force the grace window shut so ownership is the only thing that grants access.
    with patch('verification.documents.GRACE_SECONDS', 0):
        og = owner_client.get(doc_path)
        check('owner can fetch their claimed doc -> 200', og.status_code == 200,
              f'{og.status_code} {getattr(og, "content", b"")[:200]}')
        check('another user cannot fetch it -> 403',
              other_client.get(doc_path).status_code == 403)
        check('unauthenticated cannot fetch it -> 401',
              Client().get(doc_path).status_code == 401)
        if admin:
            check('admin can fetch it -> 200',
                  admin_client.get(doc_path).status_code == 200)


def run():
    print('\n== Verification / password reset / document access E2E ==')
    cleanup()
    c = Client()
    test_email_otp(c)
    test_email_otp_expiry_and_lockout(c)
    test_phone_otp(c)
    test_phone_gate_toggle(c)
    test_password_reset(c)
    test_password_reset_rate_limit(c)
    test_document_access(c)
    cleanup()
    print(f'\n{"="*40}\n{PASS} passed, {FAIL} failed\n{"="*40}')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
