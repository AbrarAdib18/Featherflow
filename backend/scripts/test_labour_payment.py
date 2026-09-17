"""Priority 3 — labour payment must go through a real payment intent.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_labour_payment.py

Live DB, `labourtest+` prefixed throw-away accounts. Idempotent.

Covers: "Pay" opens an intent instead of marking paid immediately, pending
does not mark paid, success marks paid (creates WorkerPayment), failure/cancel
leave the worker unpaid, duplicate submission is idempotent (same intent,
one WorkerPayment), and cross-farmer authorization.
"""
import os
import sys
from datetime import date

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

from billing.models import PaymentIntent  # noqa: E402
from farms.models import Farm  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402
from workers.models import Worker, WorkerAttendance, WorkerPayment  # noqa: E402

PASS = FAIL = 0
PREFIX = 'labourtest+'
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
    farms = Farm.objects.filter(farmer__user__in=users)
    WorkerPayment.objects.filter(worker__farm__in=farms).delete()
    WorkerAttendance.objects.filter(worker__farm__in=farms).delete()
    Worker.objects.filter(farm__in=farms).delete()
    PaymentIntent.objects.filter(user__in=users).delete()
    farms.delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_farmer():
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u = User.objects.create_user(
        email=f'{PREFIX}{n}@example.com', password='Test1234!',
        phone=f'0193{n:07d}', full_name=f'Farmer {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Priority 3: Labour payment regression ==\n')
    cleanup()

    farmer = mk_farmer()
    c = client_for(farmer)
    # Force farm/profile creation via any farmer-namespaced call, then add a worker.
    fp, _ = FarmerProfile.objects.get_or_create(
        user=farmer, defaults={'farm_name': 'F', 'owner_name': 'F', 'farm_location': 'L', 'farm_address': 'A'})
    farm = Farm.objects.create(farmer=fp, farm_name='F', farm_type='mixed', location='L', address='A')
    worker = Worker.objects.create(farm=farm, full_name='Karim', job_role='Caretaker',
                                   daily_wage=300, join_date=date.today(), status='active')
    start = date.today().replace(day=1)
    WorkerAttendance.objects.create(worker=worker, attendance_date=date.today(), status='present')

    # 1. "Pay" creates an intent, does NOT mark paid.
    r = c.post('/api/workers/payments/', {'worker_id': str(worker.id)}, content_type=JSON)
    check('pay -> 201 with an intent (not a payment)', r.status_code == 201 and r.json().get('intents'), r.content[:300])
    intent = r.json()['intents'][0]
    check('intent starts in "created" status, not paid', intent['status'] == 'created', intent)
    check('amount computed server-side (300 for 1 present day)', intent['amount'] == 300.0, intent)
    check('tapping Pay does not create a WorkerPayment yet',
          not WorkerPayment.objects.filter(worker=worker).exists())

    intent_id = intent['id']

    # 2. Selecting a method -> pending. Still not paid.
    r2 = c.post(f'/api/payments/{intent_id}/method/', {'payment_method': 'bkash'}, content_type=JSON)
    check('select method -> pending', r2.status_code == 200 and r2.json()['status'] == 'pending', r2.content[:300])
    check('pending does not mark paid',
          not WorkerPayment.objects.filter(worker=worker).exists())

    # 3. Duplicate tap while the intent is still open reuses the SAME intent.
    r_dup = c.post('/api/workers/payments/', {'worker_id': str(worker.id)}, content_type=JSON)
    check('duplicate tap reuses the same open intent (idempotent)',
          r_dup.status_code == 201 and r_dup.json()['intents'] and
          r_dup.json()['intents'][0]['id'] == intent_id, r_dup.content[:300])

    # 4. Dev-mode failure leaves the worker unpaid.
    r3 = c.post(f'/api/payments/{intent_id}/confirm/', {'outcome': 'failure'}, content_type=JSON)
    check('confirm failure -> failed status', r3.status_code == 200 and r3.json()['status'] == 'failed', r3.content[:300])
    check('failure leaves worker unpaid', not WorkerPayment.objects.filter(worker=worker).exists())

    # 5. A fresh Pay tap after the failed one opens a NEW intent (old one is terminal).
    r4 = c.post('/api/workers/payments/', {'worker_id': str(worker.id)}, content_type=JSON)
    intent2 = r4.json()['intents'][0]
    check('new intent created after a failed one (old is terminal)', intent2['id'] != intent_id, intent2)
    c.post(f'/api/payments/{intent2["id"]}/method/', {'payment_method': 'cash'}, content_type=JSON)

    # 6. Cancel leaves unpaid too.
    r5 = c.post(f'/api/payments/{intent2["id"]}/cancel/', content_type=JSON)
    check('cancel -> cancelled', r5.status_code == 200 and r5.json()['status'] == 'cancelled', r5.content[:300])
    check('cancel leaves worker unpaid', not WorkerPayment.objects.filter(worker=worker).exists())

    # 7. Success marks paid — exactly once, even if confirmed twice.
    r6 = c.post('/api/workers/payments/', {'worker_id': str(worker.id)}, content_type=JSON)
    intent3 = r6.json()['intents'][0]
    c.post(f'/api/payments/{intent3["id"]}/method/', {'payment_method': 'nagad'}, content_type=JSON)
    r7 = c.post(f'/api/payments/{intent3["id"]}/confirm/', {'outcome': 'success'}, content_type=JSON)
    check('confirm success -> succeeded', r7.status_code == 200 and r7.json()['status'] == 'succeeded', r7.content[:300])
    check('success creates exactly one WorkerPayment',
          WorkerPayment.objects.filter(worker=worker).count() == 1)
    wp = WorkerPayment.objects.get(worker=worker)
    check('WorkerPayment amount matches the intent', float(wp.amount) == intent3['amount'])

    r8 = c.post(f'/api/payments/{intent3["id"]}/confirm/', {'outcome': 'success'}, content_type=JSON)
    check('re-confirming an already-succeeded intent is idempotent (still 200, still 1 row)',
          r8.status_code == 200 and WorkerPayment.objects.filter(worker=worker).count() == 1, r8.content[:300])

    # 8. Cross-farmer authorization — another farmer cannot act on this intent.
    other = mk_farmer()
    oc = client_for(other)
    r9 = oc.get(f'/api/payments/{intent3["id"]}/')
    check('another farmer cannot read/act on this intent (404, scoped by owner)', r9.status_code == 404, r9.content[:200])
    r10 = oc.post('/api/workers/payments/', {'worker_id': str(worker.id)}, content_type=JSON)
    check("another farmer cannot pay someone else's worker (not in their farm -> no intents)",
          r10.status_code == 201 and r10.json().get('intents') == [], r10.content[:300])

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
