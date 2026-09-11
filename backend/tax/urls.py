from django.urls import path

from . import views

# mounted at /api/farmers/tax/
urlpatterns = [
    path('calculate/', views.calculate),
    path('profile/', views.profile),
    path('payment/', views.payments),
    path('payment/upload-receipt/', views.payment_upload_receipt),
    path('payments/', views.payments),
    path('summary/', views.summary),
]
