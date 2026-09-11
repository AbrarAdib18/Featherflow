from django.urls import path

from . import views

# Subscription-facing routes are mounted under /api/subscriptions/ and the
# payment routes under /api/payments/ (see api/urls.py).
subscription_urlpatterns = [
    path('plans/', views.plans, name='subscription-plans'),
    path('current/', views.current, name='subscription-current'),
    path('checkout/', views.checkout, name='subscription-checkout'),
]

payment_urlpatterns = [
    path('webhook/<str:provider>/', views.webhook, name='payment-webhook'),
    path('<uuid:pk>/', views.payment_detail, name='payment-detail'),
    path('<uuid:pk>/method/', views.select_method, name='payment-method'),
    path('<uuid:pk>/confirm/', views.confirm, name='payment-confirm'),
    path('<uuid:pk>/cancel/', views.cancel, name='payment-cancel'),
]
