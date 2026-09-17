"""Farmer-facing feed marketplace (Priorities 5, 7) — "Order Now" -> Feed tab.

Farmers may only ever browse/order admin-approved catalogue products;
``services.order_items_from_cart`` is the sole place prices/availability are
resolved, always server-side. Orders reuse the same
``audit.AdminPanelRecord`` JSON-bridge queue pattern as
``module='pharmacy-orders'`` (module='feed-orders') so the proven
queue -> Feed Admin assign -> real DeliveryOrder flow (Priority 8) needs no
new schema.
"""
import uuid

from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import AdminPanelRecord
from consultations.permissions import IsFarmer

from .models import FeedProduct
from .services import delivery_fee_for, order_items_from_cart, order_key, product_json

PAYMENT_METHODS = ('cod', 'bkash', 'nagad', 'card')


@api_view(['GET'])
@permission_classes([IsFarmer])
def products(request):
    qs = FeedProduct.objects.select_related('company').filter(
        approval_status='approved', company__status='active')
    q = request.query_params
    if q.get('bird_type'):
        qs = qs.filter(bird_type=q['bird_type'])
    if q.get('feed_type'):
        qs = qs.filter(feed_type=q['feed_type'])
    if q.get('company_id'):
        qs = qs.filter(company_id=q['company_id'])
    if q.get('search'):
        from django.db.models import Q
        term = q['search']
        qs = qs.filter(Q(product_name__icontains=term) | Q(brand__icontains=term))
    if q.get('max_price'):
        try:
            qs = qs.filter(price__lte=float(q['max_price']))
        except ValueError:
            pass
    if q.get('min_price'):
        try:
            qs = qs.filter(price__gte=float(q['min_price']))
        except ValueError:
            pass
    if q.get('in_stock_only') == 'true':
        qs = qs.filter(stock_quantity__gt=0)
    qs = qs.order_by('product_name')
    total = qs.count()
    try:
        limit = min(int(q.get('limit', 50)), 200)
    except (TypeError, ValueError):
        limit = 50
    try:
        offset = max(int(q.get('offset', 0)), 0)
    except (TypeError, ValueError):
        offset = 0
    page = qs[offset:offset + limit]
    return Response({'results': [product_json(p) for p in page],
                      'total': total, 'offset': offset, 'limit': limit})


@api_view(['GET'])
@permission_classes([IsFarmer])
def product_detail(request, product_id):
    try:
        product = FeedProduct.objects.select_related('company').get(
            pk=product_id, approval_status='approved')
    except (FeedProduct.DoesNotExist, ValueError):
        return Response({'detail': 'Product not found or not currently available.'}, status=404)
    return Response(product_json(product))


def _order_json(record):
    payload = record.payload or {}
    order_flow = ['created', 'confirmed', 'preparing', 'ready_for_pickup', 'assigned',
                 'picked_up', 'out_for_delivery', 'delivered']
    status = payload.get('status', 'created')
    return {
        **payload,
        'timeline': [{'step': s, 'done': (order_flow.index(s) <= order_flow.index(status)
                                          if status in order_flow else False)}
                    for s in order_flow],
        'can_cancel': status in ('created', 'confirmed'),
    }


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def orders(request):
    if request.method == 'GET':
        qs = AdminPanelRecord.objects.filter(
            module='feed-orders', payload__farmer_id=str(request.user.id)).order_by('-created_at')
        total = qs.count()
        try:
            limit = min(int(request.query_params.get('limit', 50)), 200)
        except (TypeError, ValueError):
            limit = 50
        try:
            offset = max(int(request.query_params.get('offset', 0)), 0)
        except (TypeError, ValueError):
            offset = 0
        page = qs[offset:offset + limit]
        return Response({'results': [_order_json(r) for r in page],
                          'total': total, 'offset': offset, 'limit': limit})

    data = request.data
    cart = data.get('items') or []
    payment_method = str(data.get('payment_method', 'cod')).lower()
    if payment_method not in PAYMENT_METHODS:
        return Response({'detail': f'payment_method must be one of {PAYMENT_METHODS}.'}, status=400)
    delivery_address = (data.get('delivery_address') or request.user.present_address or '').strip()
    if not delivery_address:
        return Response({'detail': 'A delivery address is required.'}, status=400)
    try:
        latitude = float(data['latitude']) if data.get('latitude') is not None else None
        longitude = float(data['longitude']) if data.get('longitude') is not None else None
    except (TypeError, ValueError):
        return Response({'detail': 'latitude/longitude must be numeric.'}, status=400)

    with transaction.atomic():
        items, products_by_id, error = order_items_from_cart(cart, lock=True)
        if error:
            return Response({'detail': error}, status=409)

        subtotal = round(sum(i['line_total'] for i in items), 2)
        try:
            distance = float(data['distance_km']) if data.get('distance_km') else None
        except (TypeError, ValueError):
            distance = None
        delivery_fee = delivery_fee_for(distance) if distance is not None else 60.0
        total = round(subtotal + delivery_fee, 2)

        for item in items:
            product = products_by_id[item['product_id']]
            product.stock_quantity -= item['quantity']
            product.orders_count += 1
            product.updated_at = timezone.now()
            product.save(update_fields=['stock_quantity', 'orders_count', 'updated_at'])

        order_id = f'FEED-{uuid.uuid4().hex[:10].upper()}'
        # Dev/sandbox only: no real bKash/Nagad/card provider is configured
        # anywhere in this backend (see billing.services.billing_mode) — a
        # non-COD method is marked paid immediately and clearly labelled as
        # such rather than pretending to process a real payment.
        payment_status = 'pending' if payment_method == 'cod' else 'paid'
        payload = {
            'id': order_id,
            'order_number': f'#FD-{order_id[-6:]}',
            'farmer_id': str(request.user.id),
            'farmer_name': request.user.full_name or request.user.email,
            'farmer_phone': request.user.phone or '',
            'delivery_address': delivery_address,
            'latitude': latitude, 'longitude': longitude,
            'location_label': data.get('location_label', ''),
            'contact_phone': data.get('contact_phone') or request.user.phone or '',
            'payment_method': payment_method,
            'payment_status': payment_status,
            'payment_mode': 'sandbox' if payment_method != 'cod' else 'cod',
            'delivery_fee': delivery_fee,
            'subtotal': subtotal,
            'total_amount': total,
            'items': items,
            'status': 'created',
            'delivery_notes': str(data.get('notes', '')),
            'created_at': timezone.now().isoformat(),
            'delivered_at': None,
            'delivery_order_id': None,
            'assigned_rider_id': None,
        }
        record = AdminPanelRecord.objects.create(
            module='feed-orders', record_id=order_key(order_id), payload=payload)

    from notifications.models import Notification
    from users.models import User
    for admin in User.objects.filter(roles__name='feed_admin').distinct():
        Notification.objects.create(
            user=admin, title='New feed order',
            body=f'{payload["farmer_name"]} placed {payload["order_number"]} '
                 f'({len(items)} item(s), ৳{total:.0f}).',
            notification_type='alert', reference_type='feed_order')
    Notification.objects.create(
        user=request.user, title='Order placed',
        body=f'Your feed order {payload["order_number"]} has been placed.',
        notification_type='system', reference_type='feed_order')
    return Response(_order_json(record), status=201)


@api_view(['GET'])
@permission_classes([IsFarmer])
def order_detail(request, order_id):
    record = AdminPanelRecord.objects.filter(
        module='feed-orders', payload__id=order_id, payload__farmer_id=str(request.user.id)).first()
    if record is None:
        return Response({'detail': 'Order not found.'}, status=404)
    return Response(_order_json(record))


@api_view(['POST'])
@permission_classes([IsFarmer])
def order_cancel(request, order_id):
    with transaction.atomic():
        record = AdminPanelRecord.objects.select_for_update().filter(
            module='feed-orders', payload__id=order_id, payload__farmer_id=str(request.user.id)).first()
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        if payload.get('status') not in ('created', 'confirmed'):
            return Response({'detail': 'This order can no longer be cancelled.'}, status=409)
        for item in payload.get('items', []):
            product = FeedProduct.objects.filter(pk=item['product_id']).select_for_update().first()
            if product is not None:
                product.stock_quantity += int(item.get('quantity', 0))
                product.updated_at = timezone.now()
                product.save(update_fields=['stock_quantity', 'updated_at'])
        payload['status'] = 'cancelled'
        payload['cancel_reason'] = str(request.data.get('reason', 'Cancelled by farmer.'))
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
    return Response(_order_json(record))
