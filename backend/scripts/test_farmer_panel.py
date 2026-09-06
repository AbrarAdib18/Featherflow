"""End-to-end check of the Farmer / User Panel (Pass 1).

Run:  backend/venv/Scripts/python.exe backend/scripts/test_farmer_panel.py

Django test Client against the *live* configured database (needs
featherflow_schema.sql + postgres_backend_extension.sql + farmers_panel_extension.sql
applied). Creates throw-away accounts prefixed ``farmertest+`` and cleans its
own rows on entry. Idempotent.

Covers: profile read/edit + photo upload, shed/flock CRUD, cost dashboard,
expense CRUD + receipt + pay, revenue CRUD, loan request + (admin approve) +
repay, inventory, batch cost tracking, reports (CSV + PDF), cashout, feed
consumption, labor history, and the home dashboard aggregate.
"""
import io
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

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from expenses.models import Expense, Loan, Revenue  # noqa: E402
from farms.models import Farm, Flock, Shed  # noqa: E402
from feed.models import FeedConsumption  # noqa: E402
from notifications.models import Notification  # noqa: E402
from payments.models import Payment  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'farmertest+'


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
    for u in users:
        farms = Farm.objects.filter(farmer__user=u)
        FeedConsumption.objects.filter(flock__farm__in=farms).delete()
        Flock.objects.filter(farm__in=farms).delete()
        Shed.objects.filter(farm__in=farms).delete()
        Expense.objects.filter(farm__in=farms).delete()
        Revenue.objects.filter(farm__in=farms).delete()
        Loan.objects.filter(farm__in=farms).delete()
        farms.delete()
        FarmerProfile.objects.filter(user=u).delete()
        Payment.objects.filter(user=u).delete()
        Notification.objects.filter(user=u).delete()
    users.delete()


def mk_farmer(tag):
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!',
        phone=f'0180000{tag:04d}', full_name=f'Farmer {tag}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def png_upload(name='photo.png'):
    import base64
    data = base64.b64decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    return SimpleUploadedFile(name, data, content_type='image/png')


def run():
    global PASS, FAIL
    print('\n== Farmer Panel E2E ==\n')
    cleanup()
    farmer = mk_farmer(1)
    admin = None
    c = client_for(farmer)
    J = 'application/json'

    # ── profile ──────────────────────────────────────────────────────────
    r = c.get('/api/farmers/profile/')
    check('profile GET', r.status_code == 200 and 'farm_name' in r.json(), r.content[:200])
    r = c.put('/api/farmers/profile/', {
        'farm_name': 'Test Poultry Farm', 'farm_type': 'broiler', 'number_of_birds': 5000,
        'years_in_farming': 6, 'experience_level': 'expert',
        'primary_diseases_faced': 'Newcastle', 'number_of_active_workers': 4,
    }, content_type=J)
    body = r.json()
    check('profile PUT', r.status_code == 200 and body['farm_type'] == 'broiler'
          and body['number_of_birds'] == 5000, r.content[:200])
    check('profile PUT syncs Farm row',
          Farm.objects.filter(farmer__user=farmer, farm_name='Test Poultry Farm').exists())
    r = c.post('/api/farmers/profile/upload-photo/',
               {'image': png_upload()})
    check('farm photo upload', r.status_code == 201 and r.json()['farm_photos'], r.content[:200])

    # ── sheds + flocks ──────────────────────────────────────────────────
    r = c.post('/api/farmers/sheds/', {'shed_name': 'Shed A', 'capacity': 3000}, content_type=J)
    check('shed create', r.status_code == 201, r.content[:200])
    shed_id = r.json()['id']
    r = c.post('/api/farmers/flocks/', {
        'batch_name': 'Batch-2026-01', 'bird_type': 'broiler', 'breed': 'Cobb 500',
        'quantity': 2500, 'shed_id': shed_id, 'start_date': date.today().isoformat(),
    }, content_type=J)
    check('flock create', r.status_code == 201, r.content[:200])
    flock_id = r.json()['id']
    r = c.get('/api/farmers/flocks/')
    check('flock list', r.status_code == 200 and len(r.json()['results']) == 1)

    # ── cost: expenses ─────────────────────────────────────────────────
    r = c.post('/api/farmers/costs/expenses/', {
        'category': 'Feed', 'amount': 85000, 'expense_date': date.today().isoformat(),
        'supplier_name': 'AgroFeeds', 'payment_status': 'pending', 'flock_id': flock_id,
    }, content_type=J)
    check('expense create', r.status_code == 201, r.content[:200])
    exp_id = r.json()['id']
    r = c.post('/api/farmers/costs/expenses/', {
        'category': 'Medicines', 'amount': 12000, 'expense_date': date.today().isoformat(),
        'payment_status': 'paid',
    }, content_type=J)
    check('expense create (paid)', r.status_code == 201, r.content[:200])
    r = c.get('/api/farmers/costs/expenses/?category=Feed')
    check('expense list + filter', r.status_code == 200 and len(r.json()['results']) == 1
          and r.json()['total'] == 85000.0, r.content[:200])
    r = c.patch(f'/api/farmers/costs/expenses/{exp_id}/', {'amount': 90000}, content_type=J)
    check('expense edit', r.status_code == 200 and r.json()['amount'] == 90000.0, r.content[:200])
    r = c.post('/api/farmers/costs/expenses/upload-receipt/',
               {'image': png_upload()})
    check('receipt upload', r.status_code == 201 and 'image_url' in r.json(), r.content[:200])
    r = c.post(f'/api/farmers/costs/expenses/{exp_id}/pay/', {'payment_method': 'bkash'}, content_type=J)
    check('expense pay', r.status_code == 200 and r.json()['payment_status'] == 'paid'
          and Payment.objects.filter(user=farmer, payment_type='expense_payment').exists(),
          r.content[:200])

    # ── cost: revenue ─────────────────────────────────────────────────
    r = c.post('/api/farmers/costs/revenue/', {
        'source': 'Bird Sales', 'amount': 240000, 'revenue_date': date.today().isoformat(),
        'buyer_name': 'City Market', 'flock_id': flock_id,
    }, content_type=J)
    check('revenue create', r.status_code == 201, r.content[:200])
    rev_id = r.json()['id']
    r = c.get('/api/farmers/costs/revenue/')
    check('revenue list + by_source', r.status_code == 200 and r.json()['total'] == 240000.0
          and any(s['source'] == 'Bird Sales' for s in r.json()['by_source']), r.content[:200])
    r = c.delete(f'/api/farmers/costs/revenue/{rev_id}/')
    check('revenue delete', r.status_code == 204)
    c.post('/api/farmers/costs/revenue/', {
        'source': 'Bird Sales', 'amount': 240000, 'revenue_date': date.today().isoformat(),
        'flock_id': flock_id}, content_type=J)

    # ── cost dashboard ────────────────────────────────────────────────
    r = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    d = r.json()
    check('cost dashboard', r.status_code == 200
          and d['summary']['total_revenue'] == 240000.0
          and d['summary']['total_expense'] == 102000.0
          and d['summary']['net_profit'] == 138000.0
          and d['summary']['due_tax'] is None, r.content[:300])
    check('cost dashboard sections', len(d['expense_sections']) == 9
          and any(s['category'] == 'Feed' and s['total_spent'] == 90000.0 for s in d['expense_sections']))
    check('cost dashboard alerts', isinstance(d['alerts'], list))

    # ── loans ─────────────────────────────────────────────────────────
    r = c.post('/api/farmers/costs/loans/', {
        'loan_amount': 500000, 'purpose': 'New shed', 'term_months': 12}, content_type=J)
    check('loan request', r.status_code == 201 and r.json()['status'] == 'pending', r.content[:200])
    loan_id = r.json()['id']
    # admin approves directly (admin-panel flow tested elsewhere) —
    loan = Loan.objects.get(pk=loan_id)
    loan.status = 'active'
    loan.start_date = date.today()
    loan.due_date = date.today() + timedelta(days=365)
    loan.interest_rate = Decimal('12.00')
    loan.save()
    from expenses.models import LoanInstallment
    LoanInstallment.objects.create(loan=loan, due_date=date.today() + timedelta(days=30),
                                   amount=Decimal('45000'))
    r = c.get(f'/api/farmers/costs/loans/{loan_id}/')
    check('loan detail w/ installment', r.status_code == 200
          and r.json()['next_payment_amount'] == 45000.0, r.content[:200])
    r = c.post(f'/api/farmers/costs/loans/{loan_id}/', {'amount': 45000, 'payment_method': 'bank_transfer'},
               content_type=J)
    check('loan repay', r.status_code == 200 and r.json()['remaining_balance'] == 455000.0
          and Payment.objects.filter(user=farmer, payment_type='loan_repayment').exists(), r.content[:200])

    # ── inventory + batches ──────────────────────────────────────────
    r = c.get('/api/farmers/costs/inventory/')
    check('inventory', r.status_code == 200 and 'feed' in r.json() and 'other' in r.json(), r.content[:200])
    r = c.get('/api/farmers/costs/batches/')
    b = r.json()['results']
    check('batch cost tracking', r.status_code == 200 and len(b) == 1
          and b[0]['total_expense'] == 90000.0 and b[0]['total_revenue'] == 240000.0
          and b[0]['net_profit'] == 150000.0, r.content[:300])

    # ── reports ──────────────────────────────────────────────────────
    r = c.get('/api/farmers/costs/reports/?type=profit_loss&export=csv')
    check('report CSV', r.status_code == 200 and r['Content-Type'] == 'text/csv'
          and b'Net profit' in r.content, r.content[:120])
    r = c.get('/api/farmers/costs/reports/?type=expense&export=pdf')
    check('report PDF', r.status_code == 200 and r['Content-Type'] == 'application/pdf'
          and r.content[:4] == b'%PDF', r.content[:20])

    # ── cashout ──────────────────────────────────────────────────────
    r = c.post('/api/farmers/costs/cashout/', {'amount': 50000, 'payment_method': 'bkash'}, content_type=J)
    check('cashout request', r.status_code == 201 and r.json()['status'] == 'pending', r.content[:200])
    r = c.get('/api/farmers/costs/cashout/')
    check('cashout history', r.status_code == 200 and len(r.json()['results']) >= 1)

    # ── feed consumption ─────────────────────────────────────────────
    c.post('/api/farmers/feed/inventory/', {
        'name': 'Starter Crumble', 'unit': 'kg', 'quantity': 500, 'cost_per_unit': 60,
        'brand': 'AgroFeeds'}, content_type=J)
    feed_list = c.get('/api/farmers/feed/inventory/').json()['stock']
    ft_id = feed_list[0]['feed_type_id']
    r = c.post('/api/farmers/feed/consumption/', {
        'flock_id': flock_id, 'feed_type_id': ft_id, 'quantity_consumed': 120,
        'consumed_date': date.today().isoformat()}, content_type=J)
    check('feed consumption log', r.status_code == 201 and 'cost_per_bird' in r.json(), r.content[:200])
    r = c.get(f'/api/farmers/feed/consumption/?flock={flock_id}')
    check('feed consumption list', r.status_code == 200 and r.json()['total_consumed'] == 120.0,
          r.content[:200])

    # ── labor ────────────────────────────────────────────────────────
    r = c.post('/api/farmers/labor/workers/', {
        'full_name': 'Karim', 'job_role': 'Feeder', 'daily_wage': 500,
        'join_date': date.today().isoformat()}, content_type=J)
    check('worker create (farmers ns)', r.status_code == 201, r.content[:200])
    wid = r.json()['id']
    c.patch('/api/farmers/labor/attendance/', {'worker_id': wid, 'status': 'present'}, content_type=J)
    r = c.get('/api/farmers/labor/attendance/history/')
    check('attendance history', r.status_code == 200 and len(r.json()['results']) == 1, r.content[:200])
    r = c.patch(f'/api/farmers/labor/workers/{wid}/', {'daily_wage': 550, 'phone': '01811111111'},
                content_type=J)
    check('worker full edit', r.status_code == 200, r.content[:200])

    # ── home dashboard aggregate ────────────────────────────────────
    r = c.get('/api/farmers/dashboard/')
    d = r.json()
    check('home dashboard', r.status_code == 200
          and d['farm']['name'] == 'Test Poultry Farm'
          and d['farm']['total_birds'] == 2500
          and d['finance']['total_revenue'] == 240000.0
          and d['counts']['pending_loans'] == 0
          and isinstance(d['recent_activity'], list)
          and isinstance(d['alerts'], list), r.content[:400])

    # ── permission guard ────────────────────────────────────────────
    other = mk_farmer(2)
    oc = client_for(other)
    r = oc.get(f'/api/farmers/costs/expenses/{exp_id}/')
    check('cross-farmer isolation', r.status_code == 404, r.content[:120])

    print(f'\n{PASS} passed, {FAIL} failed\n')
    cleanup()
    return FAIL == 0


if __name__ == '__main__':
    sys.exit(0 if run() else 1)
