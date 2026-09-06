"""Pharmacy-facing catalogue, inventory, order and supplier endpoints.

Catalogue / inventory / suppliers use the real relational tables
(pharmacy_catalogue_medicines, pharmacy_suppliers, pharmacy_expiry_alerts).
Orders stay on the tested pharmacy-orders / delivery-queue JSON bridge, but now
derive cold-chain and prescription flags from the real medicine rows.
"""

import csv
import io
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from notifications.models import Notification
from users.models import User

from pharmacy.models import (
    LOW_STOCK_THRESHOLD, PharmacyExpiryAlert, PharmacyMedicine, PharmacySupplier,
)
from pharmacy.services import (
    BRIDGE_TO_APP_STATUS, apply_auto_approval, clean_medicine_payload,
    delivery_fee_for, expiry_alert_json, generate_otp, inventory_summary,
    log_action, medicine_json, notify, order_key, regenerate_expiry_alerts,
)
from pharmacy.views import IsPharmacyUser, _profile

MAX_IMAGE_BYTES = 5 * 1024 * 1024
ALLOWED_IMAGE_EXT = {'jpg', 'jpeg', 'png', 'webp'}


# ── Medicine management ────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsPharmacyUser])
def medicines(request):
    if request.method == 'GET':
        qs = PharmacyMedicine.objects.filter(pharmacy_user=request.user)
        category = request.query_params.get('category')
        if category:
            qs = qs.filter(category=category)
        prescription = request.query_params.get('prescription_required')
        if prescription in ('true', 'false'):
            qs = qs.filter(prescription_required=(prescription == 'true'))
        stock = request.query_params.get('stock_status')
        if stock == 'low':
            qs = qs.filter(stock_quantity__lt=LOW_STOCK_THRESHOLD, stock_quantity__gt=0)
        elif stock == 'out':
            qs = qs.filter(stock_quantity__lte=0)
        search = (request.query_params.get('search') or '').strip()
        if search:
            qs = qs.filter(name__icontains=search) | qs.filter(generic_name__icontains=search)
        return Response({'results': [medicine_json(m) for m in qs]})

    cleaned, error = clean_medicine_payload(request.data, partial=False)
    if error:
        return Response({'detail': error}, status=400)
    now = timezone.now()
    medicine = PharmacyMedicine(pharmacy_user=request.user, created_at=now, updated_at=now,
                                **cleaned)
    apply_auto_approval(medicine)
    medicine.save()
    regenerate_expiry_alerts(request.user)
    log_action(request.user, 'Add medicine', medicine.id, medicine_json(medicine))
    if not medicine.is_approved:
        _notify_pharmacy_admins(
            'Medicine pending approval',
            f'{_profile(request.user)["name"]} added "{medicine.name}" (prescription) — needs review.',
        )
    return Response(medicine_json(medicine), status=201)


@api_view(['GET', 'PUT', 'PATCH', 'DELETE'])
@permission_classes([IsPharmacyUser])
def medicine_detail(request, medicine_id):
    medicine = _get_medicine(request, medicine_id)
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)

    if request.method == 'GET':
        return Response(medicine_json(medicine))

    if request.method == 'DELETE':
        medicine.is_active = False
        medicine.updated_at = timezone.now()
        medicine.save(update_fields=['is_active', 'updated_at'])
        PharmacyExpiryAlert.objects.filter(medicine=medicine).delete()
        log_action(request.user, 'Retire medicine', medicine.id)
        return Response(status=204)

    partial = request.method == 'PATCH'
    cleaned, error = clean_medicine_payload(request.data, partial=partial)
    if error:
        return Response({'detail': error}, status=400)
    prescription_changed = 'prescription_required' in cleaned and \
        cleaned['prescription_required'] != medicine.prescription_required
    for field, value in cleaned.items():
        setattr(medicine, field, value)
    if prescription_changed:
        apply_auto_approval(medicine)
    medicine.updated_at = timezone.now()
    medicine.save()
    regenerate_expiry_alerts(request.user)
    log_action(request.user, 'Update medicine', medicine.id, cleaned)
    return Response(medicine_json(medicine))


@api_view(['POST'])
@permission_classes([IsPharmacyUser])
def medicine_upload_image(request, medicine_id):
    medicine = _get_medicine(request, medicine_id)
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    url, error = _store_image(request, f'pharmacy_medicines/{request.user.id}/{medicine.id}')
    if error:
        return Response({'detail': error}, status=400)
    images = list(medicine.images or [])
    if len(images) >= 5:
        return Response({'detail': 'A medicine can have at most 5 images.'}, status=400)
    images.append(url)
    medicine.images = images
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['images', 'updated_at'])
    return Response({'image_url': url, 'images': images}, status=201)


@api_view(['PATCH'])
@permission_classes([IsPharmacyUser])
def medicine_stock(request, medicine_id):
    medicine = _get_medicine(request, medicine_id)
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    if 'stock_quantity' in request.data:
        try:
            new_stock = int(request.data['stock_quantity'])
        except (TypeError, ValueError):
            return Response({'detail': 'stock_quantity must be a whole number.'}, status=400)
    elif 'delta' in request.data:
        try:
            new_stock = medicine.stock_quantity + int(request.data['delta'])
        except (TypeError, ValueError):
            return Response({'detail': 'delta must be a whole number.'}, status=400)
    else:
        return Response({'detail': 'Provide stock_quantity or delta.'}, status=400)
    if new_stock < 0:
        return Response({'detail': 'Stock quantity cannot be negative.'}, status=400)
    medicine.stock_quantity = new_stock
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['stock_quantity', 'updated_at'])
    log_action(request.user, 'Update stock', medicine.id, {'stock_quantity': new_stock})
    return Response(medicine_json(medicine))


@api_view(['PATCH'])
@permission_classes([IsPharmacyUser])
def medicine_price(request, medicine_id):
    medicine = _get_medicine(request, medicine_id)
    if medicine is None:
        return Response({'detail': 'Medicine not found.'}, status=404)
    try:
        price = round(float(request.data.get('price')), 2)
    except (TypeError, ValueError):
        return Response({'detail': 'price must be a number.'}, status=400)
    if price <= 0:
        return Response({'detail': 'Price must be greater than 0.'}, status=400)
    medicine.price = price
    medicine.updated_at = timezone.now()
    medicine.save(update_fields=['price', 'updated_at'])
    log_action(request.user, 'Update price', medicine.id, {'price': price})
    return Response(medicine_json(medicine))


BULK_COLUMNS = ['name', 'generic_name', 'manufacturer', 'category', 'prescription_required',
                'price', 'stock_quantity', 'unit', 'pack_size', 'expiry_date',
                'batch_number', 'cold_chain_required', 'description']


@api_view(['GET', 'POST'])
@permission_classes([IsPharmacyUser])
def medicines_bulk_upload(request):
    if request.method == 'GET':
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(BULK_COLUMNS)
        writer.writerow(['Oxytetracycline 20%', 'Oxytetracycline', 'Renata', 'antibiotic',
                         'true', '420', '24', 'bottle', '100ml', '2027-01-31', 'B-1042',
                         'false', 'Broad-spectrum antibiotic'])
        from django.http import HttpResponse
        response = HttpResponse(buffer.getvalue(), content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="medicine-template.csv"'
        return response

    file = request.FILES.get('file')
    if not file:
        return Response({'detail': 'A CSV file is required.'}, status=400)
    try:
        rows = list(csv.DictReader(io.StringIO(file.read().decode('utf-8-sig'))))
    except (UnicodeDecodeError, csv.Error):
        return Response({'detail': 'Could not read the CSV file.'}, status=400)
    if not rows:
        return Response({'detail': 'The CSV file has no data rows.'}, status=400)

    created, errors = [], []
    now = timezone.now()
    with transaction.atomic():
        for index, row in enumerate(rows, start=2):
            cleaned, error = clean_medicine_payload(row, partial=False)
            if error:
                errors.append({'row': index, 'error': error})
                continue
            medicine = PharmacyMedicine(pharmacy_user=request.user, created_at=now,
                                        updated_at=now, **cleaned)
            apply_auto_approval(medicine)
            medicine.save()
            created.append(str(medicine.id))
    regenerate_expiry_alerts(request.user)
    log_action(request.user, 'Bulk medicine upload', values={'created': len(created), 'errors': len(errors)})
    return Response({'created': len(created), 'created_ids': created, 'errors': errors},
                    status=201 if created else 400)


# ── Inventory & expiry ─────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def inventory_summary_view(request):
    return Response(inventory_summary(request.user))


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def inventory_expiring_soon(request):
    regenerate_expiry_alerts(request.user)
    qs = PharmacyExpiryAlert.objects.filter(pharmacy_user=request.user).select_related('medicine')
    level = request.query_params.get('alert_level')
    if level in ('critical', 'warning', 'info'):
        qs = qs.filter(alert_level=level)
    grouped = {'critical': [], 'warning': [], 'info': []}
    for alert in qs:
        grouped[alert.alert_level].append(expiry_alert_json(alert))
    return Response({'results': [expiry_alert_json(a) for a in qs], 'grouped': grouped})


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def inventory_low_stock(request):
    qs = PharmacyMedicine.objects.filter(
        pharmacy_user=request.user, is_active=True,
        stock_quantity__lt=LOW_STOCK_THRESHOLD,
    ).order_by('stock_quantity')
    return Response({'results': [medicine_json(m) for m in qs],
                     'threshold': LOW_STOCK_THRESHOLD})


@api_view(['POST'])
@permission_classes([IsPharmacyUser])
def inventory_alerts_acknowledge(request):
    alert_ids = request.data.get('alert_ids')
    qs = PharmacyExpiryAlert.objects.filter(pharmacy_user=request.user)
    if alert_ids:
        qs = qs.filter(id__in=alert_ids)
    updated = qs.update(is_acknowledged=True)
    log_action(request.user, 'Acknowledge expiry alerts', values={'count': updated})
    return Response({'acknowledged': updated})


# ── Suppliers ──────────────────────────────────────────────────────────────

def _supplier_json(supplier):
    return {
        'supplier_id': str(supplier.id),
        'id': str(supplier.id),
        'supplier_name': supplier.supplier_name,
        'contact_person': supplier.contact_person,
        'phone': supplier.phone,
        'email': supplier.email,
        'address': supplier.address,
        'products_supplied': supplier.products_supplied,
        'payment_terms': supplier.payment_terms or '',
        'is_active': supplier.is_active,
        'created_at': supplier.created_at.isoformat() if supplier.created_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsPharmacyUser])
def suppliers(request):
    if request.method == 'GET':
        qs = PharmacySupplier.objects.filter(pharmacy_user=request.user)
        if request.query_params.get('active') == 'true':
            qs = qs.filter(is_active=True)
        search = (request.query_params.get('search') or '').strip()
        if search:
            qs = qs.filter(supplier_name__icontains=search) | \
                qs.filter(products_supplied__icontains=search)
        return Response({'results': [_supplier_json(s) for s in qs]})

    name = str(request.data.get('supplier_name', '')).strip()
    if not name:
        return Response({'detail': 'Supplier name is required.'}, status=400)
    now = timezone.now()
    supplier = PharmacySupplier.objects.create(
        pharmacy_user=request.user, supplier_name=name,
        contact_person=str(request.data.get('contact_person', '')).strip(),
        phone=str(request.data.get('phone', '')).strip(),
        email=str(request.data.get('email', '')).strip(),
        address=str(request.data.get('address', '')).strip(),
        products_supplied=str(request.data.get('products_supplied', '')).strip(),
        payment_terms=str(request.data.get('payment_terms') or '').strip() or None,
        created_at=now, updated_at=now,
    )
    log_action(request.user, 'Add supplier', supplier.id, _supplier_json(supplier))
    return Response(_supplier_json(supplier), status=201)


@api_view(['GET', 'PUT', 'PATCH', 'DELETE'])
@permission_classes([IsPharmacyUser])
def supplier_detail(request, supplier_id):
    supplier = PharmacySupplier.objects.filter(pk=supplier_id, pharmacy_user=request.user).first()
    if supplier is None:
        return Response({'detail': 'Supplier not found.'}, status=404)
    if request.method == 'GET':
        return Response(_supplier_json(supplier))
    if request.method == 'DELETE':
        supplier.is_active = False
        supplier.updated_at = timezone.now()
        supplier.save(update_fields=['is_active', 'updated_at'])
        log_action(request.user, 'Deactivate supplier', supplier.id)
        return Response(status=204)
    for api_field, model_field in [
        ('supplier_name', 'supplier_name'), ('contact_person', 'contact_person'),
        ('phone', 'phone'), ('email', 'email'), ('address', 'address'),
        ('products_supplied', 'products_supplied'),
    ]:
        if api_field in request.data:
            setattr(supplier, model_field, str(request.data[api_field] or '').strip())
    if 'payment_terms' in request.data:
        supplier.payment_terms = str(request.data['payment_terms'] or '').strip() or None
    if 'is_active' in request.data:
        supplier.is_active = bool(request.data['is_active'])
    supplier.updated_at = timezone.now()
    supplier.save()
    log_action(request.user, 'Update supplier', supplier.id)
    return Response(_supplier_json(supplier))


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def supplier_orders(request, supplier_id):
    supplier = PharmacySupplier.objects.filter(pk=supplier_id, pharmacy_user=request.user).first()
    if supplier is None:
        return Response({'detail': 'Supplier not found.'}, status=404)
    # Restock/purchase-order tracking is a Pass 2 item; for now we surface the
    # catalogue lines attributed to this supplier's product list.
    names = [n.strip().lower() for n in supplier.products_supplied.split(',') if n.strip()]
    matched = []
    if names:
        qs = PharmacyMedicine.objects.filter(pharmacy_user=request.user, is_active=True)
        for medicine in qs:
            if any(token in medicine.name.lower() or token in (medicine.generic_name or '').lower()
                   for token in names):
                matched.append(medicine_json(medicine))
    return Response({'supplier': _supplier_json(supplier), 'catalogue_matches': matched,
                     'purchase_orders': []})


# ── Orders (JSON bridge) ───────────────────────────────────────────────────

def _order_records(pharmacy_user):
    return AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__owner_id=str(pharmacy_user.id))


def _rider_for_order(record_pk):
    order = DeliveryOrder.objects.select_related('delivery_person__user').filter(
        order_reference_id=record_pk,
    ).exclude(status__in=['rejected', 'cancelled']).order_by('-assigned_at').first()
    if order is None:
        return None
    rider = order.delivery_person
    return {
        'delivery_order_id': str(order.id),
        'delivery_status': order.status,
        'rider_name': rider.user.full_name or rider.user.email,
        'rider_phone': rider.user.phone or '',
        'rider_rating': float(rider.rating or 0),
        'otp_code': order.otp_code,
        'is_cold_chain': order.is_cold_chain,
        'is_prescription_required': order.is_prescription_required,
        'assigned_at': order.assigned_at.isoformat() if order.assigned_at else None,
    }


def order_json(record, *, detail=False):
    payload = record.payload or {}
    bridge_status = payload.get('status', 'pending')
    items = payload.get('items', [])
    subtotal = sum(float(i.get('unit_price', 0)) * int(i.get('quantity', 0)) for i in items)
    data = {
        'order_id': payload.get('id'),
        'id': payload.get('id'),
        'record_pk': str(record.id),
        'order_number': payload.get('order_number', ''),
        'farmer_id': payload.get('farmer_id', ''),
        'farmer_name': payload.get('farmer_name', ''),
        'farmer_phone': payload.get('farmer_phone', ''),
        'farm_name': payload.get('farm_name', ''),
        'status': BRIDGE_TO_APP_STATUS.get(bridge_status, bridge_status),
        'bridge_status': bridge_status,
        'payment_status': payload.get('payment_status', 'pending'),
        'payment_method': payload.get('payment_method', 'cod'),
        'delivery_method': payload.get('delivery_method', 'delivery'),
        'delivery_fee': float(payload.get('delivery_fee', 0) or 0),
        'delivery_address': payload.get('delivery_address', ''),
        'prescription_image': payload.get('prescription_image'),
        'notes': payload.get('notes', ''),
        'items_count': len(items),
        'subtotal': round(subtotal, 2),
        'total_amount': float(payload.get('total_amount', subtotal + float(payload.get('delivery_fee', 0) or 0))),
        'created_at': payload.get('created_at'),
        'delivered_at': payload.get('delivered_at'),
        'requires_prescription': any(i.get('prescription_required') for i in items),
        'requires_cold_chain': any(i.get('cold_chain_required') for i in items),
    }
    if detail:
        data['items'] = items
        data['status_history'] = payload.get('status_history', [])
    data['delivery'] = _rider_for_order(record.id)
    return data


def _get_order(request, order_id):
    return AdminPanelRecord.objects.filter(
        module='pharmacy-orders', record_id=order_key(request.user.id, order_id),
        payload__owner_id=str(request.user.id),
    ).first()


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def orders_list(request):
    qs = _order_records(request.user).order_by('-created_at')
    status_filter = request.query_params.get('status')
    rows = [order_json(r) for r in qs]
    if status_filter:
        wanted = {s.strip() for s in status_filter.split(',')}
        rows = [r for r in rows if r['status'] in wanted or r['bridge_status'] in wanted]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def order_detail(request, order_id):
    record = _get_order(request, order_id)
    if record is None:
        return Response({'detail': 'Order not found.'}, status=404)
    return Response(order_json(record, detail=True))


def _append_history(payload, from_status, to_status, message, actor):
    history = list(payload.get('status_history', []))
    history.append({
        'from': from_status, 'to': to_status, 'message': message,
        'changed_at': timezone.now().isoformat(),
        'changed_by': actor.full_name or actor.email,
    })
    payload['status_history'] = history


def _restock_order(payload):
    for item in payload.get('items', []):
        mid = item.get('medicine_id') or item.get('product_id')
        medicine = PharmacyMedicine.objects.filter(pk=mid).select_for_update().first()
        if medicine is not None:
            medicine.stock_quantity += int(item.get('quantity', 0))
            medicine.updated_at = timezone.now()
            medicine.save(update_fields=['stock_quantity', 'updated_at'])


_APP_TO_BRIDGE = {
    'confirmed': 'processing', 'preparing': 'processing',
    'ready_for_pickup': 'shipped', 'ready_for_delivery': 'shipped',
    'delivered': 'delivered', 'cancelled': 'cancelled',
}
_BRIDGE_TRANSITIONS = {
    'pending': {'processing', 'cancelled'},
    'processing': {'shipped', 'cancelled'},
    'shipped': {'delivered'},
}


@api_view(['POST'])
@permission_classes([IsPharmacyUser])
def order_confirm(request, order_id):
    return _do_confirm(request, order_id)


@api_view(['POST'])
@permission_classes([IsPharmacyUser])
def order_cancel(request, order_id):
    return _do_cancel(request, order_id)


@api_view(['POST'])
@permission_classes([IsPharmacyUser])
def order_ready_for_delivery(request, order_id):
    return _do_ready(request, order_id)


@api_view(['PATCH'])
@permission_classes([IsPharmacyUser])
def order_status(request, order_id):
    target = str(request.data.get('status', '')).strip()
    bridge_target = _APP_TO_BRIDGE.get(target, target)
    if bridge_target not in {'processing', 'shipped', 'delivered', 'cancelled'}:
        return Response({'detail': f'Unsupported status "{target}".'}, status=400)
    if bridge_target == 'shipped':
        return _do_ready(request, order_id)
    if bridge_target == 'cancelled':
        return _do_cancel(request, order_id)

    with transaction.atomic():
        record = _lock_order(request, order_id)
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        current = payload.get('status', 'pending')
        if bridge_target not in _BRIDGE_TRANSITIONS.get(current, set()):
            return Response({'detail': f'Cannot move an order from {current} to {bridge_target}.'}, status=409)
        message = str(request.data.get('message') or f'Status set to {target}.')
        _append_history(payload, current, bridge_target, message, request.user)
        payload['status'] = bridge_target
        if bridge_target == 'delivered':
            if request.data.get('delivery_confirmed') is not True:
                return Response({'detail': 'Delivery confirmation is required.'}, status=400)
            payload['delivered_at'] = timezone.now().isoformat()
            AdminPanelRecord.objects.filter(module='delivery-queue', record_id=f'DQ-{order_id}').delete()
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
    _notify_farmer(payload, f'Order {BRIDGE_TO_APP_STATUS.get(bridge_target, bridge_target).replace("_", " ")}',
                   f'{payload.get("order_number", "Your order")}: {message}')
    log_action(request.user, 'Update order status', record.id, {'status': bridge_target})
    return Response(order_json(record, detail=True))


def _do_confirm(request, order_id):
    with transaction.atomic():
        record = _lock_order(request, order_id)
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        if payload.get('status') != 'pending':
            return Response({'detail': f'Only pending orders can be confirmed (currently {payload.get("status")}).'}, status=409)
        if payload.get('requires_prescription_review') and not payload.get('prescription_image'):
            return Response({'detail': 'This order needs a prescription image before it can be confirmed.'}, status=400)
        _append_history(payload, 'pending', 'processing',
                        str(request.data.get('message') or 'Order confirmed by pharmacy.'), request.user)
        payload['status'] = 'processing'
        payload['confirmed_at'] = timezone.now().isoformat()
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
    _notify_farmer(payload, 'Order confirmed',
                   f'{payload.get("order_number", "Your order")} was confirmed. '
                   + ('Please complete payment.' if payload.get('payment_method') != 'cod'
                      else 'Payment will be collected on delivery.'))
    log_action(request.user, 'Confirm order', record.id, {'order': order_id})
    return Response(order_json(record, detail=True))


def _do_cancel(request, order_id):
    reason = str(request.data.get('reason', '')).strip()
    if not reason:
        return Response({'detail': 'A cancellation reason is required.'}, status=400)
    with transaction.atomic():
        record = _lock_order(request, order_id)
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        if payload.get('status') in ('delivered', 'cancelled', 'refunded'):
            return Response({'detail': f'A {payload.get("status")} order cannot be cancelled.'}, status=409)
        if DeliveryOrder.objects.filter(order_reference_id=record.id).exclude(
                status__in=['rejected', 'cancelled']).exists():
            return Response({'detail': 'A rider is already handling this delivery; contact the delivery desk.'}, status=409)
        _restock_order(payload)
        AdminPanelRecord.objects.filter(module='delivery-queue', record_id=f'DQ-{order_id}').delete()
        _append_history(payload, payload.get('status'), 'cancelled', reason, request.user)
        payload['status'] = 'cancelled'
        payload['cancel_reason'] = reason
        if payload.get('payment_status') == 'paid':
            payload['payment_status'] = 'refunded'
            payload['status'] = 'refunded'
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])
    _notify_farmer(payload, 'Order cancelled',
                   f'{payload.get("order_number", "Your order")} was cancelled: {reason}')
    log_action(request.user, 'Cancel order', record.id, {'reason': reason})
    return Response(order_json(record, detail=True))


def _do_ready(request, order_id):
    """Auto-create the delivery-queue entry (industry decision §E.6). This is the
    pharmacy -> delivery hand-off; a delivery admin then assigns a rider."""
    with transaction.atomic():
        record = _lock_order(request, order_id)
        if record is None:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        current = payload.get('status', 'pending')
        if current not in ('processing',):
            return Response({'detail': f'Confirm and prepare the order first (currently {current}).'}, status=409)
        if payload.get('delivery_method') == 'pickup':
            _append_history(payload, current, 'shipped', 'Ready for pharmacy pickup.', request.user)
            payload['status'] = 'shipped'
            payload['ready_at'] = timezone.now().isoformat()
            record.payload = payload
            record.save(update_fields=['payload', 'updated_at'])
            _notify_farmer(payload, 'Order ready for pickup',
                           f'{payload.get("order_number", "Your order")} is ready to collect from the pharmacy.')
            return Response(order_json(record, detail=True))

        items = payload.get('items', [])
        cold_chain = any(i.get('cold_chain_required') for i in items)
        prescription = bool(payload.get('prescription_image')) or any(
            i.get('prescription_required') for i in items)
        otp = payload.get('delivery_otp') or generate_otp()
        payload['delivery_otp'] = otp
        _append_history(payload, current, 'shipped', 'Ready for delivery — queued for a rider.', request.user)
        payload['status'] = 'shipped'
        payload['ready_at'] = timezone.now().isoformat()
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])

        profile = _profile(request.user)
        AdminPanelRecord.objects.update_or_create(
            module='delivery-queue', record_id=f'DQ-{order_id}',
            defaults={'payload': {
                'id': f'DQ-{order_id}',
                'pharmacy_order_record_id': str(record.id),
                'pharmacy_order_id': order_id,
                'order_type': 'pharmacy',
                'customer': payload.get('farmer_name', ''),
                'customer_phone': payload.get('farmer_phone', ''),
                'pickup_address': profile['location'],
                'delivery_address': payload.get('delivery_address', ''),
                'pharmacy': profile['name'],
                'pharmacy_id': str(request.user.id),
                'pharmacy_contact': profile['phone'],
                'items': items,
                'package_description': f'Medicine order ({len(items)} item(s))',
                'special_instructions': payload.get('notes', ''),
                'otp_code': otp,
                'queued_at': timezone.now().isoformat(),
                'is_pharmacy_delivery': True,
                'is_cold_chain': cold_chain,
                'is_prescription_required': prescription,
                'prescription_required': prescription,
                'cold_chain_required': cold_chain,
            }},
        )
    _notify_farmer(payload, 'Order out for delivery',
                   f'{payload.get("order_number", "Your medicine order")} from {_profile(request.user)["name"]} '
                   'is ready and waiting for a delivery rider.')
    _notify_delivery_admins('New pharmacy delivery',
                            f'{_profile(request.user)["name"]} queued order {order_id} for delivery'
                            + (' — cold chain required.' if cold_chain else '.'))
    log_action(request.user, 'Ready for delivery', record.id, {'order': order_id, 'cold_chain': cold_chain})
    return Response(order_json(record, detail=True))


# ── Analytics ──────────────────────────────────────────────────────────────

def _delivered_orders(pharmacy_user):
    return [r.payload for r in _order_records(pharmacy_user)
            if r.payload.get('status') == 'delivered']


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def analytics_sales(request):
    period = request.query_params.get('period', 'daily')
    buckets = {}
    for payload in _delivered_orders(request.user):
        stamp = payload.get('delivered_at') or payload.get('created_at') or ''
        key = stamp[:10] if period == 'daily' else stamp[:7]
        total = float(payload.get('total_amount', 0) or 0)
        entry = buckets.setdefault(key, {'period': key, 'orders': 0, 'revenue': 0.0})
        entry['orders'] += 1
        entry['revenue'] = round(entry['revenue'] + total, 2)
    return Response({'period': period, 'results': sorted(buckets.values(), key=lambda x: x['period'])})


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def analytics_top_products(request):
    qs = PharmacyMedicine.objects.filter(pharmacy_user=request.user).order_by(
        '-orders_count', '-views_count')[:10]
    return Response({'results': [{
        'medicine_id': str(m.id), 'name': m.name, 'category': m.category,
        'orders_count': m.orders_count, 'views_count': m.views_count,
        'stock_quantity': m.stock_quantity, 'price': float(m.price),
    } for m in qs]})


@api_view(['GET'])
@permission_classes([IsPharmacyUser])
def analytics_revenue(request):
    by_category, by_payment = {}, {}
    total = 0.0
    medicine_cat = {str(m.id): m.category for m in
                    PharmacyMedicine.objects.filter(pharmacy_user=request.user)}
    for payload in _delivered_orders(request.user):
        total += float(payload.get('total_amount', 0) or 0)
        method = payload.get('payment_method', 'cod')
        by_payment[method] = round(by_payment.get(method, 0) + float(payload.get('total_amount', 0) or 0), 2)
        for item in payload.get('items', []):
            cat = medicine_cat.get(str(item.get('medicine_id')), item.get('category', 'other'))
            line = float(item.get('unit_price', 0)) * int(item.get('quantity', 0))
            by_category[cat] = round(by_category.get(cat, 0) + line, 2)
    return Response({
        'total_revenue': round(total, 2),
        'by_category': [{'category': k, 'revenue': v} for k, v in sorted(by_category.items())],
        'by_payment_method': [{'method': k, 'revenue': v} for k, v in sorted(by_payment.items())],
    })


# ── helpers ────────────────────────────────────────────────────────────────

def _get_medicine(request, medicine_id):
    return PharmacyMedicine.objects.filter(pk=medicine_id, pharmacy_user=request.user).first()


def _lock_order(request, order_id):
    return AdminPanelRecord.objects.select_for_update().filter(
        module='pharmacy-orders', record_id=order_key(request.user.id, order_id),
        payload__owner_id=str(request.user.id),
    ).first()


def _store_image(request, prefix):
    file = request.FILES.get('image') or request.FILES.get('file')
    if not file:
        return None, 'An image file is required.'
    if not str(file.content_type).startswith('image/'):
        return None, 'Only JPG, PNG or WebP images are supported.'
    if file.size > MAX_IMAGE_BYTES:
        return None, 'Image must be 5 MB or smaller.'
    ext = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else 'jpg'
    if ext not in ALLOWED_IMAGE_EXT:
        return None, 'Only JPG, PNG or WebP images are supported.'
    stamp = timezone.now().strftime('%Y%m%d%H%M%S')
    path = default_storage.save(f'{prefix}/{stamp}_{uuid.uuid4().hex[:8]}.{ext}',
                                ContentFile(file.read()))
    return request.build_absolute_uri(default_storage.url(path)), None


def _notify_farmer(payload, title, body):
    farmer_id = payload.get('farmer_id')
    if not farmer_id:
        return
    try:
        notify(User.objects.get(pk=farmer_id), title, body, reference_type='pharmacy_order')
    except (User.DoesNotExist, ValueError, TypeError):
        pass


def _notify_pharmacy_admins(title, body):
    admins = User.objects.filter(
        roles__name__in=['admin_super', 'admin_operations', 'admin_pharmacy']).distinct()
    for admin in admins:
        Notification.objects.create(user=admin, title=title, body=body,
                                    notification_type='alert', reference_type='admin_pharmacy')


def _notify_delivery_admins(title, body):
    admins = User.objects.filter(
        roles__name__in=['admin_super', 'admin_operations', 'admin_delivery']).distinct()
    for admin in admins:
        Notification.objects.create(user=admin, title=title, body=body,
                                    notification_type='alert', reference_type='delivery_order')
