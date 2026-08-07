from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny


@api_view(['GET'])
@permission_classes([AllowAny])
def api_root(request):
    return Response({
        'message': 'Featherflow API root. Use the module endpoints below.',
        'auth': request.build_absolute_uri('/api/auth/'),
        'current_user': request.build_absolute_uri('/api/auth/me/'),
        'token_refresh': request.build_absolute_uri('/api/token/refresh/'),
        'modules': {
            'workers': request.build_absolute_uri('/api/workers/'),
            'feed': request.build_absolute_uri('/api/feed/'),
            'costs': request.build_absolute_uri('/api/costs/'),
            'consultations': request.build_absolute_uri('/api/consultations/'),
            'pharmacy': request.build_absolute_uri('/api/pharmacy/'),
            'community': request.build_absolute_uri('/api/community/'),
            'notifications': request.build_absolute_uri('/api/notifications/'),
            'admin_panel': request.build_absolute_uri('/api/admin-panel/dashboard/'),
        },
        'notes': [
            'This is the API root for Featherflow.',
            'Protected endpoints require a JWT bearer token.',
        ],
    })
