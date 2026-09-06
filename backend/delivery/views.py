import json
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import timedelta, timezone as dt_timezone
from decimal import Decimal
from math import asin, cos, radians, sin, sqrt

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import BasePermission
from rest_framework.response import Response

from audit.models import AdminPanelRecord
from notifications.models import Notification
from profiles.models import DeliveryProfile
from users.models import User

from .models import DeliveryAttendance, DeliveryEarning, DeliveryOrder


OFFER_WINDOW = timedelta(minutes=3)
ON_TIME_WINDOW = timedelta(minutes=45)


class IsDeliveryUser(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (user.is_superuser or (user.account_status == 'active' and user.roles.filter(name='delivery').exists())))


def _rider_profile(user):
    try:
        return DeliveryProfile.objects.get(user=user)
    except DeliveryProfile.DoesNotExist:
        return None


def _aware(dt):
    # DB-sourced datetimes come back naive (the schema's columns are
    # `timestamp without time zone`), but Django stores them as UTC wall-clock
    # under USE_TZ=True — so the naive value must be labeled UTC, not the
    # local TIME_ZONE, or elapsed-time math ends up off by the UTC offset.
    if dt is not None and timezone.is_naive(dt):
        return dt.replace(tzinfo=dt_timezone.utc)
    return dt


def _distance(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    dlat, dlon = radians(float(lat2) - float(lat1)), radians(float(lon2) - float(lon1))
    a = sin(dlat / 2) ** 2 + cos(radians(float(lat1))) * cos(radians(float(lat2))) * sin(dlon / 2) ** 2
    return 6371 * 2 * asin(sqrt(a))


def _notify_delivery_admins(title, body, order=None):
    admins = User.objects.filter(roles__name__in=['admin_super', 'admin_operations', 'admin_delivery']).distinct()
    for admin in admins:
        Notification.objects.create(
            user=admin, title=title, body=body, notification_type='alert',
            reference_id=order.id if order else None, reference_type='delivery_order',
        )


def _pharmacy_source(order):
    if not order.is_pharmacy_delivery:
        return None
    return AdminPanelRecord.objects.filter(module='pharmacy-orders', id=order.order_reference_id).first()


def _order_json(order):
    source = _pharmacy_source(order)
    payload = source.payload if source else {}
    distance = _distance(order.pickup_lat, order.pickup_lng, order.delivery_lat, order.delivery_lng)
    try:
        earning = float(order.earning.total_earned)
    except DeliveryEarning.DoesNotExist:
        earning = 0.0
    return {
        'id': str(order.id),
        'order_number': payload.get('order_number', str(order.id)[:8].upper()),
        'pickup_address': order.pickup_address,
        'delivery_address': order.delivery_address,
        'pickup_lat': float(order.pickup_lat) if order.pickup_lat is not None else None,
        'pickup_lng': float(order.pickup_lng) if order.pickup_lng is not None else None,
        'delivery_lat': float(order.delivery_lat) if order.delivery_lat is not None else None,
        'delivery_lng': float(order.delivery_lng) if order.delivery_lng is not None else None,
        'customer_name': payload.get('farmer_name', ''),
        'customer_phone': payload.get('farmer_phone', ''),
        'distance_km': round(distance, 1) if distance is not None else 0,
        'order_type': 'pharmacy' if order.is_pharmacy_delivery else 'regular',
        'status': order.status,
        'items': [
            {'name': item.get('product_name', ''), 'quantity': item.get('quantity', 1)}
            for item in payload.get('items', [])
        ],
        'special_instructions': order.notes,
        'requires_otp': bool(order.otp_code),
        'earning': earning,
        'created_at': order.created_at.isoformat() if order.created_at else None,
        'assigned_at': order.assigned_at.isoformat() if order.assigned_at else None,
        'expires_at': (order.assigned_at + OFFER_WINDOW).isoformat() if (order.status == 'pending' and order.assigned_at) else None,
        'failure_reason': order.failure_reason,
        'proof_of_delivery_url': order.proof_of_delivery_url,
        'is_cold_chain': order.is_cold_chain,
        'is_prescription_required': order.is_prescription_required,
    }


def _expire_if_stale(order):
    if order.status != 'pending' or not order.assigned_at:
        return False
    if timezone.now() - _aware(order.assigned_at) <= OFFER_WINDOW:
        return False
    with transaction.atomic():
        locked = DeliveryOrder.objects.select_for_update().get(pk=order.id)
        if locked.status != 'pending':
            return True
        locked.status = 'rejected'
        locked.failure_reason = 'Offer expired'
        locked.save(update_fields=['status', 'failure_reason'])
    _notify_delivery_admins(
        'Delivery offer expired',
        f'A rider did not respond in time for order {str(locked.order_reference_id)[:8]}. It needs reassignment.',
        locked,
    )
    return True


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def dashboard(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    today = timezone.now().date()
    active_order = DeliveryOrder.objects.filter(
        delivery_person=rider, status__in=['accepted', 'picked_up', 'on_the_way'],
    ).order_by('-assigned_at').first()
    completed_today = DeliveryOrder.objects.filter(
        delivery_person=rider, status='delivered', delivered_at__date=today,
    ).count()
    pending_requests = DeliveryOrder.objects.filter(delivery_person=rider, status='pending').count()
    today_earnings = DeliveryEarning.objects.filter(
        delivery_person=rider, created_at__date=today,
    ).aggregate(total=Sum('total_earned'))['total'] or 0
    attendance = DeliveryAttendance.objects.filter(delivery_person=rider, attendance_date=today).first()
    return Response({
        'is_online': bool(rider.is_online),
        'current_status': rider.current_status,
        'rating': float(rider.rating or 0),
        'pending_requests': pending_requests,
        'completed_today': completed_today,
        'today_earnings': float(today_earnings),
        'attendance_status': attendance.status if attendance else 'not_marked',
        'checked_in': bool(attendance and attendance.check_in_time and not attendance.check_out_time),
        'active_order': _order_json(active_order) if active_order else None,
    })


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def availability(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    is_online = request.data.get('is_online')
    current_status = request.data.get('current_status')
    if is_online is not None:
        rider.is_online = bool(is_online)
        rider.current_status = 'active' if is_online else 'offline'
    if current_status in ('active', 'on_break', 'unavailable', 'offline'):
        rider.current_status = current_status
        rider.is_online = current_status != 'offline'
    rider.save(update_fields=['is_online', 'current_status', 'updated_at'])
    return Response({'is_online': rider.is_online, 'current_status': rider.current_status})


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def location(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    lat, lng = request.data.get('lat'), request.data.get('lng')
    if lat is None or lng is None:
        return Response({'detail': 'lat and lng are required.'}, status=400)
    try:
        lat, lng = float(lat), float(lng)
    except (TypeError, ValueError):
        return Response({'detail': 'lat and lng must be numbers.'}, status=400)
    rider.current_lat = lat
    rider.current_lng = lng
    rider.location_updated_at = timezone.now()
    rider.save(update_fields=['current_lat', 'current_lng', 'location_updated_at'])

    active_order = DeliveryOrder.objects.filter(
        delivery_person=rider, status__in=['picked_up', 'on_the_way'],
    ).order_by('-assigned_at').first()
    if active_order and active_order.delivery_lat is not None:
        dist = _distance(lat, lng, active_order.delivery_lat, active_order.delivery_lng)
        if dist is not None and dist <= 1.0 and not Notification.objects.filter(
                reference_id=active_order.id, reference_type='delivery_nearby').exists():
            source = _pharmacy_source(active_order)
            farmer_id = source.payload.get('farmer_id') if source else None
            try:
                farmer = User.objects.get(pk=farmer_id)
                Notification.objects.create(
                    user=farmer, title='Rider is nearby',
                    body='Your delivery rider is almost at your location.',
                    notification_type='system', reference_id=active_order.id, reference_type='delivery_nearby',
                )
            except (User.DoesNotExist, ValidationError, ValueError, TypeError):
                pass
    return Response({'current_lat': rider.current_lat, 'current_lng': rider.current_lng})


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def route(request, order_id):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    try:
        order = DeliveryOrder.objects.get(id=order_id, delivery_person=rider)
    except DeliveryOrder.DoesNotExist:
        return Response({'detail': 'Delivery order not found.'}, status=404)
    if not settings.GOOGLE_MAPS_API_KEY:
        return Response({'detail': 'Routing is not configured.'}, status=503)
    origin = (f'{order.pickup_lat},{order.pickup_lng}' if order.pickup_lat is not None
              else order.pickup_address)
    destination = (f'{order.delivery_lat},{order.delivery_lng}' if order.delivery_lat is not None
                   else order.delivery_address)
    params = urllib.parse.urlencode({
        'origin': origin, 'destination': destination, 'key': settings.GOOGLE_MAPS_API_KEY,
    })
    url = f'https://maps.googleapis.com/maps/api/directions/json?{params}'
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError, ValueError):
        return Response({'detail': 'Could not reach the routing service.'}, status=502)
    if data.get('status') != 'OK' or not data.get('routes'):
        return Response({'detail': 'No route found.'}, status=404)
    leg = data['routes'][0]['legs'][0]
    return Response({
        'polyline': data['routes'][0]['overview_polyline']['points'],
        'distance_km': round(leg['distance']['value'] / 1000, 2),
        'duration_min': round(leg['duration']['value'] / 60),
    })


@api_view(['POST'])
@permission_classes([IsDeliveryUser])
def proof_upload(request):
    file = request.FILES.get('file')
    if not file:
        return Response({'detail': 'An image file is required.'}, status=400)
    if not str(file.content_type).startswith('image/'):
        return Response({'detail': 'Only image files are supported.'}, status=400)
    if file.size > 5 * 1024 * 1024:
        return Response({'detail': 'Image must be 5 MB or smaller.'}, status=400)
    extension = file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else 'jpg'
    path = default_storage.save(f'delivery/{request.user.id}/{uuid.uuid4()}.{extension}', ContentFile(file.read()))
    return Response({'url': request.build_absolute_uri(default_storage.url(path))}, status=201)


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def requests_view(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    qs = DeliveryOrder.objects.filter(delivery_person=rider, status='pending').order_by('-assigned_at')
    results = []
    for o in qs:
        if _expire_if_stale(o):
            continue
        results.append(_order_json(o))
    return Response({'results': results})


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def respond(request, order_id):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    action = request.data.get('action')
    if action not in ('accept', 'reject'):
        return Response({'detail': 'action must be "accept" or "reject".'}, status=400)
    with transaction.atomic():
        try:
            order = DeliveryOrder.objects.select_for_update().get(id=order_id, delivery_person=rider)
        except DeliveryOrder.DoesNotExist:
            return Response({'detail': 'Delivery request not found.'}, status=404)
        if order.status != 'pending':
            return Response({'detail': f'This request is no longer available ({order.status}).'}, status=409)
        if order.assigned_at and timezone.now() - _aware(order.assigned_at) > OFFER_WINDOW:
            order.status = 'rejected'
            order.failure_reason = 'Offer expired'
            order.save(update_fields=['status', 'failure_reason'])
            _notify_delivery_admins(
                'Delivery offer expired',
                f'A rider did not respond in time for order {str(order.order_reference_id)[:8]}. It needs reassignment.',
                order,
            )
            return Response({'detail': 'This offer has expired.'}, status=409)
        order.status = 'accepted' if action == 'accept' else 'rejected'
        order.save(update_fields=['status'])
        if action == 'reject':
            _notify_delivery_admins(
                'Delivery request rejected',
                f'{rider.user.full_name or rider.user.email} rejected order {str(order.order_reference_id)[:8]}. It needs reassignment.',
                order,
            )
    return Response(_order_json(order))


_TRANSITIONS = {
    'accepted': {'picked_up', 'failed'},
    'picked_up': {'on_the_way', 'failed'},
    'on_the_way': {'delivered', 'failed'},
}


def _create_earning(order):
    base_pay = Decimal('60.00')
    distance = _distance(order.pickup_lat, order.pickup_lng, order.delivery_lat, order.delivery_lng)
    if distance and distance > 2:
        base_pay += Decimal(str(round(distance - 2, 3))) * Decimal('15.00')
    DeliveryEarning.objects.create(
        delivery_person=order.delivery_person, delivery_order=order,
        base_pay=base_pay, bonus=Decimal('0'), penalty=Decimal('0'),
        total_earned=base_pay, payout_status='pending', created_at=timezone.now(),
    )
    return base_pay


def _restock_failed_order(payload):
    owner_id = payload.get('owner_id')
    for order_item in payload.get('items', []):
        try:
            product_record = AdminPanelRecord.objects.select_for_update().get(
                module='pharmacy-products', record_id=f"{owner_id}:{order_item['product_id']}")
            product = dict(product_record.payload)
            product['stock_count'] = int(product.get('stock_count', 0)) + int(order_item.get('quantity', 0))
            product_record.payload = product
            product_record.save(update_fields=['payload', 'updated_at'])
        except (AdminPanelRecord.DoesNotExist, KeyError, TypeError, ValueError):
            pass


def _sync_pharmacy_order(order, actor, new_status):
    source = AdminPanelRecord.objects.filter(module='pharmacy-orders', id=order.order_reference_id).first()
    if not source:
        return
    payload = dict(source.payload)
    history = list(payload.get('status_history', []))
    history.append({
        'from': payload.get('status'), 'to': f'delivery_{new_status}',
        'message': f'Delivery {new_status.replace("_", " ")}.',
        'changed_at': timezone.now().isoformat(),
        'changed_by': actor.full_name or actor.email,
    })
    payload['status_history'] = history
    if new_status == 'delivered':
        payload.update({
            'status': 'delivered',
            'delivered_at': timezone.now().isoformat(),
            'completed_by': actor.full_name or actor.email,
        })
    elif new_status == 'failed':
        payload['status'] = 'delivery_failed'
        _restock_failed_order(payload)
    source.payload = payload
    source.save(update_fields=['payload', 'updated_at'])

    messages = {
        'picked_up': 'Your order has been picked up and is on the way.',
        'delivered': 'Your medicine order was delivered successfully.',
        'failed': 'The delivery could not be completed. The pharmacy will follow up on a redelivery or refund.',
    }
    try:
        farmer = User.objects.get(pk=payload.get('farmer_id'))
        Notification.objects.create(
            user=farmer, title=f'Delivery {new_status.replace("_", " ").title()}',
            body=f'{payload.get("order_number", "Your order")}: {messages.get(new_status, "")}',
            notification_type='system', reference_type='pharmacy_order',
        )
    except (User.DoesNotExist, ValidationError, ValueError, TypeError):
        pass
    if new_status == 'failed':
        try:
            pharmacy_user = User.objects.get(pk=payload.get('owner_id'))
            Notification.objects.create(
                user=pharmacy_user, title='Delivery failed',
                body=f'{payload.get("order_number", "An order")} could not be delivered. Items were restocked; move it back to Processing to redeliver.',
                notification_type='alert', reference_type='pharmacy_order',
            )
        except (User.DoesNotExist, ValidationError, ValueError, TypeError):
            pass


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def update_status(request, order_id):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    new_status = request.data.get('status')
    with transaction.atomic():
        try:
            order = DeliveryOrder.objects.select_for_update().get(id=order_id, delivery_person=rider)
        except DeliveryOrder.DoesNotExist:
            return Response({'detail': 'Delivery order not found.'}, status=404)
        allowed = _TRANSITIONS.get(order.status, set())
        if new_status not in allowed:
            return Response({'detail': f'Cannot move delivery from {order.status} to {new_status}.'}, status=409)
        if new_status == 'delivered' and order.is_pharmacy_delivery:
            otp = str(request.data.get('otp_code', '')).strip()
            if not order.otp_code or otp != order.otp_code:
                return Response({'detail': 'Incorrect or missing delivery OTP.'}, status=400)
        if new_status == 'failed':
            reason = str(request.data.get('failure_reason', '')).strip()
            if not reason:
                return Response({'detail': 'A failure reason is required.'}, status=400)
            order.failure_reason = reason
        if 'proof_of_delivery_url' in request.data:
            order.proof_of_delivery_url = request.data['proof_of_delivery_url']
        order.status = new_status
        if new_status == 'delivered':
            order.delivered_at = timezone.now()
        order.save()
        earned = None
        if new_status == 'delivered':
            earned = _create_earning(order)
            rider.total_deliveries = (rider.total_deliveries or 0) + 1
            rider.save(update_fields=['total_deliveries', 'updated_at'])
            Notification.objects.create(
                user=rider.user, title='Delivery completed',
                body=f'You earned ৳{earned} for this delivery.',
                notification_type='system', reference_id=order.id, reference_type='delivery_order',
            )
        if new_status == 'failed':
            _notify_delivery_admins(
                'Delivery failed',
                f'Order {str(order.order_reference_id)[:8]} failed: {order.failure_reason}',
                order,
            )
        if order.is_pharmacy_delivery and new_status in ('picked_up', 'delivered', 'failed'):
            _sync_pharmacy_order(order, request.user, new_status)
    return Response(_order_json(order))


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def orders_view(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    qs = DeliveryOrder.objects.filter(delivery_person=rider).exclude(status='pending').order_by('-created_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)
    try:
        limit = min(int(request.query_params.get('limit', 50)), 200)
    except (TypeError, ValueError):
        limit = 50
    try:
        offset = max(int(request.query_params.get('offset', 0)), 0)
    except (TypeError, ValueError):
        offset = 0
    total = qs.count()
    page = qs[offset:offset + limit]
    return Response({'results': [_order_json(o) for o in page], 'total': total, 'offset': offset, 'limit': limit})


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def checkin(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    today = timezone.now().date()
    existing = DeliveryAttendance.objects.filter(delivery_person=rider, attendance_date=today).first()
    if existing and existing.check_in_time and not existing.check_out_time:
        return Response({'detail': 'Already checked in.'}, status=409)
    item, _created = DeliveryAttendance.objects.update_or_create(
        delivery_person=rider, attendance_date=today,
        defaults={
            'check_in_time': timezone.now(), 'check_out_time': None,
            'status': 'present', 'created_at': timezone.now(),
        },
    )
    rider.is_online = True
    rider.current_status = 'active'
    rider.save(update_fields=['is_online', 'current_status', 'updated_at'])
    return Response({'id': str(item.id), 'check_in_time': item.check_in_time.isoformat()})


@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def checkout(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    today = timezone.now().date()
    try:
        item = DeliveryAttendance.objects.get(delivery_person=rider, attendance_date=today)
    except DeliveryAttendance.DoesNotExist:
        return Response({'detail': 'You have not checked in today.'}, status=400)
    if not item.check_in_time:
        return Response({'detail': 'You have not checked in today.'}, status=400)
    if item.check_out_time:
        return Response({'detail': 'Already checked out.'}, status=409)
    item.check_out_time = timezone.now()
    item.save(update_fields=['check_out_time'])
    rider.is_online = False
    rider.current_status = 'offline'
    rider.save(update_fields=['is_online', 'current_status', 'updated_at'])
    return Response({'id': str(item.id), 'check_out_time': item.check_out_time.isoformat()})


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def attendance_history(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    today = timezone.now().date()
    month_start = today.replace(day=1)
    rows = DeliveryAttendance.objects.filter(
        delivery_person=rider, attendance_date__gte=month_start,
    ).order_by('attendance_date')
    return Response({'records': [{
        'date': r.attendance_date.isoformat(), 'status': r.status,
        'check_in_time': r.check_in_time.isoformat() if r.check_in_time else None,
        'check_out_time': r.check_out_time.isoformat() if r.check_out_time else None,
    } for r in rows]})


@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def earnings_summary(request):
    rider = _rider_profile(request.user)
    if rider is None:
        return Response({'detail': 'Delivery profile not found.'}, status=404)
    today = timezone.now().date()
    week_start = today - timedelta(days=today.weekday())
    month_start = today.replace(day=1)
    qs = DeliveryEarning.objects.filter(delivery_person=rider)

    def total_since(since):
        return float(qs.filter(created_at__date__gte=since).aggregate(v=Sum('total_earned'))['v'] or 0)

    total_all = float(qs.aggregate(v=Sum('total_earned'))['v'] or 0)
    pending_payout = float(qs.filter(payout_status='pending').aggregate(v=Sum('total_earned'))['v'] or 0)
    orders_qs = DeliveryOrder.objects.filter(delivery_person=rider).exclude(status='pending')
    total_orders = orders_qs.count()
    delivered_qs = orders_qs.filter(status='delivered')
    delivered = delivered_qs.count()
    failed = orders_qs.filter(status__in=['failed', 'cancelled']).count()
    completion_rate = (delivered / total_orders * 100) if total_orders else 0
    cancellation_rate = (failed / total_orders * 100) if total_orders else 0

    ever_offered = orders_qs.filter(status__in=['accepted', 'rejected', 'picked_up', 'on_the_way', 'delivered', 'failed', 'cancelled']).count()
    accepted_count = orders_qs.exclude(status='rejected').count() if ever_offered else 0
    acceptance_rate = (accepted_count / ever_offered * 100) if ever_offered else 0

    on_time = sum(
        1 for o in delivered_qs
        if o.assigned_at and o.delivered_at and (_aware(o.delivered_at) - _aware(o.assigned_at)) <= ON_TIME_WINDOW
    )
    on_time_rate = (on_time / delivered * 100) if delivered else 0

    distances = [
        d for d in (
            _distance(o.pickup_lat, o.pickup_lng, o.delivery_lat, o.delivery_lng)
            for o in delivered_qs
        ) if d is not None
    ]
    avg_distance_km = round(sum(distances) / len(distances), 1) if distances else 0

    payout_history = [{
        'order_id': str(e.delivery_order_id), 'amount': float(e.total_earned),
        'is_paid': e.payout_status == 'paid',
        'date': e.created_at.isoformat() if e.created_at else None,
    } for e in qs.order_by('-created_at')[:20]]
    return Response({
        'today_earnings': total_since(today),
        'week_earnings': total_since(week_start),
        'month_earnings': total_since(month_start),
        'total_earnings': total_all,
        'pending_payout': pending_payout,
        'completion_rate': round(completion_rate, 1),
        'cancellation_rate': round(cancellation_rate, 1),
        'acceptance_rate': round(acceptance_rate, 1),
        'on_time_rate': round(on_time_rate, 1),
        'avg_distance_km': avg_distance_km,
        'avg_rating': float(rider.rating or 0),
        'payout_history': payout_history,
    })
