"""End-to-end coverage for the real pharmacy catalogue + farmer ordering +
delivery hand-off. Complements tests.py (which locks the legacy JSON bridge)."""

from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from pharmacy.models import PharmacyExpiryAlert, PharmacyMedicine
from pharmacy.services import regenerate_expiry_alerts
from profiles.models import DeliveryProfile
from users.models import Role, User


def _future(days):
    return (timezone.now().date() + timedelta(days=days)).isoformat()


class PharmacyCatalogueTests(APITestCase):
    def setUp(self):
        self.pharmacy = self._user('ph@test.local', 'pharmacy', 'Test Pharmacy', '01900000001')
        self.farmer = self._user('fa@test.local', 'farmer', 'Test Farmer', '01900000002')
        self.rider = self._user('rd@test.local', 'delivery', 'Test Rider', '01900000003')
        self.admin = self._user('ad@test.local', 'admin_super', 'Test Admin', '01900000004')
        DeliveryProfile.objects.create(
            user=self.rider, drivers_license_number='DL-CAT-1', license_class='A',
            license_expiry_date='2030-01-01', license_photo_url='x', current_status='offline')

    def _user(self, email, role, name, phone):
        user = User.objects.create_user(
            email=email, password='test', full_name=name, account_status='active',
            phone=phone, date_of_birth='1990-01-01', present_address='Test Rd', consent_terms=True)
        role_obj, _ = Role.objects.get_or_create(name=role, defaults={'panel_type': role})
        user.roles.add(role_obj)
        return user

    def _add_medicine(self, **overrides):
        body = {
            'name': 'Oxytetracycline 20%', 'manufacturer': 'Renata', 'category': 'antibiotic',
            'price': 420, 'stock_quantity': 40, 'unit': 'bottle', 'pack_size': '100ml',
            'expiry_date': _future(200), 'prescription_required': False,
        }
        body.update(overrides)
        return self.client.post('/api/pharmacy/medicines/', body, format='json')

    # ── catalogue + auto-approval ─────────────────────────────────────────

    def test_otc_auto_approves_prescription_needs_admin(self):
        self.client.force_authenticate(self.pharmacy)
        otc = self._add_medicine()
        self.assertEqual(otc.status_code, 201)
        self.assertTrue(otc.data['is_approved'])

        rx = self._add_medicine(name='Enrofloxacin', prescription_required=True,
                                cold_chain_required=True, expiry_date=_future(20))
        self.assertEqual(rx.status_code, 201)
        self.assertFalse(rx.data['is_approved'])
        rx_id = rx.data['id']

        # farmer cannot see the unapproved prescription medicine yet
        self.client.force_authenticate(self.farmer)
        search = self.client.get('/api/farmers/medicines/search/?query=Enro')
        self.assertEqual(search.data['results'], [])

        # admin approves it
        self.client.force_authenticate(self.admin)
        pending = self.client.get('/api/admin-panel/pharmacy/medicines/?pending=true')
        self.assertIn(rx_id, [m['id'] for m in pending.data['results']])
        approve = self.client.patch(f'/api/admin-panel/pharmacy/medicines/{rx_id}/approve/', {}, format='json')
        self.assertEqual(approve.status_code, 200)
        self.assertTrue(approve.data['is_approved'])

        self.client.force_authenticate(self.farmer)
        search = self.client.get('/api/farmers/medicines/search/?query=Enro')
        self.assertEqual(len(search.data['results']), 1)

    def test_medicine_validation(self):
        self.client.force_authenticate(self.pharmacy)
        self.assertEqual(self._add_medicine(price=0).status_code, 400)
        self.assertEqual(self._add_medicine(stock_quantity=-1).status_code, 400)
        self.assertEqual(self._add_medicine(expiry_date=_future(-2)).status_code, 400)
        self.assertEqual(self._add_medicine(category='banana').status_code, 400)

    def test_low_stock_and_expiry_alerts(self):
        self.client.force_authenticate(self.pharmacy)
        self._add_medicine(name='LowOne', stock_quantity=8)
        self._add_medicine(name='CritOne', stock_quantity=50, expiry_date=_future(5))
        self._add_medicine(name='WarnOne', stock_quantity=50, expiry_date=_future(20))

        summary = self.client.get('/api/pharmacy/inventory/summary/')
        self.assertEqual(summary.data['low_stock_count'], 1)
        self.assertGreaterEqual(summary.data['expiring_soon_count'], 2)
        self.assertEqual(summary.data['critical_expiry_count'], 1)

        low = self.client.get('/api/pharmacy/inventory/low-stock/')
        self.assertEqual([m['name'] for m in low.data['results']], ['LowOne'])

        expiring = self.client.get('/api/pharmacy/inventory/expiring-soon/')
        self.assertEqual(len(expiring.data['grouped']['critical']), 1)
        self.assertEqual(len(expiring.data['grouped']['warning']), 1)

        ack = self.client.post('/api/pharmacy/inventory/alerts/acknowledge/', {}, format='json')
        self.assertGreaterEqual(ack.data['acknowledged'], 2)

    # ── full order + delivery flow ───────────────────────────────────────

    def test_full_flow_with_delivery(self):
        # 1. pharmacy adds a cold-chain prescription vaccine + an OTC vitamin
        self.client.force_authenticate(self.pharmacy)
        vax = self._add_medicine(name='Newcastle Vaccine', category='vaccine',
                                 prescription_required=True, cold_chain_required=True,
                                 stock_quantity=10, price=680)
        vit = self._add_medicine(name='Vitamin AD3E', category='vitamin',
                                 stock_quantity=30, price=290)
        self.client.force_authenticate(self.admin)
        self.client.patch(f'/api/admin-panel/pharmacy/medicines/{vax.data["id"]}/approve/', {}, format='json')

        # 2. farmer finds the pharmacy + medicines
        self.client.force_authenticate(self.farmer)
        directory = self.client.get('/api/farmers/pharmacies/')
        self.assertEqual(len(directory.data['results']), 1)
        pharmacy_id = directory.data['results'][0]['id']

        # 3. ordering the vaccine without a prescription fails
        cart = [{'medicine_id': vax.data['id'], 'quantity': 2},
                {'medicine_id': vit.data['id'], 'quantity': 3}]
        blocked = self.client.post('/api/farmers/orders/', {
            'pharmacy_id': pharmacy_id, 'items': cart, 'delivery_method': 'delivery',
            'delivery_address': 'Green Valley Farm', 'payment_method': 'cod',
        }, format='json')
        self.assertEqual(blocked.status_code, 400)
        self.assertEqual(blocked.data['code'], 'prescription_required')

        # 4. with a prescription photo it succeeds and decrements stock
        placed = self.client.post('/api/farmers/orders/', {
            'pharmacy_id': pharmacy_id, 'items': cart, 'delivery_method': 'delivery',
            'delivery_address': 'Green Valley Farm', 'payment_method': 'cod',
            'prescription_image': 'http://x/rx.jpg', 'distance_km': 5,
        }, format='json')
        self.assertEqual(placed.status_code, 201)
        order_id = placed.data['order_id']
        self.assertEqual(placed.data['delivery_fee'], 105.0)  # 60 + 3km*15
        self.assertEqual(PharmacyMedicine.objects.get(pk=vax.data['id']).stock_quantity, 8)

        # 5. pharmacy confirms + hands off to delivery
        self.client.force_authenticate(self.pharmacy)
        incoming = self.client.get('/api/pharmacy/orders/?status=pending')
        self.assertIn(order_id, [o['order_id'] for o in incoming.data['results']])
        self.assertEqual(self.client.post(f'/api/pharmacy/orders/{order_id}/confirm/', {}, format='json').status_code, 200)
        ready = self.client.post(f'/api/pharmacy/orders/{order_id}/ready-for-delivery/', {}, format='json')
        self.assertEqual(ready.status_code, 200)
        queue = AdminPanelRecord.objects.get(module='delivery-queue', record_id=f'DQ-{order_id}')
        self.assertTrue(queue.payload['is_cold_chain'])
        self.assertTrue(queue.payload['is_prescription_required'])

        # 6. delivery admin approves the rider and assigns the queued job
        self.client.force_authenticate(self.admin)
        riders = self.client.get('/api/admin-panel/riders/')
        rider_row = next(r for r in riders.data['results'] if r['name'] == 'Test Rider')
        self.client.patch(f"/api/admin-panel/riders/{rider_row['id']}/", {'action': 'approve'}, format='json')
        assigned = self.client.patch(f'/api/admin-panel/delivery-orders/DQ-{order_id}/',
                                     {'action': 'assign', 'rider_id': rider_row['id']}, format='json')
        self.assertEqual(assigned.status_code, 201)
        delivery_order_id = assigned.data['id']
        real = DeliveryOrder.objects.get(pk=delivery_order_id)
        self.assertTrue(real.is_cold_chain)

        # pharmacy now sees the assigned rider on the order
        self.client.force_authenticate(self.pharmacy)
        detail = self.client.get(f'/api/pharmacy/orders/{order_id}/detail/')
        self.assertEqual(detail.data['delivery']['rider_name'], 'Test Rider')

        # 7. rider delivers with the OTP
        self.client.force_authenticate(self.rider)
        self.client.patch(f'/api/delivery/requests/{delivery_order_id}/respond/', {'action': 'accept'}, format='json')
        self.client.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'picked_up'}, format='json')
        self.client.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'on_the_way'}, format='json')
        done = self.client.patch(f'/api/delivery/orders/{delivery_order_id}/status/',
                                 {'status': 'delivered', 'otp_code': real.otp_code}, format='json')
        self.assertEqual(done.status_code, 200)

        # 8. farmer sees it delivered with a completed timeline
        self.client.force_authenticate(self.farmer)
        my_order = self.client.get(f'/api/farmers/orders/{order_id}/')
        self.assertEqual(my_order.data['status'], 'delivered')
        self.assertTrue(all(step['done'] for step in my_order.data['timeline']))

    def test_farmer_cancel_before_confirmation_restocks(self):
        self.client.force_authenticate(self.pharmacy)
        med = self._add_medicine(stock_quantity=20)
        self.client.force_authenticate(self.farmer)
        directory = self.client.get('/api/farmers/pharmacies/')
        placed = self.client.post('/api/farmers/orders/', {
            'pharmacy_id': directory.data['results'][0]['id'],
            'items': [{'medicine_id': med.data['id'], 'quantity': 5}],
            'delivery_method': 'pickup', 'payment_method': 'cod',
        }, format='json')
        order_id = placed.data['order_id']
        self.assertEqual(PharmacyMedicine.objects.get(pk=med.data['id']).stock_quantity, 15)
        cancelled = self.client.post(f'/api/farmers/orders/{order_id}/cancel/',
                                     {'reason': 'Found local stock'}, format='json')
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(PharmacyMedicine.objects.get(pk=med.data['id']).stock_quantity, 20)

    # ── suppliers ────────────────────────────────────────────────────────

    def test_supplier_crud(self):
        self.client.force_authenticate(self.pharmacy)
        created = self.client.post('/api/pharmacy/suppliers/', {
            'supplier_name': 'Renata Animal Health', 'contact_person': 'Mr Rahman',
            'phone': '01711111111', 'products_supplied': 'Oxytetracycline, Enrofloxacin',
        }, format='json')
        self.assertEqual(created.status_code, 201)
        sid = created.data['supplier_id']
        listed = self.client.get('/api/pharmacy/suppliers/')
        self.assertEqual(len(listed.data['results']), 1)
        updated = self.client.patch(f'/api/pharmacy/suppliers/{sid}/',
                                    {'payment_terms': 'Net 30'}, format='json')
        self.assertEqual(updated.data['payment_terms'], 'Net 30')
        self.client.delete(f'/api/pharmacy/suppliers/{sid}/')
        self.assertFalse(self.client.get('/api/pharmacy/suppliers/?active=true').data['results'])
