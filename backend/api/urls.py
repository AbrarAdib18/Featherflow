from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView

from api.views import api_root
from api.admin_views import admin_collection, admin_dashboard, admin_profile, admin_record

urlpatterns = [
    path('', api_root, name='api-root'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/', include('users.urls')),
    path('workers/', include('workers.urls')),
    path('feed/', include('feed.urls')),
    path('costs/', include('expenses.urls')),
    path('community/', include('community.urls')),
    path('notifications/', include('notifications.urls')),
    path('consultations/', include('consultations.urls')),
    path('admin-panel/dashboard/', admin_dashboard),
    path('admin-panel/profile/', admin_profile),
    path('admin-panel/<str:module>/', admin_collection),
    path('admin-panel/<str:module>/<str:record_id>/', admin_record),
]
