from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny


@api_view(['GET'])
@permission_classes([AllowAny])
def api_root(request):
    base = request.build_absolute_uri('/')
    return Response({
        'message': 'Featherflow API root. Use the module endpoints below.',
        'auth': request.build_absolute_uri('/api/auth/'),
        'current_user': request.build_absolute_uri('/api/auth/me/'),
        'token_refresh': request.build_absolute_uri('/api/token/refresh/'),
        'modules': {
            'subscriptions': request.build_absolute_uri('/api/subscriptions/'),
            'payments': request.build_absolute_uri('/api/payments/'),
            'profiles': request.build_absolute_uri('/api/profiles/'),
            'farms': request.build_absolute_uri('/api/farms/'),
            'workers': request.build_absolute_uri('/api/workers/'),
            'feed': request.build_absolute_uri('/api/feed/'),
            'expenses': request.build_absolute_uri('/api/expenses/'),
            'disease': request.build_absolute_uri('/api/disease/'),
            'chatbot': request.build_absolute_uri('/api/chatbot/'),
            'consultations': request.build_absolute_uri('/api/consultations/'),
            'messaging': request.build_absolute_uri('/api/messaging/'),
            'pharmacy': request.build_absolute_uri('/api/pharmacy/'),
            'delivery': request.build_absolute_uri('/api/delivery/'),
            'community': request.build_absolute_uri('/api/community/'),
            'articles': request.build_absolute_uri('/api/articles/'),
            'notifications': request.build_absolute_uri('/api/notifications/'),
            'audit': request.build_absolute_uri('/api/audit/'),
        },
        'notes': [
            'This is the API root for Featherflow.',
            'Add the rest of the module routers to api/urls.py as each SQL module is implemented.',
        ],
    })
