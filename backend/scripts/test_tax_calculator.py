"""Tests for the Bangladesh tax calculator + the /api/farmers/tax/ endpoints.

    backend/venv/Scripts/python.exe backend/scripts/test_tax_calculator.py

Pure-function tests need no DB. The endpoint tests use Django's test client
against the live configured database and a throw-away farmer (``taxtest+…``);
re-running is idempotent (rows are cleaned on entry).
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402

if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from tax import calculator as C  # noqa: E402
from tax.models import TaxPayment, TaxProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'taxtest+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}   {extra}')


def near(a, b, tol=1.0):
    return abs(float(a) - float(b)) <= tol


# ── 1. income tax slabs (TaxEase/Calculator.php) ────────────────────────────

def test_income_tax():
    print('\n== income tax: slabs ==')

    # Non-agricultural so the 200k agri exemption does not apply.
    r = C.calculate_income_tax(300_000, income_type='business')
    check('below threshold -> 0 tax', r['tax'] == 0, r['tax'])

    r = C.calculate_income_tax(350_000, income_type='business')
    check('exactly at threshold -> 0 tax', r['tax'] == 0, r['tax'])

    # 450,000 business income: (450k - 350k) = 100k @ 5% = 5,000
    r = C.calculate_income_tax(450_000, income_type='business')
    check('first slab 5% -> 5,000', near(r['tax'], 5_000), r['tax'])

    # 850,000: 100k@5% (5,000) + 400k@10% (40,000) = 45,000
    r = C.calculate_income_tax(850_000, income_type='business')
    check('into 10% slab -> 45,000', near(r['tax'], 45_000), r['tax'])

    # 1,350,000: 5,000 + 40,000 + 500k@15% (75,000) = 120,000
    r = C.calculate_income_tax(1_350_000, income_type='business')
    check('into 15% slab -> 120,000', near(r['tax'], 120_000), r['tax'])

    # 1,850,000: +500k@25% (125,000) = 245,000
    r = C.calculate_income_tax(1_850_000, income_type='business')
    check('into 25% slab -> 245,000', near(r['tax'], 245_000), r['tax'])

    # 2,350,000: +500k@30% (150,000) = 395,000
    r = C.calculate_income_tax(2_350_000, income_type='business')
    check('into 30% slab -> 395,000', near(r['tax'], 395_000), r['tax'])

    print('\n== income tax: senior threshold ==')
    r = C.calculate_income_tax(400_000, income_type='business', is_senior=True)
    check('senior 400k threshold -> 0', r['tax'] == 0, r['tax'])
    r = C.calculate_income_tax(400_000, income_type='business', is_senior=False)
    check('non-senior 400k -> 2,500', near(r['tax'], 2_500), r['tax'])

    print('\n== income tax: rebate + exemptions ==')
    r = C.calculate_income_tax(450_000, income_type='business', rebates=2_000)
    check('rebate reduces tax', near(r['tax'], 3_000), r['tax'])
    r = C.calculate_income_tax(450_000, income_type='business', rebates=99_999)
    check('rebate cannot go below 0', r['tax'] == 0, r['tax'])
    r = C.calculate_income_tax(600_000, income_type='business', exemptions=150_000)
    check('exemptions reduce taxable income', near(r['tax'], 5_000), r['tax'])

    check('breakdown is a non-empty list of strings',
          isinstance(r['breakdown'], list) and r['breakdown']
          and all(isinstance(x, str) for x in r['breakdown']), r['breakdown'])


def test_agricultural_exemption():
    print('\n== agricultural income exemption (BD-specific) ==')

    # 500k agri: -200k agri exemption -> 300k, below 350k threshold -> 0
    r = C.calculate_income_tax(500_000, income_type='agricultural')
    check('500k agri income -> 0 tax (200k exempt + threshold)', r['tax'] == 0, r['tax'])

    # 800k agri: -200k -> 600k; (600k-350k)=250k @ 5% first 100k + 10% next 150k
    #            = 5,000 + 15,000 = 20,000
    r = C.calculate_income_tax(800_000, income_type='agricultural')
    check('800k agri income -> 20,000', near(r['tax'], 20_000), r['tax'])

    # same 800k as business income (no agri exemption): (800k-350k)=450k
    #   100k@5% + 350k@10% = 5,000 + 35,000 = 40,000
    r = C.calculate_income_tax(800_000, income_type='business')
    check('800k business income -> 40,000 (no agri exemption)', near(r['tax'], 40_000), r['tax'])

    # mixed: total 800k, of which 250k agricultural -> only 200k of it exempt
    r = C.calculate_income_tax(800_000, income_type='mixed', agricultural_income=250_000)
    check('mixed income exempts up to 200k of the agri part', near(r['tax'], 20_000), r['tax'])


def test_business_tax():
    print('\n== business / corporate tax (TaxEase/businesscalcu.php) ==')
    r = C.calculate_business_tax(1_000_000, expenses=600_000)
    # net 400k * 27.5% = 110,000 vs min 6,000 -> 110,000
    check('profit -> 27.5% of net profit', near(r['tax'], 110_000), r['tax'])
    r = C.calculate_business_tax(1_000_000, expenses=1_200_000)
    # loss -> minimum tax 0.6% of 1,000,000 = 6,000
    check('loss -> 0.6% minimum tax', near(r['tax'], 6_000), r['tax'])
    r = C.calculate_business_tax(1_000_000, expenses=980_000)
    # net 20k * 27.5% = 5,500 < min 6,000 -> 6,000
    check('tiny profit -> minimum tax floor', near(r['tax'], 6_000), r['tax'])


def test_land_tax():
    print('\n== land tax ==')
    # 50 katha agricultural rural: 50 * 1.65 = 82.5 decimal, all under the 825-decimal
    # (25-bigha) exemption -> 0
    r = C.calculate_land_tax(50, 'katha', location='rural', land_use='agricultural')
    check('50 katha agri rural -> exempt (0)', r['tax'] == 0 and r['exempt'], r)

    # 40 bigha agricultural: 40*33 = 1,320 decimal; 825 exempt; 495 @ 2 = 990
    r = C.calculate_land_tax(40, 'bigha', location='rural', land_use='agricultural')
    check('40 bigha agri -> 990 (495 taxable decimal @ 2)', near(r['tax'], 990), r['tax'])

    # 10 katha commercial urban: 16.5 decimal @ 60 = 990
    r = C.calculate_land_tax(10, 'katha', location='urban', land_use='commercial')
    check('10 katha commercial urban -> 990', near(r['tax'], 990), r['tax'])

    # 5 decimal residential rural: 5 @ 6 = 30
    r = C.calculate_land_tax(5, 'decimal', location='rural', land_use='residential')
    check('5 decimal residential rural -> 30', near(r['tax'], 30), r['tax'])

    r = C.calculate_land_tax(0, 'katha')
    check('zero land -> 0 tax', r['tax'] == 0, r['tax'])
    r = C.calculate_land_tax(-5, 'katha')
    check('negative land -> 0 tax', r['tax'] == 0, r['tax'])


def test_vehicle_tax():
    print('\n== vehicle tax ==')
    r = C.calculate_vehicle_tax([{'type': 'motorcycle', 'count': 1}])
    check('motorcycle -> 0', r['tax'] == 0, r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'power_tiller', 'count': 2}])
    check('power tiller (agri) -> exempt', r['tax'] == 0, r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'truck', 'count': 1}])
    check('truck -> 10,000', near(r['tax'], 10_000), r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'car', 'count': 1}])
    check('car alias -> 25,000', near(r['tax'], 25_000), r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'car_above_2500cc', 'count': 1}])
    check('big car -> 125,000', near(r['tax'], 125_000), r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'motorcycle', 'count': 1},
                                 {'type': 'van', 'count': 2}])
    check('mixed fleet -> 8,000 (2 vans)', near(r['tax'], 8_000), r['tax'])
    r = C.calculate_vehicle_tax([{'type': 'spaceship', 'count': 1}])
    check('unknown type -> skipped, 0', r['tax'] == 0, r['tax'])
    r = C.calculate_vehicle_tax([])
    check('no vehicles -> 0', r['tax'] == 0, r['tax'])


def test_total_and_edges():
    print('\n== combined calculation ==')
    result = C.calculate_total_tax(
        revenue_breakdown={'Bird Sales': 900_000, 'Egg Sales': 300_000},
        assets={'land_area': 50, 'land_unit': 'katha', 'location': 'rural',
                'land_use': 'agricultural',
                'vehicles': [{'type': 'motorcycle', 'count': 1},
                             {'type': 'van', 'count': 1}]},
        income_type='agricultural', expenses=400_000)
    # net income 1,200,000 - 400,000 = 800,000 agricultural -> income tax 20,000
    check('combined income tax -> 20,000', near(result['income_tax'], 20_000), result['income_tax'])
    check('combined land tax -> 0 (under 25 bigha)', result['land_tax'] == 0, result['land_tax'])
    check('combined vehicle tax -> 4,000 (1 van)', near(result['vehicle_tax'], 4_000), result['vehicle_tax'])
    check('combined total -> 24,000', near(result['total'], 24_000), result['total'])
    check('combined breakdown present', isinstance(result['breakdown'], list) and result['breakdown'], '')

    print('\n== edge cases ==')
    r = C.calculate_income_tax(0)
    check('zero income -> 0 tax', r['tax'] == 0, r['tax'])
    r = C.calculate_income_tax(-500_000)
    check('negative income -> 0 tax', r['tax'] == 0, r['tax'])
    r = C.calculate_income_tax('not a number')
    check('garbage income -> 0 tax', r['tax'] == 0, r['tax'])
    r = C.calculate_income_tax(50_000_000, income_type='business')
    # (50,000,000 - 350,000) = 49,650,000
    #   100k@5 (5,000) + 400k@10 (40,000) + 500k@15 (75,000) + 500k@25 (125,000)
    #   + 48,150,000@30 (14,445,000) = 14,690,000
    check('very high income -> 14,690,000', near(r['tax'], 14_690_000, tol=5), r['tax'])
    r = C.calculate_total_tax()
    check('empty total call -> 0 total', r['total'] == 0, r['total'])


# ── endpoint tests ─────────────────────────────────────────────────────────

def _farmer():
    role = Role.objects.get(name='farmer')
    u, _ = User.objects.get_or_create(email=f'{PREFIX}farmer@featherflow.dev', defaults=dict(
        full_name='Tax Test Farmer', phone='+8801700880011',
        date_of_birth=date(1988, 3, 3), present_address='Bogura', consent_terms=True,
        account_status='active'))
    u.account_status = 'active'
    u.set_password('Testpass!2026')
    u.save()
    u.roles.add(role)
    return u


def cleanup():
    for u in User.objects.filter(email__startswith=PREFIX):
        TaxPayment.objects.filter(user=u).delete()
        TaxProfile.objects.filter(user=u).delete()


def test_endpoints():
    print('\n== endpoints ==')
    cleanup()
    u = _farmer()
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(u).access_token}'

    # profile: auto-created on first GET
    r = c.get('/api/farmers/tax/profile/')
    check('GET profile 200', r.status_code == 200, r.content[:200])
    check('profile has defaults', r.json().get('income_type') == 'agricultural', r.json())

    r = c.put('/api/farmers/tax/profile/', data={
        'land_area': 50, 'land_unit': 'katha', 'land_use': 'agricultural',
        'location': 'rural', 'income_type': 'agricultural',
        'vehicles': [{'type': 'motorcycle', 'count': 1}, {'type': 'van', 'count': 1}],
    }, content_type='application/json')
    check('PUT profile 200', r.status_code == 200, r.content[:300])
    check('profile saved vehicles', len(r.json().get('vehicles', [])) == 2, r.json())

    # calculate with an explicit payload
    r = c.post('/api/farmers/tax/calculate/', data={
        'revenue_breakdown': {'Bird Sales': 900000, 'Egg Sales': 300000},
        'expenses': 400000, 'income_type': 'agricultural',
    }, content_type='application/json')
    check('POST calculate 200', r.status_code == 200, r.content[:300])
    body = r.json()
    check('calculate returns income_tax ~20,000', near(body.get('income_tax'), 20_000), body.get('income_tax'))
    check('calculate returns vehicle_tax ~4,000', near(body.get('vehicle_tax'), 4_000), body.get('vehicle_tax'))
    check('calculate returns a breakdown list', isinstance(body.get('breakdown'), list) and body['breakdown'], '')

    # record payments
    r = c.post('/api/farmers/tax/payment/', data={
        'tax_type': 'land', 'amount': 5000, 'payment_date': str(date.today()),
        'reference_number': 'CH-DEMO-1',
    }, content_type='application/json')
    check('POST payment (land) 201', r.status_code == 201, r.content[:200])

    r = c.post('/api/farmers/tax/payment/', data={
        'tax_type': 'vehicle', 'amount': 2000, 'payment_date': str(date.today()),
    }, content_type='application/json')
    check('POST payment (vehicle) 201', r.status_code == 201, r.content[:200])

    r = c.post('/api/farmers/tax/payment/', data={
        'tax_type': 'income', 'amount': -50, 'payment_date': str(date.today()),
    }, content_type='application/json')
    check('POST payment negative amount -> 400', r.status_code == 400, r.content[:200])

    r = c.get('/api/farmers/tax/payments/')
    check('GET payments 200', r.status_code == 200, r.content[:200])
    check('payments list has 2 rows', r.json().get('count') == 2, r.json())
    check('payments total_paid = 7,000', near(r.json().get('total_paid'), 7_000), r.json())

    # summary
    r = c.get('/api/farmers/tax/summary/')
    check('GET summary 200', r.status_code == 200, r.content[:200])
    s = r.json()
    check('summary has estimated_total', isinstance(s.get('estimated_total'), (int, float)), s)
    check('summary total_paid = 7,000', near(s.get('total_paid'), 7_000), s)
    check('summary lines cover 3 tax types',
          {ln['tax_type'] for ln in s.get('lines', [])} >= {'income', 'land', 'vehicle'}, s)
    check('summary has disclaimer', 'estimate' in (s.get('disclaimer') or '').lower(), s)

    # auth
    r = Client().get('/api/farmers/tax/summary/')
    check('unauthenticated -> 401', r.status_code == 401, r.status_code)

    cleanup()


def main():
    test_income_tax()
    test_agricultural_exemption()
    test_business_tax()
    test_land_tax()
    test_vehicle_tax()
    test_total_and_edges()
    try:
        test_endpoints()
    except Exception as exc:  # noqa: BLE001
        check('endpoint tests ran', False, repr(exc))
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
