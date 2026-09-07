from django.urls import path
from .views import (booking_options, chat_detail, chats, clinical_results,
                    consultation_action, consultation_receipt, consultation_video,
                    consultations, disputes, mark_consultation_paid,
                    prescription_pdf, vet_detail, vets, vets_nearby)

urlpatterns = [
    path('', consultations),
    path('vets/', vets),
    # Simple radius search: GET /api/consultations/vets/nearby/?lat=&lng=&radius=50
    # (mirror of /api/vets/nearby/).
    path('vets/nearby/', vets_nearby),
    path('vets/<uuid:doctor_id>/', vet_detail),
    path('vets/<uuid:doctor_id>/booking-options/', booking_options),
    path('disputes/', disputes),
    path('<uuid:consultation_id>/action/', consultation_action),
    path('<uuid:consultation_id>/clinical-results/', clinical_results),
    path('<uuid:consultation_id>/receipt/', consultation_receipt),
    path('<uuid:consultation_id>/mark-paid/', mark_consultation_paid),
    path('<uuid:consultation_id>/video/', consultation_video),
    path('chats/', chats),
    path('chats/<uuid:conversation_id>/', chat_detail),
    path('prescriptions/<uuid:prescription_id>/pdf/', prescription_pdf),
]
