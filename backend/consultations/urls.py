from django.urls import path
from .views import consultations, vets

urlpatterns = [
    path('', consultations),
    path('vets/', vets),
]
