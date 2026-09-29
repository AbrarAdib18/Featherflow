"""Finance Admin dashboard / subscriptions / cashout / RBAC / revenue tests.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_finance_admin.py

Live DB, `financetest+`-prefixed throw-away accounts + their financial
records. Idempotent (cleans up at both start and end). See
FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md / FINANCE_ADMIN_CASHOUT_WORKFLOW.md
/ FINANCE_ADMIN_RBAC_CHANGES.md.
"""
import hashlib
import os
import sys
from datetime import date, timedelta

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from api.finance_models import CashoutReview, RevenueEntry  # noqa: E402
from payments.models import Payment  # noqa: E402
from subscriptions.models import Subscription, SubscriptionPlan  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'financetest+'


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
    payments = Payment.objects.filter(user__in=users)
    CashoutReview.objects.filter(payment_id__in=list(payments.values_list('id', flat=True))).delete()
    RevenueEntry.objects.filter(source_payment_id__in=list(payments.values_list('id', flat=True))).delete()
    Subscription.objects.filter(user__in=users).delete()
    payments.delete()
    SubscriptionPlan.objects.filter(name__startswith='financetest-plan-').delete()
    users.delete()


def mk_admin(tag, role_name):
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin'})
    email = f'{PREFIX}{tag}@example.com'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'{tag} tester', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    user.set_password('Test1234!')
    user.account_status = 'active'
    user.save()
    user.roles.clear()
    user.roles.add(role)
    from profiles.models import AdminProfile
    AdminProfile.objects.update_or_create(user=user, defaults=dict(
        admin_role=role, job_title='Tester', department='QA', start_date=date(2024, 1, 1),
        admin_sub_role=role_name.replace('admin_', ''), approval_status='approved',
        is_active=True, is_suspended=False, internal_approval_by_founder_hr=True))
    return user


def mk_farmer(tag):
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': None})
    email = f'{PREFIX}{tag}@example.com'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'{tag} farmer', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    user.roles.add(role)
    return user


def auth(client, user):
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'


def main():
    cleanup()
    finance = mk_admin('finance', 'admin_finance')
    ops = mk_admin('ops', 'admin_operations')
    fc = Client()
    auth(fc, finance)
    oc = Client()
    auth(oc, ops)

    # ── RBAC ─────────────────────────────────────────────────────────────
    print('\n== RBAC: Finance Admin scope ==')
    check('finance can view finance dashboard (200)',
          fc.get('/api/admin-panel/finance/dashboard/').status_code == 200)
    check('finance can view subscription plans (200)',
          fc.get('/api/admin-panel/subscription-plans/').status_code == 200)
    check('finance can view pending cashouts (200)',
          fc.get('/api/admin-panel/cashouts/pending/').status_code == 200)
    check('finance BLOCKED from user list (403)',
          fc.get('/api/admin-panel/users/').status_code == 403)
    check('finance BLOCKED from the operational approval queue (403)',
          fc.get('/api/admin-panel/approval-queue/').status_code == 403)
    check('finance BLOCKED from doctor verification (403)',
          fc.get('/api/admin-panel/doctors/').status_code == 403)
    check('finance BLOCKED from pharmacy module (403)',
          fc.get('/api/admin-panel/pharmacies/').status_code == 403)
    check('finance BLOCKED from delivery riders/payouts (403)',
          fc.get('/api/admin-panel/riders/').status_code == 403)
    check('finance BLOCKED from admin account management (403)',
          fc.get('/api/admin-panel/admins/').status_code == 403)
    r = fc.patch('/api/admin-panel/admins/00000000-0000-0000-0000-000000000000/hourly-rate/',
                 data={'hourly_rate': '900'}, content_type='application/json')
    check('finance cannot touch admin hourly-rate endpoint (403/404, never 200)',
          r.status_code in (403, 404), r.status_code)
    check('anonymous request is refused (401/403)',
          Client().get('/api/admin-panel/finance/dashboard/').status_code in (401, 403))

    # ── Active users ─────────────────────────────────────────────────────
    print('\n== active users definition ==')
    before = fc.get('/api/admin-panel/finance/dashboard/').json()['active_users']
    active_u = mk_farmer('activeuser')
    active_u.account_status = 'active'
    active_u.save(update_fields=['account_status'])
    pending_u = mk_farmer('pendinguser')
    pending_u.account_status = 'pending'
    pending_u.save(update_fields=['account_status'])
    suspended_u = mk_farmer('suspendeduser')
    suspended_u.account_status = 'suspended'
    suspended_u.save(update_fields=['account_status'])
    rejected_u = mk_farmer('rejecteduser')
    # This project's account_status check constraint allows
    # pending/active/suspended/banned — 'banned' is the closest existing
    # status to a rejected/deactivated account.
    rejected_u.account_status = 'banned'
    rejected_u.save(update_fields=['account_status'])
    after = fc.get('/api/admin-panel/finance/dashboard/').json()['active_users']
    check('active_users increases by exactly 1 for the one truly-active user',
          after - before == 1, (before, after))

    # ── Subscription plans ───────────────────────────────────────────────
    print('\n== subscription plans (real DB, not seed data) ==')
    r = fc.post('/api/admin-panel/subscription-plans/', data={
        'name': 'financetest-plan-basic', 'price': '199.00', 'currency': 'BDT',
        'duration_days': 30, 'features_unlocked': ['x'],
    }, content_type='application/json')
    check('create plan 201', r.status_code == 201, r.content[:200])
    plan_id = r.json()['id'] if r.status_code == 201 else None
    r2 = fc.post('/api/admin-panel/subscription-plans/', data={
        'name': 'financetest-plan-basic', 'price': '50.00', 'currency': 'BDT',
    }, content_type='application/json')
    check('duplicate plan name rejected (400/409)', r2.status_code in (400, 409), r2.status_code)
    r3 = fc.post('/api/admin-panel/subscription-plans/', data={
        'name': 'financetest-plan-bad', 'price': '-5.00', 'currency': 'BDT',
    }, content_type='application/json')
    check('negative price rejected (400)', r3.status_code == 400, r3.content[:200])
    if plan_id:
        plan = SubscriptionPlan.objects.get(pk=plan_id)
        u = mk_farmer('plansubscriber')
        sub = Subscription.objects.create(user=u, plan=plan, status='active', started_at=timezone.now())
        r4 = fc.patch(f'/api/admin-panel/subscription-plans/{plan_id}/',
                      data={'is_active': False}, content_type='application/json')
        check('deactivate plan 200', r4.status_code == 200, r4.content[:200])
        sub.refresh_from_db()
        check('deactivating a plan does not corrupt its historical subscription',
              sub.status == 'active' and sub.plan_id == plan.id)
    check('ops (non-finance) cannot manage subscription plans (403)',
          oc.post('/api/admin-panel/subscription-plans/', data={'name': 'x', 'price': '1'},
                  content_type='application/json').status_code == 403)

    # ── Revenue idempotency ──────────────────────────────────────────────
    print('\n== revenue recognition idempotency ==')
    from billing.services import recognize_revenue, reverse_revenue
    payer = mk_farmer('payer')
    payment = Payment.objects.create(user=payer, amount=450, currency='BDT',
                                     payment_type='subscription', status='completed',
                                     created_at=timezone.now())
    recognize_revenue(payment)
    recognize_revenue(payment)  # duplicate confirmation
    check('exactly one revenue entry after a duplicate confirmation',
          RevenueEntry.objects.filter(source_payment_id=payment.id,
                                      category=RevenueEntry.CATEGORY_SUBSCRIPTION).count() == 1)
    check('revenue amount matches the payment amount',
          RevenueEntry.objects.get(source_payment_id=payment.id,
                                   category=RevenueEntry.CATEGORY_SUBSCRIPTION).amount == payment.amount)
    reverse_revenue(payment)
    reverse_revenue(payment)  # duplicate refund
    check('exactly one reversal entry after a duplicate refund',
          RevenueEntry.objects.filter(source_payment_id=payment.id,
                                      category=RevenueEntry.CATEGORY_REFUND_ADJUSTMENT).count() == 1)
    check('original recognition row is never deleted by a reversal',
          RevenueEntry.objects.filter(source_payment_id=payment.id,
                                      category=RevenueEntry.CATEGORY_SUBSCRIPTION).exists())
    net = RevenueEntry.objects.filter(source_payment_id=payment.id).count()
    check('reversal + original net out to two distinct visible rows (not silently deleted)', net == 2)

    pending_payment = Payment.objects.create(user=payer, amount=300, currency='BDT',
                                             payment_type='subscription', status='pending',
                                             created_at=timezone.now())
    check('a pending (never-recognized) payment has no revenue entry',
          not RevenueEntry.objects.filter(source_payment_id=pending_payment.id).exists())

    # ── Cashout workflow ─────────────────────────────────────────────────
    print('\n== cashout workflow ==')
    requester = mk_farmer('cashoutrequester')
    cash_payment = Payment.objects.create(user=requester, amount=1200, currency='BDT',
                                          payment_method='bkash', payment_type='cashout',
                                          status='pending', created_at=timezone.now())
    review = CashoutReview.objects.create(payment_id=cash_payment.id)
    r = fc.get('/api/admin-panel/cashouts/pending/')
    ids = [row['id'] for row in r.json()['results']]
    check('new cashout appears in Pending Cashout Requests', str(review.id) in ids)
    check('no user-verification data mixed into the cashout row',
          'is_verified' not in r.json()['results'][0] and 'license_number' not in r.json()['results'][0])

    r2 = fc.post(f'/api/admin-panel/cashouts/{review.id}/review/',
                 data={'decision': 'approve'}, content_type='application/json')
    check('approve cashout 200', r2.status_code == 200, r2.content[:200])
    r3 = fc.get('/api/admin-panel/cashouts/approved/')
    check('approved cashout now appears in Approved Cashout Requests',
          str(review.id) in [row['id'] for row in r3.json()['results']])
    r4 = fc.post(f'/api/admin-panel/cashouts/{review.id}/review/',
                 data={'decision': 'approve'}, content_type='application/json')
    check('duplicate approval is idempotently rejected (409)', r4.status_code == 409, r4.content[:200])

    review2 = CashoutReview.objects.create(payment_id=Payment.objects.create(
        user=requester, amount=500, currency='BDT', payment_method='nagad',
        payment_type='cashout', status='pending', created_at=timezone.now()).id)
    r5 = fc.post(f'/api/admin-panel/cashouts/{review2.id}/review/',
                 data={'decision': 'reject'}, content_type='application/json')
    check('reject without a reason is rejected (400)', r5.status_code == 400, r5.content[:200])
    r6 = fc.post(f'/api/admin-panel/cashouts/{review2.id}/review/',
                 data={'decision': 'reject', 'reason': 'Suspicious account details.'},
                 content_type='application/json')
    check('reject with a reason succeeds (200)', r6.status_code == 200, r6.content[:200])
    check('rejected cashout is neither pending nor approved',
          review2.id != review.id and
          CashoutReview.objects.get(pk=review2.id).status == 'rejected')

    # self-approval
    self_payment = Payment.objects.create(user=finance, amount=100, currency='BDT',
                                          payment_type='cashout', status='pending',
                                          created_at=timezone.now())
    self_review = CashoutReview.objects.create(payment_id=self_payment.id)
    r7 = fc.post(f'/api/admin-panel/cashouts/{self_review.id}/review/',
                 data={'decision': 'approve'}, content_type='application/json')
    check('Finance Admin cannot approve their own cashout request (403)',
          r7.status_code == 403, r7.content[:200])

    # above-threshold escalation
    big_payment = Payment.objects.create(user=requester, amount=6000, currency='BDT',
                                         payment_method='bkash', payment_type='cashout',
                                         status='pending', created_at=timezone.now())
    big_review = CashoutReview.objects.create(payment_id=big_payment.id)
    r8 = fc.post(f'/api/admin-panel/cashouts/{big_review.id}/review/',
                 data={'decision': 'approve'}, content_type='application/json')
    check('above-threshold cashout is queued for Operations/Super Admin (202), not auto-approved',
          r8.status_code == 202, r8.content[:200])
    big_review.refresh_from_db()
    check('queued cashout is marked under_review, not approved, until decided',
          big_review.status == 'under_review')

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


if __name__ == '__main__':
    main()
