from rest_framework.decorators import api_view
from rest_framework.response import Response

from .serializers import serialize_notifications


@api_view(['GET', 'PATCH'])
def inbox(request):
    qs = request.user.notifications.order_by('-created_at')
    if request.method == 'PATCH':
        qs.filter(is_read=False).update(is_read=True)
        return Response({'unread_count': 0})
    # created_at is returned as timezone-aware ISO 8601 and `time` is computed
    # from that aware value — see notifications/serializers.py for why the old
    # `timesince(x.created_at)` reported "6 hours ago" for brand-new rows.
    return Response({
        'notifications': serialize_notifications(request.user, qs[:100]),
        'unread_count': qs.filter(is_read=False).count(),
    })
