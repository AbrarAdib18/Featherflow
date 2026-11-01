"""F-001 regression — admin consultations list with NULL appointment time.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_admin_consultations_null_time.py

Live DB, `nulltime+` throw-away accounts/rows; idempotent (cleans on entry and
exit). Before the fix, `GET /api/admin-panel/consultations/` raised
`TypeError: unsupported format string passed to NoneType.__format__` (HTTP 500)
as soon as one consultation had no appointment time (the SQL schema allows it:
farmer_panel_integrity_extension.sql dropped NOT NULL on date and time).

Proves: scheduled rows still serialise; NULL-time and NULL-date rows are
returned (not dropped, no 500); mixed lists sort scheduled-first newest-first
with unscheduled rows last; null serialises as JSON null (+ `scheduled:false`);
the dispute serialiser is null-safe too; unauthenticated / non-admin /
wrong-module admins stay denied.
"""
import os
import sys
from datetime import date, time, timedelta

import django
import django.utils.timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from consultations.models import Consultation, ConsultationDispute  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'nulltime+'
URL = '/api/admin-panel/consultations/?page_size=200'
_n = [0]


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
    ConsultationDispute.objects.filter(consultation__farmer__in=users).delete()
    Consultation.objects.filter(farmer__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin' if role_name.startswith('admin') else role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0196{n:07d}', full_name=f'NullTime {tag} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def mk_consult(farmer, doctor, d, t, topic):
    return Consultation.objects.create(
        farmer=farmer, doctor=doctor, mode='online', status='requested',
        urgency_level='routine', appointment_date=d, appointment_time=t, review_text=topic)


def mine(rows, tag):
    return [r for r in rows if r['topic'].startswith(tag)]


def run():
    print('\n== F-001: admin consultations with NULL appointment time ==\n')
    cleanup()
    doctor = mk_user('doctor', 'doc')
    farmer = mk_user('farmer', 'farm')
    other = mk_user('farmer', 'other')
    admin = mk_user('admin_doctor', 'docadmin')
    finance = mk_user('admin_finance', 'finadmin')
    ac, fc, oc, nc = client_for(admin), client_for(finance), client_for(other), Client()

    today = date.today()
    # 1. Consultation WITH an appointment time.
    print('-- 1. scheduled consultation')
    mk_consult(farmer, doctor, today + timedelta(days=5), time(10, 30), 'T-sched-a')
    r = ac.get(URL)
    check('list returns 200 with a scheduled consultation', r.status_code == 200, r.content[:200])
    row = mine(r.json()['results'], 'T-sched-a')
    check('scheduled row present', len(row) == 1, len(row))
    if row:
        row = row[0]
        check('appointment_time serialised as HH:MM', row['appointment_time'] == '10:30', row)
        check('appointment_date serialised as ISO date', row['appointment_date'] == (today + timedelta(days=5)).isoformat(), row)
        check('scheduled == true', row['scheduled'] is True)
        check('legacy `time` string unchanged ("YYYY-MM-DD HH:MM")', row['time'] == f'{today + timedelta(days=5)} 10:30', row['time'])

    # 2. Consultation with NULL appointment time (and NULL date).
    print('-- 2. NULL appointment time')
    mk_consult(farmer, doctor, None, None, 'T-null-both')
    r = ac.get(URL)
    check('list still 200 with a NULL date+time consultation (was 500)', r.status_code == 200, r.content[:300])
    row = mine(r.json()['results'], 'T-null-both')
    check('NULL-time consultation is returned (not dropped)', len(row) == 1, len(row))
    if row:
        row = row[0]
        check('appointment_time is JSON null', row['appointment_time'] is None, row)
        check('appointment_date is JSON null', row['appointment_date'] is None, row)
        check('time is JSON null (not "None"/garbled)', row['time'] is None, row['time'])
        check('scheduled == false', row['scheduled'] is False)
        check('patient/doctor/status still populated', bool(row['patient']) and bool(row['doctor']) and row['status'] == 'requested', row)
    # date present but time missing
    mk_consult(farmer, doctor, today + timedelta(days=2), None, 'T-null-time')
    r = ac.get(URL)
    check('date-only consultation does not crash (200)', r.status_code == 200, r.content[:300])
    row = mine(r.json()['results'], 'T-null-time')
    check('date-only row: date kept, time null, scheduled false',
          len(row) == 1 and row[0]['appointment_date'] == (today + timedelta(days=2)).isoformat()
          and row[0]['appointment_time'] is None and row[0]['scheduled'] is False, row)

    # 3/5. Mixed list, ordering.
    print('-- 3/5. mixed NULL / non-NULL: ordering')
    mk_consult(farmer, doctor, today + timedelta(days=9), time(8, 0), 'T-sched-new')
    mk_consult(farmer, doctor, today + timedelta(days=9), time(15, 45), 'T-sched-newer')
    mk_consult(farmer, doctor, None, None, 'T-null-2')
    mk_consult(farmer, doctor, today - timedelta(days=30), time(9, 0), 'T-sched-old')
    r = ac.get(URL)
    check('mixed list returns 200', r.status_code == 200, r.content[:200])
    rows = r.json()['results']
    mine_rows = [x for x in rows if x['topic'].startswith('T-')]
    check('all 7 test consultations returned', len(mine_rows) == 7, len(mine_rows))
    order = [x['topic'] for x in mine_rows]
    sched = [t for t in order if t.startswith('T-sched')]
    check('scheduled rows newest-first (date desc, then time desc)',
          sched == ['T-sched-newer', 'T-sched-new', 'T-sched-a', 'T-sched-old'], sched)
    first_unscheduled = min(i for i, x in enumerate(rows) if not x['scheduled'])
    check('every scheduled row (whole table) precedes every unscheduled row',
          all(not x['scheduled'] for x in rows[first_unscheduled:]), [x['scheduled'] for x in rows])
    check('count/total includes NULL-time rows', r.json()['count'] >= 7, r.json().get('count'))
    r2 = ac.get('/api/admin-panel/consultations/?page_size=2&page=1')
    check('paginated request (page_size=2) is 200 and bounded', r2.status_code == 200 and len(r2.json()['results']) == 2, r2.content[:200])

    # 4. The other serialiser that formatted the time (disputes).
    print('-- dispute serialiser')
    null_c = Consultation.objects.get(farmer=farmer, review_text='T-null-2')
    ConsultationDispute.objects.create(
        consultation=null_c, raised_by=farmer, raised_role='farmer', category='other', description='null-time dispute', status='open',
        created_at=django.utils.timezone.now(), updated_at=django.utils.timezone.now())
    r = ac.get('/api/admin-panel/consultation-disputes/')
    check('disputes list 200 for a consultation with no time (was a latent 500)', r.status_code == 200, r.content[:300])
    d = [x for x in r.json()['results'] if x.get('description') == 'null-time dispute']
    check('dispute row present with a readable appointment label', len(d) == 1 and d[0]['appointment'] == 'Time not scheduled', d)

    # 7. Authorization unchanged.
    print('-- authorization')
    check('anonymous -> 401', nc.get(URL).status_code == 401)
    check('farmer (non-admin) -> 403', oc.get(URL).status_code == 403)
    check('admin without the doctors module (finance) -> 403', fc.get(URL).status_code == 403)
    check('doctor admin -> 200', ac.get(URL).status_code == 200)

    cleanup()
    print(f'\n== {PASS} passed, {FAIL} failed ==')
    return FAIL == 0


if __name__ == '__main__':
    try:
        ok = run()
    finally:
        cleanup()
    sys.exit(0 if ok else 1)
