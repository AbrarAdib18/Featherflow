"""Signup file uploads are persisted + access-controlled.

    backend/venv/Scripts/python.exe backend/scripts/test_signup_documents.py

For every role: upload the role's documents anonymously, register with the
returned URLs, then assert a ``signup_documents`` row links each file to the new
account. Then exercises the access-control matrix on the private document
endpoint (owner / other user / admin / unclaimed-grace) and the atomic-rollback
guarantee. Uses the live DB; throw-away accounts prefixed ``docstest+``.
"""
import io
import os
import sys
from datetime import date, timedelta

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
os.environ.setdefault('THROTTLE_REGISTRATION', '5000/hour')
os.environ.setdefault('THROTTLE_REGISTRATION_UPLOAD', '5000/hour')
os.environ.setdefault('THROTTLE_DOCUMENT_FETCH', '5000/hour')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402

if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from users.models import Role, User  # noqa: E402
from verification import documents as docs  # noqa: E402
from verification.models import SignupDocument  # noqa: E402

PASS = FAIL = 0
PREFIX = 'docstest+'
_PHONE = [300_000_000]

PNG = b'\x89PNG\r\n\x1a\n' + b'\x00' * 128
PDF = b'%PDF-1.4\n%stub\n'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def phone():
    _PHONE[0] += 1
    return '+8801' + str(_PHONE[0])  # +8801 + 9 digits starting 3.. -> valid BD mobile


def cleanup():
    for u in User.objects.filter(email__startswith=PREFIX):
        SignupDocument.objects.filter(user=u).delete()
        u.delete()
    SignupDocument.objects.filter(original_filename__startswith='docstest-').delete()


def upload(c, kind, pdf=False):
    payload = PDF if pdf else PNG
    ext = 'pdf' if pdf else 'png'
    ct = 'application/pdf' if pdf else 'image/png'
    f = SimpleUploadedFile(f'docstest-{kind}.{ext}', payload, content_type=ct)
    r = c.post('/api/auth/registration-upload/', {'kind': kind, 'file': f})
    assert r.status_code == 201, r.content[:300]
    return r.json()['url']


def register(c, email, role, role_data):
    body = {
        'email': email, 'password': 'Sup3r!Secret2026', 'password2': 'Sup3r!Secret2026',
        'phone': phone(), 'full_name': 'Docs Test', 'present_address': 'Mirpur, Dhaka',
        'date_of_birth': '1990-01-01', 'consent_terms': True, 'role': role,
        'role_data': role_data,
    }
    return c.post('/api/auth/register/', body, content_type='application/json')


ROLE_CASES = {
    'farmer': (
        {'farm_name': 'F', 'farm_location': 'L'},
        [('profile_photo', 'profile_photo_url', False)],
        {'farm_photos': [('farm_photo', 'farm_photo', False)]},
    ),
    'doctor': (
        {'clinic_name': 'C', 'practice_address': 'A', 'degree': 'DVM', 'university': 'U',
         'graduation_year': '2015', 'license_number': 'L1', 'issuing_authority': 'BVC',
         'license_expiry': '2031-01-01', 'specialty': 'poultry', 'years_experience': '6'},
        [('profile_photo', 'profile_photo_url', False),
         ('council_proof', 'council_registration_proof_url', False),
         ('cv', 'cv_url', True)],
        {},
    ),
    'pharmacy': (
        {'business_name': 'B', 'contact_person': 'P', 'business_reg_number': 'BR1',
         'tax_number': 'T1', 'business_address': 'A'},
        [('profile_photo', 'profile_photo_url', False),
         ('trade_license', 'trade_license', True),
         ('certificate', 'business_registration_cert_url', True),
         ('certificate', 'responsible_pharmacist_cert_url', True)],
        {},
    ),
    'delivery': (
        {'license_number': 'DL1', 'license_class': 'B', 'license_expiry': '2031-01-01',
         'vehicle_type': 'Motorcycle', 'vehicle_registration': 'DHK-1', 'area_coverage': 'Dhaka'},
        [('profile_photo', 'profile_photo_url', False),
         ('license_photo', 'license_photo_url', False),
         ('vehicle_photo', 'vehicle_photo_url', False)],
        {},
    ),
    'researcher': (
        {'institution': 'I', 'department': 'D', 'degree': 'PhD', 'field_of_study': 'F',
         'university': 'U', 'graduation_year': '2015', 'years_experience': '6',
         'areas_of_expertise': 'a,b'},
        [('profile_photo', 'profile_photo_url', False),
         ('cv', 'cv_url', True),
         ('certificate', 'ethics_certificate_url', True)],
        {},
    ),
    'admin': (
        {'job_title': 'JT', 'department': 'Ops', 'start_date': '2026-01-01', 'access_level': 'support'},
        [('profile_photo', 'profile_photo_url', False), ('cv', 'cv_url', True)],
        {},
    ),
}


def run_role(c, role):
    base_rd, doc_specs, extra = ROLE_CASES[role]
    rd = dict(base_rd)
    expected = {}  # url -> doc_type
    for kind, key, pdf in doc_specs:
        url = upload(c, kind, pdf=pdf)
        rd[key] = url
        expected[url] = None  # doc_type asserted loosely below
    for list_key, items in extra.items():
        rd[list_key] = []
        for kind, _dt, pdf in items:
            url = upload(c, kind, pdf=pdf)
            rd[list_key].append(url)
            expected[url] = None

    email = f'{PREFIX}{role}@featherflow.dev'
    User.objects.filter(email=email).delete()
    r = register(c, email, role, rd)
    check(f'{role}: signup 201', r.status_code == 201, r.content[:300])
    if r.status_code != 201:
        return None

    user = User.objects.get(email=email)
    rows = SignupDocument.objects.filter(user=user)
    check(f'{role}: every uploaded file has a claimed signup_documents row',
          rows.count() == len(expected), f'{rows.count()} rows vs {len(expected)} uploads')
    tokens = {docs.token_from(u) for u in expected}
    claimed_tokens = set(rows.values_list('token', flat=True))
    check(f'{role}: claimed rows match the uploaded tokens', tokens == claimed_tokens,
          f'missing {tokens - claimed_tokens}')
    check(f'{role}: all rows carry a file_path + document_type',
          all(row.file_path and row.document_type for row in rows), '')
    check(f'{role}: all rows are claimed (user + claimed_at set)',
          all(row.user_id == user.pk and row.claimed_at for row in rows), '')
    return user


def token_url(u):
    return f'/api/auth/registration-documents/{docs.token_from(u)}/'


def test_access_control(c, owner):
    """`owner` must be an *active* account (a pending professional can't get a
    session at all — their docs are admin-only until approval)."""
    print('\n-- access control --')
    private_doc = (SignupDocument.objects.filter(user=owner)
                   .exclude(document_type='profile_photo').first())
    photo_doc = SignupDocument.objects.filter(user=owner, document_type='profile_photo').first()
    check('owner has a private (non-photo) document + a profile photo',
          private_doc is not None and photo_doc is not None, '')
    url = private_doc.url_path
    check('owner account is active (precondition)', owner.is_active, owner.account_status)

    oc = Client()
    oc.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(owner).access_token}'
    r = oc.get(url)
    check('owner can fetch their own document (200)', r.status_code == 200, r.status_code)

    # a different active user
    other = (User.objects.filter(email__startswith=PREFIX, account_status='active')
             .exclude(pk=owner.pk).first())
    if other is None:
        register(c, f'{PREFIX}other@featherflow.dev', 'farmer',
                 {'farm_name': 'F2', 'farm_location': 'L2'})
        other = User.objects.get(email=f'{PREFIX}other@featherflow.dev')
    xc = Client()
    xc.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(other).access_token}'
    r = xc.get(url)
    check('another user is refused a private document (403)', r.status_code == 403, r.status_code)

    # profile photos are viewable by any signed-in user
    r = xc.get(photo_doc.url_path)
    check('another signed-in user CAN fetch a profile photo (200)', r.status_code == 200, r.status_code)
    r = Client().get(photo_doc.url_path)
    check('an anonymous request for a claimed profile photo is still refused (401)',
          r.status_code == 401, r.status_code)

    # anonymous, after the file is claimed -> 401
    r = Client().get(url)
    check('anonymous is refused once the file is claimed (401)', r.status_code == 401, r.status_code)

    # owner can fetch their own profile photo
    r = oc.get(photo_doc.url_path)
    check('owner can fetch their own profile photo (200)', r.status_code == 200, r.status_code)

    # admin (a user holding an admin-panel role)
    admin = (User.objects.filter(roles__panel_type='admin', account_status='active')
             .distinct().first())
    check('an admin account exists to test with', admin is not None, '')
    if admin is not None:
        ac = Client()
        ac.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(admin).access_token}'
        r = ac.get(url)
        check('an admin can fetch any document (200)', r.status_code == 200, r.status_code)


def test_unclaimed_grace(c):
    print('\n-- unclaimed grace window --')
    url = upload(c, 'cv', pdf=True)
    r = Client().get(url)
    check('fresh unclaimed upload is readable with the signed link (200)',
          r.status_code == 200, r.status_code)

    # age it past the grace window -> no longer readable anonymously
    tok = docs.token_from(url)
    SignupDocument.objects.filter(token=tok).update(
        uploaded_at=timezone.now() - timedelta(hours=3))
    # the token's own timestamp still drives can_access; simulate an old token
    import time as _t
    from django.core import signing
    payload = docs.resolve(tok)
    payload['t'] = int(_t.time()) - docs.GRACE_SECONDS - 60
    old_token = signing.dumps(payload, salt=docs._SALT)
    SignupDocument.objects.filter(token=tok).update(token=old_token)
    r = Client().get(f'/api/auth/registration-documents/{old_token}/')
    check('an old unclaimed upload is no longer public (401)', r.status_code == 401, r.status_code)


def test_rollback(c):
    """If any DB write during create() fails, the whole signup rolls back — no
    orphan User and no half-written signup_documents rows."""
    print('\n-- atomic rollback --')
    from unittest.mock import patch

    url = upload(c, 'profile_photo')
    email = f'{PREFIX}rollback@featherflow.dev'
    User.objects.filter(email=email).delete()
    users_before = User.objects.count()
    quiet = Client(raise_request_exception=False)

    with patch('users.serializers._claim_signup_documents', side_effect=RuntimeError('boom')):
        r = quiet.post('/api/auth/register/', {
            'email': email, 'password': 'Sup3r!Secret2026', 'password2': 'Sup3r!Secret2026',
            'phone': phone(), 'full_name': 'Rollback', 'present_address': 'Mirpur, Dhaka',
            'date_of_birth': '1990-01-01', 'consent_terms': True, 'role': 'farmer',
            'role_data': {'farm_name': 'F', 'farm_location': 'L', 'profile_photo_url': url},
        }, content_type='application/json')
    check('a failure while saving file links is not a 201', r.status_code != 201, r.status_code)
    check('the user was rolled back (no orphan account)',
          not User.objects.filter(email=email).exists(), '')
    check('user count unchanged after the failed signup',
          User.objects.count() == users_before, User.objects.count() - users_before)
    check('no signup_documents rows were left claimed to a missing user',
          not SignupDocument.objects.filter(user__email=email).exists(), '')


def main():
    cleanup()
    c = Client()

    owner = None
    for role in ('farmer', 'doctor', 'pharmacy', 'delivery', 'researcher', 'admin'):
        print(f'\n== {role} ==')
        u = run_role(c, role)
        if role == 'farmer':          # farmer is active immediately -> can hold a session
            owner = u

    if owner is not None:
        test_access_control(c, owner)
    test_unclaimed_grace(c)
    test_rollback(c)

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
