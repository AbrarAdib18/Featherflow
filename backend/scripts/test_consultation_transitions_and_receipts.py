"""Coverage for the consultation status-transition gaps found while auditing
the doctor-farmer workflow (see CONSULTATION_WORKFLOW_AUDIT.md): reject with
reason, reschedule propose/accept/decline, no-show, the doctor's direct
`start` action, and — critically — the video-call `start` path, which used to
write `status='in_progress'` directly and skip `ConsultationStatusHistory`
(fixed in `doctor/views.py:video`). Also covers receipt generation/access
control and payment-status updates, which `test_doctor_flow.py` exercises for
the "happy path" only, not ownership isolation.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_consultation_transitions_and_receipts.py

Uses Django's test Client against the *live* configured database. Creates
throw-away accounts prefixed ``transtest+`` and cleans its own rows on entry.
Idempotent.
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

from consultations.models import Consultation  # noqa: E402
from consultations.payments import payment_breakdown  # noqa: E402
from doctor.models import AvailabilitySlot, ConsultationStatusHistory, DoctorEarning  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'transtest+'


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
        full_name=f'TT {handle.title()}', phone=phone, date_of_birth=date(1988, 3, 3),
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
    ConsultationStatusHistory.objects.filter(consultation_id__in=cons).delete()
    DoctorEarning.objects.filter(consultation_id__in=cons).delete()
    Payment.objects.filter(reference_id__in=cons).delete()
    Consultation.objects.filter(id__in=cons).delete()
    AvailabilitySlot.objects.filter(doctor_id__in=ids).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def make_consultation(doctor, farmer, appt_date, appt_time, fee=Decimal('1500.00')):
    return Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='requested',
        urgency_level='routine', appointment_date=appt_date, appointment_time=appt_time,
        consultation_fee=fee,
    )


def main():
    c = Client()
    doctor = make_user('doc', 'doctor')
    doctor2 = make_user('doc2', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    cleanup([doctor, doctor2, farmer, farmer2])

    for user, label in ((doctor, 'A'), (doctor2, 'B')):
        DoctorProfile.objects.create(
            user=user, clinic_hospital_name=f'TT Clinic {label}', practice_address='Rajshahi Sadar',
            veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
            license_number=f'TT-LIC-{user.id.hex[:8]}', license_issuing_authority='BVC',
            license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
            years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
            prescription_authority=True, emergency_on_call_availability=True, service_fee=Decimal('1500.00'),
            consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
        )
    FarmerProfile.objects.create(
        user=farmer, farm_name='TT Farm', owner_name='TT Farmer',
        farm_location='Paba', farm_address='Paba, Rajshahi', farm_type='broiler',
        consent_data_collection=True,
    )
    FarmerProfile.objects.create(
        user=farmer2, farm_name='TT Farm 2', owner_name='TT Farmer 2',
        farm_location='Paba', farm_address='Paba, Rajshahi', farm_type='broiler',
        consent_data_collection=True,
    )

    # Appointment/proposed dates span 10..20 days out; publish a near-full-day
    # online slot on every distinct weekday touched so reschedule proposals
    # never fail the published-availability check regardless of what "today"
    # is when this runs (test_doctor_flow.py's hardcoded weekday=2 slot is
    # exactly the kind of date-dependent flakiness this avoids).
    offsets = range(10, 21)
    dates = {n: date.today() + timedelta(days=n) for n in offsets}
    published_weekdays = set()
    for d in dates.values():
        wd = d.weekday()
        if wd in published_weekdays:
            continue
        published_weekdays.add(wd)
        AvailabilitySlot.objects.create(
            doctor=doctor, weekday=wd, start_time=time(0, 0), end_time=time(23, 59), mode='online')

    auth(c, doctor)

    print('\n== reject with reason ==')
    c1 = make_consultation(doctor, farmer, dates[10], time(10, 0))
    auth(c, doctor2)
    r = c.post(f'/api/doctor/appointments/{c1.id}/action/', {'action': 'reject', 'reason': 'x'},
               content_type='application/json')
    check("other doctor can't act on this consultation (404)", r.status_code == 404, r.status_code)
    auth(c, doctor)
    r = c.post(f'/api/doctor/appointments/{c1.id}/action/',
               {'action': 'reject', 'reason': 'Not specialized in this case.'},
               content_type='application/json')
    check('reject 200', r.status_code == 200, r.content[:200])
    c1.refresh_from_db()
    check('status is rejected', c1.status == 'rejected', c1.status)
    check('decision_reason saved', c1.decision_reason == 'Not specialized in this case.', c1.decision_reason)
    check('history row logged', ConsultationStatusHistory.objects.filter(
        consultation=c1, to_status='rejected', reason='Not specialized in this case.').exists())
    check('farmer notified of rejection', Notification.objects.filter(
        user=farmer, reference_id=c1.id, title__icontains='reject').exists())

    print('\n== reschedule: doctor proposes, farmer accepts ==')
    c2 = make_consultation(doctor, farmer, dates[11], time(10, 0))
    r = c.post(f'/api/doctor/appointments/{c2.id}/action/', {'action': 'accept'}, content_type='application/json')
    check('accept 200', r.status_code == 200, r.content[:200])
    r = c.post(f'/api/doctor/appointments/{c2.id}/action/',
               {'action': 'reschedule', 'appointment_date': dates[15].isoformat(),
                'appointment_time': '11:00', 'reason': 'Clinic emergency, need to move this.'},
               content_type='application/json')
    check('reschedule propose 200', r.status_code == 200, r.content[:200])
    c2.refresh_from_db()
    check('status is reschedule_proposed', c2.status == 'reschedule_proposed', c2.status)
    check('proposed date/time saved', c2.proposed_date == dates[15] and str(c2.proposed_time) == '11:00:00',
          (c2.proposed_date, c2.proposed_time))
    check('farmer notified of reschedule proposal', Notification.objects.filter(
        user=farmer, reference_id=c2.id, title__icontains='reschedule').exists())
    auth(c, farmer)
    r = c.post(f'/api/consultations/{c2.id}/action/', {'action': 'accept_reschedule'},
               content_type='application/json')
    check('farmer accepts reschedule 200', r.status_code == 200, r.content[:200])
    c2.refresh_from_db()
    check('status back to accepted', c2.status == 'accepted', c2.status)
    check('appointment moved to the proposed slot',
          c2.appointment_date == dates[15] and str(c2.appointment_time) == '11:00:00',
          (c2.appointment_date, c2.appointment_time))
    check('proposed_date/time cleared', c2.proposed_date is None and c2.proposed_time is None)
    check('conversation returned', 'conversation_id' in r.json(), r.json())

    print('\n== reschedule: doctor proposes, farmer declines ==')
    auth(c, doctor)
    c3 = make_consultation(doctor, farmer, dates[12], time(10, 0))
    c.post(f'/api/doctor/appointments/{c3.id}/action/', {'action': 'accept'}, content_type='application/json')
    r = c.post(f'/api/doctor/appointments/{c3.id}/action/',
               {'action': 'reschedule', 'appointment_date': dates[16].isoformat(), 'appointment_time': '09:30'},
               content_type='application/json')
    check('reschedule propose 200', r.status_code == 200, r.content[:200])
    auth(c, farmer)
    r = c.post(f'/api/consultations/{c3.id}/action/', {'action': 'decline_reschedule'},
               content_type='application/json')
    check('farmer declines reschedule 200', r.status_code == 200, r.content[:200])
    c3.refresh_from_db()
    check('status is cancelled', c3.status == 'cancelled', c3.status)
    check('proposed_date/time cleared', c3.proposed_date is None and c3.proposed_time is None)
    check('doctor notified of decline', Notification.objects.filter(
        user=doctor, reference_id=c3.id, title__icontains='declined').exists())

    print('\n== no-show ==')
    auth(c, doctor)
    c4 = make_consultation(doctor, farmer, dates[13], time(10, 0))
    r = c.post(f'/api/doctor/appointments/{c4.id}/action/', {'action': 'no_show'}, content_type='application/json')
    check('no_show blocked while requested (409)', r.status_code == 409, r.status_code)
    c.post(f'/api/doctor/appointments/{c4.id}/action/', {'action': 'accept'}, content_type='application/json')
    auth(c, doctor2)
    r = c.post(f'/api/doctor/appointments/{c4.id}/action/', {'action': 'no_show'}, content_type='application/json')
    check("other doctor can't mark no-show (404)", r.status_code == 404, r.status_code)
    auth(c, doctor)
    r = c.post(f'/api/doctor/appointments/{c4.id}/action/', {'action': 'no_show'}, content_type='application/json')
    check('no_show 200', r.status_code == 200, r.content[:200])
    c4.refresh_from_db()
    check('status is no_show', c4.status == 'no_show', c4.status)
    check('history row logged', ConsultationStatusHistory.objects.filter(
        consultation=c4, to_status='no_show').exists())

    print("\n== doctor's direct 'start' action (accepted -> in_progress) ==")
    c5 = make_consultation(doctor, farmer, dates[14], time(10, 0))
    c.post(f'/api/doctor/appointments/{c5.id}/action/', {'action': 'accept'}, content_type='application/json')
    r = c.post(f'/api/doctor/appointments/{c5.id}/action/', {'action': 'start'}, content_type='application/json')
    check('start 200', r.status_code == 200, r.content[:200])
    c5.refresh_from_db()
    check('status is in_progress', c5.status == 'in_progress', c5.status)
    check('history row logged', ConsultationStatusHistory.objects.filter(
        consultation=c5, to_status='in_progress').exists())

    print('\n== video-call start path also logs status history (regression '
          'check for the doctor/views.py:video fix) ==')
    c6 = make_consultation(doctor, farmer, dates[17], time(10, 0))
    c.post(f'/api/doctor/appointments/{c6.id}/action/', {'action': 'accept'}, content_type='application/json')
    r = c.post(f'/api/doctor/appointments/{c6.id}/video/', {}, content_type='application/json')
    check('video start 200', r.status_code == 200, r.content[:200])
    c6.refresh_from_db()
    check('status is in_progress', c6.status == 'in_progress', c6.status)
    check('video_room + video_started_at set', bool(c6.video_room) and c6.video_started_at is not None)
    check('history row logged for the video-start transition too', ConsultationStatusHistory.objects.filter(
        consultation=c6, to_status='in_progress').exists(),
        'this is the exact gap the doctor/views.py:video fix closes')
    r = c.post(f'/api/doctor/appointments/{c6.id}/video/', {'action': 'end'}, content_type='application/json')
    check('video end 200', r.status_code == 200, r.content[:200])
    c6.refresh_from_db()
    check('status still in_progress (end does not transition status)', c6.status == 'in_progress', c6.status)
    check('video_ended_at set', c6.video_ended_at is not None)

    print('\n== receipt generation + access control ==')
    r = c.post(f'/api/doctor/appointments/{c6.id}/action/', {'action': 'complete'}, content_type='application/json')
    check('complete 200', r.status_code == 200, r.content[:200])
    c6.refresh_from_db()
    check('status is completed', c6.status == 'completed', c6.status)
    gross, platform_charge, net = payment_breakdown(c6)
    auth(c, farmer)
    r = c.get(f'/api/consultations/{c6.id}/receipt/')
    check('farmer can view receipt 200', r.status_code == 200, r.content[:200])
    receipt = r.json()
    check('receipt number set', receipt['receipt_number'] == f'CASH-{c6.id}', receipt.get('receipt_number'))
    check('receipt fee breakdown matches', abs(receipt['gross_fee'] - float(gross)) < 0.01
          and abs(receipt['platform_charge'] - float(platform_charge)) < 0.01
          and abs(receipt['doctor_net_amount'] - float(net)) < 0.01, receipt)
    check('receipt names + mode/date present', receipt['doctor_name'] and receipt['farmer_name']
          and receipt['consultation_mode'] == 'online' and receipt['appointment_date'], receipt)
    check('doctor_handled_sequence is present', receipt['doctor_handled_sequence'] is not None, receipt)
    check('receipt starts unpaid', receipt['status'] == 'pending' and receipt['already_paid'] is False, receipt)
    auth(c, farmer2)
    r = c.get(f'/api/consultations/{c6.id}/receipt/')
    check("other farmer can't view this receipt (404)", r.status_code == 404, r.status_code)
    auth(c, doctor)
    r = c.get(f'/api/consultations/{c6.id}/receipt/')
    check("a doctor account can't use the farmer receipt endpoint (403)", r.status_code == 403, r.status_code)

    print('\n== payment status updates (mark-paid) ==')
    auth(c, farmer2)
    r = c.post(f'/api/consultations/{c6.id}/mark-paid/')
    check("other farmer can't mark this consultation paid (404)", r.status_code == 404, r.status_code)
    auth(c, farmer)
    r = c.post(f'/api/consultations/{c6.id}/mark-paid/')
    check('mark-paid 200', r.status_code == 200, r.content[:200])
    paid = r.json()
    check('payment now completed, not already-paid the first time',
          paid['status'] == 'completed' and paid['already_paid'] is False, paid)
    check('paid_at set', paid['paid_at'] is not None, paid)
    check('doctor earning accrued net of platform fee', DoctorEarning.objects.filter(
        consultation=c6, doctor=doctor, net_amount=net).exists())
    # Re-fetch from the farmer's own receipt view: the status update is
    # visible there too (both sides see the same underlying Payment row).
    r = c.get(f'/api/consultations/{c6.id}/receipt/')
    check('receipt now reflects paid status', r.json()['status'] == 'completed', r.json())
    r = c.post(f'/api/consultations/{c6.id}/mark-paid/')
    check('mark-paid is idempotent (200, already_paid True, no duplicate earning)',
          r.status_code == 200 and r.json()['already_paid'] is True
          and DoctorEarning.objects.filter(consultation=c6).count() == 1, r.json())

    print(f'\n{PASS} passed, {FAIL} failed')
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
