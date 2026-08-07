from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from audit.models import AdminPanelRecord
from django.utils import timezone
from django.core.exceptions import ValidationError
from notifications.models import Notification
from users.models import User

class IsDeliveryUser(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (user.is_superuser or (user.account_status == 'active' and user.roles.filter(name='delivery').exists())))

@api_view(['GET'])
@permission_classes([IsDeliveryUser])
def orders(request):
    return Response({'results': [r.payload for r in AdminPanelRecord.objects.filter(module='delivery-orders')]})

@api_view(['PATCH'])
@permission_classes([IsDeliveryUser])
def order_detail(request, record_id):
    try:
        record = AdminPanelRecord.objects.get(module='delivery-orders', record_id=record_id)
    except AdminPanelRecord.DoesNotExist:
        return Response({'detail': 'Delivery order not found.'}, status=404)
    allowed = {k: v for k, v in request.data.items() if k in {'status', 'assigned_rider'}}
    current_status = record.payload.get('status', 'Pending')
    new_status = allowed.get('status')
    transitions = {
        'Pending': {'Accepted', 'Failed'},
        'Accepted': {'Picked Up'},
        'Picked Up': {'On The Way'},
        'On The Way': {'Delivered'},
        'Delivered': set(), 'Failed': set(),
    }
    if new_status and new_status not in transitions.get(current_status, set()):
        return Response({'detail': f'Cannot move delivery from {current_status} to {new_status}.'}, status=409)
    if new_status == 'Delivered' and request.data.get('delivery_confirmed') is not True:
        return Response({'detail': 'Delivery confirmation is required before completing the order.'}, status=400)
    if request.data.get('status') == 'Accepted':
        allowed['assigned_rider'] = request.user.full_name or request.user.email
    record.payload = {**record.payload, **allowed}
    record.save(update_fields=['payload', 'updated_at'])
    pharmacy_order_id = record.payload.get('pharmacy_order_id')
    if pharmacy_order_id and allowed.get('status'):
        order_record = AdminPanelRecord.objects.filter(module='pharmacy-orders', payload__id=pharmacy_order_id).first()
        if order_record:
            order = dict(order_record.payload)
            status = allowed['status']
            messages = {
                'Accepted': 'A delivery rider accepted your medicine order.',
                'Picked Up': 'Your medicine order was picked up from the pharmacy.',
                'On The Way': 'Your medicine order is on the way.',
                'Delivered': 'Your medicine order was delivered successfully.',
                'Failed': 'A rider could not accept the delivery. Another rider may be assigned.',
            }
            if status == 'Delivered':
                history = list(order.get('status_history', []))
                history.append({'from': order.get('status'), 'to': 'delivered', 'message': messages[status], 'changed_at': timezone.now().isoformat(), 'changed_by': request.user.full_name or request.user.email})
                order.update({'status': 'delivered', 'delivered_at': timezone.now().isoformat(), 'status_history': history})
                order_record.payload = order
                order_record.save(update_fields=['payload', 'updated_at'])
            try:
                farmer = User.objects.get(pk=order.get('farmer_id'))
                Notification.objects.create(user=farmer, title=f'Delivery {status}', body=f'{order.get("order_number", "Your order")}: {messages.get(status, "Delivery status updated.")}', notification_type='system', reference_type='pharmacy_order')
            except (User.DoesNotExist, ValidationError, ValueError, TypeError):
                pass
    return Response(record.payload)
