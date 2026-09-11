"""End-to-end check of the disease-detection ML endpoint.

    backend/venv/Scripts/python.exe backend/scripts/test_disease_detection.py

Runs Django's test client against the live DB. Loads the real EfficientNet
checkpoint (currently b0) on the first predict call, so the first run takes
~10-15s. Creates a
throw-away farmer (``diseasetest+…``) and leaves it; re-running is idempotent.
"""
import io
import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('THROTTLE_DISEASE_PREDICT', '1000/hour')
django.setup()

from datetime import date  # noqa: E402

from django.conf import settings as dj_settings  # noqa: E402
from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from PIL import Image  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from users.models import Role, User  # noqa: E402

if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

PASS, FAIL = 0, 0


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def jpeg_bytes(color=(150, 110, 70), size=(400, 400)):
    buf = io.BytesIO()
    Image.new('RGB', size, color).save(buf, 'JPEG')
    return buf.getvalue()


def farmer():
    role = Role.objects.get(name='farmer')
    u, _ = User.objects.get_or_create(email='diseasetest+farmer@featherflow.dev', defaults=dict(
        full_name='Disease Test Farmer', phone='+8801700990011',
        date_of_birth=date(1990, 1, 1), present_address='Test', consent_terms=True,
        account_status='active'))
    u.account_status = 'active'
    u.set_password('Testpass!2026')
    u.save()
    u.roles.add(role)
    return u


def auth(client, user):
    token = str(RefreshToken.for_user(user).access_token)
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'


def main():
    c = Client()
    user = farmer()
    auth(c, user)

    print('\n== health ==')
    r = c.get('/api/ml/health/')
    check('health 200', r.status_code == 200, r.content[:200])
    body = r.json()
    check('checkpoint present', body.get('checkpoint_present') is True, body)
    check('threshold exposed', isinstance(body.get('confidence_threshold'), float), body)

    print('\n== predict: valid image ==')
    img = SimpleUploadedFile('bird.jpg', jpeg_bytes(), content_type='image/jpeg')
    r = c.post('/api/ml/predict-disease/', {'image': img})
    check('predict 201', r.status_code == 201, r.content[:300])
    p = r.json()
    scan_id = p.get('scan_id')
    check('has scan_id', bool(scan_id), p)
    check('has a disease label', bool(p.get('disease')), p)
    check('confidence in 0..1', 0.0 <= (p.get('confidence') or -1) <= 1.0, p)
    check('severity valid', p.get('severity') in (None, 'low', 'medium', 'high', 'critical'), p)
    check('urgency valid', p.get('urgency') in ('urgent', 'routine'), p)
    check('recommendations is a non-empty list',
          isinstance(p.get('recommendations'), list) and p['recommendations'], p)
    check('avoid is a list', isinstance(p.get('avoid'), list), p)
    check('all_predictions has 5', len(p.get('all_predictions') or []) == 5, p)
    check('disclaimer present', 'vet' in (p.get('disclaimer') or '').lower(), p)
    check('text is clean ascii',
          all(ord(ch) < 128 for ch in ' '.join(p.get('recommendations', []))), p)

    print('\n== validation / errors ==')
    r = c.post('/api/ml/predict-disease/', {})
    check('no file -> 400', r.status_code == 400, r.content[:120])
    bad = SimpleUploadedFile('x.txt', b'not an image', content_type='text/plain')
    r = c.post('/api/ml/predict-disease/', {'image': bad})
    check('non-image -> 400', r.status_code == 400, r.content[:120])
    fake = SimpleUploadedFile('x.jpg', b'\xff\xd8notjpeg', content_type='image/jpeg')
    r = c.post('/api/ml/predict-disease/', {'image': fake})
    check('corrupt image -> 400', r.status_code == 400, r.content[:120])
    big = SimpleUploadedFile('big.jpg', b'0' * (6 * 1024 * 1024), content_type='image/jpeg')
    r = c.post('/api/ml/predict-disease/', {'image': big})
    check('oversize -> 400', r.status_code == 400, r.content[:120])

    print('\n== auth ==')
    anon = Client()
    r = anon.post('/api/ml/predict-disease/', {'image': SimpleUploadedFile(
        'b.jpg', jpeg_bytes(), content_type='image/jpeg')})
    check('unauthenticated -> 401', r.status_code == 401, r.content[:120])

    print('\n== scans history ==')
    r = c.get('/api/ml/scans/?limit=5')
    check('scans 200', r.status_code == 200, r.content[:200])
    rows = r.json().get('results', [])
    check('history has our scan', any(x['scan_id'] == scan_id for x in rows), len(rows))
    check('history hides failed scans', all(x['status'] == 'completed' for x in rows), rows)
    ours = next((x for x in rows if x['scan_id'] == scan_id), None)
    check('history row carries advice',
          ours is not None and isinstance(ours.get('recommendations'), list), ours)

    r = c.get(f'/api/ml/scans/{scan_id}/')
    check('scan detail 200', r.status_code == 200, r.content[:200])
    r = c.get('/api/ml/scans/00000000-0000-0000-0000-000000000000/')
    check('missing scan -> 404', r.status_code == 404, r.content[:120])

    print('\n== disease reference ==')
    ref_id = next((x['disease_ref_id'] for x in rows if x.get('disease_ref_id')), None)
    if ref_id:
        r = c.get(f'/api/ml/diseases/{ref_id}/')
        check('disease ref 200', r.status_code == 200, r.content[:200])
        d = r.json()
        check('ref has symptoms + avoid',
              isinstance(d.get('symptoms'), list) and isinstance(d.get('avoid'), list), d)
    else:
        print('  --   (no non-healthy prediction to check a reference card)')

    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
