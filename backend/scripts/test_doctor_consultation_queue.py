"""Doctor-side consultation delivery checks (see DOCTOR_CONSULTATION_QUEUE_FIX.md).

Reproduces the 2026-10-30 bug report: a farmer's request reached the farmer's
"My Consultations" and both notification inboxes, but never appeared anywhere
on the doctor side. The backend already linked and returned the row; the
doctor app crashed parsing its ``scheduled_at: null``. These checks pin the
backend half of the contract the doctor app now relies on:

  * A farmer booking (open-ended AND dated) is stored against the doctor's
    *user* id, not the doctor-profile id the farmer sent.
  * Both appear in ``GET /api/doctor/appointments/`` as ``status: pending``;
    the open-ended one has ``scheduled_at: null`` and an aware ``requested_at``.
  * ``?status=pending`` filters to requested rows only.
  * ``GET /api/doctor/dashboard/`` exposes ``pending_requests`` and
    ``consultation_counts``, which move as the lifecycle advances.
  * The doctor's notification carries the consultation id and navigates to
    ``/doctor/appointments``.
  * Another doctor cannot see or act on it (404); a suspended doctor and a
    farmer are refused (401/403); an unauthenticated call is refused (401).
  * Lifecycle: accept -> start -> complete, with invalid transitions
    (double accept, complete-before-accept) rejected with a structured error,
    and a farmer cancellation surfacing to the doctor as ``cancelled``.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_doctor_consultation_queue.py

Uses Django's test Client against the *live* configured database. Creates
throw-away accounts prefixed ``doctorqtest+`` only (never the seeded demo
users) and cleans its own rows on entry and on exit. Idempotent.
"""
import os
import sys
from datetime import date, datetime, timedelta
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
    CaseDetail, ClinicalPrescription, ConsultationNote, ConsultationStatusHistory,
    Conversation, DoctorEarning, FollowUp, Message, PrescriptionItem,
)
from farms.models import Farm, Flock  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'doctorqtest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def make_user(handle, role_name, account_status='active'):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'DQ {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status=account_status,
    ))
    user.account_status = account_status
    user.set_password('Testpass!2026')
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def make_doctor_profile(user, tag):
    return DoctorProfile.objects.create(
        user=user, clinic_hospital_name=f'DQ {tag} Clinic', practice_address='Dhaka',
        latitude=Decimal('23.8103'), longitude=Decimal('90.4125'),
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'DQ-{tag}-{user.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        prescription_authority=True, emergency_on_call_availability=True, service_fee=Decimal('700.00'),
        consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
    )


def auth(client, user):
    if user is None:
        client.defaults.pop('HTTP_AUTHORIZATION', None)
    else:
        client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'


def cleanup(users):
    ids = [u.id for u in users]
    cons = list(Consultation.objects.filter(farmer_id__in=ids).values_list('id', flat=True))
    cons += list(Consultation.objects.filter(doctor_id__in=ids).values_list('id', flat=True))
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
    Flock.objects.filter(farm__farmer__user_id__in=ids).delete()
    Farm.objects.filter(farmer__user_id__in=ids).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def is_aware_iso(value):
    try:
        return value is not None and datetime.fromisoformat(value).tzinfo is not None
    except ValueError:
        return False


def main():
    c = Client()
    doctor = make_user('vet', 'doctor')
    other_doctor = make_user('vet2', 'doctor')
    suspended_doctor = make_user('suspended-vet', 'doctor')
    farmer = make_user('farmer', 'farmer')
    all_users = [doctor, other_doctor, suspended_doctor, farmer]
    cleanup(all_users)

    profile = make_doctor_profile(doctor, 'A')
    make_doctor_profile(other_doctor, 'B')
    make_doctor_profile(suspended_doctor, 'C')
    fp = FarmerProfile.objects.create(
        user=farmer, farm_name='DQ Farm', owner_name='DQ Farmer',
        farm_location='Savar', farm_address='Savar, Dhaka', farm_type='broiler',
        consent_data_collection=True,
    )
    farm = Farm.objects.create(
        farmer=fp, farm_name='DQ Farm', farm_type='broiler', location='Savar',
        address='Savar, Dhaka', is_active=True)
    flock = Flock.objects.create(
        farm=farm, batch_name='DQ Batch', bird_type='broiler', breed='Cobb 500',
        quantity=500, current_quantity=480, start_date=date.today() - timedelta(days=20), status='active')

    def doctor_rows(query=None):
        r = c.get('/api/doctor/appointments/', query or {})
        return r, (r.json().get('appointments', []) if r.status_code == 200 else [])

    def summary():
        r = c.get('/api/doctor/dashboard/')
        return r.json()['summary'] if r.status_code == 200 else {}

    # ── baseline ─────────────────────────────────────────────────────────────
    print('\n== baseline (new doctor, empty queue) ==')
    auth(c, doctor)
    r, rows = doctor_rows()
    check('appointments 200 for an active doctor', r.status_code == 200, r.content[:200])
    check('empty queue is an empty list, not an error', rows == [], rows)
    s = summary()
    check('dashboard exposes pending_requests = 0', s.get('pending_requests') == 0, s)
    check('dashboard exposes consultation_counts = {}', s.get('consultation_counts') == {}, s)

    # ── farmer books: open-ended (the reported case) and dated ───────────────
    print('\n== farmer request reaches the assigned doctor ==')
    auth(c, farmer)
    r = c.post('/api/consultations/', {
        'doctor_id': str(profile.id), 'farm_id': str(farm.id), 'flock_id': str(flock.id),
        'mode': 'online', 'urgency': 'urgent', 'symptoms': ['Coughing'],
    }, content_type='application/json')
    check('open-ended booking 201', r.status_code == 201, r.content[:300])
    open_id = r.json().get('id')
    appt_date = date.today() + timedelta(days=3)
    r = c.post('/api/consultations/', {
        'doctor_id': str(profile.id), 'farm_id': str(farm.id), 'flock_id': str(flock.id),
        'mode': 'online', 'urgency': 'routine', 'symptoms': ['Lethargy'],
        'appointment_date': appt_date.isoformat(), 'appointment_time': '11:00',
    }, content_type='application/json')
    check('dated booking 201', r.status_code == 201, r.content[:300])
    dated_id = r.json().get('id')

    item = Consultation.objects.get(id=open_id)
    check('consultation.doctor is the doctor USER (not the profile id sent)',
          item.doctor_id == doctor.id and item.doctor_id != profile.id, (item.doctor_id, profile.id))
    check('stored status is requested', item.status == 'requested', item.status)

    auth(c, doctor)
    r, rows = doctor_rows()
    by_id = {x['id']: x for x in rows}
    check('doctor queue contains the open-ended request', open_id in by_id, list(by_id))
    check('doctor queue contains the dated request', dated_id in by_id, list(by_id))
    row = by_id.get(open_id, {})
    check('requested is exposed as status "pending"', row.get('status') == 'pending', row)
    check('open-ended row has scheduled_at null and has_preferred_slot false',
          row.get('scheduled_at') is None and row.get('has_preferred_slot') is False, row)
    check('open-ended row has a timezone-aware requested_at',
          is_aware_iso(row.get('requested_at')), row.get('requested_at'))
    check('row carries urgency + farm-safe farmer context',
          row.get('urgency') == 'urgent' and row.get('is_urgent') is True
          and row.get('farmer_name') and row.get('farm_name') == 'DQ Farm', row)
    dated = by_id.get(dated_id, {})
    check('dated row carries its slot', (dated.get('scheduled_at') or '').startswith(appt_date.isoformat()), dated)

    r, pending_rows = doctor_rows({'status': 'pending'})
    check('?status=pending returns both requested rows',
          {x['id'] for x in pending_rows} == {open_id, dated_id}, [x['id'] for x in pending_rows])

    s = summary()
    check('dashboard pending_requests = 2', s.get('pending_requests') == 2, s)
    check('dashboard urgent_requests = 1', s.get('urgent_requests') == 1, s)
    check('dashboard consultation_counts = {requested: 2}',
          s.get('consultation_counts') == {'requested': 2}, s)

    # ── notification -> navigation ───────────────────────────────────────────
    print('\n== doctor notification points at the request ==')
    r = c.get('/api/notifications/')
    notes = [n for n in r.json().get('notifications', []) if n.get('reference_id') == open_id]
    check('doctor received a notification for the open-ended request', len(notes) == 1, r.content[:300])
    nav = (notes[0].get('navigation') or {}) if notes else {}
    check('notification navigates to /doctor/appointments',
          nav.get('route') == '/doctor/appointments' and nav.get('target_id') == open_id
          and nav.get('available') is True, nav)

    # ── isolation & permissions ──────────────────────────────────────────────
    print('\n== only the assigned doctor sees or acts ==')
    auth(c, other_doctor)
    r, rows = doctor_rows()
    check('another doctor does not see the request',
          r.status_code == 200 and open_id not in {x['id'] for x in rows}, rows)
    r = c.post(f'/api/doctor/appointments/{open_id}/action/', {'action': 'accept'},
               content_type='application/json')
    check('another doctor cannot accept it (404)', r.status_code == 404, r.content[:200])
    s = summary()
    check("another doctor's pending_requests unaffected", s.get('pending_requests') == 0, s)

    suspended_doctor.account_status = 'suspended'
    suspended_doctor.save(update_fields=['account_status'])
    auth(c, suspended_doctor)
    r, _ = doctor_rows()
    # Refused at authentication (401 user_inactive) before IsDoctor's 403.
    check('suspended doctor refused (401/403)', r.status_code in (401, 403), r.content[:200])
    check('refusal is a structured {detail} error', 'detail' in r.json(), r.content[:200])

    auth(c, farmer)
    r, _ = doctor_rows()
    check('farmer refused from the doctor queue (403)', r.status_code == 403, r.content[:200])
    auth(c, None)
    r, _ = doctor_rows()
    check('unauthenticated refused (401)', r.status_code == 401, r.content[:200])

    # ── lifecycle ────────────────────────────────────────────────────────────
    print('\n== lifecycle and transition rules ==')
    auth(c, doctor)

    def act(cid, action, **extra):
        return c.post(f'/api/doctor/appointments/{cid}/action/', {'action': action, **extra},
                      content_type='application/json')

    r = act(open_id, 'complete')
    check('complete before accept rejected (409/400)', r.status_code in (400, 409), r.content[:200])
    check('invalid transition returns a structured detail', 'detail' in r.json(), r.content[:200])
    r = act(open_id, 'accept')
    check('accept 200', r.status_code == 200, r.content[:200])
    r = act(open_id, 'accept')
    check('duplicate accept rejected', r.status_code in (400, 409), r.content[:200])

    _, rows = doctor_rows()
    row = next((x for x in rows if x['id'] == open_id), {})
    check('accepted row reads status accepted', row.get('status') == 'accepted', row)
    s = summary()
    check('pending_requests drops to 1 after accept', s.get('pending_requests') == 1, s)

    r = act(open_id, 'start')
    check('start 200', r.status_code == 200, r.content[:200])
    _, rows = doctor_rows()
    row = next((x for x in rows if x['id'] == open_id), {})
    check('in-progress row reads status in_progress', row.get('status') == 'in_progress', row)

    r = act(open_id, 'complete')
    check('complete 200', r.status_code == 200, r.content[:200])
    s = summary()
    check('consultation_counts reflects completed', s.get('consultation_counts', {}).get('completed') == 1, s)
    history = list(ConsultationStatusHistory.objects.filter(consultation_id=open_id)
                   .order_by('created_at').values_list('to_status', flat=True))
    check('status history recorded accept/start/complete',
          history[-3:] == ['accepted', 'in_progress', 'completed'], history)

    # Farmer cancels the dated request — the doctor must see it as cancelled,
    # not as a still-pending request.
    auth(c, farmer)
    r = c.post(f'/api/consultations/{dated_id}/action/', {'action': 'cancel', 'reason': 'Resolved'},
               content_type='application/json')
    check('farmer cancellation accepted', r.status_code == 200, r.content[:200])
    auth(c, doctor)
    _, rows = doctor_rows()
    row = next((x for x in rows if x['id'] == dated_id), {})
    check('doctor sees the cancelled request as cancelled', row.get('status') == 'cancelled', row)
    s = summary()
    check('pending_requests back to 0', s.get('pending_requests') == 0, s)
    r = act(dated_id, 'accept')
    check('cannot accept a cancelled request', r.status_code in (400, 409), r.content[:200])

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup(all_users)
    return FAIL


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
