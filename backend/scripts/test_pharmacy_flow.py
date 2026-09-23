"""Pharmacy panel — Cost Management mirroring regression.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_pharmacy_flow.py

Live DB, `pharmtest+` prefixed throw-away accounts. Idempotent.

Covers: placing a pharmacy order decrements stock, a pharmacist-confirmed
delivery mirrors the order into `expenses` exactly once (Medicines category),
a rider-confirmed delivery (OTP flow) also mirrors exactly once, a duplicate
delivered call does not double-mirror, and a cancelled order never mirrors.
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
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from delivery.models import DeliveryOrder  # noqa: E402
from expenses.models import Expense  # noqa: E402
from profiles.models import DeliveryProfile  # noqa: E402
from pharmacy.models import PharmacyMedicine  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'pharmtest+'
JSON = 'application/json'
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
    from delivery.models import DeliveryEarning

    users = User.objects.filter(email__startswith=PREFIX)
    Expense.objects.filter(created_by__in=users).delete()
    orders = DeliveryOrder.objects.filter(delivery_person__user__in=users)
    DeliveryEarning.objects.filter(delivery_order__in=orders).delete()
    orders.delete()
    PharmacyMedicine.objects.filter(pharmacy_user__in=users).delete()
    DeliveryProfile.objects.filter(user__in=users).delete()
    users.delete()


def mk_user(role_name, tag):
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}{n}@example.com', password='Test1234!',
        phone=f'0198{n:07d}', full_name=f'{tag.title()} {n}',
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
    print('\n== Pharmacy Cost Management mirroring ==\n')
    cleanup()

    pharmacy = mk_user('pharmacy', 'pharm')
    farmer = mk_user('farmer', 'farmer')
    pc = client_for(pharmacy)
    fc = client_for(farmer)

    medicine = PharmacyMedicine.objects.create(
        pharmacy_user=pharmacy, name='Test Vitamin Mix', generic_name='Vitamins',
        category='vitamin', price=150, stock_quantity=50,
        unit='pack', expiry_date=date.today() + timedelta(days=365),
        is_active=True, is_approved=True,
        created_at=timezone.now(), updated_at=timezone.now(),
    )

    # 1. Farmer places an order.
    r = fc.post('/api/farmers/orders/', {
        'pharmacy_id': str(pharmacy.id),
        'items': [{'medicine_id': str(medicine.id), 'quantity': 3}],
        'delivery_method': 'pickup',
        'payment_method': 'cod',
    }, content_type=JSON)
    check('order placed -> 201', r.status_code == 201, r.content[:300])
    order_id = r.json()['id']
    medicine.refresh_from_db()
    check('stock decremented', medicine.stock_quantity == 47, medicine.stock_quantity)

    # 2. Pharmacist confirms, ships, then confirms delivered directly.
    r_conf = pc.patch(f'/api/pharmacy/orders/{order_id}/status/', {'status': 'processing'}, content_type=JSON)
    check('confirm -> processing', r_conf.status_code == 200, r_conf.content[:300])
    r_ship = pc.patch(f'/api/pharmacy/orders/{order_id}/status/', {'status': 'shipped'}, content_type=JSON)
    check('ship -> shipped', r_ship.status_code == 200, r_ship.content[:300])
    r_delivered = pc.patch(f'/api/pharmacy/orders/{order_id}/status/', {
        'status': 'delivered', 'delivery_confirmed': True,
    }, content_type=JSON)
    check('pharmacist can mark delivered directly (no rider assigned)',
          r_delivered.status_code == 200, r_delivered.content[:300])

    mirrored = Expense.objects.filter(source_pharmacy_order_id=order_id)
    check('delivered order mirrors into exactly one expense', mirrored.count() == 1,
          list(mirrored.values('id', 'amount')))
    if mirrored.count() == 1:
        exp = mirrored.first()
        check('mirrored expense amount matches order total', float(exp.amount) == 450.0, exp.amount)
        check('mirrored expense is categorised as Medicines', exp.category.name.lower() == 'medicines')
        check('mirrored expense is marked paid', exp.payment_status == 'paid')
        check('mirrored expense belongs to the farmer', exp.created_by_id == farmer.id)

    # 3. Re-confirming an already-delivered order is a 409 and does not
    #    double-mirror (status machine already forbids the transition).
    r_dup = pc.patch(f'/api/pharmacy/orders/{order_id}/status/', {
        'status': 'delivered', 'delivery_confirmed': True,
    }, content_type=JSON)
    check('repeat delivered call is rejected by the status machine',
          r_dup.status_code == 409, r_dup.content[:300])
    check('still exactly one mirrored expense',
          Expense.objects.filter(source_pharmacy_order_id=order_id).count() == 1)

    # 4. A cancelled order never mirrors an expense.
    medicine2 = PharmacyMedicine.objects.create(
        pharmacy_user=pharmacy, name='Test Antibiotic', generic_name='Amoxicillin',
        category='antibiotic', price=200, stock_quantity=20,
        unit='tablet', expiry_date=date.today() + timedelta(days=365),
        is_active=True, is_approved=True,
        created_at=timezone.now(), updated_at=timezone.now(),
    )
    r2 = fc.post('/api/farmers/orders/', {
        'pharmacy_id': str(pharmacy.id),
        'items': [{'medicine_id': str(medicine2.id), 'quantity': 1}],
        'delivery_method': 'pickup',
        'payment_method': 'cod',
    }, content_type=JSON)
    order2_id = r2.json()['id']
    r2c = fc.post(f'/api/farmers/orders/{order2_id}/cancel/', {}, content_type=JSON)
    check('farmer can cancel a still-pending order', r2c.status_code == 200, r2c.content[:300])
    check('cancelled order mirrors nothing',
          not Expense.objects.filter(source_pharmacy_order_id=order2_id).exists())

    # 5. The other real path to "delivered": a rider completes the delivery
    #    via OTP (delivery.views._sync_pharmacy_order), not the pharmacist's
    #    direct status PATCH. Must also mirror exactly once.
    admin = mk_user('admin_super', 'admin')
    rider = mk_user('delivery', 'rider')
    DeliveryProfile.objects.create(
        user=rider, drivers_license_number=f'DL-PHARMTEST-{rider.id.hex[:8]}',
        license_class='A', license_expiry_date='2030-01-01',
        license_photo_url='pending', current_status='offline',
    )
    ac = client_for(admin)
    rc = client_for(rider)

    medicine3 = PharmacyMedicine.objects.create(
        pharmacy_user=pharmacy, name='Test Dewormer', generic_name='Levamisole',
        category='antiparasitic', price=100, stock_quantity=30,
        unit='ml', expiry_date=date.today() + timedelta(days=365),
        is_active=True, is_approved=True,
        created_at=timezone.now(), updated_at=timezone.now(),
    )
    r3 = fc.post('/api/farmers/orders/', {
        'pharmacy_id': str(pharmacy.id),
        'items': [{'medicine_id': str(medicine3.id), 'quantity': 2}],
        'delivery_method': 'delivery',
        'delivery_address': 'Farm Road, Rider Test',
        'payment_method': 'cod',
    }, content_type=JSON)
    check('delivery-method order placed -> 201', r3.status_code == 201, r3.content[:300])
    order3_id = r3.json()['id']

    pc.patch(f'/api/pharmacy/orders/{order3_id}/status/', {'status': 'processing'}, content_type=JSON)
    r3_ship = pc.patch(f'/api/pharmacy/orders/{order3_id}/status/', {'status': 'shipped'}, content_type=JSON)
    check('delivery-method order ships into the delivery queue', r3_ship.status_code == 200, r3_ship.content[:300])

    r_queue = ac.get('/api/admin-panel/delivery-orders/')
    queue_row = next((row for row in r_queue.json()['results']
                       if row.get('is_queue') and row.get('customer') == farmer.full_name), None)
    check('order appears in the admin delivery queue', queue_row is not None, r_queue.content[:300])

    if queue_row is not None:
        r_riders = ac.get('/api/admin-panel/riders/')
        rider_row = next(row for row in r_riders.json()['results'] if row['name'] == rider.full_name)
        ac.patch(f"/api/admin-panel/riders/{rider_row['id']}/", {'action': 'approve'}, content_type=JSON)
        r_assign = ac.patch(f"/api/admin-panel/delivery-orders/{queue_row['id']}/", {
            'action': 'assign', 'rider_id': rider_row['id'],
        }, content_type=JSON)
        check('rider assigned from the queue', r_assign.status_code == 201, r_assign.content[:300])
        real_order_id = r_assign.json()['id']

        rc.patch(f'/api/delivery/requests/{real_order_id}/respond/', {'action': 'accept'}, content_type=JSON)
        rc.patch(f'/api/delivery/orders/{real_order_id}/status/', {'status': 'picked_up'}, content_type=JSON)
        rc.patch(f'/api/delivery/orders/{real_order_id}/status/', {'status': 'on_the_way'}, content_type=JSON)

        from delivery.models import DeliveryOrder
        real_order = DeliveryOrder.objects.get(id=real_order_id)
        r_otp_delivered = rc.patch(f'/api/delivery/orders/{real_order_id}/status/', {
            'status': 'delivered', 'otp_code': real_order.otp_code,
        }, content_type=JSON)
        check('rider marks delivered with OTP -> 200', r_otp_delivered.status_code == 200, r_otp_delivered.content[:300])

        mirrored3 = Expense.objects.filter(source_pharmacy_order_id=order3_id)
        check('rider-completed delivery mirrors into exactly one expense', mirrored3.count() == 1,
              list(mirrored3.values('id', 'amount')))
        if mirrored3.count() == 1:
            check('rider-path expense amount matches order total',
                  float(mirrored3.first().amount) == float(r3.json()['total_amount']))

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
