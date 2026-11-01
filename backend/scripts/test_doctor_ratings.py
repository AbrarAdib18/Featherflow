"""Checks for doctor ratings and the demo-consultation cleanup (DOCTOR_RATINGS_FIX.md).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_doctor_ratings.py

Uses Django's test Client against the configured DB. Creates throw-away
accounts prefixed ``ratingtest+`` and cleans its own rows; the management
commands are always scoped to those accounts. Idempotent.
"""
import io
import os
import sys
from datetime import date, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj  # noqa: E402
if 'testserver' not in dj.ALLOWED_HOSTS:
    dj.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation  # noqa: E402
from doctor.models import CaseDetail, ConsultationStatusHistory, Conversation, Message  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'ratingtest+'


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
        full_name=f'RT {handle.title()}', phone=phone, date_of_birth=date(1988, 3, 3),
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
    CaseDetail.objects.filter(consultation_id__in=cons).delete()
    Message.objects.filter(conversation__participant_one_id__in=ids).delete()
    Message.objects.filter(conversation__participant_two_id__in=ids).delete()
    Conversation.objects.filter(participant_one_id__in=ids).delete()
    Conversation.objects.filter(participant_two_id__in=ids).delete()
    Consultation.objects.filter(id__in=cons).delete()
    FarmerProfile.objects.filter(user_id__in=ids).delete()
    DoctorProfile.objects.filter(user_id__in=ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def doctor_profile(user, rating):
    return DoctorProfile.objects.create(
        user=user, clinic_hospital_name='RT Clinic', practice_address='Rajshahi Sadar',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'RT-LIC-{user.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        service_fee=Decimal('1000.00'), consent_platform_guidelines=True, is_verified=True,
        is_available=True, availability_status='available', rating=Decimal(rating))


def real_consultation(farmer, doctor, rating=None, days_ago=1):
    """A consultation as the app makes it: with a case and status history."""
    item = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='completed', urgency_level='routine',
        rating=rating, review_text=f'Review {rating}' if rating else '',
        rated_at=timezone.now() - timedelta(days=days_ago) if rating else None)
    CaseDetail.objects.create(consultation=item, farmer_name=farmer.full_name)
    ConsultationStatusHistory.objects.create(
        consultation=item, actor=doctor, from_status='in_progress', to_status='completed')
    return item


def run(*args):
    out = io.StringIO()
    call_command(*args, stdout=out)
    return out.getvalue()


def stored(doctor):
    return DoctorProfile.objects.get(user=doctor).rating


def main():
    c = Client()
    farmer = make_user('farmer', 'farmer')
    doctor = make_user('vet', 'doctor')
    unrated = make_user('newvet', 'doctor')
    users = [farmer, doctor, unrated]
    cleanup(users)

    FarmerProfile.objects.create(
        user=farmer, farm_name='RT Farm', owner_name='RT Farmer', farm_location='Paba',
        farm_address='Paba, Rajshahi', farm_type='broiler', consent_data_collection=True)
    # Stored copy is stale on purpose: 0.00 while real ratings exist.
    doctor_profile(doctor, '0.00')
    doctor_profile(unrated, '0.00')
    real_consultation(farmer, doctor, 3, days_ago=3)
    real_consultation(farmer, doctor, 4, days_ago=2)
    real_consultation(farmer, doctor, 5, days_ago=1)

    print('\n== doctor sees the live rating, not the stale stored copy ==')
    auth(c, doctor)
    r = c.get('/api/doctor/dashboard/')
    body = r.json() if r.status_code == 200 else {}
    check('dashboard 200', r.status_code == 200, r.content[:200])
    check('dashboard summary: 4.0 from 3 ratings',
          body.get('summary', {}).get('rating') == 4.0 and body['summary'].get('total_ratings') == 3,
          body.get('summary'))
    check('dashboard profile: 4.0 from 3 ratings',
          body.get('profile', {}).get('rating') == 4.0 and body['profile'].get('total_ratings') == 3,
          body.get('profile'))
    r = c.get('/api/doctor/profile/')
    check('profile endpoint: 4.0 from 3 ratings',
          r.status_code == 200 and r.json().get('rating') == 4.0 and r.json().get('total_ratings') == 3,
          r.content[:300])
    r = c.get('/api/doctor/earnings/')
    body = r.json() if r.status_code == 200 else {}
    check('earnings 200', r.status_code == 200, r.content[:200])
    check('earnings rating_summary matches the ratings list',
          body.get('rating_summary') == {'average': 4.0, 'count': 3,
                                         'distribution': {'5': 1, '4': 1, '3': 1, '2': 0, '1': 0}},
          body.get('rating_summary'))
    check('ratings list newest first',
          [x['rating'] for x in body.get('ratings', [])] == [5.0, 4.0, 3.0], body.get('ratings'))

    print('\n== recalculate_doctor_ratings fixes the stored copy ==')
    out = run('recalculate_doctor_ratings', '--dry-run', '--email', doctor.email, unrated.email)
    check('dry run reports the change', f'{doctor.email}: 0.00 -> 4.00 (3 rating(s))' in out, out)
    check('dry run writes nothing', stored(doctor) == Decimal('0.00'), stored(doctor))
    check('doctor without ratings is unchanged', unrated.email not in out, out)
    run('recalculate_doctor_ratings', '--email', doctor.email, unrated.email)
    check('stored rating now 4.00', stored(doctor) == Decimal('4.00'), stored(doctor))
    out = run('recalculate_doctor_ratings', '--email', doctor.email)
    check('second run changes nothing', 'Done: 0 doctor rating(s) updated.' in out, out)

    print('\n== a new in-app rating refreshes both ==')
    pending = real_consultation(farmer, doctor)
    auth(c, farmer)
    r = c.patch('/api/consultations/', {'id': str(pending.id), 'rating': 1, 'review': 'Late reply'},
                content_type='application/json')
    check('rating 200', r.status_code == 200, r.content[:200])
    check('stored rating = (3+4+5+1)/4 = 3.25', stored(doctor) == Decimal('3.25'), stored(doctor))
    auth(c, doctor)
    s = c.get('/api/doctor/dashboard/').json()['summary']
    check('dashboard 3.25 from 4', s['rating'] == 3.25 and s['total_ratings'] == 4, s)

    print('\n== doctor with no ratings ==')
    auth(c, unrated)
    body = c.get('/api/doctor/dashboard/').json()
    check('dashboard 0 ratings, 0.0 average',
          body['summary']['rating'] == 0.0 and body['summary']['total_ratings'] == 0
          and body['profile']['total_ratings'] == 0, body['summary'])
    rs = c.get('/api/doctor/earnings/').json()['rating_summary']
    check('earnings summary empty', rs['count'] == 0 and set(rs['distribution'].values()) == {0}, rs)

    print('\n== remove_demo_consultations ==')
    seeded = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='completed', urgency_level='routine',
        rating=5, review_text='Very helpful, clear guidance on treatment.')
    seeded_open = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='requested', urgency_level='routine')
    convo = Conversation.objects.create(participant_one=farmer, participant_two=doctor, consultation=seeded)
    Message.objects.create(conversation=convo, sender=doctor, content='Scripted hello')
    real_ids = set(Consultation.objects.filter(farmer=farmer, case_detail__isnull=False).values_list('id', flat=True))
    auth(c, doctor)
    s = c.get('/api/doctor/dashboard/').json()['summary']
    check('fake rating inflates the count before cleanup', s['total_ratings'] == 5, s)

    out = run('remove_demo_consultations', '--farmer', farmer.email)
    check('dry run lists exactly the 2 seeded rows',
          '2 seeded consultation(s), 1 conversation(s), 1 message(s).' in out
          and str(seeded.id) in out and str(seeded_open.id) in out, out)
    check('dry run deletes nothing', Consultation.objects.filter(id=seeded.id).exists())
    out = run('remove_demo_consultations', '--farmer', farmer.email, '--apply')
    check('apply reports the deletes',
          'Deleted 2 consultation(s), 1 conversation(s), 1 message(s).' in out, out)
    check('seeded rows, chat and messages gone',
          not Consultation.objects.filter(id__in=[seeded.id, seeded_open.id]).exists()
          and not Conversation.objects.filter(id=convo.id).exists()
          and not Message.objects.filter(conversation_id=convo.id).exists())
    check('real consultations kept',
          set(Consultation.objects.filter(farmer=farmer).values_list('id', flat=True)) == real_ids
          and len(real_ids) == 4)
    s = c.get('/api/doctor/dashboard/').json()['summary']
    check('dashboard back to 3.25 from 4', s['rating'] == 3.25 and s['total_ratings'] == 4, s)
    out = run('remove_demo_consultations', '--farmer', farmer.email)
    check('second run finds nothing', '0 seeded consultation(s)' in out, out)

    cleanup(users)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
