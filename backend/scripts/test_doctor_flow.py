"""End-to-end check of the Doctor Panel + its cross-panel wiring.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_doctor_flow.py

Uses Django's test Client against the *live* configured database (needs
featherflow_schema.sql + postgres_backend_extension.sql applied). Creates
throw-away accounts prefixed ``doctortest+`` and cleans its own rows on entry.
Idempotent.

Covers the full loop: farmer discovers a vet -> books -> doctor accepts (chat
opens) -> case notes -> complete -> farmer pays (doctor earning accrues, minus
platform fee) -> clinical results + receipt -> rating (feeds doctor rating) ->
prescription (+PDF) -> follow-up -> earnings summary -> realtime-less chat.
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
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation, ConsultationDispute  # noqa: E402
from doctor.models import (  # noqa: E402
    AvailabilitySlot, CaseDetail, ClinicalPrescription, ConsultationNote,
    ConsultationStatusHistory, Conversation, DoctorEarning, FollowUp, Message,
    PayoutRequest, PrescriptionItem,
)
from farms.models import Farm, Flock  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'doctortest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def make_user(handle, role_name):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'DT {handle.title()}', phone=phone, date_of_birth=date(1988, 3, 3),
        present_address='Rajshahi', consent_terms=True, account_status='active',
    ))
    user.account_status = 'active'
    user.set_password('Testpass!2026')
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def auth(client, user):
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'


def cleanup(users):
    ids = [u.id for u in users]
    cons = list(Consultation.objects.filter(farmer_id__in=ids).values_list('id', flat=True))
    ConsultationDispute.objects.filter(consultation_id__in=cons).delete()
    PrescriptionItem.objects.filter(prescription__consultation_id__in=cons).delete()
    ClinicalPrescription.objects.filter(consultation_id__in=cons).delete()
    ConsultationNote.objects.filter(consultation_id__in=cons).delete()
    ConsultationStatusHistory.objects.filter(consultation_id__in=cons).delete()
    FollowUp.objects.filter(consultation_id__in=cons).delete()
    DoctorEarning.objects.filter(consultation_id__in=cons).delete()
    CaseDetail.objects.filter(consultation_id__in=cons).delete()
    Message.objects.filter(conversation__participant_one_id__in=ids).delete()
    Message.objects.filter(conversation__participant_two_id__in=ids).delete()
    Conversation.objects.filter(participant_one_id__in=ids).delete()
    Conversation.objects.filter(participant_two_id__in=ids).delete()
    Payment.objects.filter(reference_id__in=cons).delete()
    Consultation.objects.filter(id__in=cons).delete()
    PayoutRequest.objects.filter(doctor_id__in=ids).delete()
    AvailabilitySlot.objects.filter(doctor_id__in=ids).delete()
    Flock.objects.filter(farm__farmer__user_id__in=ids).delete()
    Farm.objects.filter(farmer__user_id__in=ids).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def main():
    c = Client()
    doctor = make_user('vet', 'doctor')
    farmer = make_user('farmer', 'farmer')
    cleanup([doctor, farmer])

    # ── doctor profile: verified, available, both modes, prescription rights ──
    DoctorProfile.objects.create(
        user=doctor, clinic_hospital_name='DT Poultry Clinic', practice_address='Rajshahi Sadar',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'DT-LIC-{doctor.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        prescription_authority=True, emergency_on_call_availability=True, service_fee=Decimal('2000.00'),
        consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
    )
    fp = FarmerProfile.objects.create(
        user=farmer, farm_name='DT Farm', owner_name='DT Farmer',
        farm_location='Paba', farm_address='Paba, Rajshahi', farm_type='broiler',
        consent_data_collection=True,
    )
    farm = Farm.objects.create(
        farmer=fp, farm_name='DT Farm', farm_type='broiler', location='Paba', address='Paba, Rajshahi', is_active=True)

    appt_date = date.today() + timedelta(days=7)
    AvailabilitySlot.objects.create(
        doctor=doctor, weekday=appt_date.weekday(), start_time=time(9, 0), end_time=time(17, 0), mode='online')
    AvailabilitySlot.objects.create(
        doctor=doctor, weekday=(appt_date + timedelta(days=1)).weekday(),
        start_time=time(9, 0), end_time=time(17, 0), mode='online')

    print('\n== farmer discovery ==')
    auth(c, farmer)
    r = c.get('/api/consultations/vets/')
    check('vets list 200', r.status_code == 200, r.content[:200])
    row = next((d for d in r.json()['doctors'] if d['user_id'] == str(doctor.id)), None)
    check('our vet is discoverable & verified', row and row['verified'] and row['available'], row)
    doctor_profile_id = row['id']
    r = c.get(f'/api/consultations/vets/{doctor_profile_id}/')
    check('vet detail 200 + slots', r.status_code == 200 and len(r.json()['availability_slots']) >= 1, r.content[:200])
    r = c.get(f'/api/consultations/vets/{doctor_profile_id}/booking-options/',
              {'date': appt_date.isoformat(), 'mode': 'online'})
    check('booking-options lists farm + times', r.status_code == 200
          and any(f['name'] == 'DT Farm' for f in r.json()['farms'])
          and '10:00' in r.json().get('available_times', []), r.content[:300])

    print('\n== farmer books ==')
    r = c.post('/api/consultations/', {
        'doctor_id': doctor_profile_id, 'farm_id': str(farm.id), 'mode': 'online',
        'urgency': 'moderate', 'appointment_date': appt_date.isoformat(), 'appointment_time': '10:00',
        'symptoms': ['Lethargy', 'Reduced feed intake'], 'bird_age_weeks': 4, 'breed': 'Cobb 500',
        'flock_count': 500, 'mortality_count': 6,
    }, content_type='application/json')
    check('booking 201', r.status_code == 201, r.content[:300])
    consult_id = r.json()['id']
    check('doctor + farmer both notified of request',
          Notification.objects.filter(user=doctor, reference_id=consult_id).exists()
          and Notification.objects.filter(user=farmer, reference_id=consult_id).exists(), 'missing notification')
    r = c.post('/api/consultations/', {
        'doctor_id': doctor_profile_id, 'farm_id': str(farm.id), 'mode': 'online',
        'appointment_date': appt_date.isoformat(), 'appointment_time': '10:00', 'symptoms': ['x'],
        'bird_age_weeks': 4, 'breed': 'x', 'flock_count': 10,
    }, content_type='application/json')
    check('double-booking same slot rejected', r.status_code == 400, r.status_code)

    print('\n== doctor accepts ==')
    auth(c, doctor)
    r = c.get('/api/doctor/dashboard/')
    check('doctor dashboard 200', r.status_code == 200, r.content[:200])
    check('dashboard counts the urgent-ish request', r.json()['summary']['today_appointments'] >= 0)
    r = c.get('/api/doctor/appointments/')
    appt = next(a for a in r.json()['appointments'] if a['id'] == consult_id)
    check('appointment shows as pending', appt['status'] == 'pending', appt['status'])
    r = c.post(f'/api/doctor/appointments/{consult_id}/action/', {'action': 'accept'},
               content_type='application/json')
    check('accept 200 + conversation opened', r.status_code == 200 and r.json().get('conversation_id'), r.content[:300])
    conversation_id = r.json()['conversation_id']
    check('farmer notified of acceptance',
          Notification.objects.filter(user=farmer, title__icontains='accepted').exists(), 'no notify')

    print('\n== doctor writes the case ==')
    r = c.post('/api/doctor/cases/', {
        'consultation_id': consult_id, 'diagnosis': 'Early coccidiosis',
        'treatment_plan': 'Amprolium in water 5 days; improve litter dryness',
        'disease_tags': ['coccidiosis'], 'symptoms': ['Lethargy', 'Reduced feed intake', 'Wet droppings'],
        'status': 'in_progress',
    }, content_type='application/json')
    check('case note saved', r.status_code in (200, 201) and r.json()['diagnosis'] == 'Early coccidiosis', r.content[:300])

    print('\n== prescription is blocked until completion ==')
    r = c.post('/api/doctor/prescriptions/', {
        'consultation_id': consult_id, 'case_advice': 'Treat and re-check in a week',
        'medicines': [{'name': 'Amprolium', 'dosage': '1ml/L', 'duration': '5 days', 'notes': 'in drinking water'}],
    }, content_type='application/json')
    check('prescription before completion -> 409', r.status_code == 409, r.status_code)

    print('\n== doctor completes ==')
    r = c.post(f'/api/doctor/appointments/{consult_id}/action/', {'action': 'complete'},
               content_type='application/json')
    check('complete 200', r.status_code == 200, r.content[:200])
    check('consultation completed + case closed',
          Consultation.objects.get(id=consult_id).status == 'completed'
          and CaseDetail.objects.get(consultation_id=consult_id).case_status == 'closed')
    check('pending cash receipt was created',
          Payment.objects.filter(reference_id=consult_id, status='pending').exists())

    print('\n== farmer results, receipt, payment ==')
    auth(c, farmer)
    r = c.get(f'/api/consultations/{consult_id}/clinical-results/')
    check('clinical results 200 after completion',
          r.status_code == 200 and r.json()['clinical_note']['diagnosis'] == 'Early coccidiosis', r.content[:300])
    r = c.get(f'/api/consultations/{consult_id}/receipt/')
    check('receipt 200', r.status_code == 200, r.content[:200])
    # fee 2000, threshold 1500, rate 5% -> platform 25, net 1975
    check('platform fee only above threshold (2000 -> 25 / net 1975)',
          abs(r.json()['platform_charge'] - 25.0) < 0.01 and abs(r.json()['doctor_net_amount'] - 1975.0) < 0.01,
          r.json())
    r = c.post(f'/api/consultations/{consult_id}/mark-paid/', {}, content_type='application/json')
    check('mark-paid 200', r.status_code == 200 and r.json()['status'] == 'completed', r.content[:200])
    earning = DoctorEarning.objects.filter(consultation_id=consult_id).first()
    check('doctor earning accrued net of platform fee',
          earning and abs(float(earning.net_amount) - 1975.0) < 0.01 and earning.payout_status == 'pending', earning)

    print('\n== farmer rates -> doctor rating updates ==')
    r = c.patch('/api/consultations/', {'id': consult_id, 'rating': 5, 'review': 'Fast and clear advice.'},
                content_type='application/json')
    check('rating 200', r.status_code == 200 and r.json()['rating'] == 5, r.content[:200])
    DoctorProfile.objects.get(user=doctor).refresh_from_db()
    check('doctor profile rating reflects the review',
          float(DoctorProfile.objects.get(user=doctor).rating) == 5.0)

    print('\n== doctor issues prescription (+PDF) + follow-up ==')
    auth(c, doctor)
    fu_date = appt_date + timedelta(days=1)
    r = c.post('/api/doctor/prescriptions/', {
        'consultation_id': consult_id, 'case_advice': 'Re-check flock in 7 days; cull severe cases',
        'dosage_notes': 'Give early morning', 'follow_up_instructions': 'Send droppings photo in 3 days',
        'medicines': [
            {'name': 'Amprolium 20%', 'dosage': '1 ml / L', 'duration': '5 days', 'notes': 'drinking water'},
            {'name': 'Vitamin AD3E', 'dosage': '1 g / L', 'duration': '7 days', 'notes': 'supportive'},
        ],
        'follow_up_date': fu_date.isoformat(), 'follow_up_time': '11:00',
    }, content_type='application/json')
    check('prescription 201', r.status_code == 201 and len(r.json()['medicines']) == 2, r.content[:400])
    presc_id = r.json()['id']
    r = c.get(f'/api/consultations/prescriptions/{presc_id}/pdf/')
    check('prescription PDF renders', r.status_code == 200
          and r['Content-Type'] == 'application/pdf' and r.content[:4] == b'%PDF', r.status_code)
    check('follow-up created + notified',
          FollowUp.objects.filter(consultation_id=consult_id, status='pending').exists()
          and Notification.objects.filter(user=farmer, title__icontains='Follow-up').exists())

    print('\n== earnings summary ==')
    r = c.get('/api/doctor/earnings/')
    check('earnings 200', r.status_code == 200, r.content[:200])
    s = r.json()['summary']
    check('earnings summary nets the platform charge',
          abs(s['gross_amount'] - 2000.0) < 0.01 and abs(s['platform_charge'] - 25.0) < 0.01
          and abs(s['net_amount'] - 1975.0) < 0.01, s)
    check('rating appears in earnings feed', any(x['rating'] == 5.0 for x in r.json()['ratings']))
    r = c.post('/api/doctor/earnings/', {'amount': '1975.00'}, content_type='application/json')
    check('payout request 201', r.status_code == 201, r.content[:200])
    r = c.post('/api/doctor/earnings/', {'amount': '9999.00'}, content_type='application/json')
    check('over-balance payout rejected', r.status_code == 400, r.status_code)

    print('\n== availability CRUD ==')
    r = c.post('/api/doctor/availability/', {'weekday': 2, 'start_time': '08:00', 'end_time': '12:00', 'mode': 'offline'},
               content_type='application/json')
    check('add slot 201', r.status_code == 201, r.content[:200])
    slot_id = r.json()['id']
    r = c.post('/api/doctor/availability/', {'weekday': 2, 'start_time': '09:00', 'end_time': '10:00', 'mode': 'offline'},
               content_type='application/json')
    check('overlapping slot rejected', r.status_code == 409, r.status_code)
    r = c.delete('/api/doctor/availability/', {'id': slot_id}, content_type='application/json')
    check('delete slot 204', r.status_code == 204, r.status_code)

    print('\n== farmer <-> doctor chat (REST, Socket.IO-independent) ==')
    r = c.post(f'/api/doctor/conversations/{conversation_id}/', {'content': 'Please start Amprolium today.'},
               content_type='application/json')
    check('doctor sends message 201', r.status_code == 201, r.content[:200])
    auth(c, farmer)
    r = c.get('/api/consultations/chats/')
    conv = next(x for x in r.json()['conversations'] if x['id'] == conversation_id)
    check('farmer sees the doctor message + unread',
          any(m['content'] == 'Please start Amprolium today.' for m in conv['messages']) and conv['unread_count'] == 1,
          conv)
    r = c.post(f'/api/consultations/chats/{conversation_id}/', {'content': 'Started this morning, thanks.'},
               content_type='application/json')
    check('farmer replies over REST 201', r.status_code == 201, r.content[:200])
    r = c.patch(f'/api/consultations/chats/{conversation_id}/', {}, content_type='application/json')
    check('farmer marks chat read', r.status_code == 200 and r.json()['unread_count'] == 0, r.content[:120])

    print('\n== prescription email resend ==')
    auth(c, doctor)
    from django.core import mail
    mail.outbox.clear()
    r = c.post(f'/api/doctor/prescriptions/{presc_id}/resend-email/', {}, content_type='application/json')
    check('resend 200 + email recorded', r.status_code == 200 and r.json()['email_sent_at'], r.content[:200])
    check('an email actually went out (locmem)', len(mail.outbox) == 1
          and mail.outbox[0].attachments and mail.outbox[0].attachments[0][0].endswith('.pdf'), len(mail.outbox))

    print('\n== video consultation (Jitsi room) ==')
    # need a fresh accepted online consultation
    appt2 = date.today() + timedelta(days=8)
    AvailabilitySlot.objects.get_or_create(doctor=doctor, weekday=appt2.weekday(),
                                           start_time=time(9, 0), end_time=time(17, 0), mode='online')
    auth(c, farmer)
    r = c.post('/api/consultations/', {
        'doctor_id': doctor_profile_id, 'farm_id': str(farm.id), 'mode': 'online',
        'appointment_date': appt2.isoformat(), 'appointment_time': '14:00', 'symptoms': ['Coughing'],
        'bird_age_weeks': 5, 'breed': 'Cobb', 'flock_count': 400,
    }, content_type='application/json')
    video_consult = r.json()['id']
    auth(c, doctor)
    c.post(f'/api/doctor/appointments/{video_consult}/action/', {'action': 'accept'}, content_type='application/json')
    r = c.post(f'/api/doctor/appointments/{video_consult}/video/', {'action': 'start'}, content_type='application/json')
    check('doctor starts video 200 + jitsi url', r.status_code == 200
          and r.json()['active'] and 'meet.jit.si/' in r.json()['room_url'], r.content[:300])
    check('starting video moves consultation to in_progress',
          Consultation.objects.get(id=video_consult).status == 'in_progress')
    check('farmer notified to join', Notification.objects.filter(
        user=farmer, title__icontains='Video call').exists())
    auth(c, farmer)
    r = c.get(f'/api/consultations/{video_consult}/video/')
    check('farmer gets the same active room', r.status_code == 200
          and r.json()['active'] and r.json()['room'] == Consultation.objects.get(id=video_consult).video_room,
          r.content[:200])
    auth(c, doctor)
    r = c.post(f'/api/doctor/appointments/{video_consult}/video/', {'action': 'end'}, content_type='application/json')
    check('doctor ends video', r.status_code == 200 and not r.json()['active'], r.content[:200])

    print('\n== consultation disputes (farmer + doctor -> admin) ==')
    auth(c, farmer)
    r = c.post('/api/consultations/disputes/', {
        'consultation_id': consult_id, 'category': 'payment',
        'description': 'I was charged the wrong consultation fee for this visit.',
    }, content_type='application/json')
    check('farmer raises dispute 201', r.status_code == 201 and r.json()['status'] == 'open', r.content[:250])
    dispute_id = r.json()['id']
    r = c.post('/api/consultations/disputes/', {'consultation_id': consult_id, 'category': 'x', 'description': 'short'},
               content_type='application/json')
    check('invalid dispute rejected', r.status_code == 400, r.status_code)
    r = c.get('/api/consultations/disputes/')
    check('farmer sees own dispute', any(d['id'] == dispute_id for d in r.json()['disputes']))
    auth(c, doctor)
    r = c.post('/api/doctor/disputes/', {
        'consultation_id': consult_id, 'category': 'conduct',
        'description': 'The farmer used abusive language during the chat.',
    }, content_type='application/json')
    check('doctor raises dispute 201', r.status_code == 201, r.content[:200])
    r = c.get('/api/doctor/disputes/')
    check('doctor sees both disputes on the consultation', len(r.json()['disputes']) >= 2)

    print('\n== admin doctor oversight (cross-panel) ==')
    admin = make_user('admin', 'admin_super')
    from profiles.models import AdminProfile
    AdminProfile.objects.update_or_create(user=admin, defaults=dict(
        job_title='A', department='Ops', start_date=date(2024, 1, 1), admin_sub_role='super',
        approval_status='approved', is_active=True, is_suspended=False, internal_approval_by_founder_hr=True))
    auth(c, admin)
    r = c.get('/api/admin-panel/doctors/')
    doc_row = next((d for d in r.json()['results'] if d.get('name') == 'DT Vet'), None)
    check('admin sees the doctor in oversight', r.status_code == 200 and doc_row is not None, r.status_code)
    check('doctor row carries response-time + dispute metrics',
          doc_row and doc_row['avg_response_minutes'] is not None and doc_row['open_disputes'] >= 2, doc_row)
    r = c.get('/api/admin-panel/consultation-disputes/')
    check('admin dispute queue lists them', r.status_code == 200
          and any(d['id'] == dispute_id for d in r.json()['results']), r.status_code)
    r = c.patch(f'/api/admin-panel/consultation-disputes/{dispute_id}/', {'action': 'review'},
                content_type='application/json')
    check('admin moves dispute to under_review', r.status_code == 200 and r.json()['status'] == 'under_review',
          r.content[:200])
    r = c.patch(f'/api/admin-panel/consultation-disputes/{dispute_id}/',
                {'action': 'resolve', 'resolution': 'Fee corrected and refunded to the farmer.'},
                content_type='application/json')
    check('admin resolves dispute (needs resolution note)', r.status_code == 200
          and r.json()['status'] == 'resolved' and r.json()['resolution'], r.content[:200])
    r = c.patch(f'/api/admin-panel/consultation-disputes/{dispute_id}/', {'action': 'resolve'},
                content_type='application/json')
    check('resolve without a note is rejected', r.status_code == 400, r.status_code)
    check('both parties notified of resolution',
          Notification.objects.filter(user=farmer, reference_id=dispute_id, title__icontains='resolved').exists()
          and Notification.objects.filter(user=doctor, reference_id=dispute_id).exists())

    cleanup([doctor, farmer, admin])
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
