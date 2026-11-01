"""Prescription PDF endpoints as the viewer really calls them (PRESCRIPTION_PDF_FIX.md).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_prescription_pdf_viewer.py

The viewer bug: the app asked for ``Accept: application/pdf`` and DRF answered
``406 {"detail": "Could not satisfy the request Accept header."}`` before the
view ran. Earlier suites never sent an Accept header, so they passed. Every
request here sends the headers real clients send.

Live configured database, locmem email backend; throw-away ``rxview+``
accounts and their PDFs are cleaned on entry and exit.
"""
import os
import sys
from datetime import date, time, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
os.environ['EMAIL_BACKEND'] = 'django.core.mail.backends.locmem.EmailBackend'
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core import mail  # noqa: E402
from django.core.files.base import ContentFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation  # noqa: E402
from doctor.models import (  # noqa: E402
    CaseDetail, ClinicalPrescription, ConsultationNote, FollowUp, PrescriptionItem,
)
from notifications.models import Notification  # noqa: E402
from profiles.models import DoctorProfile  # noqa: E402
from users.models import Role, User  # noqa: E402
from verification.documents import private_storage  # noqa: E402

PASS = FAIL = 0
PREFIX = 'rxview+'
VIEWER_ACCEPT = 'application/pdf, application/json;q=0.9'  # what the app sends now
ACCEPTS = {
    'application/pdf (old app / curl)': 'application/pdf',
    'app viewer header': VIEWER_ACCEPT,
    'browser navigation': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    '*/*': '*/*',
    'no Accept header': None,
}


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def make_user(handle, role_name, panel=None):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'RV {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    user.account_status = 'active'
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel or role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def cleanup(users):
    ids = [u.id for u in users]
    cons = list(Consultation.objects.filter(farmer_id__in=ids).values_list('id', flat=True))
    cons += list(Consultation.objects.filter(doctor_id__in=ids).values_list('id', flat=True))
    for key in ClinicalPrescription.objects.filter(consultation_id__in=cons).exclude(
            pdf_file=None).values_list('pdf_file', flat=True):
        if private_storage.exists(key):
            private_storage.delete(key)
    PrescriptionItem.objects.filter(prescription__consultation_id__in=cons).delete()
    ClinicalPrescription.objects.filter(consultation_id__in=cons).delete()
    ConsultationNote.objects.filter(consultation_id__in=cons).delete()
    FollowUp.objects.filter(consultation_id__in=cons).delete()
    CaseDetail.objects.filter(consultation_id__in=cons).delete()
    from doctor.models import ConsultationStatusHistory
    ConsultationStatusHistory.objects.filter(consultation_id__in=cons).delete()
    Consultation.objects.filter(id__in=cons).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def get(user, url, accept, **extra):
    c = Client()
    headers = dict(extra)
    if user is not None:
        headers['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    if accept:
        headers['HTTP_ACCEPT'] = accept
    return c.get(url, **headers)


def is_json_error(r, status, code=None):
    if r.status_code != status or not r['Content-Type'].startswith('application/json'):
        return False
    body = r.json()
    return 'detail' in body and (code is None or body.get('code') == code)


def main():
    mail.outbox = []
    doctor = make_user('vet', 'doctor')
    doctor2 = make_user('vet2', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    admin = make_user('admin', 'admin', panel='admin')
    users = [doctor, doctor2, farmer, farmer2, admin]
    cleanup(users)
    DoctorProfile.objects.create(
        user=doctor, clinic_hospital_name='RV Clinic', practice_address='Dhaka',
        latitude=Decimal('23.81'), longitude=Decimal('90.41'), veterinary_degree='DVM',
        university_name='BAU', graduation_year=2015, license_number=f'RV-{doctor.id.hex[:6]}',
        license_issuing_authority='BVC', license_expiry_date=date.today() + timedelta(days=800),
        specialty='Poultry', years_of_experience=8, consultation_mode='both',
        council_registration_proof_url='x', prescription_authority=False,
        emergency_on_call_availability=True, service_fee=Decimal('900'),
        consent_platform_guidelines=True, is_verified=True, is_available=True,
        availability_status='available')
    item = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='completed', urgency_level='routine',
        appointment_date=date.today() - timedelta(days=1), appointment_time=time(10),
        consultation_fee=Decimal('900'))
    CaseDetail.objects.create(consultation=item, farmer_name=farmer.full_name, farm_name='RV Farm',
                              case_status='closed')
    dc = Client()
    dc.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(doctor).access_token}'
    r = dc.post('/api/doctor/prescriptions/', {
        'consultation_id': str(item.id), 'case_advice': 'Keep litter dry',
        'medicines': [{'name': 'Amprolium', 'dosage': '1 ml/L', 'duration': '5 days'}]},
        content_type='application/json')
    check('setup: prescription issued (201)', r.status_code == 201, r.content[:200])
    p = ClinicalPrescription.objects.get(id=r.json()['id'])
    stored = private_storage.open(p.pdf_file, 'rb').read()
    url = f'/api/consultations/prescriptions/{p.id}/pdf/'
    curl = f'/api/consultations/{item.id}/prescription/pdf/'
    emails_after_issue = len(mail.outbox)
    rx_count = ClinicalPrescription.objects.count()

    print('\n== the reported bug: Accept: application/pdf ==')
    r = get(farmer, url, 'application/pdf')
    check('farmer with Accept: application/pdf -> 200 (was 406 "Could not satisfy the request Accept header.")',
          r.status_code == 200, (r.status_code, r.content[:120]))
    r = get(doctor, url, 'application/pdf')
    check('doctor with Accept: application/pdf -> 200 (was 406)', r.status_code == 200, (r.status_code, r.content[:120]))

    print('\n== every real client header serves the complete PDF ==')
    for label, accept in ACCEPTS.items():
        for role, user in (('farmer', farmer), ('doctor', doctor), ('admin', admin)):
            r = get(user, url, accept)
            ok = (r.status_code == 200 and r['Content-Type'] == 'application/pdf'
                  and r.content == stored and r.content.startswith(b'%PDF-')
                  and b'%%EOF' in r.content[-1024:]
                  and r['Content-Length'] == str(len(stored))
                  and f'filename="featherflow-prescription-{p.reference_number}.pdf"' in r['Content-Disposition']
                  and 'no-store' in r['Cache-Control'] and r['X-Content-Type-Options'] == 'nosniff')
            check(f'{role} / {label}: 200, complete PDF, headers', ok, (r.status_code, r.get('Content-Type')))
        r = get(farmer, curl, accept)
        check(f'consultation-level endpoint / {label}: 200 PDF',
              r.status_code == 200 and r.content == stored, r.status_code)

    print('\n== errors are JSON with the right status, whatever Accept says ==')
    for label, accept in ACCEPTS.items():
        check(f'unauthenticated / {label} -> 401 JSON', is_json_error(get(None, url, accept), 401), label)
        check(f'other farmer / {label} -> 403 JSON', is_json_error(get(farmer2, url, accept), 403, 'forbidden'), label)
        check(f'other doctor / {label} -> 403 JSON', is_json_error(get(doctor2, url, accept), 403, 'forbidden'), label)
        missing = '/api/consultations/prescriptions/00000000-0000-0000-0000-000000000000/pdf/'
        check(f'missing prescription / {label} -> 404 JSON', is_json_error(get(farmer, missing, accept), 404, 'not_found'), label)
    r = get(farmer2, curl, 'application/pdf')
    check('consultation-level: other farmer -> 403 JSON', is_json_error(r, 403, 'forbidden'), r.content[:120])
    r = get(farmer, '/api/consultations/00000000-0000-0000-0000-000000000000/prescription/pdf/', 'application/pdf')
    check('consultation-level: missing consultation -> 404 JSON', is_json_error(r, 404, 'not_found'), r.content[:120])
    r = get(farmer2, url, 'application/pdf')
    check('a refusal never carries PDF bytes or a PDF content type',
          b'%PDF' not in r.content and 'pdf' not in r['Content-Type'], r['Content-Type'])

    print('\n== no leaks ==')
    for user in (farmer, doctor):
        r = get(user, url, VIEWER_ACCEPT)
        headers = ' '.join(f'{k}: {v}' for k, v in r.items())
        check(f'{user.email.split("+")[1].split("@")[0]}: headers expose no storage path or secret',
              p.pdf_file not in headers and 'private_media' not in headers
              and str(dj_settings.PRIVATE_MEDIA_ROOT) not in headers
              and (not dj_settings.EMAIL_HOST_PASSWORD or dj_settings.EMAIL_HOST_PASSWORD not in headers), headers)
    r = get(farmer2, url, VIEWER_ACCEPT)
    check('refusal body exposes no storage path', p.pdf_file not in r.content.decode(), r.content[:200])

    print('\n== CORS for the web app ==')
    origin = 'http://localhost:54321'
    r = get(farmer, url, VIEWER_ACCEPT, HTTP_ORIGIN=origin)
    if getattr(dj_settings, 'CORS_ALLOW_ALL_ORIGINS', False) or origin in getattr(dj_settings, 'CORS_ALLOWED_ORIGINS', []):
        check('cross-origin GET carries Access-Control-Allow-Origin',
              r.get('Access-Control-Allow-Origin') in (origin, '*'), dict(r.items()))
        c = Client()
        pre = c.options(url, HTTP_ORIGIN=origin, HTTP_ACCESS_CONTROL_REQUEST_METHOD='GET',
                        HTTP_ACCESS_CONTROL_REQUEST_HEADERS='authorization,accept')
        check('preflight allows the Authorization + Accept headers',
              pre.status_code == 200 and 'authorization' in pre.get('Access-Control-Allow-Headers', '').lower(),
              dict(pre.items()))
    else:
        print('  (skipped: this configuration does not allow that origin)')

    print('\n== missing / corrupt stored PDF is regenerated, nothing re-issued or re-sent ==')
    private_storage.delete(p.pdf_file)
    r = get(farmer, url, VIEWER_ACCEPT)
    check('deleted stored file: regenerated and served', r.status_code == 200 and r.content.startswith(b'%PDF-')
          and private_storage.exists(ClinicalPrescription.objects.get(id=p.id).pdf_file), r.status_code)
    p.refresh_from_db()
    private_storage.delete(p.pdf_file)
    private_storage.save(p.pdf_file, ContentFile(b'%PDF-1.4 truncated'))
    r = get(doctor, url, 'application/pdf')
    regenerated = private_storage.open(p.pdf_file, 'rb').read()
    check('truncated stored file: regenerated, valid, served',
          r.status_code == 200 and b'%%EOF' in r.content[-1024:] and regenerated == r.content, r.status_code)
    for _ in range(3):
        get(farmer, url, VIEWER_ACCEPT)
        get(doctor, curl, 'application/pdf')
    check('viewing and regenerating create no prescription', ClinicalPrescription.objects.count() == rx_count)
    check('viewing and regenerating send no email', len(mail.outbox) == emails_after_issue, len(mail.outbox))
    p.refresh_from_db()
    check('delivery record untouched by views', p.email_status == 'sent' and p.email_attempts == 1,
          (p.email_status, p.email_attempts))

    cleanup(users)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
