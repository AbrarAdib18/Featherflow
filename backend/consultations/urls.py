from django.urls import path
from .views import (booking_options, chats, clinical_results,
                    consultation_action, consultation_receipt, consultations,
                    mark_consultation_paid, prescription_pdf, vet_detail, vets)

urlpatterns = [
    path('', consultations),
    path('vets/', vets),
    path('vets/<uuid:doctor_id>/', vet_detail),
    path('vets/<uuid:doctor_id>/booking-options/', booking_options),
    path('<uuid:consultation_id>/action/', consultation_action),
    path('<uuid:consultation_id>/clinical-results/', clinical_results),
    path('<uuid:consultation_id>/receipt/', consultation_receipt),
    path('<uuid:consultation_id>/mark-paid/', mark_consultation_paid),
    path('chats/', chats),
    path('prescriptions/<uuid:prescription_id>/pdf/', prescription_pdf),
]
