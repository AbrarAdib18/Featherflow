from django.urls import path
from delivery.views import (
    attendance_history, availability, checkin, checkout, dashboard,
    earnings_summary, location, orders_view, proof_upload, requests_view,
    respond, route, update_status,
)

urlpatterns = [
    path('dashboard/', dashboard),
    path('availability/', availability),
    path('location/', location),
    path('requests/', requests_view),
    path('requests/<uuid:order_id>/respond/', respond),
    path('orders/', orders_view),
    path('orders/<uuid:order_id>/status/', update_status),
    path('orders/<uuid:order_id>/route/', route),
    path('proof-upload/', proof_upload),
    path('attendance/', attendance_history),
    path('attendance/checkin/', checkin),
    path('attendance/checkout/', checkout),
    path('earnings/', earnings_summary),
]
