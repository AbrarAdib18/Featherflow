import uuid
from datetime import datetime, timedelta

from django.db import transaction
from django.core.exceptions import ValidationError
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, BasePermission
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from audit.models import ActivityLog, AdminPanelRecord
from notifications.models import Notification
from users.models import User


@api_view(['GET'])
@permission_classes([AllowAny])
def pharmacy_root(request):
    return Response({
        'message': 'Featherflow Pharmacy API',
        'dashboard': request.build_absolute_uri('dashboard/'),
        'products': request.build_absolute_uri('products/'),
        'orders': request.build_absolute_uri('orders/'),
        'authentication': 'Send a pharmacy JWT as Authorization: Bearer <token>.',
    })


class IsPharmacyUser(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            user.is_superuser or (user.account_status == 'active' and user.roles.filter(name='pharmacy').exists())
        ))


def _profile(user):
    data = user.profile_data if isinstance(user.profile_data, dict) else {}
    return {
        'name': data.get('business_name') or user.full_name or user.email,
        'license_number': data.get('pharmacy_license_number', ''),
        'location': data.get('business_address') or user.present_address or '',
        'phone': user.phone or '',
    }


def _log(request, action, entity_id, values=None):
    try:
        target_id = uuid.UUID(str(entity_id))
    except (TypeError, ValueError, AttributeError):
        target_id = None
    ActivityLog.objects.create(
        user=request.user, module='Pharmacy', action=action,
        entity_type='pharmacy', entity_id=target_id,
        new_values=values,
    )


def _key(user, record_id):
    return f'{user.id}:{record_id}'


def _admin_medicine_payload(user, product, status='Pending'):
    expiry = product.get('expiry_date')
    try:
        expires_in_days = max(0, (datetime.fromisoformat(expiry).date() - timezone.now().date()).days)
    except (TypeError, ValueError):
        expires_in_days = 0
    return {
        'id': product['id'],
        'name': product.get('name', ''),
        'pharmacy': _profile(user)['name'],
        'pharmacy_user_id': str(user.id),
        'status': status,
        'price': product.get('price', 0),
        'expires_in_days': expires_in_days,
    }


def _sync_admin_medicine(user, product, status=None):
    record, _ = AdminPanelRecord.objects.get_or_create(
        module='medicines', record_id=product['id'],
        defaults={'payload': _admin_medicine_payload(user, product)},
    )
    current_status = status or record.payload.get('status', 'Pending')
    record.payload = _admin_medicine_payload(user, product, current_status)
    record.save(update_fields=['payload', 'updated_at'])


def _records(user, module):
    _seed(user)
    return [r.payload for r in AdminPanelRecord.objects.filter(
        module=module, payload__owner_id=str(user.id)
    )]


def _seed(user):
    owner = str(user.id)
    now = timezone.now()
    products = [
        {'id': 'MED-001', 'name': 'Oxytetracycline 20%', 'category': 'medicines', 'stock_count': 24, 'min_stock': 10, 'unit': 'bottle', 'price': 420, 'manufacturer': 'Renata Animal Health', 'expiry_date': (now + timedelta(days=240)).date().isoformat(), 'description': 'Broad-spectrum veterinary antibiotic.'},
        {'id': 'VAC-001', 'name': 'Newcastle Vaccine', 'category': 'vaccines', 'stock_count': 7, 'min_stock': 10, 'unit': 'vial', 'price': 680, 'manufacturer': 'ACI Animal Health', 'expiry_date': (now + timedelta(days=120)).date().isoformat(), 'description': 'Live vaccine for poultry flocks.'},
        {'id': 'SUP-001', 'name': 'Vitamin AD3E Supplement', 'category': 'supplements', 'stock_count': 36, 'min_stock': 12, 'unit': 'bottle', 'price': 290, 'manufacturer': 'Square Agrovet', 'expiry_date': (now + timedelta(days=360)).date().isoformat(), 'description': 'Vitamin supplement for poultry.'},
        {'id': 'EQP-001', 'name': 'Automatic Vaccinator', 'category': 'equipment', 'stock_count': 0, 'min_stock': 3, 'unit': 'piece', 'price': 1850, 'manufacturer': 'Agro Tools BD', 'expiry_date': (now + timedelta(days=1825)).date().isoformat(), 'description': 'Reusable poultry vaccination equipment.'},
    ]
    orders = [
        {'id': 'ORD-001', 'order_number': '#PH-1042', 'farmer_id': 'F001', 'farmer_name': 'Karim Hossain', 'farm_name': 'Green Valley Poultry', 'status': 'pending', 'created_at': (now - timedelta(hours=2)).isoformat(), 'delivered_at': None, 'notes': 'Please pack vaccines with ice.', 'items': [{'product_id': 'VAC-001', 'product_name': 'Newcastle Vaccine', 'quantity': 2, 'unit_price': 680}]},
        {'id': 'ORD-002', 'order_number': '#PH-1041', 'farmer_id': 'F002', 'farmer_name': 'Jamal Mia', 'farm_name': 'Mia Poultry Farm', 'status': 'processing', 'created_at': (now - timedelta(days=1)).isoformat(), 'delivered_at': None, 'notes': '', 'items': [{'product_id': 'MED-001', 'product_name': 'Oxytetracycline 20%', 'quantity': 3, 'unit_price': 420}]},
        {'id': 'ORD-003', 'order_number': '#PH-1040', 'farmer_id': 'F003', 'farmer_name': 'Salma Akter', 'farm_name': 'Akter Layers', 'status': 'delivered', 'created_at': (now - timedelta(days=2)).isoformat(), 'delivered_at': now.isoformat(), 'notes': '', 'items': [{'product_id': 'SUP-001', 'product_name': 'Vitamin AD3E Supplement', 'quantity': 4, 'unit_price': 290}]},
    ]
    with transaction.atomic():
        for module, entries in [('pharmacy-products', products), ('pharmacy-orders', orders)]:
            if AdminPanelRecord.objects.filter(module=module, payload__owner_id=owner).exists():
                continue
            for entry in entries:
                payload = {**entry, 'owner_id': owner}
                AdminPanelRecord.objects.get_or_create(
                    module=module, record_id=_key(user, entry['id']),
                    defaults={'payload': payload},
                )
                if module == 'pharmacy-products':
                    _sync_admin_medicine(user, payload, status='Approved')


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def dashboard(request):
    products = _records(request.user, 'pharmacy-products')
    orders = _records(request.user, 'pharmacy-orders')
    return Response({'profile': _profile(request.user), 'products': products, 'orders': orders})


@api_view(['GET', 'POST'])
@permission_classes([IsPharmacyUser])
def collection(request, kind):
    module = {'products': 'pharmacy-products', 'orders': 'pharmacy-orders'}.get(kind)
    if not module:
        return Response({'detail': 'Unknown pharmacy resource.'}, status=404)
    if request.method == 'GET':
        return Response({'results': _records(request.user, module)})
    data = dict(request.data)
    record_id = str(data.get('id') or uuid.uuid4())
    data.update({'id': record_id, 'owner_id': str(request.user.id)})
    if kind == 'products':
        required = ['name', 'category', 'unit', 'manufacturer', 'expiry_date']
        missing = [field for field in required if not str(data.get(field, '')).strip()]
        if missing:
            return Response({'detail': f'Missing required fields: {", ".join(missing)}.'}, status=400)
        if data.get('category') not in {'medicines', 'vaccines', 'supplements', 'equipment'}:
            return Response({'detail': 'Invalid product category.'}, status=400)
    record, created = AdminPanelRecord.objects.get_or_create(
        module=module, record_id=_key(request.user, record_id),
        defaults={'payload': data},
    )
    if not created:
        return Response({'detail': 'A record with this ID already exists.'}, status=409)
    if kind == 'products':
        _sync_admin_medicine(request.user, data)
    _log(request, f'Create {kind[:-1]}', record_id, data)
    return Response(data, status=201)


@api_view(['GET', 'PATCH', 'DELETE'])
@permission_classes([IsPharmacyUser])
def record(request, kind, record_id):
    module = {'products': 'pharmacy-products', 'orders': 'pharmacy-orders'}.get(kind)
    if not module:
        return Response({'detail': 'Unknown pharmacy resource.'}, status=404)
    _seed(request.user)
    try:
        item = AdminPanelRecord.objects.get(module=module, record_id=_key(request.user, record_id))
    except AdminPanelRecord.DoesNotExist:
        return Response({'detail': 'Record not found.'}, status=404)
    if request.method == 'GET':
        return Response(item.payload)
    if request.method == 'DELETE':
        if kind == 'products':
            _sync_admin_medicine(request.user, item.payload, status='Removed')
        item.delete()
        _log(request, f'Delete {kind[:-1]}', record_id)
        return Response(status=204)
    allowed = ({'name', 'category', 'stock_count', 'min_stock', 'unit', 'price', 'manufacturer', 'expiry_date', 'description'}
               if kind == 'products' else {'status', 'delivered_at', 'notes', 'status_message'})
    changes = {key: value for key, value in request.data.items() if key in allowed}
    if kind == 'orders' and 'status' in changes:
        current_status = item.payload.get('status', 'pending')
        new_status = changes['status']
        transitions = {
            'pending': {'processing', 'cancelled'},
            'processing': {'pending', 'shipped', 'cancelled'},
            'shipped': {'processing', 'delivered'},
            'delivered': set(), 'cancelled': set(),
        }
        if new_status not in transitions.get(current_status, set()):
            return Response({'detail': f'Cannot move an order from {current_status} to {new_status}.'}, status=409)
        message = str(changes.get('status_message', '')).strip()
        if not message:
            return Response({'detail': 'A status update message is required.'}, status=400)
        if new_status == 'delivered' and request.data.get('delivery_confirmed') is not True:
            return Response({'detail': 'Delivery confirmation is required before completing the order.'}, status=400)
        if current_status == 'shipped' and new_status == 'processing':
            delivery = AdminPanelRecord.objects.filter(
                module='delivery-orders', record_id=f'DEL-{record_id}').first()
            if delivery and delivery.payload.get('status') != 'Pending':
                return Response({'detail': 'This order cannot be returned because a rider has already accepted the delivery.'}, status=409)
            if delivery:
                delivery.delete()
        history = list(item.payload.get('status_history', []))
        history.append({
            'from': current_status, 'to': new_status, 'message': message,
            'changed_at': timezone.now().isoformat(),
            'changed_by': request.user.full_name or request.user.email,
        })
        changes['status_history'] = history
        if new_status == 'delivered':
            changes['delivered_at'] = timezone.now().isoformat()
            delivery = AdminPanelRecord.objects.filter(
                module='delivery-orders', record_id=f'DEL-{record_id}').first()
            if delivery:
                delivery.payload = {**delivery.payload, 'status': 'Delivered', 'completed_by': request.user.full_name or request.user.email, 'completed_at': timezone.now().isoformat()}
                delivery.save(update_fields=['payload', 'updated_at'])
        if new_status == 'cancelled':
            for order_item in item.payload.get('items', []):
                try:
                    product_record = AdminPanelRecord.objects.get(
                        module='pharmacy-products',
                        record_id=_key(request.user, order_item['product_id']))
                    product = dict(product_record.payload)
                    product['stock_count'] = int(product.get('stock_count', 0)) + int(order_item.get('quantity', 0))
                    product_record.payload = product
                    product_record.save(update_fields=['payload', 'updated_at'])
                except (AdminPanelRecord.DoesNotExist, KeyError, TypeError, ValueError):
                    pass
    item.payload = {**item.payload, **changes}
    item.save(update_fields=['payload', 'updated_at'])
    if kind == 'products':
        _sync_admin_medicine(request.user, item.payload)
    elif kind == 'orders' and changes.get('status') == 'shipped':
        order = item.payload
        delivery_id = f'DEL-{record_id}'
        AdminPanelRecord.objects.update_or_create(
            module='delivery-orders', record_id=delivery_id,
            defaults={'payload': {
                'id': delivery_id,
                'pharmacy_order_id': record_id,
                'customer': order.get('farmer_name', ''),
                'customer_phone': order.get('farmer_phone', ''),
                'destination': order.get('delivery_address', ''),
                'pickup': _profile(request.user)['location'],
                'pharmacy': _profile(request.user)['name'],
                'items': order.get('items', []),
                'status': 'Pending', 'type': 'pharmacy',
                'assigned_rider': None,
            }},
        )
    if kind == 'orders' and changes.get('status'):
        try:
            farmer = User.objects.get(pk=item.payload.get('farmer_id'))
            readable = changes['status'].replace('_', ' ').title()
            Notification.objects.create(
                user=farmer,
                title=f'Order {readable}',
                body=f'{item.payload.get("order_number", "Your medicine order")}: {changes["status_message"]}',
                notification_type='system', reference_type='pharmacy_order',
            )
        except (User.DoesNotExist, ValidationError, ValueError, TypeError):
            pass
    _log(request, f'Update {kind[:-1]}', record_id, changes)
    return Response(item.payload)


class IsFarmerUser(BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and (
            request.user.is_superuser or (request.user.account_status == 'active' and request.user.roles.filter(name='farmer').exists())
        ))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def marketplace(request):
    approved = {
        r.record_id for r in AdminPanelRecord.objects.filter(module='medicines')
        if r.payload.get('status') == 'Approved'
    }
    results = []
    for record in AdminPanelRecord.objects.filter(module='pharmacy-products'):
        product = record.payload
        if product.get('id') not in approved or int(product.get('stock_count', 0)) <= 0:
            continue
        owner_id = product.get('owner_id')
        try:
            pharmacy_user = User.objects.get(pk=owner_id)
        except (User.DoesNotExist, ValidationError, ValueError, TypeError):
            continue
        results.append({**product, 'pharmacy_user_id': owner_id, 'pharmacy_name': _profile(pharmacy_user)['name'], 'pharmacy_location': _profile(pharmacy_user)['location']})
    return Response({'results': results})


@api_view(['POST'])
@permission_classes([IsFarmerUser])
def place_order(request):
    pharmacy_id = str(request.data.get('pharmacy_user_id', ''))
    requested_items = request.data.get('items') or []
    if not pharmacy_id or not requested_items:
        return Response({'detail': 'Pharmacy and at least one item are required.'}, status=400)
    try:
        pharmacy_user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValidationError, ValueError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    order_id = f'ORD-{uuid.uuid4().hex[:10].upper()}'
    items = []
    with transaction.atomic():
        for requested in requested_items:
            product_id = str(requested.get('product_id', ''))
            quantity = int(requested.get('quantity', 0))
            if quantity <= 0:
                return Response({'detail': 'Item quantity must be positive.'}, status=400)
            try:
                product_record = AdminPanelRecord.objects.select_for_update().get(
                    module='pharmacy-products', record_id=_key(pharmacy_user, product_id))
            except AdminPanelRecord.DoesNotExist:
                return Response({'detail': f'Product {product_id} was not found.'}, status=404)
            product = dict(product_record.payload)
            medicine = AdminPanelRecord.objects.filter(module='medicines', record_id=product_id).first()
            if medicine is None or medicine.payload.get('status') != 'Approved':
                return Response({'detail': f'{product.get("name", "Product")} is not approved for sale.'}, status=409)
            if int(product.get('stock_count', 0)) < quantity:
                return Response({'detail': f'Insufficient stock for {product.get("name", "product")}.'}, status=409)
            product['stock_count'] = int(product['stock_count']) - quantity
            product_record.payload = product
            product_record.save(update_fields=['payload', 'updated_at'])
            items.append({'product_id': product_id, 'product_name': product['name'], 'quantity': quantity, 'unit_price': product['price']})
        farmer_profile = request.user.profile_data if isinstance(request.user.profile_data, dict) else {}
        order = {
            'id': order_id, 'order_number': f'#PH-{order_id[-6:]}',
            'farmer_id': str(request.user.id),
            'farmer_name': request.user.full_name or request.user.email,
            'farm_name': farmer_profile.get('farm_name', 'Poultry Farm'),
            'farmer_phone': request.user.phone or '',
            'delivery_address': request.data.get('delivery_address') or request.user.present_address,
            'items': items, 'status': 'pending', 'created_at': timezone.now().isoformat(),
            'delivered_at': None, 'notes': request.data.get('notes', ''),
            'owner_id': str(pharmacy_user.id),
        }
        AdminPanelRecord.objects.create(module='pharmacy-orders', record_id=_key(pharmacy_user, order_id), payload=order)
        Notification.objects.create(user=pharmacy_user, title='New pharmacy order', body=f'{order["farmer_name"]} placed order {order["order_number"]}.', notification_type='system', reference_type='pharmacy_order')
    return Response(order, status=201)
