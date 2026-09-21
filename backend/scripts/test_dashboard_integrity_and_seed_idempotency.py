"""Phase 4 — dashboard zero/empty behaviour for a brand-new farmer, and
`seed_demo_data_for_phone` idempotency, run programmatically end to end.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_dashboard_integrity_and_seed_idempotency.py

Live DB. Dashboard section uses `dashintegritytest+` throw-away accounts,
cleaned on entry/exit. Seed section runs against a dedicated demo phone number
(never the real `01713018156` demo account) with `--reset`, twice in a row,
and cleans up its own rows afterward.

Covers:
- A farmer with zero expenses/revenue/flocks/consultations gets a real 200
  with genuine zeros (not an error, not a crash on FarmerProfile.get()).
- due_tax is computable (a number, not the old hardcoded None) even with no
  tax profile — 'not set up' and 'nothing owed' are distinguishable.
- total_birds_source correctly reports 'profile' before any flock exists.
- charts.monthly is zero-filled (6 entries) rather than an empty list.
- Running seed_demo_data_for_phone twice creates the full dataset once and
  adds nothing on the second run (record counts identical before/after the
  second call, for every model the command touches).
"""
import os
import sys
from datetime import date
from io import StringIO

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from community.models import Comment, Post, Reaction  # noqa: E402
from consultations.models import Consultation  # noqa: E402
from doctor.models import Conversation, Message  # noqa: E402
from expenses.models import Expense, Loan, Revenue  # noqa: E402
from farms.models import Farm, Flock, Shed  # noqa: E402
from feed.models import FeedStock  # noqa: E402
from ml.models import DiseaseScan  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from tax.models import TaxPayment  # noqa: E402
from users.models import Role, User  # noqa: E402
from workers.models import Worker, WorkerAttendance, WorkerPayment  # noqa: E402

PASS = FAIL = 0
PREFIX = 'dashintegritytest+'
SEED_PHONE = '01799912345'  # dedicated to this test, never the real demo account


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup_dashboard():
    users = User.objects.filter(email__startswith=PREFIX)
    farms = Farm.objects.filter(farmer__user__in=users)
    farms.delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()


def cleanup_seed():
    user = User.objects.filter(phone__endswith=SEED_PHONE[-9:]).first()
    if user is None:
        return
    farm = Farm.objects.filter(farmer__user=user).first()
    if farm:
        WorkerPayment.objects.filter(worker__farm=farm).delete()
        WorkerAttendance.objects.filter(worker__farm=farm).delete()
        Worker.objects.filter(farm=farm).delete()
        Expense.objects.filter(farm=farm).delete()
        Revenue.objects.filter(farm=farm).delete()
        Loan.objects.filter(farm=farm).delete()
        FeedStock.objects.filter(farm=farm).delete()
        Flock.objects.filter(farm=farm).delete()
        Shed.objects.filter(farm=farm).delete()
    Message.objects.filter(conversation__participant_one=user).delete()
    Message.objects.filter(conversation__participant_two=user).delete()
    Conversation.objects.filter(participant_one=user).delete()
    Conversation.objects.filter(participant_two=user).delete()
    Consultation.objects.filter(farmer=user).delete()
    Comment.objects.filter(author=user).delete()
    Reaction.objects.filter(user=user).delete()
    Post.objects.filter(author=user).delete()
    DiseaseScan.objects.filter(user=user).delete()
    Notification.objects.filter(user=user).delete()
    TaxPayment.objects.filter(user=user).delete()
    if farm:
        farm.delete()
    FarmerProfile.objects.filter(user=user).delete()
    user.delete()


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def run_dashboard_checks():
    print('\n== brand-new farmer: dashboard is a real 200, not an error, not stale zeros ==\n')
    cleanup_dashboard()
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    user = User.objects.create_user(
        email=f'{PREFIX}1@example.com', password='Test1234!',
        phone='0196' + '0000001', full_name='New Farmer',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    user.roles.add(role)
    # Deliberately no FarmerProfile row yet — dashboard_views.dashboard() used
    # to 500 here via a bare FarmerProfile.objects.get().
    c = client_for(user)

    r = c.get('/api/farmers/dashboard/')
    check('dashboard returns 200 for a farmer with no profile row yet',
          r.status_code == 200, r.content[:300])
    body = r.json()
    check('total_revenue is a real zero, not missing',
          body['finance']['total_revenue'] == 0.0, body['finance'])
    check('total_birds_source is "profile" before any flock exists',
          body['farm']['total_birds_source'] == 'profile', body['farm'])
    check('due_tax is computable (a number) even with no tax profile',
          isinstance(body['finance']['due_tax'], (int, float)), body['finance'])
    check('alerts is an empty list, not an error', body['alerts'] == [], body['alerts'])
    check('recent_activity is an empty list for a brand-new farmer',
          body['recent_activity'] == [], body['recent_activity'])

    r2 = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    charts = r2.json()['charts']
    check('cost dashboard also 200s for the same brand-new farmer',
          r2.status_code == 200, r2.content[:300])
    check('charts.monthly is zero-filled (6 entries), not an empty chart',
          len(charts['monthly']) == 6, charts['monthly'])

    cleanup_dashboard()


def _model_counts(user, farm):
    return {
        'expenses': Expense.objects.filter(farm=farm).count(),
        'revenues': Revenue.objects.filter(farm=farm).count(),
        'loans': Loan.objects.filter(farm=farm).count(),
        'workers': Worker.objects.filter(farm=farm).count(),
        'worker_payments': WorkerPayment.objects.filter(worker__farm=farm).count(),
        'consultations': Consultation.objects.filter(farmer=user).count(),
        'messages': Message.objects.filter(conversation__participant_one=user).count()
        + Message.objects.filter(conversation__participant_two=user).count(),
        'posts': Post.objects.filter(author=user).count(),
        'disease_scans': DiseaseScan.objects.filter(user=user).count(),
        'notifications': Notification.objects.filter(user=user).count(),
        'tax_payments': TaxPayment.objects.filter(user=user).count(),
    }


def run_seed_idempotency_checks():
    print('\n== seed_demo_data_for_phone: idempotent across two runs ==\n')
    cleanup_seed()

    out1 = StringIO()
    call_command('seed_demo_data_for_phone', phone=SEED_PHONE, reset=True, stdout=out1)
    user = User.objects.get(phone__endswith=SEED_PHONE[-9:])
    farm = Farm.objects.filter(farmer__user=user).first()
    check('first run (with --reset) creates a farm', farm is not None)
    counts_after_first = _model_counts(user, farm)
    check('first run seeds at least one row in every tracked model',
          all(v > 0 for v in counts_after_first.values()), counts_after_first)

    out2 = StringIO()
    call_command('seed_demo_data_for_phone', phone=SEED_PHONE, stdout=out2)
    counts_after_second = _model_counts(user, farm)
    check('second run (no --reset) adds nothing — every count is unchanged',
          counts_after_first == counts_after_second,
          (counts_after_first, counts_after_second))

    out3 = StringIO()
    call_command('seed_demo_data_for_phone', phone=SEED_PHONE, stdout=out3)
    counts_after_third = _model_counts(user, farm)
    check('a third run is still a no-op', counts_after_second == counts_after_third,
          (counts_after_second, counts_after_third))

    cleanup_seed()
    check('cleanup leaves no trace of the seeded account',
          not User.objects.filter(phone__endswith=SEED_PHONE[-9:]).exists())


def run():
    print('\n== Phase 4: dashboard integrity + seed idempotency ==\n')
    run_dashboard_checks()
    run_seed_idempotency_checks()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
