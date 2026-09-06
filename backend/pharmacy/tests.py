from rest_framework.test import APITestCase

from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from profiles.models import DeliveryProfile
from users.models import Role, User


class PharmacyEcosystemTests(APITestCase):
    def setUp(self):
        self.pharmacy = self._user('pharmacy@test.local', 'pharmacy', 'Test Pharmacy', '01700000001')
        self.farmer = self._user('farmer@test.local', 'farmer', 'Test Farmer', '01700000002')
        self.delivery = self._user('delivery@test.local', 'delivery', 'Test Rider', '01700000003')
        self.admin = self._user('admin@test.local', 'admin_super', 'Test Admin', '01700000004')
        DeliveryProfile.objects.create(
            user=self.delivery, drivers_license_number='DL-TEST-001', license_class='A',
            license_expiry_date='2030-01-01', license_photo_url='pending', current_status='offline',
        )

    def _user(self, email, role_name, name, phone):
        user = User.objects.create_user(
            email=email, password='test', full_name=name, account_status='active',
            phone=phone, date_of_birth='1990-01-01', present_address='Test Address',
            consent_terms=True,
        )
        role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
        user.roles.add(role)
        return user

    def test_complete_order_bridge(self):
        self.client.force_authenticate(self.pharmacy)
        response = self.client.post('/api/pharmacy/products/', {
            'id': 'ECO-MED', 'name': 'Eco Medicine', 'category': 'medicines',
            'stock_count': 10, 'min_stock': 2, 'unit': 'bottle', 'price': 100,
            'manufacturer': 'Eco Lab', 'expiry_date': '2027-12-31',
        }, format='json')
        self.assertEqual(response.status_code, 201)

        self.client.force_authenticate(self.admin)
        response = self.client.patch('/api/admin-panel/medicines/ECO-MED/', {'status': 'Approved'}, format='json')
        self.assertEqual(response.status_code, 200)

        self.client.force_authenticate(self.farmer)
        response = self.client.get('/api/pharmacy/marketplace/')
        self.assertIn('ECO-MED', [row['id'] for row in response.data['results']])
        response = self.client.post('/api/pharmacy/place-order/', {
            'pharmacy_user_id': str(self.pharmacy.id),
            'items': [{'product_id': 'ECO-MED', 'quantity': 2}],
            'delivery_address': 'Farm Road',
        }, format='json')
        self.assertEqual(response.status_code, 201)
        order_id = response.data['id']

        product = AdminPanelRecord.objects.get(module='pharmacy-products', record_id=f'{self.pharmacy.id}:ECO-MED')
        self.assertEqual(product.payload['stock_count'], 8)

        self.client.force_authenticate(self.pharmacy)
        self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'processing', 'status_message': 'Preparing the medicines.'}, format='json')
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'shipped', 'status_message': 'Packed and handed to delivery.'}, format='json')
        self.assertEqual(response.status_code, 200)
        # No rider has accepted yet, so the order can still be pulled back for repacking.
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'processing', 'status_message': 'Package needs repacking before rider assignment.'}, format='json')
        self.assertEqual(response.status_code, 200)
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'shipped', 'status_message': 'Repacked and ready for delivery.'}, format='json')
        self.assertEqual(response.status_code, 200)

        # A delivery-queue entry should now exist, awaiting admin assignment.
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/admin-panel/delivery-orders/')
        queue_row = next(row for row in response.data['results'] if row['is_queue'] and row['customer'] == 'Test Farmer')
        queue_id = queue_row['id']

        # Approving the rider is required before they can be assigned.
        response = self.client.get('/api/admin-panel/riders/')
        rider_row = next(row for row in response.data['results'] if row['name'] == 'Test Rider')
        self.assertFalse(rider_row['approved'])
        response = self.client.patch(f'/api/admin-panel/delivery-orders/{queue_id}/', {
            'action': 'assign', 'rider_id': rider_row['id'],
        }, format='json')
        self.assertEqual(response.status_code, 409)

        response = self.client.patch(f"/api/admin-panel/riders/{rider_row['id']}/", {'action': 'approve'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['approved'])

        response = self.client.patch(f'/api/admin-panel/delivery-orders/{queue_id}/', {
            'action': 'assign', 'rider_id': rider_row['id'],
        }, format='json')
        self.assertEqual(response.status_code, 201)
        real_order_id = response.data['id']

        # Once assigned, the pharmacy order can no longer be pulled back for repacking.
        self.client.force_authenticate(self.pharmacy)
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'processing', 'status_message': 'Trying to recall it.'}, format='json')
        self.assertEqual(response.status_code, 409)

        self.client.force_authenticate(self.delivery)
        response = self.client.get('/api/delivery/requests/')
        job = next(row for row in response.data['results'] if row['id'] == real_order_id)
        response = self.client.patch(f"/api/delivery/requests/{job['id']}/respond/", {'action': 'accept'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'accepted')

        response = self.client.patch(f"/api/delivery/orders/{job['id']}/status/", {'status': 'picked_up'}, format='json')
        self.assertEqual(response.status_code, 200)
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/status/", {'status': 'on_the_way'}, format='json')
        self.assertEqual(response.status_code, 200)

        response = self.client.patch(f"/api/delivery/orders/{job['id']}/status/", {'status': 'delivered', 'otp_code': '000000'}, format='json')
        self.assertEqual(response.status_code, 400)

        real_order = DeliveryOrder.objects.get(id=job['id'])
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/status/", {'status': 'delivered', 'otp_code': real_order.otp_code}, format='json')
        self.assertEqual(response.status_code, 200)

        pharmacy_order = AdminPanelRecord.objects.get(module='pharmacy-orders', payload__id=order_id)
        self.assertEqual(pharmacy_order.payload['status'], 'delivered')
        self.assertGreaterEqual(self.farmer.notifications.count(), 2)

        response = self.client.get('/api/delivery/earnings/')
        self.assertGreater(response.data['total_earnings'], 0)

    def test_seeded_order_with_non_uuid_farmer_can_move_backward(self):
        self.client.force_authenticate(self.pharmacy)
        self.client.get('/api/pharmacy/dashboard/')
        order = AdminPanelRecord.objects.get(
            module='pharmacy-orders',
            record_id=f'{self.pharmacy.id}:ORD-002',
        )
        order.payload = {**order.payload, 'farmer_id': 'F002', 'status': 'processing'}
        order.save(update_fields=['payload', 'updated_at'])
        response = self.client.patch(
            '/api/pharmacy/orders/ORD-002/',
            {'status': 'pending', 'status_message': 'Waiting for farmer confirmation.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'pending')

    def test_pharmacist_can_confirm_shipped_order_as_delivered(self):
        self.client.force_authenticate(self.pharmacy)
        self.client.get('/api/pharmacy/dashboard/')

        processing = self.client.patch(
            '/api/pharmacy/orders/ORD-001/',
            {'status': 'processing', 'status_message': 'Preparing the order.'},
            format='json',
        )
        self.assertEqual(processing.status_code, 200)
        shipped = self.client.patch(
            '/api/pharmacy/orders/ORD-001/',
            {'status': 'shipped', 'status_message': 'Order handed over for delivery.'},
            format='json',
        )
        self.assertEqual(shipped.status_code, 200)
        self.assertTrue(
            AdminPanelRecord.objects.filter(module='delivery-queue', record_id='DQ-ORD-001').exists()
        )

        unconfirmed = self.client.patch(
            '/api/pharmacy/orders/ORD-001/',
            {'status': 'delivered', 'status_message': 'Customer received the order.'},
            format='json',
        )
        self.assertEqual(unconfirmed.status_code, 400)

        delivered = self.client.patch(
            '/api/pharmacy/orders/ORD-001/',
            {
                'status': 'delivered',
                'status_message': 'Customer received the order.',
                'delivery_confirmed': True,
            },
            format='json',
        )
        self.assertEqual(delivered.status_code, 200)
        self.assertEqual(delivered.data['status'], 'delivered')
        self.assertTrue(delivered.data['delivered_at'])

        # The order was completed directly by the pharmacist, so the stale
        # unassigned queue entry should have been cleaned up.
        self.assertFalse(
            AdminPanelRecord.objects.filter(module='delivery-queue', record_id='DQ-ORD-001').exists()
        )
