from rest_framework.test import APITestCase

from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from profiles.models import DeliveryProfile
from users.models import Role, User

_PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489'
    '0000000d4944415478da6364f8cf000000030101002718d6a40000000049454e44ae426082')


def complete_via_proof(test, rider, admin, delivery_order_id, otp=None):
    """F-005 lifecycle: arrive -> proof photo (+OTP) -> admin approves.
    Returns the approval response."""
    from django.core.files.uploadedfile import SimpleUploadedFile
    test.client.force_authenticate(rider)
    r = test.client.patch(f'/api/delivery/orders/{delivery_order_id}/status/', {'status': 'arrived'}, format='json')
    test.assertEqual(r.status_code, 200)
    if otp is not None:
        bad = test.client.post(f'/api/delivery/orders/{delivery_order_id}/proof/',
                               {'file': SimpleUploadedFile('p.png', _PNG, content_type='image/png'), 'otp_code': '000000'},
                               format='multipart')
        test.assertEqual(bad.status_code, 400)
    r = test.client.post(f'/api/delivery/orders/{delivery_order_id}/proof/',
                         {'file': SimpleUploadedFile('p.png', _PNG, content_type='image/png'),
                          **({'otp_code': otp} if otp is not None else {})}, format='multipart')
    test.assertEqual(r.status_code, 201)
    test.client.force_authenticate(admin)
    return test.client.post(f"/api/admin-panel/delivery-proofs/{r.data['proof']['id']}/approve/", {}, format='json')


def _seed_pharmacy_order(pharmacy, order_id, status, farmer_id):
    """A pharmacy order record as the bridge stores it (the GET handlers no
    longer fabricate demo orders - F-004 - so tests create what they need)."""
    from django.utils import timezone
    return AdminPanelRecord.objects.create(
        module='pharmacy-orders', record_id=f'{pharmacy.id}:{order_id}',
        payload={'id': order_id, 'order_number': f'#{order_id}', 'owner_id': str(pharmacy.id),
                 'pharmacy_user_id': str(pharmacy.id), 'farmer_id': farmer_id, 'farmer_name': 'Seed Farmer',
                 'customer': 'Seed Farmer', 'items': [], 'total_amount': 100, 'status': status,
                 'delivery_address': 'Seed Road', 'created_at': timezone.now().isoformat(),
                 'status_history': []})


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

        # F-005: a rider can no longer complete a delivery directly.
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/status/", {'status': 'delivered', 'otp_code': '000000'}, format='json')
        self.assertEqual(response.status_code, 409)

        real_order = DeliveryOrder.objects.get(id=job['id'])
        response = complete_via_proof(self, self.delivery, self.admin, job['id'], otp=real_order.otp_code)
        self.assertEqual(response.status_code, 200)

        pharmacy_order = AdminPanelRecord.objects.get(module='pharmacy-orders', payload__id=order_id)
        self.assertEqual(pharmacy_order.payload['status'], 'delivered')
        self.assertGreaterEqual(self.farmer.notifications.count(), 2)

        self.client.force_authenticate(self.delivery)
        response = self.client.get('/api/delivery/earnings/')
        self.assertGreater(response.data['total_earnings'], 0)

    def test_seeded_order_with_non_uuid_farmer_can_move_backward(self):
        self.client.force_authenticate(self.pharmacy)
        _seed_pharmacy_order(self.pharmacy, 'ORD-002', 'processing', 'F002')
        response = self.client.patch(
            '/api/pharmacy/orders/ORD-002/',
            {'status': 'pending', 'status_message': 'Waiting for farmer confirmation.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'pending')

    def test_pharmacist_can_confirm_shipped_order_as_delivered(self):
        self.client.force_authenticate(self.pharmacy)
        _seed_pharmacy_order(self.pharmacy, 'ORD-001', 'pending', str(self.farmer.id))

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
