"""Farmer panel — chat must work on a completed consultation.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_consultation_chat_access.py

Live DB, `chatacc+` prefixed throw-away accounts. Idempotent.

Root cause this guards against: `Conversation` rows were only ever created by
the accept workflow (consultations/workflow.py:accept_consultation). Seeded and
legacy consultations are written straight to `status='completed'` without going
through accept, so they had no conversation at all — the farmer saw a completed
consultation naming a doctor with no way to message them, because
`conversation_id` came back null and the chat button was gated on it.

Covers: a completed consultation created directly still resolves a conversation,
the farmer can read and send on it, messages persist, doctor identity is exposed,
and a non-participant is locked out.
"""
import os
import sys
from datetime import date, timedelta
from decimal import Decimal

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation  # noqa: E402
from doctor.models import Conversation, Message  # noqa: E402
from farms.models import Farm  # noqa: E402
from profiles.models import DoctorProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'chatacc+'
JSON = 'application/json'


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
    Message.objects.filter(conversation__participant_one__in=users).delete()
    Message.objects.filter(conversation__participant_two__in=users).delete()
    Conversation.objects.filter(participant_one__in=users).delete()
    Conversation.objects.filter(participant_two__in=users).delete()
    Consultation.objects.filter(farmer__in=users).delete()
    Consultation.objects.filter(doctor__in=users).delete()
    Farm.objects.filter(farmer__user__in=users).delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    DoctorProfile.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_user(role_name, panel):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': panel})
    u = User.objects.create_user(
        email=f'{PREFIX}{n}@example.com', password='Test1234!',
        phone=f'0194{n:07d}', full_name=f'{role_name.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def run():
    print('\n== Farmer panel: completed-consultation chat access ==\n')
    cleanup()

    farmer = mk_user('farmer', 'farmer')
    other_farmer = mk_user('farmer', 'farmer')
    doctor = mk_user('doctor', 'doctor')

    fp = FarmerProfile.objects.create(
        user=farmer, farm_name='Chat Farm', owner_name='Chat Farmer',
        farm_location='Savar', farm_address='Savar, Dhaka', farm_type='broiler',
        consent_data_collection=True)
    Farm.objects.create(
        farmer=fp, farm_name='Chat Farm', farm_type='broiler', location='Savar',
        address='Savar, Dhaka', is_active=True)
    FarmerProfile.objects.create(
        user=other_farmer, farm_name='Other Farm', owner_name='Other',
        farm_location='Gazipur', farm_address='Gazipur', farm_type='broiler',
        consent_data_collection=True)
    doctor_profile = DoctorProfile.objects.create(
        user=doctor, clinic_hospital_name='Chat Clinic', practice_address='Dhaka',
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'CHAT-{doctor.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        consent_platform_guidelines=True, is_verified=True, is_available=True,
        availability_status='available', service_fee=Decimal('500.00'))

    # Exactly how the seed commands write one: straight to 'completed', never
    # through accept_consultation, so no Conversation is created.
    done = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='completed',
        urgency_level='routine', appointment_date=date.today() - timedelta(days=2),
        appointment_time='11:00', consultation_fee=Decimal('500.00'))
    check('fixture has no conversation to begin with',
          not Conversation.objects.filter(participant_one__in=(farmer, doctor)).exists())

    c = client_for(farmer)

    print('\n== conversation resolution ==')
    r = c.get('/api/consultations/')
    row = next((x for x in r.json()['consultations'] if x['id'] == str(done.id)), None)
    check('completed consultation is listed', row is not None, r.content[:300])
    check('completed consultation resolves a conversation_id',
          row is not None and row.get('conversation_id'), row)
    check('completed consultation exposes doctor_id',
          row is not None and row.get('doctor_id') == str(doctor.id), row)
    check('completed consultation exposes doctor_profile_id',
          row is not None and row.get('doctor_profile_id') == str(doctor_profile.id), row)
    conversation_id = row.get('conversation_id') if row else None

    print('\n== the thread is reachable and writable ==')
    r = c.get('/api/consultations/chats/')
    ids = [x['id'] for x in r.json().get('conversations', [])]
    check('the resolved conversation appears in the chat list',
          conversation_id in ids, r.content[:300])

    r = c.post(f'/api/consultations/chats/{conversation_id}/',
               {'content': 'Thanks for the advice.'}, content_type=JSON)
    check('farmer can send on a completed consultation', r.status_code in (200, 201), r.content[:300])

    r = c.get('/api/consultations/chats/')
    thread = next((x for x in r.json().get('conversations', []) if x['id'] == conversation_id), None)
    messages = (thread or {}).get('messages', [])
    check('the message persisted', any(m.get('content') == 'Thanks for the advice.' for m in messages),
          messages[:3])
    check('the message is stored against the conversation',
          Message.objects.filter(conversation_id=conversation_id).count() == 1)

    print('\n== authorization ==')
    oc = client_for(other_farmer)
    r = oc.get('/api/consultations/chats/')
    check('a non-participant sees none of this thread',
          conversation_id not in [x['id'] for x in r.json().get('conversations', [])],
          r.content[:300])
    r = oc.post(f'/api/consultations/chats/{conversation_id}/',
                {'content': 'let me in'}, content_type=JSON)
    check('a non-participant cannot send (404/403)', r.status_code in (403, 404), r.status_code)
    check('no stray message was written',
          Message.objects.filter(conversation_id=conversation_id).count() == 1)

    print('\n== repeat resolution is stable ==')
    before = Conversation.objects.filter(participant_one__in=(farmer, doctor)).count()
    c.get('/api/consultations/')
    c.get('/api/consultations/')
    after = Conversation.objects.filter(participant_one__in=(farmer, doctor)).count()
    check('listing repeatedly does not create duplicate conversations', before == after == 1,
          f'{before} -> {after}')

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
