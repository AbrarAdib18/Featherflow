from django.urls import include, path
from users.views import UserViewSet, auth_root, registration_upload

urlpatterns = [
    path('', auth_root, name='auth-root'),
    path('register/', UserViewSet.as_view({'post': 'register'}), name='auth-register'),
    path('registration-upload/', registration_upload, name='auth-registration-upload'),
    path('login/', UserViewSet.as_view({'post': 'login'}), name='auth-login'),
    path('me/', UserViewSet.as_view({'get': 'me'}), name='auth-me'),
    path('users/<uuid:pk>/', UserViewSet.as_view({'get': 'retrieve'}), name='auth-user-detail'),
    # Contact verification, password reset, private document delivery.
    path('', include('verification.urls')),
]
