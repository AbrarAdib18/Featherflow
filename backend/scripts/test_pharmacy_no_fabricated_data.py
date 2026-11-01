"""F-004 regression — pharmacy GET handlers must never fabricate data.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_no_fabricated_data.py

Live DB, `nofab+` prefixed throw-away accounts. Idempotent (cleans its rows on
entry and exit). Counts every `AdminPanelRecord` (the JSON bridge the legacy
pharmacy endpoints write to) before/after repeated GET sweeps.

Proves: an empty pharmacy gets zero medicines/orders/totals; repeated GETs
create no rows; a pharmacy only sees its own records and cannot read or modify
another pharmacy's; Super Admin / Pharmacy Admin / farmers see only real
records (no fabricated "Owner Admin" pharmacy); the admin generic
`medicines`/`pharmacies` collections no longer seed demo rows.
"""
import os
import sys
from datetime import date, timedelta

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

from audit.models import AdminPanelRecord  # noqa: E402
from pharmacy.models import PharmacyMedicine  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'nofab+'
JSON = 'application/json'
_n = [0]
FABRICATED_IDS = {'MED-001', 'VAC-001', 'SUP-001', 'EQP-001', 'ORD-001', 'ORD-002', 'ORD-003',
                  'M001', 'M002', 'M003', 'M004', 'P001', 'P002', 'P003'}

# Every read-only pharmacy-facing endpoint a pharmacy owner can reach.
PHARMACY_GETS = [
    '/api/pharmacy/dashboard/', '/api/pharmacy/products/', '/api/pharmacy/orders/',
    '/api/pharmacy/medicines/', '/api/pharmacy/earnings/', '/api/pharmacy/permissions/',
    '/api/pharmacy/profile/', '/api/pharmacy/inventory/summary/',
    '/api/pharmacy/inventory/expiring-soon/', '/api/pharmacy/inventory/low-stock/',
    '/api/pharmacy/suppliers/', '/api/pharmacy/analytics/sales/',
    '/api/pharmacy/analytics/top-products/', '/api/pharmacy/analytics/revenue/',
    '/api/pharmacy/marketplace/', '/api/pharmacy/appeals/',
]


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
    ids = [str(u.id) for u in users]
    for rec in AdminPanelRecord.objects.filter(module__in=['pharmacy-products', 'pharmacy-orders', 'medicines']):
        if str(rec.payload.get('owner_id')) in ids or str(rec.payload.get('pharmacy_user_id')) in ids:
            rec.delete()
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin' if role_name.startswith('admin') else role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0197{n:07d}', full_name=f'{tag.title()} {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def bridge_count():
    return AdminPanelRecord.objects.count()


def mine(user):
    return AdminPanelRecord.objects.filter(payload__owner_id=str(user.id)).count()


def json_rows(r):
    j = r.json()
    if isinstance(j, list):
        return j
    for k in ('results', 'products', 'orders', 'medicines', 'items'):
        if isinstance(j.get(k), list):
            return j[k]
    return None


def run():
    print('\n== F-004: pharmacy GETs never fabricate data ==\n')
    cleanup()
    pa = mk_user('pharmacy', 'pharma')       # stays empty
    pb = mk_user('pharmacy', 'pharmb')       # gets one real product
    sa = mk_user('admin_super', 'super')
    ph_admin = mk_user('admin_pharmacy', 'phadmin')
    farmer = mk_user('farmer', 'farmer')
    ca, cb, cs, cpa, cf = (client_for(u) for u in (pa, pb, sa, ph_admin, farmer))

    # 1/2/7. Empty pharmacy: zero medicines, zero orders, zero totals.
    print('-- empty pharmacy')
    before = bridge_count()
    r = ca.get('/api/pharmacy/dashboard/')
    check('dashboard 200', r.status_code == 200, r.content[:200])
    d = r.json()
    check('empty pharmacy: dashboard products == []', d.get('products') == [], d.get('products'))
    check('empty pharmacy: dashboard orders == []', d.get('orders') == [], d.get('orders'))
    r = ca.get('/api/pharmacy/products/')
    check('empty pharmacy: /products/ == []', r.status_code == 200 and json_rows(r) == [], r.content[:200])
    r = ca.get('/api/pharmacy/orders/')
    rows = json_rows(r)
    check('empty pharmacy: /orders/ has zero orders', r.status_code == 200 and rows == [], r.content[:200])
    r = ca.get('/api/pharmacy/medicines/')
    rows = json_rows(r)
    check('empty pharmacy: /medicines/ has zero medicines', r.status_code == 200 and rows == [], r.content[:200])
    r = ca.get('/api/pharmacy/inventory/summary/')
    flat = r.json()
    def _zero(v):
        if isinstance(v, dict):
            return all(_zero(x) for x in v.values())
        if isinstance(v, list):
            return len(v) == 0
        if isinstance(v, (int, float)):
            return v == 0
        if isinstance(v, str):
            try:
                return float(v) == 0
            except ValueError:
                return True
        return v in (None, False)
    check('empty pharmacy: inventory summary totals are zero', r.status_code == 200 and _zero({k: v for k, v in flat.items() if k != 'low_stock_threshold'}), flat)  # threshold is config, not a total
    r = ca.get('/api/pharmacy/earnings/')
    e = r.json()
    check('empty pharmacy: earnings are zero',
          r.status_code == 200 and not any(float(e.get(k) or 0) for k in e if 'earn' in k or 'total' in k or 'orders' in k or 'revenue' in k), e)
    r = ca.get('/api/pharmacy/analytics/sales/')
    check('empty pharmacy: analytics sales call 200', r.status_code == 200, r.content[:200])
    r = ca.get('/api/pharmacy/analytics/top-products/')
    check('empty pharmacy: top products empty', r.status_code == 200 and not (json_rows(r) or []), r.content[:200])
    check('single sweep created no AdminPanelRecord rows', bridge_count() == before, (before, bridge_count()))
    check('empty pharmacy owns no bridge rows', mine(pa) == 0)

    # 3. Repeated GETs (all endpoints, 3 passes, every role) create nothing.
    print('-- repeated GET sweeps')
    before = bridge_count()
    meds_before = PharmacyMedicine.objects.count()
    for _ in range(3):
        for url in PHARMACY_GETS:
            ca.get(url)
        for url in ('/api/pharmacy/dashboard/', '/api/pharmacy/products/', '/api/pharmacy/orders/',
                    '/api/pharmacy/medicines/', '/api/pharmacy/marketplace/', '/api/pharmacy/earnings/'):
            cs.get(url)
            cpa.get(url)
        for url in ('/api/admin-panel/medicines/', '/api/admin-panel/pharmacies/', '/api/admin-panel/pharmacy/medicines/',
                    '/api/admin-panel/pharmacy/orders/', '/api/admin-panel/pharmacy/dashboard/',
                    '/api/admin/pharmacies/metrics/'):
            cs.get(url)
            cpa.get(url)
        cf.get('/api/pharmacy/marketplace/')
        cf.get('/api/farmers/medicines/search/?q=')
        cf.get('/api/farmers/pharmacies/')
    check('3 sweeps x all roles created no AdminPanelRecord rows', bridge_count() == before, (before, bridge_count()))
    check('3 sweeps created no PharmacyMedicine rows', PharmacyMedicine.objects.count() == meds_before)
    check('no fabricated ids anywhere in the bridge for the test users',
          not any(str(r.payload.get('id')) in FABRICATED_IDS and str(r.payload.get('owner_id')) in
                  {str(u.id) for u in (pa, pb, sa, ph_admin, farmer)} for r in AdminPanelRecord.objects.all()))

    # 5. Super Admin sees only real records.
    print('-- super admin / pharmacy admin / farmer see only real records')
    r = cs.get('/api/pharmacy/dashboard/')
    check('super admin dashboard: no fabricated products/orders',
          r.status_code == 200 and r.json().get('products') == [] and r.json().get('orders') == [], r.content[:200])
    r = cs.get('/api/pharmacy/marketplace/')
    owners = {x.get('pharmacy_user_id') for x in r.json().get('results', [])}
    check('marketplace lists no listing for admin/empty accounts',
          str(sa.id) not in owners and str(pa.id) not in owners and str(ph_admin.id) not in owners, owners)
    mod_before = {m: AdminPanelRecord.objects.filter(module=m).count() for m in ('medicines', 'pharmacies')}
    for _ in range(2):
        cs.get('/api/admin-panel/medicines/'); cs.get('/api/admin-panel/pharmacies/')
    check('admin generic medicines/pharmacies GET seeds no demo rows',
          mod_before == {m: AdminPanelRecord.objects.filter(module=m).count() for m in ('medicines', 'pharmacies')})
    r = cpa.get('/api/admin-panel/pharmacy/orders/')
    test_ids = {str(u.id) for u in (pa, pb, sa, ph_admin, farmer)}
    check('pharmacy admin order list is real (no orders for the empty test accounts)',
          r.status_code == 200 and not any(str(o.get('pharmacy_user_id') or o.get('pharmacy_id') or '') in test_ids
                                           for o in (r.json().get('results') or [])), r.content[:200])

    # 4. Isolation: B creates a real product; A cannot see/modify it.
    print('-- cross-pharmacy isolation')
    soon = (date.today() + timedelta(days=200)).isoformat()
    r = cb.post('/api/pharmacy/products/', {
        'name': 'NoFab Real Product', 'category': 'medicines', 'unit': 'bottle',
        'manufacturer': 'Acme', 'expiry_date': soon, 'stock_count': 5, 'min_stock': 1, 'price': 100,
    }, content_type=JSON)
    check('pharmacy B creates a real product (POST 201)', r.status_code == 201, r.content[:300])
    pid = r.json().get('id') if r.status_code == 201 else None
    r = cb.get('/api/pharmacy/products/')
    check('pharmacy B sees exactly its 1 real product', json_rows(r) is not None and len(json_rows(r)) == 1, r.content[:200])
    r = cb.get('/api/pharmacy/dashboard/')
    check('pharmacy B dashboard lists only that product', len(r.json().get('products', [])) == 1 and r.json().get('orders') == [])
    r = ca.get('/api/pharmacy/products/')
    check('pharmacy A (empty) still sees zero products', json_rows(r) == [], r.content[:200])
    r = ca.get('/api/pharmacy/dashboard/')
    check('pharmacy A dashboard still empty', r.json().get('products') == [], r.content[:200])
    if pid:
        r = ca.get(f'/api/pharmacy/products/{pid}/')
        check("A cannot GET B's product (404)", r.status_code == 404, r.status_code)
        r = ca.patch(f'/api/pharmacy/products/{pid}/', {'price': 1}, content_type=JSON)
        check("A cannot PATCH B's product (404)", r.status_code == 404, r.status_code)
        r = ca.delete(f'/api/pharmacy/products/{pid}/')
        check("A cannot DELETE B's product (404)", r.status_code == 404, r.status_code)
        r = cb.get(f'/api/pharmacy/products/{pid}/')
        check('B can GET its own product (200)', r.status_code == 200, r.status_code)
    r = cf.get('/api/pharmacy/dashboard/')
    check('a farmer cannot use pharmacy dashboard (403)', r.status_code in (401, 403), r.status_code)
    check('A still owns no bridge rows after B created data', mine(pa) == 0, mine(pa))
    before = bridge_count()
    for _ in range(3):
        ca.get('/api/pharmacy/dashboard/'); cb.get('/api/pharmacy/dashboard/'); ca.get('/api/pharmacy/products/')
    check('repeated GETs after real data exist still create nothing', bridge_count() == before)

    # 5b. Preserved legitimate records are untouched by GETs (read-only view of the live DB).
    real_before = AdminPanelRecord.objects.filter(module='pharmacy-orders').count()
    cs.get('/api/pharmacy/orders/'); cpa.get('/api/admin-panel/pharmacy/orders/')
    check('legitimate pharmacy-orders rows unchanged by GETs',
          AdminPanelRecord.objects.filter(module='pharmacy-orders').count() == real_before)

    cleanup()
    print(f'\n== {PASS} passed, {FAIL} failed ==')
    return FAIL == 0


if __name__ == '__main__':
    try:
        ok = run()
    finally:
        cleanup()
    sys.exit(0 if ok else 1)
