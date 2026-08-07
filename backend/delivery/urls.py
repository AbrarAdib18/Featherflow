from django.urls import path
from delivery.views import order_detail, orders

urlpatterns = [path('orders/', orders), path('orders/<str:record_id>/', order_detail)]
