from django.urls import path
from .views import (booking_options, chat_detail, chats, clinical_results,
                    consultation_action, consultation_receipt, consultation_video,
                    consultations, disputes, mark_consultation_paid,
                    prescription_pdf, vet_detail, vets)

urlpatterns = [
    path('', consultations),
    path('vets/', vets),
    # Location-based alias: GET /api/consultations/vets/nearby/?latitude=&longitude=
    # (also accepts lat=/lng=). Same handler as vets/ which already distance-sorts.
    path('vets/nearby/', vets),
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
