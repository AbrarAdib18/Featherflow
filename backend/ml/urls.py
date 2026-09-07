from django.urls import path

from . import views

urlpatterns = [
    path('predict-disease/', views.predict_disease),
    path('scans/', views.scans),
    path('scans/<uuid:scan_id>/', views.scan_detail),
    path('diseases/<uuid:disease_id>/', views.disease_detail),
    path('health/', views.health),
]
