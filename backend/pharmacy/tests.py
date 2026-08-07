from rest_framework.test import APITestCase

from audit.models import AdminPanelRecord
from users.models import Role, User


class PharmacyEcosystemTests(APITestCase):
    def setUp(self):
        self.pharmacy = self._user('pharmacy@test.local', 'pharmacy', 'Test Pharmacy')
        self.farmer = self._user('farmer@test.local', 'farmer', 'Test Farmer')
        self.delivery = self._user('delivery@test.local', 'delivery', 'Test Rider')
        self.admin = User.objects.create_superuser(email='admin@test.local', password='test')

    def _user(self, email, role_name, name):
        user = User.objects.create_user(email=email, password='test', full_name=name, account_status='active')
        role, _ = Role.objects.get_or_create(name=role_name, defaults={'display_name': role_name.title()})
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
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'pending', 'status_message': 'Prescription details require confirmation.'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'processing', 'status_message': 'Details confirmed; preparation resumed.'}, format='json')
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'shipped', 'status_message': 'Packed and handed to delivery.'}, format='json')
        self.assertEqual(response.status_code, 200)
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'processing', 'status_message': 'Package needs repacking before rider assignment.'}, format='json')
        self.assertEqual(response.status_code, 200)
        response = self.client.patch(f'/api/pharmacy/orders/{order_id}/', {'status': 'shipped', 'status_message': 'Repacked and ready for delivery.'}, format='json')

        self.client.force_authenticate(self.delivery)
        response = self.client.get('/api/delivery/orders/')
        job = next(row for row in response.data['results'] if row.get('pharmacy_order_id') == order_id)
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/", {'status': 'Accepted'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['assigned_rider'], 'Test Rider')
        self.client.patch(f"/api/delivery/orders/{job['id']}/", {'status': 'Picked Up'}, format='json')
        self.client.patch(f"/api/delivery/orders/{job['id']}/", {'status': 'On The Way'}, format='json')
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/", {'status': 'Delivered'}, format='json')
        self.assertEqual(response.status_code, 400)
        response = self.client.patch(f"/api/delivery/orders/{job['id']}/", {'status': 'Delivered', 'delivery_confirmed': True}, format='json')
        self.assertEqual(response.status_code, 200)
        pharmacy_order = AdminPanelRecord.objects.get(module='pharmacy-orders', payload__id=order_id)
        self.assertEqual(pharmacy_order.payload['status'], 'delivered')
        self.assertGreaterEqual(self.farmer.notifications.count(), 6)

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

        delivery = AdminPanelRecord.objects.get(
            module='delivery-orders', record_id='DEL-ORD-001'
        )
        self.assertEqual(delivery.payload['status'], 'Delivered')
        self.assertEqual(delivery.payload['completed_by'], 'Test Pharmacy')
