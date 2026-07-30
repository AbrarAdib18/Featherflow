from django.urls import path
from .views import workers,attendance,payments,worker_detail

urlpatterns = [path('',workers,name='workers'),path('detail/',worker_detail),path('attendance/',attendance),path('payments/',payments)]
