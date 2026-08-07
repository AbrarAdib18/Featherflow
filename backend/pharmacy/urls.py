from django.urls import path

from pharmacy.views import collection, dashboard, marketplace, pharmacy_root, place_order, record

urlpatterns = [
    path('', pharmacy_root),
    path('dashboard/', dashboard),
    path('marketplace/', marketplace),
    path('place-order/', place_order),
    path('<str:kind>/', collection),
    path('<str:kind>/<str:record_id>/', record),
]
