"""Consultation booking-rule and access-isolation checks that complement
``test_doctor_flow.py`` (which covers the full happy-path + several negative
cases already: double-booking, prescription-before-completion, overlapping
availability slots, over-balance payouts, invalid disputes).

This script fills the specific gaps identified by the 2026-09-18
Find Vet / doctor-farmer workflow integration audit
(see ``CONSULTATION_INTEGRATION_AUDIT.md``):

  * A farmer cannot book using another farmer's farm/flock.
  * A farmer cannot book an inactive or non-doctor account.
  * An unsupported consultation mode is rejected.
  * A past appointment time is rejected.
  * Emergency requests are rejected when the doctor does not support them.
  * Only the assigned doctor can act on an appointment (another doctor -> 404).
  * Only the assigned farmer can cancel/rate a consultation (another farmer -> 404).
  * A follow-up cannot be scheduled when the doctor already has one at that time.
  * The discovery endpoint's ``max_distance_km`` filter excludes farther vets.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_consultation_booking_rules.py

Uses Django's test Client against the *live* configured database. Creates
throw-away accounts prefixed ``bookrule+`` and cleans its own rows on entry
and on exit. Idempotent.
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
PREFIX = 'bookrule+'


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
        full_name=f'BR {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status=account_status,
    ))
    user.account_status = account_status
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
    FollowUp.objects.filter(doctor_id__in=ids).delete()
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
    doctor2 = make_user('vet2', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    inactive_doctor = make_user('inactive-vet', 'doctor', account_status='pending')
    all_users = [doctor, doctor2, farmer, farmer2, inactive_doctor]
    cleanup(all_users)

    DoctorProfile.objects.create(
        user=doctor, clinic_hospital_name='BR Poultry Clinic', practice_address='Dhaka Sadar',
        latitude=Decimal('23.8103'), longitude=Decimal('90.4125'),
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'BR-LIC-{doctor.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='online', council_registration_proof_url='x',
        prescription_authority=True, emergency_on_call_availability=False, service_fee=Decimal('1000.00'),
        consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
    )
    # A second, real doctor far away (~900 km, well outside a 100 km filter)
    # used for the doctor-isolation and max-distance checks.
    DoctorProfile.objects.create(
        user=doctor2, clinic_hospital_name='BR Second Clinic', practice_address='Chattogram',
        latitude=Decimal('22.3569'), longitude=Decimal('91.7832'),
        veterinary_degree='DVM', university_name='BAU', graduation_year=2016,
        license_number=f'BR-LIC2-{doctor2.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=6, consultation_mode='both', council_registration_proof_url='x',
        prescription_authority=True, emergency_on_call_availability=True, service_fee=Decimal('800.00'),
        consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
    )
    DoctorProfile.objects.create(
        user=inactive_doctor, clinic_hospital_name='BR Pending Clinic', practice_address='Dhaka',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2018,
        license_number=f'BR-LIC3-{inactive_doctor.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=3, consultation_mode='both', council_registration_proof_url='x',
        consent_platform_guidelines=True, is_verified=False, is_available=True, availability_status='available',
    )
    fp = FarmerProfile.objects.create(
        user=farmer, farm_name='BR Farm', owner_name='BR Farmer',
        farm_location='Savar', farm_address='Savar, Dhaka', farm_type='broiler',
        consent_data_collection=True,
    )
    fp2 = FarmerProfile.objects.create(
        user=farmer2, farm_name='BR Farm 2', owner_name='BR Farmer 2',
        farm_location='Gazipur', farm_address='Gazipur', farm_type='broiler',
        consent_data_collection=True,
    )
    farm = Farm.objects.create(
        farmer=fp, farm_name='BR Farm', farm_type='broiler', location='Savar',
        address='Savar, Dhaka', is_active=True)
    other_farm = Farm.objects.create(
        farmer=fp2, farm_name='BR Farm 2', farm_type='broiler', location='Gazipur',
        address='Gazipur', is_active=True)
    flock = Flock.objects.create(
        farm=farm, batch_name='Batch A', bird_type='broiler', breed='Cobb 500',
        quantity=500, current_quantity=480, start_date=date.today() - timedelta(days=20), status='active')
    other_flock = Flock.objects.create(
        farm=other_farm, batch_name='Batch B', bird_type='broiler', breed='Ross 308',
        quantity=300, current_quantity=290, start_date=date.today() - timedelta(days=10), status='active')

    appt_date = date.today() + timedelta(days=5)
    AvailabilitySlot.objects.create(
        doctor=doctor, weekday=appt_date.weekday(), start_time=time(9, 0), end_time=time(17, 0), mode='online')
    AvailabilitySlot.objects.create(
        doctor=doctor2, weekday=appt_date.weekday(), start_time=time(9, 0), end_time=time(17, 0), mode='online')

    def book(farm_id, flock_id=None, mode='online', urgency='routine',
             appt_time='11:00', appt_date_=appt_date, doctor_profile_id=None):
        payload = {
            'doctor_id': doctor_profile_id, 'farm_id': farm_id, 'mode': mode,
            'urgency': urgency, 'appointment_date': appt_date_.isoformat(),
            'appointment_time': appt_time, 'symptoms': ['Lethargy'],
            'bird_age_weeks': 4, 'breed': 'Cobb 500', 'flock_count': 500, 'mortality_count': 2,
        }
        if flock_id:
            payload['flock_id'] = flock_id
        return c.post('/api/consultations/', payload, content_type='application/json')

    auth(c, farmer)
    doctor_profile_id = str(DoctorProfile.objects.get(user=doctor).id)
    doctor2_profile_id = str(DoctorProfile.objects.get(user=doctor2).id)

    print('\n== ownership & mode/status validation ==')
    r = book(str(farm.id), flock_id=str(other_flock.id), doctor_profile_id=doctor_profile_id)
    check('booking with another farmer\'s flock rejected',
          r.status_code == 400 and 'flock_id' in r.json(), r.content[:200])

    r = c.post('/api/consultations/', {
        'doctor_id': doctor_profile_id, 'farm_id': str(other_farm.id), 'mode': 'online',
        'urgency': 'routine', 'appointment_date': appt_date.isoformat(), 'appointment_time': '11:00',
        'symptoms': ['x'], 'bird_age_weeks': 4, 'breed': 'x', 'flock_count': 10,
    }, content_type='application/json')
    check('booking with another farmer\'s farm rejected',
          r.status_code == 400 and 'farm_id' in r.json(), r.content[:200])

    inactive_profile_id = str(DoctorProfile.objects.get(user=inactive_doctor).id)
    r = book(str(farm.id), doctor_profile_id=inactive_profile_id)
    check('booking an unapproved/inactive doctor rejected',
          r.status_code == 400 and 'doctor_id' in r.json(), r.content[:200])

    r = book(str(farm.id), mode='offline', doctor_profile_id=doctor_profile_id)
    check('unsupported consultation mode rejected',
          r.status_code == 400 and 'mode' in r.json(), r.content[:200])

    r = book(str(farm.id), urgency='emergency', doctor_profile_id=doctor_profile_id)
    check('emergency request rejected when doctor does not support it',
          r.status_code == 400 and 'urgency' in r.json(), r.content[:200])

    past_date = date.today() - timedelta(days=1)
    r = book(str(farm.id), appt_date_=past_date, doctor_profile_id=doctor_profile_id)
    check('past appointment date rejected', r.status_code == 400, r.content[:200])

    r = book(str(farm.id), flock_id=str(flock.id), doctor_profile_id=doctor_profile_id)
    check('legitimate booking with owned farm+flock accepted', r.status_code == 201, r.content[:300])
    consult_id = r.json()['id']

    print('\n== actor isolation ==')
    auth(c, doctor2)
    r = c.post(f'/api/doctor/appointments/{consult_id}/action/', {'action': 'accept'},
               content_type='application/json')
    check('a different doctor cannot act on this appointment (404)', r.status_code == 404, r.status_code)

    auth(c, farmer2)
    r = c.post(f'/api/consultations/{consult_id}/action/', {'action': 'cancel'},
               content_type='application/json')
    check('a different farmer cannot cancel this consultation (404)', r.status_code == 404, r.status_code)

    auth(c, doctor)
    r = c.post(f'/api/doctor/appointments/{consult_id}/action/', {'action': 'accept'},
               content_type='application/json')
    check('the assigned doctor can accept', r.status_code == 200, r.content[:200])

    auth(c, farmer)
    r = c.post(f'/api/consultations/{consult_id}/action/', {'action': 'cancel'},
               content_type='application/json')
    check('the assigned farmer can cancel', r.status_code == 200, r.content[:200])

    print('\n== follow-up scheduling conflicts ==')
    # A second, independent completed consultation to attach a follow-up to.
    r = book(str(farm.id), flock_id=str(flock.id), appt_time='13:00', doctor_profile_id=doctor_profile_id)
    check('second booking accepted', r.status_code == 201, r.content[:300])
    consult2_id = r.json()['id']
    auth(c, doctor)
    c.post(f'/api/doctor/appointments/{consult2_id}/action/', {'action': 'accept'}, content_type='application/json')
    c.post(f'/api/doctor/appointments/{consult2_id}/action/', {'action': 'complete'}, content_type='application/json')

    follow_up_dt = f'{(appt_date + timedelta(days=3)).isoformat()}'
    r = c.post('/api/doctor/follow-ups/', {
        'consultation_id': consult2_id, 'scheduled_date': follow_up_dt, 'scheduled_time': '10:00',
        'notes': 'Recheck mortality',
    }, content_type='application/json')
    check('follow-up scheduled 201', r.status_code == 201, r.content[:200])

    # A third booking + completion, to try to schedule a follow-up for the same
    # doctor at the exact same date/time -> must be rejected as a conflict.
    auth(c, farmer)
    r = book(str(farm.id), flock_id=str(flock.id), appt_time='15:00', doctor_profile_id=doctor_profile_id)
    check('third booking accepted', r.status_code == 201, r.content[:300])
    consult3_id = r.json()['id']
    auth(c, doctor)
    c.post(f'/api/doctor/appointments/{consult3_id}/action/', {'action': 'accept'}, content_type='application/json')
    c.post(f'/api/doctor/appointments/{consult3_id}/action/', {'action': 'complete'}, content_type='application/json')
    r = c.post('/api/doctor/follow-ups/', {
        'consultation_id': consult3_id, 'scheduled_date': follow_up_dt, 'scheduled_time': '10:00',
        'notes': 'Conflicting follow-up',
    }, content_type='application/json')
    check('conflicting follow-up at the same doctor time slot rejected',
          r.status_code == 409, r.content[:200])

    print('\n== discovery max_distance_km filter ==')
    auth(c, farmer2)
    r = c.get('/api/consultations/vets/', {
        'latitude': '23.8103', 'longitude': '90.4125', 'max_distance_km': '50',
    })
    check('max_distance_km 200', r.status_code == 200, r.content[:200])
    ids_within = {d['user_id'] for d in r.json()['doctors']}
    check('nearby doctor included within 50km', str(doctor.id) in ids_within, ids_within)
    check('far doctor excluded beyond 50km', str(doctor2.id) not in ids_within, ids_within)

    r = c.get('/api/consultations/vets/', {
        'latitude': '23.8103', 'longitude': '90.4125', 'max_distance_km': '500',
    })
    ids_within_wide = {d['user_id'] for d in r.json()['doctors']}
    check('far doctor included with a wide radius', str(doctor2.id) in ids_within_wide, ids_within_wide)

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup(all_users)
    return FAIL


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
