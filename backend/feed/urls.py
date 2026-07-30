from django.urls import path
from .views import feed, schedules,stock_detail,orders

urlpatterns = [path('',feed,name='feed'),path('stock/',stock_detail),path('schedules/',schedules,name='feed-schedules'),path('orders/',orders)]
