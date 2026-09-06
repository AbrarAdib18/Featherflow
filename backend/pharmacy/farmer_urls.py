from django.urls import path

from pharmacy import farmer_views as f

urlpatterns = [
    path('pharmacies/', f.pharmacies),
    path('pharmacies/<uuid:pharmacy_id>/medicines/', f.pharmacy_medicines),
    path('medicines/search/', f.medicine_search),
    path('medicines/<uuid:medicine_id>/', f.medicine_detail),
    path('prescriptions/upload/', f.prescription_upload),
    path('orders/', f.orders),
    path('orders/<str:order_id>/cancel/', f.order_cancel),
    path('orders/<str:order_id>/pay/', f.order_pay),
    path('orders/<str:order_id>/', f.order_detail),
]
