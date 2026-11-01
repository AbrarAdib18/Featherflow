"""Prescription authority, PDF and email delivery (DOCTOR_PRESCRIPTION_PDF_EMAIL.md).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_prescription_pdf_email.py

Uses Django's test Client against the *live* configured database with the
locmem email backend (nothing leaves the machine). Throw-away accounts are
prefixed ``rxmail+`` and cleaned on entry and exit; generated PDFs of those
prescriptions are deleted from private storage too.

The doctor here has ``prescription_authority = False`` — exactly like every
real doctor account — which used to block every prescription with
"Prescription authority has not been approved."
"""
import base64
import os
import re
import sys
import threading
import zlib
from datetime import date, time, timedelta
from decimal import Decimal
from smtplib import SMTPAuthenticationError

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
from django.core.mail.backends.base import BaseEmailBackend  # noqa: E402
from django.core.management import call_command  # noqa: E402
from django.db import connection  # noqa: E402
from django.test import Client  # noqa: E402
from django.test.utils import override_settings  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation  # noqa: E402
from doctor.models import (  # noqa: E402
    CaseDetail, ClinicalPrescription, ConsultationNote, ConsultationStatusHistory,
    Conversation, DoctorEarning, FollowUp, Message, PrescriptionItem,
)
from doctor.prescription_pdf import build_prescription_pdf  # noqa: E402
from doctor.prescriptions import deliver_email  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import DoctorProfile  # noqa: E402
from users.models import Role, User  # noqa: E402
from verification.documents import private_storage  # noqa: E402

PASS = FAIL = 0
PREFIX = 'rxmail+'
SECRET = 's3cret-smtp-password'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


class FailingBackend(BaseEmailBackend):
    """An SMTP provider that refuses the login (message includes the password
    the way a careless provider error might)."""

    def send_messages(self, messages):
        raise SMTPAuthenticationError(535, f'auth failed for password {SECRET}'.encode())


def pdf_text(pdf):
    """Text drawn in a ReportLab PDF (its streams are ASCII85 + Flate encoded)."""
    out = []
    for raw in re.findall(rb'stream\r?\n(.*?)endstream', pdf, re.S):
        data = raw.strip()
        try:
            if data.endswith(b'~>'):
                data = base64.a85decode(data[:-2])  # ReportLab omits the leading <~
            out.append(zlib.decompress(data).decode('latin-1'))
        except (ValueError, zlib.error):
            out.append(raw.decode('latin-1', 'ignore'))
    # ReportLab may draw one line as several adjacent runs: (Farm <) Tj (A) Tj …
    joined = re.sub(r'\)\s*Tj\s*\(', '', ' '.join(out))
    return re.sub(r'\\(.)', r'\1', joined)


def make_user(handle, role_name, panel=None, email=None):
    import hashlib
    email = email or f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'RX {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active',
    ))
    user.account_status = 'active'
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel or role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def make_doctor_profile(user, tag, authority):
    return DoctorProfile.objects.create(
        user=user, clinic_hospital_name=f'RX {tag} Clinic', practice_address='Dhaka',
        latitude=Decimal('23.8103'), longitude=Decimal('90.4125'),
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'BVC-{tag}-{user.id.hex[:6]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        prescription_authority=authority, emergency_on_call_availability=True,
        service_fee=Decimal('900.00'), consent_platform_guidelines=True,
        is_verified=True, is_available=True, availability_status='available',
    )


def client_for(user=None):
    c = Client()
    if user is not None:
        c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


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
    ConsultationStatusHistory.objects.filter(consultation_id__in=cons).delete()
    FollowUp.objects.filter(consultation_id__in=cons).delete()
    DoctorEarning.objects.filter(consultation_id__in=cons).delete()
    CaseDetail.objects.filter(consultation_id__in=cons).delete()
    for field in ('participant_one_id__in', 'participant_two_id__in'):
        Message.objects.filter(**{f'conversation__{field}': ids}).delete()
        Conversation.objects.filter(**{field: ids}).delete()
    Payment.objects.filter(reference_id__in=cons).delete()
    Consultation.objects.filter(id__in=cons).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def consultation(farmer, doctor, status='completed', days=-1, hour=10, farm='Green Valley Layers'):
    item = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status=status, urgency_level='routine',
        appointment_date=date.today() + timedelta(days=days), appointment_time=time(hour, 0),
        consultation_fee=Decimal('900.00'))
    CaseDetail.objects.create(
        consultation=item, farmer_name=farmer.full_name, farm_name=farm, breed='Sonali',
        flock_count=800, bird_age='6 weeks', symptoms_description='Wet droppings', case_status='closed')
    ConsultationNote.objects.create(consultation=item, doctor=doctor, diagnosis='Early coccidiosis',
                                    treatment_plan='Amprolium course')
    return item


RX = {
    'case_advice': 'Keep litter dry; isolate weak birds; clean drinkers daily.',
    'dosage_notes': 'Mix fresh every morning.',
    'follow_up_instructions': 'Send a droppings photo on day 3.',
    'medicines': [
        {'name': 'Amprolium 20%', 'dosage': '1 ml / L', 'duration': '5 days', 'notes': 'In drinking water'},
        {'name': 'Vitamin AD3E', 'dosage': '1 ml / 2 L', 'duration': '3 days', 'notes': ''},
    ],
}


def main():
    mail.outbox = []
    doctor = make_user('vet', 'doctor')
    doctor2 = make_user('vet2', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    noemail = make_user('noemail', 'farmer')
    admin = make_user('admin', 'admin', panel='admin')
    users = [doctor, doctor2, farmer, farmer2, noemail, admin]
    cleanup(users)
    make_doctor_profile(doctor, 'a', authority=False)
    make_doctor_profile(doctor2, 'b', authority=None)
    dc, d2, fc, f2, ac, anon = (client_for(doctor), client_for(doctor2), client_for(farmer),
                                client_for(farmer2), client_for(admin), client_for())

    def prescribe(client, cons, **extra):
        return client.post('/api/doctor/prescriptions/', {'consultation_id': str(cons.id), **RX, **extra},
                           content_type='application/json')

    item = consultation(farmer, doctor)
    fu_date = date.today() + timedelta(days=9)

    # ── authority / eligibility ──────────────────────────────────────────────
    print('\n== prescription authority no longer blocks the assigned doctor ==')
    check('doctor really has prescription_authority = False',
          DoctorProfile.objects.get(user=doctor).prescription_authority is False)
    check('another doctor cannot prescribe for this case (404)', prescribe(d2, item).status_code == 404)
    check('farmer cannot prescribe (403)', prescribe(fc, item).status_code == 403)
    check('unauthenticated cannot prescribe (401)', prescribe(anon, item).status_code == 401)
    r = d2.post('/api/doctor/prescriptions/', {'consultation_id': '00000000-0000-0000-0000-000000000000', **RX},
                content_type='application/json')
    check('nonexistent consultation -> 404 structured', r.status_code == 404 and r.json().get('code') == 'not_found', r.content[:200])
    open_item = consultation(farmer, doctor, status='accepted', days=3)
    r = prescribe(dc, open_item)
    check('not-yet-completed consultation -> 409 consultation_not_completed',
          r.status_code == 409 and r.json().get('code') == 'consultation_not_completed', r.content[:200])
    check('refused requests wrote nothing and sent nothing',
          not ClinicalPrescription.objects.filter(consultation__in=[item, open_item]).exists() and not mail.outbox)

    print('\n== validation ==')
    r = dc.post('/api/doctor/prescriptions/', {'consultation_id': str(item.id), 'medicines': RX['medicines']},
                content_type='application/json')
    check('missing case advice -> 400 with field error', r.status_code == 400 and 'case_advice' in r.json().get('errors', {}), r.content[:200])
    r = prescribe(dc, item, medicines=[{'name': 'X', 'dosage': '', 'duration': '1 day'}])
    check('medicine without dosage -> 400', r.status_code == 400 and 'medicines' in r.json().get('errors', {}), r.content[:200])
    r = prescribe(dc, item, medicines=[{'name': 'X', 'dosage': 'd' * 101, 'duration': '1 day'}])
    check('over-long dosage -> 400 (was a 500 from the DB)', r.status_code == 400, r.status_code)
    r = prescribe(dc, item, medicines=[{'name': 'X', 'dosage': '1', 'duration': '1'}] * 31)
    check('more than 30 medicines -> 400', r.status_code == 400, r.status_code)
    check('invalid submissions created no prescription', not ClinicalPrescription.objects.filter(consultation=item).exists())

    # ── issue ────────────────────────────────────────────────────────────────
    print('\n== issue: persisted, PDF stored, emailed once ==')
    mail.outbox = []
    r = prescribe(dc, item, follow_up_date=fu_date.isoformat(), follow_up_time='15:30')
    check('assigned doctor without authority -> 201', r.status_code == 201, r.content[:300])
    row = r.json()
    p = ClinicalPrescription.objects.get(id=row['id'])
    items = list(PrescriptionItem.objects.filter(prescription=p).order_by('medicine_name'))
    check('prescription persisted with advice / dosage notes / follow-up instructions',
          p.case_advice == RX['case_advice'] and p.dosage_notes == RX['dosage_notes']
          and p.follow_up_instructions == RX['follow_up_instructions'] and p.doctor_id == doctor.id)
    check('medicines persisted (name, dosage, duration, instructions)',
          [(x.medicine_name, x.dosage, x.duration, x.instructions) for x in items]
          == [('Amprolium 20%', '1 ml / L', '5 days', 'In drinking water'),
              ('Vitamin AD3E', '1 ml / 2 L', '3 days', '')], [(x.medicine_name, x.instructions) for x in items])
    check('stable reference RX-YYYYMMDD-XXXXXXXX stored',
          re.fullmatch(r'RX-\d{8}-[0-9A-F]{8}', p.reference_number or '') is not None
          and p.reference_number == f'RX-{date.today():%Y%m%d}-{p.id.hex[:8].upper()}', p.reference_number)
    check('follow-up stored with exact time',
          FollowUp.objects.filter(consultation=item, status='pending', scheduled_date=fu_date,
                                  scheduled_time=time(15, 30)).count() == 1)
    check('PDF stored in private storage (not MEDIA_ROOT), path recorded',
          bool(p.pdf_file) and private_storage.exists(p.pdf_file) and p.pdf_generated_at is not None
          and 'private_media' in private_storage.path(p.pdf_file)
          and str(dj_settings.MEDIA_ROOT) not in private_storage.path(p.pdf_file), p.pdf_file)
    check('API row never exposes the storage path', 'pdf_file' not in row and p.pdf_file not in str(row))
    check('response carries delivery state', row.get('email_status') == 'sent'
          and row.get('reference_number') == p.reference_number and row.get('pdf_available') is True, row)
    check('farmer notified in-app', Notification.objects.filter(
        user=farmer, title='Prescription added', reference_type='prescription').count() == 1)

    check('exactly one email', len(mail.outbox) == 1, len(mail.outbox))
    msg = mail.outbox[0]
    stored_pdf = private_storage.open(p.pdf_file, 'rb').read()
    check('recipient is the farmer\'s registered email', msg.to == [farmer.email], msg.to)
    check('subject "Your prescription from Dr. … – FeatherFlow"',
          msg.subject == f'Your prescription from Dr. {doctor.full_name} – FeatherFlow', msg.subject)
    att = msg.attachments[0] if msg.attachments else (None, b'', None)
    check('PDF attached (name, type, same bytes as the stored PDF)',
          att[0] == f'featherflow-prescription-{p.reference_number}.pdf' and att[2] == 'application/pdf'
          and att[1] == stored_pdf, att[0])
    body = msg.body
    check('body: greeting, doctor, farm, date, reference, open-the-PDF',
          f'Dear {farmer.full_name}' in body and f'Dr. {doctor.full_name}' in body
          and 'Green Valley Layers' in body and date.today().strftime('%d %b %Y') in body
          and p.reference_number in body and 'attached PDF' in body, body)
    check('body carries no medical detail, links, tokens or paths',
          not any(x in body for x in ('Amprolium', 'coccidiosis', '/api/', 'private_media', 'token', 'http')), body)
    p.refresh_from_db()
    check('delivery persisted: sent, recipient, 1 attempt, timestamps, message id',
          p.email_status == 'sent' and p.email_recipient == farmer.email and p.email_attempts == 1
          and p.email_sent_at and p.email_last_attempt_at and p.email_error is None
          and p.email_message_id and p.email_message_id == msg.extra_headers.get('Message-ID'),
          (p.email_status, p.email_attempts, p.email_message_id))

    # ── PDF content ──────────────────────────────────────────────────────────
    print('\n== PDF content (from persisted records) ==')
    text = pdf_text(stored_pdf)
    for label, needle in (('FeatherFlow header', 'FeatherFlow'), ('reference', p.reference_number),
                          ('date', date.today().strftime('%d %b %Y')), ('doctor name', f'Dr. {doctor.full_name}'),
                          ('doctor qualification', 'DVM'), ('licence', 'BVC-a-'),
                          ('farmer name', farmer.full_name), ('farm name', 'Green Valley Layers'),
                          ('diagnosis', 'Early coccidiosis'), ('medicine', 'Amprolium 20%'),
                          ('dosage', '1 ml / L'), ('duration', '5 days'), ('instructions', 'In drinking water'),
                          ('case advice', 'isolate weak birds'), ('dosage notes', 'Mix fresh every morning'),
                          ('follow-up instructions', 'droppings photo on day 3'),
                          ('follow-up date/time', fu_date.strftime('%d %b %Y') + ' at 03:30 PM'),
                          ('signature line', 'Issued electronically on'), ('generation timestamp', 'Generated')):
        check(f'PDF shows {label}', needle in text, needle)

    print('\n== PDF robustness ==')
    from types import SimpleNamespace
    bare = SimpleNamespace(id='x', doctor=None, consultation=None, items=None, case_advice=None,
                           dosage_notes='', follow_up_instructions=None, referred_to=None)
    check('empty optional fields: still a PDF', build_prescription_pdf(bare).startswith(b'%PDF-'))
    long_rx = consultation(farmer, doctor, days=-2, farm='Farm <A&B> "Ltd"')
    r = prescribe(dc, long_rx, case_advice='Very long advice. ' * 270, dosage_notes='',
                  follow_up_instructions='',
                  medicines=[{'name': f'Medicine <{i}> & co ' + 'x' * 100, 'dosage': 'd' * 100,
                              'duration': 'u' * 50, 'notes': 'n ' * 900} for i in range(30)])
    check('30 long medicines + 5000-char advice + markup characters -> 201', r.status_code == 201, r.content[:200])
    long_p = ClinicalPrescription.objects.get(id=r.json()['id'])
    long_pdf = private_storage.open(long_p.pdf_file, 'rb').read()
    pages = len(re.findall(rb'/Type /Page[^s]', long_pdf))
    check('long prescription paginates (multi-page PDF)', pages >= 3, pages)
    check('markup characters printed literally, not parsed', 'Farm <A&B> "Ltd"' in pdf_text(long_pdf))

    # ── PDF access ───────────────────────────────────────────────────────────
    print('\n== PDF access control ==')
    url = f'/api/consultations/prescriptions/{p.id}/pdf/'
    r = fc.get(url)
    check('farmer gets the PDF (200, application/pdf, inline filename, no-store)',
          r.status_code == 200 and r['Content-Type'] == 'application/pdf'
          and f'filename="featherflow-prescription-{p.reference_number}.pdf"' in r['Content-Disposition']
          and 'no-store' in r['Cache-Control'] and r.content == stored_pdf, r.status_code)
    check('assigned doctor gets the PDF', dc.get(url).status_code == 200)
    check('admin reviewer gets the PDF (private-document policy)', ac.get(url).status_code == 200)
    r = f2.get(url)
    check('another farmer -> 403 structured', r.status_code == 403 and r.json().get('code') == 'forbidden', r.status_code)
    check('another doctor -> 403', d2.get(url).status_code == 403)
    check('unauthenticated -> 401', anon.get(url).status_code == 401)
    r = fc.get('/api/consultations/prescriptions/00000000-0000-0000-0000-000000000000/pdf/')
    check('missing prescription -> 404 structured', r.status_code == 404 and r.json().get('code') == 'not_found')
    curl = f'/api/consultations/{item.id}/prescription/pdf/'
    r = fc.get(curl)
    check('consultation-level PDF endpoint serves the latest prescription',
          r.status_code == 200 and r.content == stored_pdf, r.status_code)
    check('consultation-level: another farmer -> 403', f2.get(curl).status_code == 403)
    check('consultation-level: unauthenticated -> 401', anon.get(curl).status_code == 401)
    r = fc.get(f'/api/consultations/{open_item.id}/prescription/pdf/')
    check('consultation without prescription -> 404 no_prescription',
          r.status_code == 404 and r.json().get('code') == 'no_prescription', r.content[:200])
    check('PDF is not reachable as a public media file',
          anon.get(f'/media/{p.pdf_file}').status_code == 404 and fc.get(f'/media/{p.pdf_file}').status_code == 404)

    # ── no duplicate emails ──────────────────────────────────────────────────
    print('\n== views, fetches and retries never duplicate a sent email ==')
    mail.outbox = []
    fc.get(url); fc.get(curl); dc.get(url)
    fc.get('/api/consultations/'); fc.get(f'/api/consultations/{item.id}/clinical-results/')
    dc.get('/api/doctor/prescriptions/'); dc.get('/api/doctor/cases/')
    check('PDF views and list/detail fetches send nothing', mail.outbox == [], len(mail.outbox))
    check('automatic delivery of a sent prescription is a no-op',
          deliver_email(p.id) == 'sent' and mail.outbox == [])
    call_command('retry_prescription_emails', stdout=open(os.devnull, 'w'))
    p.refresh_from_db()
    check('retry command skips sent prescriptions', mail.outbox == [] and p.email_attempts == 1, p.email_attempts)

    # ── farmer visibility ────────────────────────────────────────────────────
    print('\n== farmer sees the prescription ==')
    rows = fc.get('/api/consultations/').json()
    rows = rows if isinstance(rows, list) else rows.get('consultations', rows.get('results', []))
    mine = next((x for x in rows if x['id'] == str(item.id)), {})
    rx_row = (mine.get('prescriptions') or [{}])[0]
    check('consultation row: reference, doctor, date, medicines, advice, email status',
          rx_row.get('reference_number') == p.reference_number
          and rx_row.get('doctor_name') == f'Dr. {doctor.full_name}'
          and (rx_row.get('issued_at') or '').endswith('+00:00')
          and len(rx_row.get('medicines', [])) == 2 and rx_row.get('case_advice') == RX['case_advice']
          and rx_row.get('email_status') == 'sent' and 'pdf_file' not in rx_row, rx_row)
    check('follow-up date/time visible to the farmer',
          any(f['scheduled_date'] == fu_date.isoformat() and f['scheduled_time'] == '15:30'
              for f in mine.get('follow_ups', [])), mine.get('follow_ups'))
    r = fc.get(f'/api/consultations/{item.id}/clinical-results/')
    check('clinical results carry the same prescription',
          r.status_code == 200 and r.json()['prescriptions'][0]['reference_number'] == p.reference_number)
    check("another farmer can't read these clinical results (404)",
          f2.get(f'/api/consultations/{item.id}/clinical-results/').status_code == 404)

    # ── SMTP failure ─────────────────────────────────────────────────────────
    print('\n== SMTP failure does not roll back; retry delivers once ==')
    failing = consultation(farmer, doctor, days=-3)
    mail.outbox = []
    with override_settings(EMAIL_BACKEND='__main__.FailingBackend', EMAIL_HOST_PASSWORD=SECRET):
        r = prescribe(dc, failing)
    check('prescription still 201 when SMTP fails', r.status_code == 201, r.content[:200])
    fp = ClinicalPrescription.objects.get(id=r.json()['id'])
    check('prescription, medicines, PDF and notification all kept',
          PrescriptionItem.objects.filter(prescription=fp).count() == 2 and fp.pdf_file
          and private_storage.exists(fp.pdf_file)
          and Notification.objects.filter(user=farmer, title='Prescription added').count() == 3)
    check('delivery recorded as failed with the provider error',
          fp.email_status == 'failed' and fp.email_attempts == 1 and 'SMTPAuthenticationError' in (fp.email_error or ''),
          (fp.email_status, fp.email_error))
    check('stored error and API row contain no secret',
          SECRET not in (fp.email_error or '') and SECRET not in r.content.decode()
          and SECRET not in dc.get('/api/doctor/prescriptions/').content.decode())
    check('nothing was delivered', mail.outbox == [])
    out = []

    class Sink:
        def write(self, text):
            out.append(text)

        def flush(self):
            pass

    call_command('retry_prescription_emails', '--dry-run', stdout=Sink())
    check('dry run lists the failed one, sends nothing',
          fp.reference_number in ''.join(out) and mail.outbox == [], ''.join(out))
    call_command('retry_prescription_emails', stdout=Sink())
    fp.refresh_from_db()
    check('retry command delivers it: sent, attempt 2, one email',
          fp.email_status == 'sent' and fp.email_attempts == 2 and len(mail.outbox) == 1
          and mail.outbox[0].attachments[0][1] == private_storage.open(fp.pdf_file, 'rb').read(),
          (fp.email_status, fp.email_attempts, len(mail.outbox)))
    call_command('retry_prescription_emails', stdout=Sink())
    check('re-running the retry command sends nothing more', len(mail.outbox) == 1)

    # ── concurrent retries ───────────────────────────────────────────────────
    print('\n== concurrent retries of one failed email -> one email ==')
    race = consultation(farmer, doctor, days=-4)
    with override_settings(EMAIL_BACKEND='__main__.FailingBackend', EMAIL_HOST_PASSWORD=SECRET):
        rp = ClinicalPrescription.objects.get(id=prescribe(dc, race).json()['id'])
    mail.outbox = []
    barrier = threading.Barrier(4)
    results = []

    def racer():
        try:
            barrier.wait()
            results.append(deliver_email(rp.id))
        finally:
            connection.close()

    threads = [threading.Thread(target=racer) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    rp.refresh_from_db()
    check('4 simultaneous retries -> exactly one email, two attempts total',
          len(mail.outbox) == 1 and rp.email_status == 'sent' and rp.email_attempts == 2,
          (len(mail.outbox), results, rp.email_attempts))

    # ── deliberate resend + no email on file ─────────────────────────────────
    print('\n== deliberate resend and missing farmer email ==')
    mail.outbox = []
    resend = f'/api/doctor/prescriptions/{p.id}/resend-email/'
    check('another doctor cannot resend (404)', d2.post(resend).status_code == 404)
    check('farmer cannot resend (403)', fc.post(resend).status_code == 403)
    r = dc.post(resend)
    check('prescribing doctor\'s deliberate resend sends one email',
          r.status_code == 200 and r.json()['email_status'] == 'sent' and len(mail.outbox) == 1
          and r.json()['email_attempts'] == 2, r.content[:200])
    User.objects.filter(id=noemail.id).update(email=f'{PREFIX}noemail-removed@featherflow.dev')
    nocons = consultation(noemail, doctor, days=-5)
    User.objects.filter(id=noemail.id).update(email='')
    mail.outbox = []
    r = prescribe(dc, nocons)
    np_ = ClinicalPrescription.objects.get(id=r.json()['id']) if r.status_code == 201 else None
    check('farmer without email: prescription 201, delivery failed with a clear reason, no email',
          np_ is not None and np_.email_status == 'failed' and 'no email address' in (np_.email_error or '')
          and mail.outbox == [], (r.status_code, np_ and np_.email_error))
    User.objects.filter(id=noemail.id).update(email=f'{PREFIX}noemail@featherflow.dev')

    cleanup(users)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
