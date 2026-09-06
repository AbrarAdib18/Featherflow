"""Farmer-facing pharmacy endpoints: browse pharmacies, search medicines, place
and track medicine orders, upload prescriptions.

Mounted under /api/farmers/ (see api/urls.py). Orders are written to the same
`pharmacy-orders` JSON bridge the pharmacy panel and delivery integration read,
so the existing tested flow is preserved end to end.
"""

import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from notifications.models import Notification
from users.models import User

from pharmacy.catalogue_views import MAX_IMAGE_BYTES, ALLOWED_IMAGE_EXT, order_json
from pharmacy.models import PharmacyMedicine
from pharmacy.services import (
    delivery_fee_for, medicine_json, notify, order_items_from_cart, order_key,
    pharmacy_public_profile,
)
from pharmacy.views import IsFarmerUser


# ── Browse ─────────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsFarmerUser])
def pharmacies(request):
    users = User.objects.filter(roles__name='pharmacy', account_status='active').distinct()
    rows = []
    for user in users:
        catalogue = PharmacyMedicine.objects.filter(
            pharmacy_user=user, is_active=True, is_approved=True, stock_quantity__gt=0)
        if not catalogue.exists():
            continue
        profile = pharmacy_public_profile(user)
        profile.update({
            'medicine_count': catalogue.count(),
            'categories': sorted({m.category for m in catalogue}),
            'has_prescription_medicines': catalogue.filter(prescription_required=True).exists(),
            'has_cold_chain': catalogue.filter(cold_chain_required=True).exists(),
        })
        rows.append(profile)
    if request.query_params.get('prescription_medicines') == 'true':
        rows = [r for r in rows if r['has_prescription_medicines']]
    if request.query_params.get('cold_chain') == 'true':
        rows = [r for r in rows if r['has_cold_chain']]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsFarmerUser])
def pharmacy_medicines(request, pharmacy_id):
    try:
        pharmacy_user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValueError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)
    qs = PharmacyMedicine.objects.filter(
        pharmacy_user=pharmacy_user, is_active=True, is_approved=True)
    category = request.query_params.get('category')
    if category:
        qs = qs.filter(category=category)
    if request.query_params.get('in_stock') == 'true':
        qs = qs.filter(stock_quantity__gt=0)
    return Response({
        'pharmacy': pharmacy_public_profile(pharmacy_user),
        'results': [medicine_json(m, for_farmer=True) for m in qs],
    })


@api_view(['GET'])
@permission_classes([IsFarmerUser])
def medicine_search(request):
    qs = PharmacyMedicine.objects.filter(is_active=True, is_approved=True).select_related('pharmacy_user')
    query = (request.query_params.get('query') or request.query_params.get('q') or '').strip()
    if query:
        qs = (qs.filter(name__icontains=query)
              | qs.filter(generic_name__icontains=query)
              | qs.filter(manufacturer__icontains=query))
    category = request.query_params.get('category')
    if category:
        qs = qs.filter(category__in=[c.strip() for c in category.split(',')])
    prescription = request.query_params.get('prescription_required')
    if prescription in ('true', 'false'):
        qs = qs.filter(prescription_required=(prescription == 'true'))
    pharmacy_id = request.query_params.get('pharmacy')
    if pharmacy_id:
        qs = qs.filter(pharmacy_user_id=pharmacy_id)
    try:
        if request.query_params.get('min_price'):
            qs = qs.filter(price__gte=float(request.query_params['min_price']))
        if request.query_params.get('max_price'):
            qs = qs.filter(price__lte=float(request.query_params['max_price']))
    except ValueError:
        return Response({'detail': 'Price filters must be numbers.'}, status=400)
    if request.query_params.get('in_stock') == 'true':
        qs = qs.filter(stock_quantity__gt=0)
    qs = qs.order_by('-orders_count', 'price')[:100]
    return Response({'results': [medicine_json(m, for_farmer=True) for m in qs]})


@api_view(['GET'])
@permission_classes([IsFarmerUser])
def medicine_detail(request, medicine_id):
    medicine = PharmacyMedicine.objects.filter(
        pk=medicine_id, is_active=True, is_approved=True).first()
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    PharmacyMedicine.objects.filter(pk=medicine.id).update(views_count=medicine.views_count + 1)
    return Response(medicine_json(medicine, for_farmer=True))


# ── Prescription upload ────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsFarmerUser])
def prescription_upload(request):
    file = request.FILES.get('image') or request.FILES.get('file')
    if not file:
        return Response({'detail': 'A prescription image is required.'}, status=400)
    if not str(file.content_type).startswith('image/'):
        return Response({'detail': 'Only JPG, PNG or WebP images are supported.'}, status=400)
    if file.size > MAX_IMAGE_BYTES:
        return Response({'detail': 'Image must be 5 MB or smaller.'}, status=400)
    ext = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else 'jpg'
    if ext not in ALLOWED_IMAGE_EXT:
        return Response({'detail': 'Only JPG, PNG or WebP images are supported.'}, status=400)
    stamp = timezone.now().strftime('%Y%m%d%H%M%S')
    path = default_storage.save(
        f'prescriptions/{request.user.id}/{stamp}_{uuid.uuid4().hex[:8]}.{ext}',
        ContentFile(file.read()))
    return Response({'image_url': request.build_absolute_uri(default_storage.url(path))}, status=201)


# ── Orders ─────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsFarmerUser])
def orders(request):
    if request.method == 'GET':
        qs = AdminPanelRecord.objects.filter(
            module='pharmacy-orders', payload__farmer_id=str(request.user.id),
        ).order_by('-created_at')
        return Response({'results': [_farmer_order_json(r) for r in qs]})

    pharmacy_id = str(request.data.get('pharmacy_id') or request.data.get('pharmacy_user_id') or '')
    try:
        pharmacy_user = User.objects.get(pk=pharmacy_id, roles__name='pharmacy')
    except (User.DoesNotExist, ValueError):
        return Response({'detail': 'Pharmacy not found.'}, status=404)

    cart = request.data.get('items') or []
    delivery_method = request.data.get('delivery_method', 'delivery')
    if delivery_method not in ('pickup', 'delivery'):
        return Response({'detail': 'delivery_method must be "pickup" or "delivery".'}, status=400)
    payment_method = request.data.get('payment_method', 'cod')
    if payment_method not in ('cod', 'bkash', 'nagad', 'bank'):
        return Response({'detail': 'Unsupported payment method.'}, status=400)
    prescription_image = request.data.get('prescription_image') or None
    delivery_address = (request.data.get('delivery_address') or request.user.present_address or '').strip()
    if delivery_method == 'delivery' and not delivery_address:
        return Response({'detail': 'A delivery address is required.'}, status=400)

    with transaction.atomic():
        items, medicines, error = order_items_from_cart(pharmacy_user, cart, lock=True)
        if error:
            return Response({'detail': error}, status=409)

        needs_prescription = any(m.prescription_required for m in medicines.values())
        if needs_prescription and not prescription_image:
            missing = [m.name for m in medicines.values() if m.prescription_required]
            return Response({
                'detail': f'A prescription photo is required for: {", ".join(missing)}. '
                          'Upload it before placing the order.',
                'code': 'prescription_required',
            }, status=400)

        subtotal = sum(i['unit_price'] * i['quantity'] for i in items)
        delivery_fee = 0.0
        if delivery_method == 'delivery':
            try:
                distance = float(request.data['distance_km']) if request.data.get('distance_km') else None
            except (TypeError, ValueError):
                distance = None
            delivery_fee = delivery_fee_for(distance) if distance is not None else 60.0
        total = round(subtotal + delivery_fee, 2)

        for medicine in medicines.values():
            qty = next(i['quantity'] for i in items if i['medicine_id'] == str(medicine.id))
            medicine.stock_quantity -= qty
            medicine.orders_count += 1
            medicine.updated_at = timezone.now()
            medicine.save(update_fields=['stock_quantity', 'orders_count', 'updated_at'])

        order_id = f'ORD-{uuid.uuid4().hex[:10].upper()}'
        farmer_profile = request.user.profile_data if isinstance(request.user.profile_data, dict) else {}
        payload = {
            'id': order_id,
            'order_number': f'#PH-{order_id[-6:]}',
            'owner_id': str(pharmacy_user.id),
            'farmer_id': str(request.user.id),
            'farmer_name': request.user.full_name or request.user.email,
            'farmer_phone': request.user.phone or '',
            'farm_name': farmer_profile.get('farm_name', 'Poultry Farm'),
            'delivery_address': delivery_address,
            'delivery_method': delivery_method,
            'payment_method': payment_method,
            'payment_status': 'pending',
            'delivery_fee': delivery_fee,
            'subtotal': round(subtotal, 2),
            'total_amount': total,
            'prescription_image': prescription_image,
            'requires_prescription_review': needs_prescription,
            'items': items,
            'status': 'pending',
            'created_at': timezone.now().isoformat(),
            'delivered_at': None,
            'notes': str(request.data.get('notes', '')),
        }
        record = AdminPanelRecord.objects.create(
            module='pharmacy-orders', record_id=order_key(pharmacy_user.id, order_id),
            payload=payload)
        notify(pharmacy_user, 'New pharmacy order',
               f'{payload["farmer_name"]} placed order {payload["order_number"]} '
               f'({len(items)} item(s), ৳{total:.0f}).',
               reference_type='pharmacy_order', notification_type='alert')
    return Response(_farmer_order_json(record), status=201)


@api_view(['GET'])
@permission_classes([IsFarmerUser])
def order_detail(request, order_id):
    record = _farmer_record(request, order_id)
    if record is None:
        return Response({'detail': 'Order not found.'}, status=404)
    return Response(_farmer_order_json(record, detail=True))


@api_view(['POST'])
@permission_classes([IsFarmerUser])
def order_cancel(request, order_id):
    with transaction.atomic():
        record = _farmer_record(request, order_id, lock=True)
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        if payload.get('status') != 'pending':
            return Response({'detail': 'Only orders that the pharmacy has not confirmed yet can be cancelled.'}, status=409)
        for item in payload.get('items', []):
            medicine = PharmacyMedicine.objects.filter(
                pk=item.get('medicine_id') or item.get('product_id')).select_for_update().first()
            if medicine is not None:
                medicine.stock_quantity += int(item.get('quantity', 0))
                medicine.updated_at = timezone.now()
                medicine.save(update_fields=['stock_quantity', 'updated_at'])
        payload['status'] = 'cancelled'
        payload['cancel_reason'] = str(request.data.get('reason', 'Cancelled by farmer.'))
        history = list(payload.get('status_history', []))
        history.append({'from': 'pending', 'to': 'cancelled', 'message': payload['cancel_reason'],
                        'changed_at': timezone.now().isoformat(),
                        'changed_by': request.user.full_name or request.user.email})
        payload['status_history'] = history
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
    try:
        notify(User.objects.get(pk=payload['owner_id']), 'Order cancelled by farmer',
               f'{payload.get("order_number", "An order")} was cancelled before confirmation.',
               reference_type='pharmacy_order', notification_type='alert')
    except (User.DoesNotExist, KeyError, ValueError):
        pass
    return Response(_farmer_order_json(record, detail=True))


@api_view(['POST'])
@permission_classes([IsFarmerUser])
def order_pay(request, order_id):
    """Digital payment confirmation (industry decision §E.5 — pay after the
    pharmacy confirms). COD stays 'pending' until delivery."""
    record = _farmer_record(request, order_id, lock=False)
    if record is None:
        return Response({'detail': 'Order not found.'}, status=404)
    payload = dict(record.payload)
    if payload.get('status') not in ('processing', 'shipped'):
        return Response({'detail': 'Payment opens once the pharmacy confirms your order.'}, status=409)
    if payload.get('payment_status') == 'paid':
        return Response({'detail': 'This order is already paid.'}, status=409)
    method = request.data.get('payment_method', payload.get('payment_method', 'cod'))
    if method == 'cod':
        return Response({'detail': 'Cash on delivery is collected by the rider — no action needed now.'}, status=400)
    payload['payment_method'] = method
    payload['payment_status'] = 'paid'
    payload['paid_at'] = timezone.now().isoformat()
    record.payload = payload
    record.save(update_fields=['payload', 'updated_at'])
    try:
        notify(User.objects.get(pk=payload['owner_id']), 'Payment received',
               f'{payload.get("order_number", "An order")} was paid via {method}.',
               reference_type='pharmacy_order')
    except (User.DoesNotExist, KeyError, ValueError):
        pass
    return Response(_farmer_order_json(record, detail=True))


# ── helpers ────────────────────────────────────────────────────────────────

def _farmer_record(request, order_id, *, lock=False):
    qs = AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__id=order_id,
        payload__farmer_id=str(request.user.id))
    return qs.select_for_update().first() if lock else qs.first()


def _farmer_order_json(record, *, detail=False):
    payload = record.payload or {}
    pharmacy_user = User.objects.filter(pk=payload.get('owner_id')).first()
    data = order_json(record, detail=detail)
    data['pharmacy'] = pharmacy_public_profile(pharmacy_user) if pharmacy_user else None
    # Timeline the farmer app renders as a stepper.
    order_flow = ['pending', 'preparing', 'ready_for_delivery', 'out_for_delivery', 'delivered']
    delivery = data.get('delivery')
    app_status = data['status']
    if delivery and delivery['delivery_status'] in ('accepted', 'picked_up', 'on_the_way'):
        app_status = 'out_for_delivery'
        data['status'] = 'out_for_delivery'
    data['timeline'] = [{
        'step': step,
        'done': order_flow.index(step) <= (order_flow.index(app_status) if app_status in order_flow else -1),
    } for step in order_flow]
    data['can_cancel'] = payload.get('status') == 'pending'
    return data
