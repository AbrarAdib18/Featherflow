from django.urls import path

from . import views

urlpatterns = [
    path('dashboard/', views.dashboard), path('profile/', views.profile), path('availability/', views.availability),
    path('appointments/', views.appointments), path('appointments/<uuid:appointment_id>/action/', views.appointment_action),
    path('cases/', views.cases), path('cases/<uuid:case_id>/', views.cases),
    path('prescriptions/', views.prescriptions), path('follow-ups/', views.followups),
    path('earnings/', views.earnings), path('conversations/', views.conversations),
    path('conversations/<uuid:conversation_id>/', views.conversation_detail),
]
