"""Pharmacy panel — medicine image upload regression.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_medicine_images.py

Live DB, `pharmimg+` prefixed throw-away accounts. Idempotent.

Covers the root cause behind "pharmacy staff cannot add medicine images":
the Flutter Add Medicine dialog used to require saving the medicine first
before the image picker would do anything (see
lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart). This
script exercises the actual API surface the fixed dialog calls: create ->
upload -> the image is visible in the medicine's own record, in the farmer
marketplace search, and in the farmer's pharmacy-medicine detail view.
Also covers validation (bad content-type, oversized file), replacing/adding a
second image, and removing an image via the images-array PATCH.
"""
import io
import os
import sys
from datetime import date, timedelta

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from pharmacy.models import PharmacyMedicine  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'pharmimg+'
JSON = 'application/json'
_n = [0]

# A minimal valid 1x1 PNG, so Pillow/whatever validates content-type off the
# real bytes (not just the filename) can't reject it.
_PNG_1PX = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4'
    '890000000a49444154789c6360000002000100b3a8e2760000000049454e44ae'
    '426082'
)


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
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0197{n:07d}', full_name=f'{tag.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def png_file(name='photo.png'):
    return SimpleUploadedFile(name, _PNG_1PX, content_type='image/png')


def run():
    print('\n== Pharmacy medicine image upload ==\n')
    cleanup()

    pharmacy = mk_user('pharmacy', 'pharm')
    farmer = mk_user('farmer', 'farmer')
    pc = client_for(pharmacy)
    fc = client_for(farmer)

    # 1. Create the medicine first (JSON, no image) — mirrors what the
    #    Flutter dialog's create step sends.
    r = pc.post('/api/pharmacy/medicines/', {
        'name': 'Test Broiler Vitamin', 'generic_name': 'Vitamin B-Complex',
        'category': 'vitamin', 'unit': 'bottle', 'price': 250, 'stock_quantity': 40,
        'expiry_date': (date.today() + timedelta(days=365)).isoformat(),
    }, content_type=JSON)
    check('create medicine without image -> 201', r.status_code == 201, r.content[:300])
    medicine_id = r.json()['id']
    check('newly created medicine has no images yet', r.json()['images'] == [])

    # 2. Upload an image right after create (multipart) — this is the step
    #    that used to be unreachable during the create flow.
    r_up = pc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                    {'image': png_file()}, format='multipart')
    check('upload image after create -> 201', r_up.status_code == 201, r_up.content[:300])
    image_url = r_up.json().get('image_url')
    check('response includes a usable image URL', bool(image_url) and image_url.startswith('http'), r_up.content[:300])

    # 3. The medicine record itself now carries the image.
    r_detail = pc.get(f'/api/pharmacy/medicines/{medicine_id}/')
    check('medicine detail includes the uploaded image', image_url in r_detail.json().get('images', []), r_detail.content[:300])

    # 4. Farmer marketplace search and medicine detail both surface the image
    #    (the whole point of uploading it).
    r_search = fc.get('/api/farmers/medicines/search/', {'query': 'Test Broiler Vitamin'})
    hit = next((m for m in r_search.json()['results'] if m['id'] == medicine_id), None)
    check('farmer search finds the medicine', hit is not None, r_search.content[:300])
    check('farmer search result includes the image URL', hit is not None and image_url in hit.get('images', []))

    r_farmer_detail = fc.get(f'/api/farmers/medicines/{medicine_id}/')
    check('farmer medicine detail includes the image URL',
          image_url in r_farmer_detail.json().get('images', []), r_farmer_detail.content[:300])

    # 4b. Regression test for the actual bug the Flutter client had: browsers/
    #     http.MultipartFile.fromBytes with no explicit contentType send the
    #     file part as application/octet-stream, not image/png. The endpoint
    #     used to hard-reject anything that wasn't already `image/*`
    #     (`content_type.startswith('image/')`), so every real upload from the
    #     app 400'd regardless of how reachable the UI was. It now uses
    #     verification.uploads.validate_upload, which falls back to the
    #     extension + a magic-byte sniff, so a correct file with a generic/
    #     missing content-type is accepted.
    octet_stream_file = SimpleUploadedFile('photo3.png', _PNG_1PX, content_type='application/octet-stream')
    r_generic_ct = pc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                            {'image': octet_stream_file}, format='multipart')
    check('a valid PNG with application/octet-stream content-type is accepted '
          '(the exact bug the old Flutter client hit)',
          r_generic_ct.status_code == 201, r_generic_ct.content[:300])

    # 5. A second image is additive (replace/add), not a replacement.
    r_up2 = pc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                     {'image': png_file('photo2.png')}, format='multipart')
    check('second image upload -> 201', r_up2.status_code == 201, r_up2.content[:300])
    check('medicine now has three images', len(r_up2.json()['images']) == 3, r_up2.json())

    # 6. Reject invalid content type.
    bad_file = SimpleUploadedFile('not-an-image.txt', b'hello world', content_type='text/plain')
    r_bad = pc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                     {'image': bad_file}, format='multipart')
    check('non-image content-type is rejected', r_bad.status_code == 400, r_bad.content[:300])

    # 7. Reject oversized file (backend limit is 5 MB).
    oversized = SimpleUploadedFile('big.png', b'\x00' * (6 * 1024 * 1024), content_type='image/png')
    r_big = pc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                     {'image': oversized}, format='multipart')
    check('oversized image is rejected', r_big.status_code == 400, r_big.content[:300])

    # 8. Text-only edit (no image field) must not touch existing images.
    r_edit = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/', {'price': 260}, content_type=JSON)
    check('text-only edit succeeds', r_edit.status_code == 200, r_edit.content[:300])
    check('text-only edit does not drop existing images', len(r_edit.json()['images']) == 3, r_edit.json())

    # 9. Remove one image via the images-array PATCH (what the Flutter
    #    dialog's remove button now calls).
    remaining = [u for u in r_edit.json()['images'] if u != image_url]
    r_remove = pc.patch(f'/api/pharmacy/medicines/{medicine_id}/',
                         {'images': remaining}, content_type=JSON)
    check('remove one image via PATCH -> 200', r_remove.status_code == 200, r_remove.content[:300])
    check('exactly two images remain', len(r_remove.json()['images']) == 2, r_remove.json())
    check('the correct image was removed', image_url not in r_remove.json()['images'])

    # 10. A farmer cannot upload/edit another pharmacy's medicine images.
    other_pharmacy = mk_user('pharmacy', 'otherpharm')
    opc = client_for(other_pharmacy)
    r_cross = opc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                        {'image': png_file()}, format='multipart')
    check('a different pharmacy cannot upload to this medicine (404, scoped by owner)',
          r_cross.status_code == 404, r_cross.content[:300])
    r_farmer_upload = fc.post(f'/api/pharmacy/medicines/{medicine_id}/upload-image/',
                               {'image': png_file()}, format='multipart')
    check('a farmer cannot upload a medicine image (403/401)',
          r_farmer_upload.status_code in (401, 403), r_farmer_upload.content[:300])

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
