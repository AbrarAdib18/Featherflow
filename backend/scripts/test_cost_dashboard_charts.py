"""Cost Management charts (Phase 3) — `charts` block on
`GET /api/farmers/costs/dashboard/`.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_cost_dashboard_charts.py

Live DB, `chartstest+` prefixed throw-away accounts. Idempotent.

Covers: a brand-new farmer gets a zero-filled 6-month trend (not an empty
chart), a farmer with real expenses/revenue gets correct SQL-aggregated
monthly/category figures, the monthly trend is independent of the period/
date-range filter while the category charts respect it, a mirrored labour
expense reaches the Feed/Labour/Medicine comparison chart, and the charts
change after a new expense/revenue is added (no stale cache).
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

from expenses.models import Expense, ExpenseCategory, Revenue, RevenueSource  # noqa: E402
from farms.models import Farm  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402
from workers.views import farm_for  # noqa: E402

PASS = FAIL = 0
PREFIX = 'chartstest+'
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
    Expense.objects.filter(farm__in=farms).delete()
    Revenue.objects.filter(farm__in=farms).delete()
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
        phone=f'0195{n:07d}', full_name=f'Farmer {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def run():
    print('\n== Cost Management charts ==\n')
    cleanup()

    farmer = mk_farmer()
    farm = farm_for(farmer)
    c = client_for(farmer)

    print('\n== brand-new farmer: zero-filled trend, not empty ==')
    r = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    charts = r.json()['charts']
    check('monthly trend has 6 entries with no data at all',
          len(charts['monthly']) == 6, charts['monthly'])
    check('every month is zero, not missing',
          all(m['revenue'] == 0 and m['expense'] == 0 and m['profit'] == 0
              for m in charts['monthly']), charts['monthly'])
    check('months are labelled and ordered oldest to newest',
          charts['monthly'][0]['month'] < charts['monthly'][-1]['month'], charts['monthly'])
    check('category_breakdown is empty for a farmer with no expenses',
          charts['category_breakdown'] == [], charts['category_breakdown'])
    # Unlike category_breakdown (which only lists categories with spend),
    # category_comparison always shows Feed/Labor/Medicines side by side —
    # zero bars are meaningful here (nothing spent yet), not noise to hide.
    check('category_comparison lists all three comparison categories at zero',
          {x['category']: x['total'] for x in charts['category_comparison']}
          == {'Feed': 0.0, 'Labor': 0.0, 'Medicines': 0.0}, charts['category_comparison'])

    print('\n== correct SQL-level aggregation ==')
    today = date.today()
    feed_cat, _ = ExpenseCategory.objects.get_or_create(name='Feed')
    labor_cat, _ = ExpenseCategory.objects.get_or_create(name='Labor')
    bird_src, _ = RevenueSource.objects.get_or_create(name='Bird Sales')
    Expense.objects.create(farm=farm, category=feed_cat, amount=Decimal('1000.00'),
                           expense_date=today, payment_status='paid', created_by=farmer)
    Expense.objects.create(farm=farm, category=feed_cat, amount=Decimal('500.00'),
                           expense_date=today, payment_status='pending', created_by=farmer)
    Revenue.objects.create(farm=farm, source=bird_src, amount=Decimal('4000.00'),
                           revenue_date=today, created_by=farmer)

    r = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    charts = r.json()['charts']
    this_month = charts['monthly'][-1]
    check('current month revenue matches the created revenue row',
          this_month['revenue'] == 4000.0, this_month)
    check('current month expense matches the sum of both created expense rows',
          this_month['expense'] == 1500.0, this_month)
    check('current month profit = revenue - expense',
          this_month['profit'] == 2500.0, this_month)
    feed_row = next((x for x in charts['category_breakdown'] if x['category'] == 'Feed'), None)
    check('category_breakdown sums both Feed rows (paid + pending)',
          feed_row is not None and feed_row['total'] == 1500.0, charts['category_breakdown'])
    feed_cmp = next((x for x in charts['category_comparison'] if x['category'] == 'Feed'), None)
    check('category_comparison includes Feed at the same total',
          feed_cmp is not None and feed_cmp['total'] == 1500.0, charts['category_comparison'])
    other_cmp = {x['category']: x['total'] for x in charts['category_comparison']
                if x['category'] != 'Feed'}
    check('category_comparison leaves untouched categories at zero, not omitted',
          other_cmp == {'Labor': 0.0, 'Medicines': 0.0}, charts['category_comparison'])

    print('\n== labour expense (mirrored) reaches the comparison chart ==')
    Expense.objects.create(farm=farm, category=labor_cat, amount=Decimal('750.00'),
                           expense_date=today, payment_status='paid',
                           source_intent_id=None, created_by=farmer)
    r = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    charts = r.json()['charts']
    labor_cmp = next((x for x in charts['category_comparison'] if x['category'] == 'Labor'), None)
    check('Labor appears in the Feed/Labour/Medicine comparison chart',
          labor_cmp is not None and labor_cmp['total'] == 750.0, charts['category_comparison'])

    print('\n== period / date-range filtering ==')
    old_expense = Expense.objects.create(
        farm=farm, category=feed_cat, amount=Decimal('999.00'),
        expense_date=today - timedelta(days=200), payment_status='paid', created_by=farmer)
    r_life = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    r_month = c.get('/api/farmers/costs/dashboard/?period=monthly')
    life_feed = next(x for x in r_life.json()['charts']['category_breakdown'] if x['category'] == 'Feed')
    month_feed = next(x for x in r_month.json()['charts']['category_breakdown'] if x['category'] == 'Feed')
    check('lifetime period includes the 200-day-old expense',
          life_feed['total'] == 2499.0, life_feed)
    check('monthly period excludes the 200-day-old expense',
          month_feed['total'] == 1500.0, month_feed)
    check('monthly trend is unaffected by the period filter (still 6, still zero-filled shape)',
          len(r_month.json()['charts']['monthly']) == 6, r_month.json()['charts']['monthly'])

    custom_from = (today - timedelta(days=250)).isoformat()
    custom_to = (today - timedelta(days=150)).isoformat()
    r_custom = c.get(f'/api/farmers/costs/dashboard/?period=custom&from={custom_from}&to={custom_to}')
    check('custom period 200 OK', r_custom.status_code == 200, r_custom.content[:200])
    custom_feed = next((x for x in r_custom.json()['charts']['category_breakdown']
                        if x['category'] == 'Feed'), None)
    check('custom date range isolates only the 200-day-old expense',
          custom_feed is not None and custom_feed['total'] == 999.0, custom_feed)
    old_expense.delete()

    print('\n== charts update after a mutation ==')
    r_before = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    before_total = next(x for x in r_before.json()['charts']['category_breakdown']
                        if x['category'] == 'Feed')['total']
    post = c.post('/api/farmers/costs/expenses/',
                  {'category': 'Feed', 'amount': '300', 'expense_date': today.isoformat(),
                   'payment_status': 'paid'}, content_type=JSON)
    check('new expense created', post.status_code == 201, post.content[:200])
    r_after = c.get('/api/farmers/costs/dashboard/?period=lifetime')
    after_total = next(x for x in r_after.json()['charts']['category_breakdown']
                       if x['category'] == 'Feed')['total']
    check('chart total increases by exactly the new expense amount',
          round(after_total - before_total, 2) == 300.0, (before_total, after_total))
    after_month = r_after.json()['charts']['monthly'][-1]
    # Running total for this month: 1000 (paid Feed) + 500 (pending Feed) +
    # 750 (Labor) + 300 (this new Feed expense) = 2550.
    check('current-month expense in the trend also reflects the new expense',
          after_month['expense'] == 2550.0, after_month)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
