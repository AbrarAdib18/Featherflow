from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView

from api.views import api_root

urlpatterns = [
    path('', api_root, name='api-root'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/', include('users.urls')),
]
