from datetime import date, datetime, timedelta
from math import asin, cos, radians, sin, sqrt

from django.shortcuts import get_object_or_404
from django.http import HttpResponse
from django.db.models import Avg
from django.db.models import Q
from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status

from notifications.models import Notification
from profiles.models import DoctorProfile, FarmerProfile
from payments.models import Payment
from .models import Consultation
from doctor.models import (AvailabilitySlot, CaseDetail, ClinicalPrescription,
                           ConsultationNote, Conversation, FollowUp, Message)
from farms.models import Farm
from .booking import available_times, create_booking
from .serializers import FarmerBookingSerializer, FarmerConsultationActionSerializer
from .permissions import IsFarmer
from .workflow import ensure_slot_available, notify, record_transition
from .payments import confirm_cash_payment, ensure_cash_receipt, receipt_row


def _distance(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    dlat, dlon = radians(float(lat2) - float(lat1)), radians(float(lon2) - float(lon1))
    a = sin(dlat / 2) ** 2 + cos(radians(float(lat1))) * cos(radians(float(lat2))) * sin(dlon / 2) ** 2
    return 6371 * 2 * asin(sqrt(a))


def _mode(value):
    normalized = (value or '').strip().lower().replace('_', '-').replace(' ', '-')
    return 'offline' if normalized in (
        'offline', 'in-person', 'inperson', 'clinic-visit', 'field-visit') else normalized


def _doctor_row(profile, latitude=None, longitude=None):
    distance = _distance(latitude, longitude, profile.latitude, profile.longitude)
    return {
        'id': str(profile.id),
        'user_id': str(profile.user_id),
        'name': profile.user.full_name or profile.user.email,
        'photo_url': profile.user.profile_photo_url,
        'clinic': profile.clinic_hospital_name,
        'address': profile.practice_address,
        'district': profile.practice_address,
        'latitude': float(profile.latitude) if profile.latitude is not None else None,
        'longitude': float(profile.longitude) if profile.longitude is not None else None,
        'degree': profile.veterinary_degree,
        'specialty': profile.specialty,
        'focus_area': profile.poultry_focus_area,
        'experience_years': profile.years_of_experience,
        'mode': profile.consultation_mode,
        'emergency': profile.emergency_on_call_availability,
        'available': profile.is_available,
        'availability_status': profile.availability_status or ('available' if profile.is_available else 'offline'),
        'verified': profile.is_verified,
        'fee': float(profile.service_fee or 0),
        'rating': float(profile.rating),
        'distance_km': round(distance, 1) if distance is not None else None,
    }


def _initial_case_row(case):
    return {
        'id': str(case.id), 'farmer_name': case.farmer_name,
        'farm_name': case.farm_name, 'flock_id': str(case.flock_id) if case.flock_id else None,
        'bird_age': case.bird_age, 'breed': case.breed, 'flock_count': case.flock_count,
        'mortality_count': case.mortality_count,
        'symptoms': [x for x in (case.symptoms_description or '').split('\n') if x],
        'farmer_notes': case.farmer_notes, 'feed_notes': case.feed_notes,
        'vaccine_history': case.vaccine_history, 'biosecurity_notes': case.biosecurity_notes,
        'status': case.case_status,
    }


def _farmer_consultation_row(item):
    try:
        case = item.case_detail
    except CaseDetail.DoesNotExist:
        case = None
    conversation = Conversation.objects.filter(
        Q(participant_one=item.farmer, participant_two=item.doctor) |
        Q(participant_one=item.doctor, participant_two=item.farmer)
    ).first()
    prescriptions = item.clinical_prescriptions.prefetch_related('items').order_by('-created_at')
    follow_ups = item.follow_ups.order_by('scheduled_date')
    payment = Payment.objects.filter(
        reference_id=item.id, payment_type='consultation',
        reference_type='consultation').first()
    return {
        'id': str(item.id), 'doctor_name': item.doctor.full_name or item.doctor.email,
        'mode': item.mode, 'status': item.status, 'urgency': item.urgency_level,
        'date': item.appointment_date.isoformat(), 'time': item.appointment_time.strftime('%H:%M'),
        'fee': float(item.consultation_fee or 0),
        'case': _initial_case_row(case) if case else None,
        'proposed_date': item.proposed_date.isoformat() if item.proposed_date else None,
        'proposed_time': item.proposed_time.strftime('%H:%M') if item.proposed_time else None,
        'decision_reason': item.decision_reason,
        'rating': item.rating,
        'review': item.review_text,
        'rated_at': item.rated_at.isoformat() if item.rated_at else None,
        'conversation_id': str(conversation.id) if conversation else None,
        'clinical_results_available': item.status == 'completed',
        'payment_receipt_available': item.status == 'completed',
        'payment_receipt': receipt_row(payment, item) if payment else None,
        'history': [{'from': x.from_status, 'to': x.to_status, 'reason': x.reason,
                     'created_at': x.created_at.isoformat()}
                    for x in item.status_history.order_by('created_at')],
        'prescriptions': [{
            'id': str(p.id), 'case_advice': p.case_advice,
            'dosage_notes': p.dosage_notes,
            'follow_up_instructions': p.follow_up_instructions,
            'referred_to': p.referred_to,
            'created_at': p.created_at.isoformat(),
            'email_sent_at': p.email_sent_at.isoformat() if p.email_sent_at else None,
            'pdf_url': f'/api/consultations/prescriptions/{p.id}/pdf/',
            'medicines': [{'name': medicine.medicine_name, 'dosage': medicine.dosage,
                           'duration': medicine.duration, 'notes': medicine.instructions}
                          for medicine in p.items.all()],
        } for p in prescriptions],
        'follow_ups': [{'id': str(f.id), 'scheduled_date': f.scheduled_date.isoformat(),
                        'scheduled_time': f.scheduled_time.strftime('%H:%M') if f.scheduled_time else None,
                        'status': f.status, 'notes': f.notes} for f in follow_ups],
    }


@api_view(['GET'])
@permission_classes([IsFarmer])
@transaction.atomic
def consultation_receipt(request, consultation_id):
    item = get_object_or_404(
        Consultation.objects.select_for_update().select_related('farmer', 'doctor'),
        id=consultation_id, farmer=request.user)
    if item.status != 'completed':
        return Response({'detail': 'A receipt is generated after consultation completion.'}, status=409)
    payment, _ = ensure_cash_receipt(item)
    return Response(receipt_row(payment, item))


@api_view(['POST'])
@permission_classes([IsFarmer])
def mark_consultation_paid(request, consultation_id):
    item = get_object_or_404(Consultation, id=consultation_id, farmer=request.user)
    if item.status != 'completed':
        return Response({'detail': 'Only completed consultations can be marked paid.'}, status=409)
    payment, locked_item, created = confirm_cash_payment(item, request.user)
    return Response(receipt_row(payment, locked_item, already_paid=not created))


def _clinical_result_row(item):
    try:
        case = item.case_detail
    except CaseDetail.DoesNotExist:
        case = None
    note = item.clinical_notes.order_by('-updated_at', '-created_at').first()
    prescriptions = item.clinical_prescriptions.prefetch_related('items').order_by('-created_at')
    follow_ups = item.follow_ups.order_by('scheduled_date')
    return {
        'consultation_id': str(item.id),
        'status': item.status,
        'doctor': {
            'id': str(item.doctor_id),
            'name': item.doctor.full_name or item.doctor.email,
        },
        'farmer_name': item.farmer.full_name or item.farmer.email,
        'completed_at': item.updated_at.isoformat(),
        'appointment_date': item.appointment_date.isoformat(),
        'appointment_time': item.appointment_time.strftime('%H:%M'),
        'case': None if not case else {
            'id': str(case.id), 'farm_name': case.farm_name,
            'bird_age': case.bird_age, 'breed': case.breed,
            'flock_count': case.flock_count, 'mortality_count': case.mortality_count,
            'symptoms': [x for x in (case.symptoms_description or '').split('\n') if x],
            'disease_tags': case.disease_tags or [], 'feed_notes': case.feed_notes,
            'vaccine_history': case.vaccine_history,
            'biosecurity_notes': case.biosecurity_notes,
        },
        'clinical_note': None if not note else {
            'diagnosis': note.diagnosis, 'treatment_plan': note.treatment_plan,
            'warnings': note.warnings, 'next_steps': note.next_steps,
            'updated_at': note.updated_at.isoformat(),
        },
        'prescriptions': [{
            'id': str(p.id), 'case_advice': p.case_advice,
            'dosage_notes': p.dosage_notes,
            'follow_up_instructions': p.follow_up_instructions,
            'referred_to': p.referred_to, 'created_at': p.created_at.isoformat(),
            'pdf_url': f'/api/consultations/prescriptions/{p.id}/pdf/',
            'medicines': [{'name': medicine.medicine_name, 'dosage': medicine.dosage,
                           'duration': medicine.duration, 'notes': medicine.instructions}
                          for medicine in p.items.all()],
        } for p in prescriptions],
        'follow_ups': [{'id': str(f.id), 'scheduled_date': f.scheduled_date.isoformat(),
                        'scheduled_time': f.scheduled_time.strftime('%H:%M') if f.scheduled_time else None,
                        'status': f.status, 'notes': f.notes} for f in follow_ups],
    }


@api_view(['GET'])
@permission_classes([IsFarmer])
def clinical_results(request, consultation_id):
    item = get_object_or_404(
        Consultation.objects.select_related('farmer', 'doctor', 'case_detail').prefetch_related(
            'clinical_notes', 'clinical_prescriptions__items', 'follow_ups'),
        id=consultation_id, farmer=request.user,
    )
    if item.status != 'completed':
        return Response(
            {'detail': 'Clinical results are released after the consultation is completed.'},
            status=409,
        )
    return Response(_clinical_result_row(item))


@api_view(['GET'])
def prescription_pdf(request, prescription_id):
    prescription = get_object_or_404(
        ClinicalPrescription.objects.select_related(
            'doctor', 'consultation__farmer', 'consultation__case_detail'
        ).prefetch_related('items'), id=prescription_id)
    if request.user.id not in (prescription.doctor_id, prescription.consultation.farmer_id):
        return Response({'detail': 'You do not have access to this prescription.'}, status=403)
    from doctor.prescription_pdf import build_prescription_pdf
    response = HttpResponse(build_prescription_pdf(prescription), content_type='application/pdf')
    response['Content-Disposition'] = f'inline; filename="featherflow-prescription-{prescription.id}.pdf"'
    response['Cache-Control'] = 'private, no-store'
    return response


@api_view(['GET'])
@permission_classes([IsFarmer])
def vets(request):
    try:
        latitude = float(request.query_params.get('latitude')) if request.query_params.get('latitude') else None
        longitude = float(request.query_params.get('longitude')) if request.query_params.get('longitude') else None
    except ValueError:
        return Response({'detail': 'Invalid coordinates.'}, status=400)
    qs = DoctorProfile.objects.select_related('user').filter(
        user__account_status='active',
        user__user_roles__role__name='doctor',
    ).distinct()
    search = request.query_params.get('search', '').strip()
    if search:
        qs = qs.filter(Q(user__full_name__icontains=search) | Q(specialty__icontains=search) |
                       Q(poultry_focus_area__icontains=search) | Q(clinic_hospital_name__icontains=search) |
                       Q(practice_address__icontains=search))
    mode = _mode(request.query_params.get('mode', ''))
    if mode in ('online', 'offline'):
        qs = qs.filter(consultation_mode__in=(mode, 'both'))
    if request.query_params.get('available') == 'true':
        qs = qs.filter(is_available=True, availability_status='available')
    if request.query_params.get('emergency') == 'true':
        qs = qs.filter(emergency_on_call_availability=True)
    if request.query_params.get('verified') == 'true':
        qs = qs.filter(is_verified=True)
    specialty = request.query_params.get('specialty', '').strip()
    if specialty:
        qs = qs.filter(Q(specialty__icontains=specialty) | Q(poultry_focus_area__icontains=specialty))
    try:
        max_fee = float(request.query_params['max_fee']) if request.query_params.get('max_fee') else None
        min_rating = float(request.query_params['min_rating']) if request.query_params.get('min_rating') else None
    except ValueError:
        return Response({'detail': 'max_fee and min_rating must be numeric.'}, status=400)
    if max_fee is not None: qs = qs.filter(service_fee__lte=max_fee)
    if min_rating is not None: qs = qs.filter(rating__gte=min_rating)
    rows = [_doctor_row(x, latitude, longitude) for x in qs]
    rows.sort(key=lambda x: (x['distance_km'] is None, x['distance_km'] or 0, -x['rating']))
    active_clinics = len({x['clinic'] for x in rows if x['available']})
    return Response({
        'doctors': rows,
        'summary': {
            'nearby_doctors': len(rows),
            'active_clinics': active_clinics,
            'available_now': sum(1 for x in rows if x['available']),
        },
    })


@api_view(['GET'])
@permission_classes([IsFarmer])
def vet_detail(request, doctor_id):
    profile = get_object_or_404(
        DoctorProfile.objects.select_related('user').filter(
            user__account_status='active', user__user_roles__role__name='doctor',
        ).distinct(), id=doctor_id,
    )
    row = _doctor_row(profile)
    row.update({
        'university': profile.university_name, 'graduation_year': profile.graduation_year,
        'license_authority': profile.license_issuing_authority,
        'prescription_authority': bool(profile.prescription_authority),
        'referral_network': profile.referral_network,
        'total_ratings': Consultation.objects.filter(doctor=profile.user, rating__isnull=False).count(),
        'availability_slots': [
            {'id': str(slot.id), 'weekday': slot.weekday,
             'start_time': slot.start_time.strftime('%H:%M'), 'end_time': slot.end_time.strftime('%H:%M'),
             'mode': slot.mode}
            for slot in AvailabilitySlot.objects.filter(doctor=profile.user, is_active=True).order_by('weekday', 'start_time')
        ],
        'recent_reviews': [
            {'rating': item.rating, 'review': item.review_text,
             'farmer_name': item.farmer.full_name, 'date': item.updated_at.date().isoformat()}
            for item in Consultation.objects.filter(doctor=profile.user, rating__isnull=False)
                .select_related('farmer').order_by('-updated_at')[:5]
        ],
    })
    return Response(row)


@api_view(['GET'])
@permission_classes([IsFarmer])
@transaction.atomic
def booking_options(request, doctor_id):
    profile = get_object_or_404(
        DoctorProfile.objects.select_related('user').filter(
            id=doctor_id, user__account_status='active', user__user_roles__role__name='doctor',
        ).distinct(),
    )
    farmer_profile = FarmerProfile.objects.select_for_update().filter(
        user=request.user).first()
    # Backfill the primary farm for accounts created before registration began
    # mirroring FarmerProfile data into the farm-management table.
    if farmer_profile and not Farm.objects.filter(farmer=farmer_profile).exists():
        Farm.objects.create(
            farmer=farmer_profile,
            farm_name=farmer_profile.farm_name,
            farm_type=farmer_profile.farm_type or 'mixed',
            location=farmer_profile.farm_location,
            address=farmer_profile.farm_address,
            registration_number=farmer_profile.farm_registration_number,
            is_active=True,
        )
    farms = Farm.objects.filter(
        farmer__user=request.user, is_active=True,
    ).prefetch_related('flocks').order_by('farm_name')
    response = {
        'doctor': _doctor_row(profile),
        'farms': [{'id': str(farm.id), 'name': farm.farm_name, 'type': farm.farm_type,
                   'flocks': [{'id': str(flock.id), 'name': flock.batch_name, 'breed': flock.breed or '',
                               'bird_type': flock.bird_type or '', 'count': flock.current_quantity,
                               'start_date': flock.start_date.isoformat()}
                              for flock in farm.flocks.filter(status='active').order_by('batch_name')]}
                  for farm in farms],
        'slot_minutes': 30,
    }
    raw_date = request.query_params.get('date')
    mode = _mode(request.query_params.get('mode'))
    if raw_date and mode:
        try:
            target_date = date.fromisoformat(raw_date)
        except ValueError:
            return Response({'detail': 'date must use YYYY-MM-DD.'}, status=400)
        if mode not in ('online', 'offline') or profile.consultation_mode not in ('both', mode):
            return Response({'detail': 'Unsupported consultation mode.'}, status=400)
        response['date'] = target_date.isoformat()
        response['mode'] = mode
        response['available_times'] = available_times(
            profile, target_date, mode, farmer=request.user)
    return Response(response)


@api_view(['GET', 'POST', 'PATCH'])
@permission_classes([IsFarmer])
@transaction.atomic
def consultations(request):
    if request.method == 'GET':
        qs = Consultation.objects.filter(farmer=request.user).select_related('doctor', 'case_detail').order_by('-created_at')
        return Response({'consultations': [_farmer_consultation_row(x) for x in qs]})
    if request.method == 'PATCH':
        item = get_object_or_404(
            Consultation.objects.select_for_update(),
            id=request.data.get('id'), farmer=request.user)
        if 'rating' in request.data:
            if item.status != 'completed':
                return Response({'detail': 'Only completed consultations can be rated.'}, status=400)
            try:
                rating = int(request.data['rating'])
            except (TypeError, ValueError):
                return Response({'detail': 'Rating must be an integer from 1 to 5.'}, status=400)
            if rating not in range(1, 6):
                return Response({'detail': 'Rating must be from 1 to 5.'}, status=400)
            if item.rating is not None:
                return Response({'detail': 'This consultation has already been rated.'}, status=409)
            profile = DoctorProfile.objects.select_for_update().get(user=item.doctor)
            item.rating = rating
            item.review_text = str(request.data.get('review', '')).strip()
            if len(item.review_text) > 2000:
                return Response({'detail': 'Review cannot exceed 2000 characters.'}, status=400)
            item.rated_at = timezone.now()
            item.save(update_fields=['rating', 'review_text', 'rated_at', 'updated_at'])
            average = Consultation.objects.filter(doctor=item.doctor, rating__isnull=False).aggregate(value=Avg('rating'))['value'] or 0
            profile.rating = average; profile.save(update_fields=['rating'])
            Notification.objects.create(
                user=item.doctor, title='New consultation rating',
                body=f'{request.user.full_name or request.user.email} rated the consultation {rating}/5.' + (f' “{item.review_text[:120]}”' if item.review_text else ''),
                notification_type='system', reference_id=item.id, reference_type='consultation_rating',
            )
            return Response({'rating': rating, 'review': item.review_text})
        if item.status not in ('requested', 'accepted'):
            return Response({'detail': 'This request can no longer be cancelled.'}, status=400)
        item.status = 'cancelled'
        item.save(update_fields=['status', 'updated_at'])
        Notification.objects.create(
            user=item.doctor, title='Consultation cancelled',
            body=f'{request.user.full_name or request.user.email} cancelled a consultation request.',
            notification_type='reminder', reference_id=item.id, reference_type='consultation',
        )
        return Response({'status': item.status})

    serializer = FarmerBookingSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    item, case = create_booking(request.user, serializer.validated_data)
    profile = DoctorProfile.objects.select_related('user').get(user=item.doctor)
    urgency = item.urgency_level
    mode = item.mode
    farmer_name = request.user.full_name or request.user.email
    Notification.objects.create(
        user=profile.user, title='New consultation request',
        body=f'{farmer_name} requested an {urgency} {mode} consultation.',
        notification_type='reminder', reference_id=item.id, reference_type='consultation',
    )
    Notification.objects.create(
        user=request.user, title='Consultation requested',
        body=f'Your request with {profile.user.full_name or profile.user.email} was submitted.',
        notification_type='reminder', reference_id=item.id, reference_type='consultation',
    )
    return Response({'id': str(item.id), 'status': item.status,
                     'case_detail_id': str(case.id), 'case': _initial_case_row(case)},
                    status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsFarmer])
@transaction.atomic
def consultation_action(request, consultation_id):
    serializer = FarmerConsultationActionSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    item = get_object_or_404(Consultation.objects.select_for_update(), id=consultation_id, farmer=request.user)
    action = serializer.validated_data['action']
    reason = serializer.validated_data.get('reason', '')
    if action == 'cancel':
        if item.status not in ('requested', 'accepted'):
            return Response({'detail': 'This consultation can no longer be cancelled.'}, status=409)
        record_transition(item, request.user, 'cancelled', reason)
        notify(item.doctor, 'Consultation cancelled', f'{request.user.full_name} cancelled the consultation.', item)
    elif action == 'accept_reschedule':
        if item.status != 'reschedule_proposed' or not item.proposed_date or not item.proposed_time:
            return Response({'detail': 'There is no reschedule proposal to accept.'}, status=409)
        ensure_slot_available(item, item.proposed_date, item.proposed_time)
        item.appointment_date, item.appointment_time = item.proposed_date, item.proposed_time
        item.proposed_date = item.proposed_time = None
        item.save(update_fields=['appointment_date', 'appointment_time', 'proposed_date', 'proposed_time'])
        record_transition(item, request.user, 'accepted', reason)
        from .workflow import get_or_create_conversation
        conversation, _ = get_or_create_conversation(item)
        notify(item.doctor, 'Reschedule accepted', f'{request.user.full_name} accepted the new consultation time.', item)
        return Response({**_farmer_consultation_row(item), 'conversation_id': str(conversation.id)})
    elif action == 'decline_reschedule':
        if item.status != 'reschedule_proposed':
            return Response({'detail': 'There is no reschedule proposal to decline.'}, status=409)
        item.proposed_date = item.proposed_time = None
        item.save(update_fields=['proposed_date', 'proposed_time'])
        record_transition(item, request.user, 'cancelled', reason)
        notify(item.doctor, 'Reschedule declined', f'{request.user.full_name} declined the proposed time.', item)
    else:
        if item.status != 'completed':
            return Response({'detail': 'Only completed consultations can be rated.'}, status=409)
        if item.rating is not None:
            return Response({'detail': 'This consultation has already been rated.'}, status=409)
        profile = DoctorProfile.objects.select_for_update().get(user=item.doctor)
        item.rating = serializer.validated_data['rating']; item.review_text = serializer.validated_data.get('review', '')
        item.rated_at = timezone.now()
        item.save(update_fields=['rating', 'review_text', 'rated_at', 'updated_at'])
        average = Consultation.objects.filter(doctor=item.doctor, rating__isnull=False).aggregate(value=Avg('rating'))['value'] or 0
        profile.rating = average; profile.save(update_fields=['rating'])
        Notification.objects.create(
            user=item.doctor, title='New consultation rating',
            body=f'{request.user.full_name or request.user.email} rated the consultation {item.rating}/5.' + (f' “{item.review_text[:120]}”' if item.review_text else ''),
            notification_type='system', reference_id=item.id,
            reference_type='consultation_rating')
    return Response(_farmer_consultation_row(item))


def _chat_row(conversation, user):
    other = conversation.participant_two if conversation.participant_one_id == user.id else conversation.participant_one
    messages = conversation.messages.order_by('sent_at')
    return {
        'id': str(conversation.id), 'participant_name': other.full_name or other.email,
        'participant_id': str(other.id), 'consultation_id': str(conversation.consultation_id) if conversation.consultation_id else None,
        'last_message_at': (conversation.last_message_at or conversation.created_at).isoformat(),
        'unread_count': messages.exclude(sender=user).filter(is_read=False).count(),
        'messages': [{'id': str(message.id), 'sender_id': str(message.sender_id),
                      'from_me': message.sender_id == user.id, 'content': message.content or message.file_url or '',
                      'message_type': message.message_type, 'file_url': message.file_url,
                      'is_read': message.is_read, 'sent_at': message.sent_at.isoformat()}
                     for message in messages],
    }


@api_view(['GET'])
def chats(request):
    if not request.user.roles.filter(name__in=('farmer', 'doctor')).exists():
        return Response({'detail': 'Chat is limited to farmers and doctors.'}, status=403)
    qs = Conversation.objects.filter(Q(participant_one=request.user) | Q(participant_two=request.user)).select_related(
        'participant_one', 'participant_two', 'consultation').order_by('-last_message_at', '-created_at')
    return Response({'conversations': [_chat_row(item, request.user) for item in qs]})
