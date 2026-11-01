"""Doctor Case page workflow + Schedule page scope (DOCTOR_CASE_PAGE_FIX.md).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_doctor_case_workflow.py

Uses Django's test Client against the *live* configured database. Creates
throw-away accounts prefixed ``casewf+`` and cleans its own rows on entry
(activity_logs rows are append-only by design and are left in place; the
checks only count rows written during this run).

Covers: editable case fields (partial save, persistence, validation, audit,
RBAC), the case stage machine (open -> closed -> Mark as Complete ->
Issue prescription), idempotent completion (incl. concurrent submits),
receipt / payment / earnings / rating / notifications after a Case-page
completion, farmer visibility, and the Schedule scope.
"""
import os
import sys
import threading
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

from django.db import connection  # noqa: E402
from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from audit.models import ActivityLog  # noqa: E402
from consultations.models import Consultation, ConsultationDispute  # noqa: E402
from doctor.models import (  # noqa: E402
    CaseDetail, ClinicalPrescription, ConsultationNote, ConsultationStatusHistory,
    Conversation, DoctorEarning, FollowUp, Message, PrescriptionItem,
)
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import DoctorProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'casewf+'


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
        full_name=f'CW {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active',
    ))
    user.account_status = 'active'
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def make_doctor_profile(user, tag):
    return DoctorProfile.objects.create(
        user=user, clinic_hospital_name=f'CW {tag} Clinic', practice_address='Dhaka',
        latitude=Decimal('23.8103'), longitude=Decimal('90.4125'),
        veterinary_degree='DVM', university_name='BAU', graduation_year=2015,
        license_number=f'CW-{tag}-{user.id.hex[:8]}', license_issuing_authority='BVC',
        license_expiry_date=date.today() + timedelta(days=800), specialty='Poultry medicine',
        years_of_experience=8, consultation_mode='both', council_registration_proof_url='x',
        prescription_authority=True, emergency_on_call_availability=True, service_fee=Decimal('2000.00'),
        consent_platform_guidelines=True, is_verified=True, is_available=True, availability_status='available',
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
    ConsultationDispute.objects.filter(consultation_id__in=cons).delete()
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


def book(farmer, doctor, status='requested', days=3, hour=9, **case_fields):
    item = Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status=status, urgency_level='routine',
        appointment_date=date.today() + timedelta(days=days), appointment_time=time(hour, 0),
        consultation_fee=Decimal('2000.00'))
    case = CaseDetail.objects.create(
        consultation=item, farmer_name=farmer.full_name, farm_name='CW Farm', breed='Sonali',
        flock_count=500, mortality_count=4, bird_age='6 weeks',
        symptoms_description='Lethargy\nWet droppings', case_status='open', **case_fields)
    return item, case


def main():
    run_started = timezone.now()
    doctor = make_user('vet', 'doctor')
    doctor2 = make_user('vet2', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    users = [doctor, doctor2, farmer, farmer2]
    cleanup(users)
    make_doctor_profile(doctor, 'a')
    make_doctor_profile(doctor2, 'b')
    dc, d2, fc, f2, anon = (client_for(doctor), client_for(doctor2), client_for(farmer),
                            client_for(farmer2), client_for())

    consult, case = book(farmer, doctor, feed_notes='Layer mash, 110 g/bird')
    case_url = f'/api/doctor/cases/{case.id}/'

    def patch(client, body, url=None):
        return client.patch(url or case_url, body, content_type='application/json')

    def act(client, cid, action):
        return client.post(f'/api/doctor/appointments/{cid}/action/', {'action': action},
                           content_type='application/json')

    def audit_rows(action=None):
        qs = ActivityLog.objects.filter(module='doctor_cases', entity_id=case.id, created_at__gte=run_started)
        return qs.filter(action=action) if action else qs

    # ── access control ───────────────────────────────────────────────────────
    print('\n== access control ==')
    check('unauthenticated GET case -> 401', anon.get(case_url).status_code == 401)
    check('unauthenticated PATCH case -> 401', patch(anon, {'diagnosis': 'x'}).status_code == 401)
    r = patch(fc, {'diagnosis': 'farmer edit'})
    check('farmer cannot use the doctor case endpoint (403)', r.status_code == 403, r.status_code)
    r = patch(d2, {'diagnosis': 'other doctor edit'})
    check("another doctor cannot edit this doctor's case (404)", r.status_code == 404, r.status_code)
    check("another doctor cannot read this doctor's case (404)", d2.get(case_url).status_code == 404)
    check('no clinical note was written by refused requests',
          not ConsultationNote.objects.filter(consultation=consult).exists())

    # ── before acceptance ────────────────────────────────────────────────────
    print('\n== stage: awaiting acceptance ==')
    r = dc.get(case_url)
    check('GET single case 200', r.status_code == 200, r.content[:200])
    check('stage awaiting_acceptance, not editable',
          r.json().get('stage') == 'awaiting_acceptance' and r.json().get('editable') is False, r.json())
    r = patch(dc, {'diagnosis': 'too early'})
    check('editing before accept -> 409 consultation_not_accepted',
          r.status_code == 409 and r.json().get('code') == 'consultation_not_accepted', r.content[:200])

    r = act(dc, consult.id, 'accept')
    check('accept 200', r.status_code == 200, r.content[:200])

    # ── editable open case ───────────────────────────────────────────────────
    print('\n== stage: open -> editable fields ==')
    r = dc.get(case_url)
    check('stage open + editable after accept', r.json().get('stage') == 'open' and r.json().get('editable') is True, r.json())
    r = patch(dc, {'diagnosis': '  Early coccidiosis  '})
    check('PATCH diagnosis only -> 200', r.status_code == 200, r.content[:300])
    row = r.json()
    check('response returns the updated case (trimmed)', row.get('diagnosis') == 'Early coccidiosis', row.get('diagnosis'))
    check('partial save left farmer intake untouched',
          row.get('feed_notes') == 'Layer mash, 110 g/bird' and row.get('symptoms') == ['Lethargy', 'Wet droppings']
          and row.get('flock_size') == 500, row)
    check('consultation status unchanged by case edits',
          Consultation.objects.get(id=consult.id).status == 'accepted')

    r = patch(dc, {'treatment_plan': 'Amprolium 1 ml/L for 5 days; dry litter'})
    check('PATCH treatment plan only keeps the diagnosis',
          r.status_code == 200 and r.json()['diagnosis'] == 'Early coccidiosis'
          and r.json()['treatment_plan'].startswith('Amprolium'), r.content[:300])
    full = {
        'warnings': 'Withdraw eggs for 7 days', 'next_steps': 'Re-check droppings on day 5',
        'vaccine_history': 'ND + IB at day 7', 'biosecurity_notes': 'Footbath at shed door',
        'feed_notes': 'Switch to grower feed', 'disease_tags': ['coccidiosis', 'Coccidiosis', ' enteric '],
    }
    r = patch(dc, full)
    check('PATCH remaining fields -> 200', r.status_code == 200, r.content[:300])
    note = ConsultationNote.objects.get(consultation=consult)
    case.refresh_from_db()
    check('clinical fields persisted in consultation_notes',
          note.diagnosis == 'Early coccidiosis' and note.warnings == 'Withdraw eggs for 7 days'
          and note.next_steps == 'Re-check droppings on day 5', vars(note))
    check('case fields persisted in consultation_case_details',
          case.vaccine_history == 'ND + IB at day 7' and case.biosecurity_notes == 'Footbath at shed door'
          and case.feed_notes == 'Switch to grower feed', vars(case))
    check('disease tags trimmed and de-duplicated', case.disease_tags == ['coccidiosis', 'enteric'], case.disease_tags)
    check('exactly one clinical note row (updated, not duplicated)',
          ConsultationNote.objects.filter(consultation=consult).count() == 1)
    reloaded = dc.get(case_url).json()
    check('reload (GET single) returns every saved value',
          all(reloaded.get(k) == v for k, v in full.items() if k != 'disease_tags')
          and reloaded['disease_tags'] == ['coccidiosis', 'enteric'], reloaded)
    listed = next(x for x in dc.get('/api/doctor/cases/').json()['cases'] if x['id'] == str(case.id))
    check('case list returns the same saved values',
          listed['diagnosis'] == 'Early coccidiosis' and listed['warnings'] == 'Withdraw eggs for 7 days', listed)
    check('updated_at is ISO 8601 with a timezone', (reloaded.get('updated_at') or '').endswith('+00:00'), reloaded.get('updated_at'))

    # ── audit history ────────────────────────────────────────────────────────
    print('\n== audit history ==')
    edits = list(audit_rows('case_fields_updated').order_by('created_at'))
    check('one audit row per save that changed something', len(edits) == 3, len(edits))
    check('audit row records actor, old and new values',
          edits and edits[0].user_id == doctor.id and edits[0].old_values == {'diagnosis': ''}
          and edits[0].new_values == {'diagnosis': 'Early coccidiosis'}, edits and vars(edits[0]))
    r = patch(dc, {'diagnosis': 'Early coccidiosis'})
    check('saving unchanged values -> 200 and no new audit row',
          r.status_code == 200 and audit_rows('case_fields_updated').count() == 3, audit_rows().count())

    # ── validation ───────────────────────────────────────────────────────────
    print('\n== validation ==')
    r = patch(dc, {'diagnosis': 'x' * 5001})
    check('over-long diagnosis -> 400 with a field error',
          r.status_code == 400 and 'diagnosis' in r.json().get('errors', {}), r.content[:200])
    r = patch(dc, {'flock_count': -1})
    check('negative flock count -> 400', r.status_code == 400 and 'flock_count' in r.json().get('errors', {}), r.content[:200])
    r = patch(dc, {'disease_tags': 'coccidiosis'})
    check('disease_tags must be a list -> 400', r.status_code == 400, r.content[:200])
    r = patch(dc, {'status': 'archived'})
    check('unknown status -> 400', r.status_code == 400, r.content[:200])
    other, other_case = book(farmer2, doctor, status='accepted', days=4)
    r = patch(dc, {'consultation_id': str(other.id), 'diagnosis': 'x'})
    check('mismatched consultation_id -> 400', r.status_code == 400, r.content[:200])
    r = patch(dc, {'status': 'closed'}, url=f'/api/doctor/cases/{other_case.id}/')
    check('closing without diagnosis/treatment -> 400 case_incomplete with field errors',
          r.status_code == 400 and r.json().get('code') == 'case_incomplete'
          and set(r.json().get('errors', {})) == {'diagnosis', 'treatment_plan'}, r.content[:300])
    check('refused close left the case open', CaseDetail.objects.get(id=other_case.id).case_status == 'open')
    check('invalid values never reached the DB', ConsultationNote.objects.get(consultation=consult).diagnosis == 'Early coccidiosis')

    # ── close / reopen ───────────────────────────────────────────────────────
    print('\n== close case on the Case page ==')
    r = patch(dc, {'status': 'closed'})
    check('close -> 200, stage closed, read-only',
          r.status_code == 200 and r.json()['stage'] == 'closed' and r.json()['editable'] is False, r.content[:300])
    check('closing does not complete the consultation', Consultation.objects.get(id=consult.id).status == 'accepted')
    check('audit row for the close', audit_rows('case_closed').count() == 1)
    r = patch(dc, {'diagnosis': 'edit after close'})
    check('editing a closed case -> 409 case_closed',
          r.status_code == 409 and r.json().get('code') == 'case_closed', r.content[:200])
    r = fc.get(f'/api/consultations/{consult.id}/clinical-results/')
    check('farmer still cannot see clinical results before completion (409)', r.status_code == 409, r.status_code)
    r = dc.post('/api/doctor/prescriptions/', {
        'consultation_id': str(consult.id), 'case_advice': 'x',
        'medicines': [{'name': 'A', 'dosage': '1', 'duration': '1'}]}, content_type='application/json')
    check('prescription before completion -> 409', r.status_code == 409, r.status_code)
    r = patch(dc, {'status': 'open'})
    check('reopen -> 200, stage open again', r.status_code == 200 and r.json()['stage'] == 'open', r.content[:200])
    check('audit row for the reopen', audit_rows('case_reopened').count() == 1)
    r = patch(dc, {'status': 'closed'})
    check('close again -> 200', r.status_code == 200 and r.json()['stage'] == 'closed', r.content[:200])

    # ── Mark as Complete (from the Case page: appointment_id from the case row) ──
    print('\n== mark as complete ==')
    appointment_id = r.json()['appointment_id']
    check('case row carries the consultation id for completion', appointment_id == str(consult.id))
    check('farmer cannot complete (403)', act(fc, appointment_id, 'complete').status_code == 403)
    check('another doctor cannot complete (404)', act(d2, appointment_id, 'complete').status_code == 404)
    check('unauthenticated complete -> 401', act(anon, appointment_id, 'complete').status_code == 401)

    results = []
    barrier = threading.Barrier(4)

    def racer():
        try:
            c = client_for(doctor)
            barrier.wait()
            resp = act(c, appointment_id, 'complete')
            results.append(resp.status_code)
        finally:
            connection.close()

    threads = [threading.Thread(target=racer) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    check('4 simultaneous Mark as Complete -> all 200', results == [200] * 4, results)
    history = ConsultationStatusHistory.objects.filter(consultation=consult, to_status='completed').count()
    check('exactly one completed history row', history == 1, history)
    payments = Payment.objects.filter(reference_id=consult.id, payment_type='consultation').count()
    check('exactly one receipt/payment row', payments == 1, payments)
    ready = Notification.objects.filter(user=farmer, title='Clinical results ready').count()
    check('farmer notified exactly once', ready == 1, ready)
    r = act(dc, appointment_id, 'complete')
    check('repeat complete -> 200 already_completed (idempotent)',
          r.status_code == 200 and r.json().get('already_completed') is True and r.json()['status'] == 'completed',
          r.content[:200])
    check('repeat complete added no side effects',
          ConsultationStatusHistory.objects.filter(consultation=consult, to_status='completed').count() == 1
          and Payment.objects.filter(reference_id=consult.id).count() == 1
          and Notification.objects.filter(user=farmer, title='Clinical results ready').count() == 1)
    row = dc.get(case_url).json()
    check('case stage completed -> Issue prescription & advice', row['stage'] == 'completed', row['stage'])
    check('case status closed, history preserved',
          row['status'] == 'closed' and list(ConsultationStatusHistory.objects.filter(consultation=consult)
                                              .order_by('created_at').values_list('to_status', flat=True))
          == ['accepted', 'completed'])
    r = patch(dc, {'diagnosis': 'edit after completion'})
    check('editing a completed case -> 409 consultation_completed',
          r.status_code == 409 and r.json().get('code') == 'consultation_completed', r.content[:200])
    r = patch(dc, {'status': 'open'})
    check('a completed case cannot be reopened (409)', r.status_code == 409, r.content[:200])

    # ── farmer visibility ────────────────────────────────────────────────────
    print('\n== farmer visibility ==')
    r = fc.get(f'/api/consultations/{consult.id}/clinical-results/')
    note_json = r.json().get('clinical_note') or {}
    check('farmer sees diagnosis/treatment/warnings/next steps after completion',
          r.status_code == 200 and note_json.get('diagnosis') == 'Early coccidiosis'
          and note_json.get('warnings') == 'Withdraw eggs for 7 days'
          and note_json.get('next_steps') == 'Re-check droppings on day 5', r.content[:300])
    check('farmer sees the doctor-annotated case fields',
          (r.json().get('case') or {}).get('vaccine_history') == 'ND + IB at day 7', r.json().get('case'))
    check("another farmer cannot view this case's results (404)",
          f2.get(f'/api/consultations/{consult.id}/clinical-results/').status_code == 404)
    check('farmer cannot write clinical fields through the farmer API',
          fc.patch('/api/consultations/', {'id': str(consult.id), 'diagnosis': 'farmer'},
                   content_type='application/json').status_code in (200, 400)
          and ConsultationNote.objects.get(consultation=consult).diagnosis == 'Early coccidiosis')

    # ── Issue prescription & advice ──────────────────────────────────────────
    print('\n== issue prescription & advice ==')
    rx = {
        'consultation_id': str(consult.id), 'case_advice': 'Keep litter dry; isolate weak birds',
        'dosage_notes': 'Mix fresh daily',
        'medicines': [{'name': 'Amprolium', 'dosage': '1 ml/L', 'duration': '5 days', 'notes': 'in water'},
                      {'name': 'Vitamin AD3E', 'dosage': '1 ml/2 L', 'duration': '3 days'}],
        'follow_up_instructions': 'Send droppings photo on day 3',
        'follow_up_date': (date.today() + timedelta(days=10)).isoformat(), 'follow_up_time': '15:30',
    }
    check('another doctor cannot prescribe (404)',
          d2.post('/api/doctor/prescriptions/', rx, content_type='application/json').status_code == 404)
    check('farmer cannot prescribe (403)',
          fc.post('/api/doctor/prescriptions/', rx, content_type='application/json').status_code == 403)
    r = dc.post('/api/doctor/prescriptions/', rx, content_type='application/json')
    check('prescription after completion -> 201', r.status_code == 201, r.content[:300])
    check('prescription stored with 2 medicines',
          PrescriptionItem.objects.filter(prescription__consultation=consult).count() == 2)
    row = dc.get(case_url).json()
    check('case stage prescribed, prescription + follow-up on the case row',
          row['stage'] == 'prescribed' and row['prescription']['case_advice'].startswith('Keep litter')
          and row['follow_up_date'].endswith('T15:30:00'), row)
    r = dc.post('/api/doctor/prescriptions/', {**rx, 'case_advice': 'Revised advice'}, content_type='application/json')
    check('existing policy: a revised prescription may be issued (201)', r.status_code == 201, r.content[:200])
    check('follow-up not duplicated by the revision',
          FollowUp.objects.filter(consultation=consult, status='pending').count() == 1)
    row = dc.get(case_url).json()
    check('case shows the latest prescription and the count',
          row['prescription']['case_advice'] == 'Revised advice' and row['prescription_count'] == 2, row)
    r = fc.get(f'/api/consultations/{consult.id}/clinical-results/')
    check('farmer sees prescriptions + follow-up',
          len(r.json()['prescriptions']) == 2 and len(r.json()['follow_ups']) == 1, r.content[:300])
    check('farmer notified of the prescription and follow-up',
          Notification.objects.filter(user=farmer, title='Prescription added').count() == 2
          and Notification.objects.filter(user=farmer, title='Follow-up scheduled').exists())

    # ── receipt / payment / earnings / rating ────────────────────────────────
    print('\n== receipt, payment, earnings, rating ==')
    r = fc.get(f'/api/consultations/{consult.id}/receipt/')
    check('farmer receipt 200', r.status_code == 200 and r.json()['receipt_number'] == f'CASH-{consult.id}', r.content[:200])
    r = fc.post(f'/api/consultations/{consult.id}/mark-paid/', {}, content_type='application/json')
    check('mark-paid 200', r.status_code == 200 and r.json()['status'] == 'completed', r.content[:200])
    fc.post(f'/api/consultations/{consult.id}/mark-paid/', {}, content_type='application/json')
    earnings = DoctorEarning.objects.filter(consultation=consult)
    check('exactly one doctor earning, net of platform fee',
          earnings.count() == 1 and abs(float(earnings.first().net_amount) - 1975.0) < 0.01, list(earnings.values()))
    r = fc.patch('/api/consultations/', {'id': str(consult.id), 'rating': 5, 'review': 'Clear advice'},
                 content_type='application/json')
    check('farmer rating 200', r.status_code == 200 and r.json()['rating'] == 5, r.content[:200])
    s = dc.get('/api/doctor/dashboard/').json()['summary']
    check('dashboard completed_cases counts completed consultations only', s['completed_cases'] == 1, s['completed_cases'])

    # ── ended consultation ───────────────────────────────────────────────────
    print('\n== ended consultation ==')
    rejected, rejected_case = book(farmer, doctor, days=5)
    act(dc, rejected.id, 'reject')
    r = patch(dc, {'diagnosis': 'x'}, url=f'/api/doctor/cases/{rejected_case.id}/')
    check('rejected consultation case is read-only (409 consultation_ended)',
          r.status_code == 409 and r.json().get('code') == 'consultation_ended', r.content[:200])

    # ── Schedule scope ───────────────────────────────────────────────────────
    print('\n== schedule page scope ==')
    pending, _ = book(farmer2, doctor, days=6)
    proposed, _ = book(farmer2, doctor, status='reschedule_proposed', days=6, hour=11)
    in_progress, _ = book(farmer2, doctor, status='in_progress', days=6, hour=13)
    cancelled, _ = book(farmer2, doctor, status='cancelled', days=6, hour=15)
    r = dc.get('/api/doctor/appointments/?scope=schedule')
    check('schedule scope 200', r.status_code == 200, r.content[:200])
    body = r.json()
    req_ids = {x['id'] for x in body['requests']}
    up_ids = {x['id'] for x in body['upcoming']}
    check('requests = requested + reschedule proposed',
          req_ids == {str(pending.id), str(proposed.id)}, req_ids)
    check('upcoming = accepted + in progress',
          up_ids == {str(other.id), str(in_progress.id)}, up_ids)
    excluded = {str(consult.id), str(rejected.id), str(cancelled.id)}
    check('completed / rejected / cancelled are not schedule items',
          not (excluded & (req_ids | up_ids)) and not (excluded & {x['id'] for x in body['appointments']}))
    check('every schedule row carries the date/time, mode and status',
          all({'scheduled_at', 'mode', 'status', 'case_id'} <= x.keys() for x in body['appointments']))
    full_list = {x['id'] for x in dc.get('/api/doctor/appointments/').json()['appointments']}
    check('unscoped appointments list is unchanged (still every consultation)', excluded <= full_list)
    r = d2.get('/api/doctor/appointments/?scope=schedule')
    check("another doctor's schedule has none of these rows",
          r.status_code == 200 and not r.json()['appointments'], r.content[:200])
    check('farmer cannot read the doctor schedule (403)',
          fc.get('/api/doctor/appointments/?scope=schedule').status_code == 403)
    check('unauthenticated schedule -> 401', anon.get('/api/doctor/appointments/?scope=schedule').status_code == 401)
    check('accept still works from the schedule', act(dc, pending.id, 'accept').status_code == 200)

    cleanup(users)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
