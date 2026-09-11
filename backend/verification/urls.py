from django.urls import path

from verification import views

# Mounted under /api/auth/ by users/urls.py.
urlpatterns = [
    path('verify/request/', views.verify_request, name='verify-request'),
    path('verify/confirm/', views.verify_confirm, name='verify-confirm'),
    path('password-reset/request/', views.password_reset_request, name='password-reset-request'),
    path('password-reset/confirm/', views.password_reset_confirm, name='password-reset-confirm'),
    path('profile-photo/', views.profile_photo, name='profile-photo'),
    path('registration-documents/<str:token>/', views.serve_registration_document,
         name='registration-document'),
]
