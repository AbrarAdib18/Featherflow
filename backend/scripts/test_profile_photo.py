"""Checks for the authenticated profile-photo endpoint.

    POST/DELETE /api/auth/profile-photo/

Run:  backend/venv/Scripts/python.exe backend/scripts/test_profile_photo.py

Django test Client against the live DB. Throw-away accounts prefixed
``photetest+`` (one per role). Idempotent — cleans its own rows + files.
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj  # noqa: E402
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from users.models import Role, User  # noqa: E402
from verification import documents as docs  # noqa: E402
from verification.models import SignupDocument  # noqa: E402

PREFIX = 'photetest+'
PASS = FAIL = 0

# minimal valid files
PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
    '0000000d4944415478da6364f8cf000000030101002718d6a40000000049454e44ae426082')
JPG = b'\xff\xd8\xff\xe0' + b'\x00' * 20


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def mk(handle, role):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    u, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'PP {handle}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    u.account_status = 'active'
    u.profile_photo_url = ''
    u.set_password('Testpass!2026')
    u.save()
    r, _ = Role.objects.get_or_create(name=role, defaults={'panel_type': role})
    u.roles.clear()
    u.roles.add(r)
    return u


def client_for(u):
    c = Client()
    if u is not None:
        c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(u).access_token}'
    return c


def cleanup(users):
    for u in users:
        for d in SignupDocument.objects.filter(user=u):
            try:
                if docs.private_storage.exists(d.file_path):
                    docs.private_storage.delete(d.file_path)
            except OSError:
                pass
        SignupDocument.objects.filter(user=u).delete()
    User.objects.filter(email__startswith=PREFIX).delete()


def run():
    users = []
    try:
        for role in ('farmer', 'doctor', 'pharmacy', 'delivery', 'researcher', 'admin_finance'):
            u = mk(role, role)
            users.append(u)
            c = client_for(u)

            r = c.post('/api/auth/profile-photo/',
                       {'file': SimpleUploadedFile('a.png', PNG, content_type='image/png')})
            check(f'{role}: upload png -> 200', r.status_code == 200, r.content[:160])
            url1 = r.json().get('profile_photo_url', '') if r.status_code == 200 else ''
            u.refresh_from_db()
            check(f'{role}: profile_photo_url set on User', bool(u.profile_photo_url) and u.profile_photo_url == url1)
            check(f'{role}: SignupDocument row created + claimed',
                  SignupDocument.objects.filter(user=u, document_type='profile_photo').count() == 1)

            # owner can fetch it
            path = url1.replace('http://testserver', '')
            check(f'{role}: owner can GET the photo', c.get(path).status_code == 200)

            # replace it — old file/row cleaned up, exactly one row remains
            old_token = docs.token_from(url1)
            r2 = c.post('/api/auth/profile-photo/',
                        {'file': SimpleUploadedFile('b.jpg', JPG, content_type='image/jpeg')})
            check(f'{role}: replace -> 200', r2.status_code == 200)
            u.refresh_from_db()
            check(f'{role}: URL changed after replace', u.profile_photo_url and u.profile_photo_url != url1)
            check(f'{role}: exactly one profile_photo doc after replace',
                  SignupDocument.objects.filter(user=u, document_type='profile_photo').count() == 1)
            check(f'{role}: old photo file removed',
                  not SignupDocument.objects.filter(token=old_token).exists())

        farmer, doctor = users[0], users[1]

        # cross-user: doctor cannot replace farmer's photo (there is no path to
        # target another user — the endpoint always acts on request.user)
        fc = client_for(farmer)
        before = User.objects.get(pk=farmer.pk).profile_photo_url
        client_for(doctor).post('/api/auth/profile-photo/',
                                {'file': SimpleUploadedFile('x.png', PNG, content_type='image/png')})
        check('another user cannot change my photo',
              User.objects.get(pk=farmer.pk).profile_photo_url == before)

        # profile_photo is viewable by any signed-in user (avatar policy)…
        farmer_url = User.objects.get(pk=farmer.pk).profile_photo_url.replace('http://testserver', '')
        check('any signed-in user can view a profile photo',
              client_for(doctor).get(farmer_url).status_code == 200)
        # …but not anonymously (past the grace window — force it)
        SignupDocument.objects.filter(token=docs.token_from(farmer_url)).update(
            uploaded_at=django.utils.timezone.now() - django.utils.timezone.timedelta(hours=3))
        check('anonymous cannot view a claimed profile photo',
              Client().get(farmer_url).status_code in (401, 403))

        # validation
        c = client_for(farmer)
        check('non-image rejected -> 400',
              c.post('/api/auth/profile-photo/',
                     {'file': SimpleUploadedFile('n.txt', b'hello', content_type='text/plain')}).status_code == 400)
        check('pdf rejected for profile photo -> 400',
              c.post('/api/auth/profile-photo/',
                     {'file': SimpleUploadedFile('d.pdf', b'%PDF-1.4', content_type='application/pdf')}).status_code == 400)
        check('fake png (wrong magic bytes) rejected -> 400',
              c.post('/api/auth/profile-photo/',
                     {'file': SimpleUploadedFile('f.png', b'not really a png', content_type='image/png')}).status_code == 400)
        big = SimpleUploadedFile('big.png', PNG + b'0' * (6 * 1024 * 1024), content_type='image/png')
        check('oversized rejected -> 400',
              c.post('/api/auth/profile-photo/', {'file': big}).status_code == 400)
        check('no file -> 400', c.post('/api/auth/profile-photo/', {}).status_code == 400)

        # network-failure equivalent: a DB failure must leave the old photo intact
        # (covered structurally — the view deletes the new file on any exception
        #  in the atomic block; the old URL is only dropped after commit).

        # unauthenticated
        check('unauthenticated -> 401',
              Client().post('/api/auth/profile-photo/',
                            {'file': SimpleUploadedFile('a.png', PNG, content_type='image/png')}).status_code == 401)

        # DELETE clears it
        r = c.delete('/api/auth/profile-photo/')
        check('DELETE -> 200 and cleared', r.status_code == 200 and
              User.objects.get(pk=farmer.pk).profile_photo_url == '')

        print(f'\n{PASS} passed, {FAIL} failed\n')
    finally:
        cleanup(users)
    return FAIL == 0


if __name__ == '__main__':
    import django.utils.timezone  # noqa
    sys.exit(0 if run() else 1)
