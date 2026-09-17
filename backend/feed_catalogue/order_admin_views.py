"""Feed Admin — order queue, order detail (with map data), and rider
assignment (Priority 8). Reuses the same delivery_orders table and rider
approval guard the pharmacy flow already uses — no parallel delivery system.
"""
from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from api.admin_rbac import IsAdminUser, can_perform_action
from audit.models import AdminPanelRecord
from delivery.models import DeliveryOrder
from delivery.services import MAX_CONCURRENT_ORDERS_PER_RIDER, capacity_error, open_order_count
from notifications.models import Notification
from profiles.models import DeliveryProfile

MODULE_ORDERS = 'feed-orders'
MODULE_DELIVERY = 'feed-delivery'


def _forbidden(module, action):
    return Response({
        'detail': f'Your admin role cannot "{action}" in the "{module}" module.',
        'code': 'forbidden_module_action',
    }, status=403)


def _order_admin_json(record):
    payload = record.payload or {}
    delivery_status = None
    can_assign = payload.get('status') in ('created', 'confirmed', 'preparing', 'ready_for_pickup')
    if payload.get('status') == 'assigned' and payload.get('delivery_order_id'):
        delivery_order = DeliveryOrder.objects.filter(pk=payload['delivery_order_id']).first()
        if delivery_order is not None:
            delivery_status = delivery_order.status
            # Mirrors order_assign()'s own reassignment guard — surfaced here
            # so the Feed Admin UI can offer "Reassign" instead of leaving the
            # order looking permanently stuck at "assigned" when a rider
            # rejects the offer or lets it expire.
            can_assign = delivery_status in ('rejected', 'failed')
    return {
        **payload,
        'record_id': str(record.id),
        'created_at_iso': record.created_at.isoformat() if record.created_at else None,
        'delivery_status': delivery_status,
        'can_assign_rider': can_assign,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def orders(request):
    if not can_perform_action(request.user, MODULE_ORDERS, 'view'):
        return _forbidden(MODULE_ORDERS, 'view')
    qs = AdminPanelRecord.objects.filter(module='feed-orders').order_by('-created_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(payload__status=status_filter)
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
    return Response({'results': [_order_admin_json(r) for r in page],
                      'total': total, 'offset': offset, 'limit': limit})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def order_detail(request, order_id):
    if not can_perform_action(request.user, MODULE_ORDERS, 'view'):
        return _forbidden(MODULE_ORDERS, 'view')
    record = AdminPanelRecord.objects.filter(module='feed-orders', payload__id=order_id).first()
    if record is None:
        return Response({'detail': 'Order not found.'}, status=404)
    return Response(_order_admin_json(record))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def available_riders(request):
    """Only admin-approved, non-suspended riders are assignable — the exact
    guard `_assign_from_queue` uses for pharmacy deliveries."""
    if not can_perform_action(request.user, MODULE_DELIVERY, 'view'):
        return _forbidden(MODULE_DELIVERY, 'view')
    riders = (DeliveryProfile.objects.select_related('user')
              .filter(approved_by_admin__isnull=False).exclude(user__account_status='suspended'))

    def _row(r):
        count = open_order_count(r)
        return {
            'id': str(r.id), 'name': r.user.full_name or r.user.email,
            'phone': r.user.phone or '', 'is_online': bool(r.is_online),
            'current_status': r.current_status or 'offline',
            'active_orders': count,
            # Surfaced so the assign-rider UI can show load ("2/3 active")
            # and let an admin pick a different rider up front, instead of
            # only finding out from a 409 after they've already chosen one.
            # The assign endpoint below still enforces the real limit either
            # way — this is a courtesy, not the guard.
            'at_capacity': count >= MAX_CONCURRENT_ORDERS_PER_RIDER,
            'max_concurrent_orders': MAX_CONCURRENT_ORDERS_PER_RIDER,
        }

    return Response({'results': [_row(r) for r in riders]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def order_assign(request, order_id):
    if not can_perform_action(request.user, MODULE_ORDERS, 'assign'):
        return _forbidden(MODULE_ORDERS, 'assign')
    rider_id = request.data.get('rider_id')
    notes = request.data.get('notes', '')
    with transaction.atomic():
        try:
            record = AdminPanelRecord.objects.select_for_update().get(
                module='feed-orders', payload__id=order_id)
        except AdminPanelRecord.DoesNotExist:
            return Response({'detail': 'Order not found.'}, status=404)
        payload = dict(record.payload)
        assignable_statuses = ('created', 'confirmed', 'preparing', 'ready_for_pickup')
        previous_order = None
        if payload.get('status') == 'assigned' and payload.get('delivery_order_id'):
            # The rider on the current assignment may have rejected it or let
            # the offer expire — `DeliveryOrder.status` moves on independently
            # of this payload's cached 'assigned' label (the same gap the
            # generic pharmacy reassign flow works around via
            # `_reassign_order`), so re-check the real delivery order instead
            # of trusting the stale label, and allow reassigning onto a fresh
            # rider when it's no longer actively in progress.
            previous_order = DeliveryOrder.objects.filter(pk=payload['delivery_order_id']).first()
            if previous_order is not None and previous_order.status in ('rejected', 'failed'):
                pass  # fall through — this is a legitimate reassignment
            elif previous_order is not None:
                return Response({'detail': f'Order is already assigned and in progress ({previous_order.status}).'}, status=409)
        elif payload.get('status') not in assignable_statuses:
            return Response({'detail': f'Order is already {payload.get("status")} and cannot be (re)assigned.'}, status=409)
        try:
            rider = DeliveryProfile.objects.select_related('user').get(pk=rider_id)
        except (DeliveryProfile.DoesNotExist, ValueError, TypeError):
            return Response({'detail': 'Rider not found.'}, status=404)
        if rider.approved_by_admin_id is None:
            return Response({'detail': 'This rider has not been approved yet.'}, status=409)
        cap_error = capacity_error(rider)
        if cap_error:
            return Response({'detail': cap_error}, status=409)
        if previous_order is not None and previous_order.status in ('rejected', 'failed'):
            previous_order.notes = f'{previous_order.notes or ""} — superseded by reassignment'.strip(' —')
            previous_order.save(update_fields=['notes'])

        order = DeliveryOrder.objects.create(
            delivery_person=rider,
            order_reference_id=record.id,
            order_type='marketplace',
            pickup_address='Feed warehouse (see order items for supplier)',
            delivery_address=payload.get('delivery_address', ''),
            delivery_lat=payload.get('latitude'), delivery_lng=payload.get('longitude'),
            status='pending',
            is_pharmacy_delivery=False,
            notes=f'Feed order {payload.get("order_number", order_id)}' + (f' — {notes}' if notes else ''),
            assigned_at=timezone.now(),
            created_at=timezone.now(),
        )
        payload['status'] = 'assigned'
        payload['delivery_order_id'] = str(order.id)
        payload['assigned_rider_id'] = str(rider.id)
        record.payload = payload
        record.save(update_fields=['payload', 'updated_at'])

        Notification.objects.create(
            user=rider.user, title='New feed delivery assignment',
            body=f'You were assigned feed order {payload.get("order_number", "")}.',
            notification_type='alert', reference_id=order.id, reference_type='delivery_order')
        try:
            from users.models import User
            farmer = User.objects.get(pk=payload.get('farmer_id'))
            Notification.objects.create(
                user=farmer, title='Rider assigned',
                body=f'A delivery rider has been assigned to {payload.get("order_number", "your order")}.',
                notification_type='system', reference_type='feed_order')
        except Exception:
            pass
    return Response(_order_admin_json(record), status=201)


@api_view(['GET'])
@permission_classes([IsAdminUser])
def analytics(request):
    if not can_perform_action(request.user, MODULE_ORDERS, 'view'):
        return _forbidden(MODULE_ORDERS, 'view')
    from .models import FeedCompany, FeedProduct
    records = list(AdminPanelRecord.objects.filter(module='feed-orders'))
    total_orders = len(records)
    by_status = {}
    revenue = 0.0
    new_orders = 0
    awaiting_assignment = 0
    failed_cancelled = 0
    assignable = ('created', 'confirmed', 'preparing', 'ready_for_pickup')
    for r in records:
        s = r.payload.get('status', 'created')
        by_status[s] = by_status.get(s, 0) + 1
        if r.payload.get('payment_status') == 'paid':
            revenue += float(r.payload.get('total_amount', 0) or 0)
        if s == 'created':
            new_orders += 1
        if s in assignable:
            awaiting_assignment += 1
        if s in ('cancelled', 'delivery_failed'):
            failed_cancelled += 1

    active_delivery_ids = [
        r.payload['delivery_order_id'] for r in records
        if r.payload.get('delivery_order_id') and r.payload.get('status') in
        ('assigned', 'out_for_delivery')
    ]
    active_deliveries = 0
    if active_delivery_ids:
        from delivery.models import DeliveryOrder
        from delivery.services import ACTIVE_ORDER_STATUSES
        active_deliveries = DeliveryOrder.objects.filter(
            id__in=active_delivery_ids, status__in=ACTIVE_ORDER_STATUSES).count()

    return Response({
        'total_orders': total_orders, 'orders_by_status': by_status, 'paid_revenue': round(revenue, 2),
        'new_orders': new_orders, 'orders_awaiting_assignment': awaiting_assignment,
        'active_deliveries': active_deliveries, 'failed_cancelled_orders': failed_cancelled,
        'total_companies': FeedCompany.objects.count(),
        'active_companies': FeedCompany.objects.filter(status='active').count(),
        'total_products': FeedProduct.objects.count(),
        'products_pending_review': FeedProduct.objects.filter(approval_status='pending_review').count(),
        'products_approved': FeedProduct.objects.filter(approval_status='approved').count(),
        'low_stock_products': FeedProduct.objects.filter(
            approval_status='approved', stock_quantity__lt=50).count(),
    })
