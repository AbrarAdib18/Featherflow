from datetime import date, datetime

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from consultations.models import Consultation, ConsultationDispute
from consultations.metrics import dispute_counts, response_time_stats
from messaging.realtime import emit_to_conversation
from notifications.models import Notification
from profiles.models import DoctorProfile, FarmerProfile

from .models import (
    AvailabilitySlot, CaseDetail, ClinicalPrescription, ConsultationNote, Conversation,
    DoctorEarning, FollowUp, Message, PayoutRequest, PrescriptionItem,
)
from .permissions import IsDoctor
from .serializers import (
    AppointmentActionSerializer, AvailabilitySlotSerializer, CaseSerializer, FollowUpSerializer,
    MessageSerializer, PayoutSerializer, PrescriptionSerializer, ProfileSerializer,
)
from consultations.workflow import (
    accept_consultation, ensure_published_availability, ensure_slot_available,
    notify, record_transition,
)
from consultations.payments import ensure_cash_receipt


def _doctor_profile(user):
    return get_object_or_404(DoctorProfile.objects.select_related('user'), user=user)


def _notify(user, title, body, item, kind='consultation'):
    Notification.objects.create(user=user, title=title, body=body, notification_type='reminder', reference_id=item.id, reference_type=kind)


def _farm_name(user):
    profile = FarmerProfile.objects.filter(user=user).first()
    return profile.farm_name if profile else ''


def _appointment_row(item):
    case = CaseDetail.objects.filter(consultation=item).first()
    return {
        'id': str(item.id), 'farmer_name': item.farmer.full_name or item.farmer.email,
        'farmer_phone': item.farmer.phone, 'farm_name': case.farm_name if case else _farm_name(item.farmer),
        'scheduled_at': f'{item.appointment_date.isoformat()}T{item.appointment_time.strftime("%H:%M:%S")}',
        'mode': item.mode, 'status': 'pending' if item.status == 'requested' else item.status,
        'urgency': item.urgency_level, 'is_urgent': item.urgency_level in ('urgent', 'emergency'),
        'case_id': str(case.id) if case else None, 'fee': float(item.consultation_fee or 0),
        'proposed_date': item.proposed_date.isoformat() if item.proposed_date else None,
        'proposed_time': item.proposed_time.strftime('%H:%M') if item.proposed_time else None,
        'decision_reason': item.decision_reason,
    }


def _prescription_row(item):
    return {
        'id': str(item.id), 'consultation_id': str(item.consultation_id),
        'case_id': str(item.consultation.case_detail.id),
        'medicines': [{'name': x.medicine_name, 'dosage': x.dosage, 'duration': x.duration, 'notes': x.instructions} for x in item.items.all()],
        'dosage_notes': item.dosage_notes, 'case_advice': item.case_advice,
        'follow_up_instructions': item.follow_up_instructions,
        'referred_to': item.referred_to, 'created_at': item.created_at.isoformat(),
        'pdf_url': f'/api/consultations/prescriptions/{item.id}/pdf/',
        'email_sent_at': item.email_sent_at.isoformat() if item.email_sent_at else None,
    }


def _case_row(case):
    consultation = case.consultation
    note = consultation.clinical_notes.order_by('-created_at').first()
    prescription = consultation.clinical_prescriptions.prefetch_related('items').order_by('-created_at').first()
    follow_up = consultation.follow_ups.filter(status='pending').order_by('scheduled_date').first()
    symptoms = [x.strip() for x in (case.symptoms_description or '').split('\n') if x.strip()]
    try:
        age = int(''.join(c for c in (case.bird_age or '') if c.isdigit()) or 0)
    except ValueError:
        age = 0
    return {
        'id': str(case.id), 'appointment_id': str(consultation.id),
        'farmer_name': case.farmer_name or consultation.farmer.full_name or consultation.farmer.email,
        'farm_name': case.farm_name or _farm_name(consultation.farmer), 'flock_size': case.flock_count or 0,
        'bird_age_weeks': age, 'breed': case.breed or '', 'mortality_count': case.mortality_count or 0,
        'symptoms': symptoms, 'diagnosis': note.diagnosis if note else None,
        'treatment_plan': note.treatment_plan if note else None, 'disease_tags': case.disease_tags or [],
        'urgency': consultation.urgency_level, 'status': case.case_status,
        'feed_notes': case.feed_notes, 'vaccine_history': case.vaccine_history,
        'farmer_notes': case.farmer_notes,
        'biosecurity_notes': case.biosecurity_notes, 'warnings': note.warnings if note else None,
        'next_steps': note.next_steps if note else None, 'created_at': case.created_at.isoformat(),
        'follow_up_date': (f'{follow_up.scheduled_date.isoformat()}T'
                           f'{follow_up.scheduled_time.strftime("%H:%M:%S")}'
                           if follow_up and follow_up.scheduled_time else
                           follow_up.scheduled_date.isoformat() if follow_up else None),
        'prescription': _prescription_row(prescription) if prescription else None,
    }


@api_view(['GET'])
@permission_classes([IsDoctor])
def dashboard(request):
    profile = _doctor_profile(request.user)
    qs = Consultation.objects.filter(doctor=request.user).select_related('farmer')
    cases = CaseDetail.objects.filter(consultation__doctor=request.user)
    unread = Message.objects.filter(conversation__in=Conversation.objects.filter(Q(participant_one=request.user) | Q(participant_two=request.user))).exclude(sender=request.user).filter(is_read=False).count()
    earnings = DoctorEarning.objects.filter(doctor=request.user)
    today_items = qs.filter(appointment_date=date.today()).order_by('appointment_time')
    followups = FollowUp.objects.filter(consultation__doctor=request.user, status='pending').select_related('consultation__farmer').order_by('scheduled_date')
    return Response({'profile': _profile_row(profile), 'summary': {
        'total_clients': qs.values('farmer_id').distinct().count(), 'today_appointments': today_items.count(),
        'active_cases': cases.filter(case_status__in=('open', 'in_progress')).count(),
        'completed_cases': cases.filter(case_status='closed').count(),
        'urgent_requests': qs.filter(status='requested', urgency_level__in=('urgent', 'emergency')).count(),
        'unread_messages': unread, 'pending_follow_ups': followups.count(), 'rating': float(profile.rating or 0),
        'total_ratings': qs.exclude(rating=None).count(),
        'gross_earnings': float(earnings.aggregate(v=Sum('gross_amount'))['v'] or 0),
        'monthly_gross_earnings': float(earnings.filter(created_at__year=date.today().year, created_at__month=date.today().month).aggregate(v=Sum('gross_amount'))['v'] or 0),
        'monthly_earnings': float(earnings.filter(created_at__year=date.today().year, created_at__month=date.today().month).aggregate(v=Sum('net_amount'))['v'] or 0),
        'pending_earnings': float(earnings.filter(payout_status='pending').aggregate(v=Sum('net_amount'))['v'] or 0),
        'response_time': response_time_stats(request.user),
        'open_disputes': dispute_counts(request.user)['open'],
    }, 'today_appointments': [_appointment_row(x) for x in today_items],
       'pending_follow_ups': [{'id': str(x.id), 'consultation_id': str(x.consultation_id), 'scheduled_date': x.scheduled_date.isoformat(), 'scheduled_time': x.scheduled_time.strftime('%H:%M') if x.scheduled_time else None, 'farmer_name': x.consultation.farmer.full_name} for x in followups[:10]]})


def _profile_row(p):
    return {'id': str(p.user_id), 'profile_id': str(p.id), 'name': p.user.full_name, 'email': p.user.email,
            'phone': p.user.phone, 'specialty': p.specialty, 'license_no': p.license_number,
            'rating': float(p.rating or 0), 'total_ratings': p.user.doctor_consultations.exclude(rating=None).count(),
            'is_verified': bool(p.is_verified), 'availability': p.availability_status or ('available' if p.is_available else 'offline'),
            'clinic': p.clinic_hospital_name, 'practice_address': p.practice_address,
            'consultation_mode': p.consultation_mode, 'service_fee': float(p.service_fee or 0),
            'poultry_focus_area': p.poultry_focus_area, 'emergency_on_call_availability': bool(p.emergency_on_call_availability)}


@api_view(['GET', 'PATCH'])
@permission_classes([IsDoctor])
def profile(request):
    item = _doctor_profile(request.user)
    if request.method == 'PATCH':
        serializer = ProfileSerializer(data=request.data); serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        availability = data.pop('availability', None)
        for key, value in data.items(): setattr(item, key, value)
        if availability:
            item.availability_status = availability; item.is_available = availability == 'available'
        item.save()
    return Response(_profile_row(item))


@api_view(['GET'])
@permission_classes([IsDoctor])
def appointments(request):
    qs = Consultation.objects.filter(doctor=request.user).select_related('farmer').order_by('appointment_date', 'appointment_time')
    if request.query_params.get('status'): qs = qs.filter(status=request.query_params['status'].replace('pending', 'requested'))
    return Response({'appointments': [_appointment_row(x) for x in qs]})


@api_view(['POST'])
@permission_classes([IsDoctor])
@transaction.atomic
def appointment_action(request, appointment_id):
    serializer = AppointmentActionSerializer(data=request.data); serializer.is_valid(raise_exception=True)
    item = get_object_or_404(
        Consultation.objects.select_for_update(), id=appointment_id, doctor=request.user,
    )
    action = serializer.validated_data['action']
    allowed = {'accept': ('requested',), 'reject': ('requested',), 'reschedule': ('requested', 'accepted'), 'start': ('accepted',), 'complete': ('accepted', 'in_progress'), 'no_show': ('accepted',)}
    if item.status not in allowed[action]: return Response({'detail': f'Cannot {action} a {item.status} appointment.'}, status=409)
    reason = serializer.validated_data.get('reason', '')
    if action == 'accept':
        conversation, _ = accept_consultation(item, request.user)
        return Response({**_appointment_row(item), 'conversation_id': str(conversation.id)})
    target = {'reject': 'rejected', 'reschedule': 'reschedule_proposed', 'start': 'in_progress', 'complete': 'completed', 'no_show': 'no_show'}[action]
    if action == 'reschedule':
        item.proposed_date = serializer.validated_data['appointment_date']; item.proposed_time = serializer.validated_data['appointment_time']
        ensure_published_availability(item, item.proposed_date, item.proposed_time)
        ensure_slot_available(item, item.proposed_date, item.proposed_time)
    record_transition(item, request.user, target, reason)
    if action == 'complete':
        CaseDetail.objects.filter(consultation=item).update(case_status='closed')
        ensure_cash_receipt(item)
    if action == 'complete':
        notify(item.farmer, 'Clinical results ready',
               f'Your consultation with {request.user.full_name or request.user.email} is complete. Clinical results are now available.', item)
    else:
        notify(item.farmer, f'Consultation {action}', f'Your consultation with {request.user.full_name} was updated: {target.replace("_", " ")}.', item)
    return Response(_appointment_row(item))


@api_view(['GET', 'POST', 'PATCH'])
@permission_classes([IsDoctor])
@transaction.atomic
def cases(request, case_id=None):
    if request.method == 'GET':
        qs = CaseDetail.objects.filter(consultation__doctor=request.user).select_related('consultation__farmer').order_by('-created_at')
        return Response({'cases': [_case_row(x) for x in qs]})
    serializer = CaseSerializer(data=request.data); serializer.is_valid(raise_exception=True); data = serializer.validated_data
    consultation = get_object_or_404(Consultation, id=data.pop('consultation_id'), doctor=request.user)
    case = get_object_or_404(CaseDetail, id=case_id, consultation__doctor=request.user) if case_id else CaseDetail.objects.filter(consultation=consultation).first()
    if case_id and case.consultation_id != consultation.id:
        return Response({'detail': 'consultation_id does not match this case.'}, status=400)
    detail_fields = ('farm_name', 'flock_id', 'bird_age', 'breed', 'flock_count', 'mortality_count', 'feed_notes', 'vaccine_history', 'biosecurity_notes', 'disease_tags')
    defaults = {k: data[k] for k in detail_fields if k in data}; defaults['symptoms_description'] = '\n'.join(data.get('symptoms', [])); defaults['case_status'] = data.get('status', case.case_status if case else 'open')
    case, _ = CaseDetail.objects.update_or_create(consultation=consultation, defaults=defaults)
    if any(k in data for k in ('diagnosis', 'treatment_plan', 'warnings', 'next_steps', 'symptoms')):
        note = ConsultationNote.objects.filter(consultation=consultation, doctor=request.user).order_by('-created_at').first()
        values = {'symptoms': defaults['symptoms_description'], 'diagnosis': data.get('diagnosis', ''), 'treatment_plan': data.get('treatment_plan', ''), 'warnings': data.get('warnings', ''), 'next_steps': data.get('next_steps', '')}
        if note:
            for key, value in values.items(): setattr(note, key, value)
            note.save()
        else:
            ConsultationNote.objects.create(consultation=consultation, doctor=request.user, **values)
    return Response(_case_row(case), status=status.HTTP_201_CREATED if request.method == 'POST' else 200)


@api_view(['GET', 'POST'])
@permission_classes([IsDoctor])
@transaction.atomic
def prescriptions(request):
    if request.method == 'GET':
        qs = ClinicalPrescription.objects.filter(doctor=request.user).select_related('consultation__case_detail').prefetch_related('items').order_by('-created_at')
        return Response({'prescriptions': [_prescription_row(x) for x in qs]})
    if not _doctor_profile(request.user).prescription_authority: return Response({'detail': 'Prescription authority has not been approved.'}, status=403)
    serializer = PrescriptionSerializer(data=request.data); serializer.is_valid(raise_exception=True); data = serializer.validated_data
    consultation = get_object_or_404(
        Consultation.objects.select_for_update(), id=data.pop('consultation_id'), doctor=request.user)
    if consultation.status != 'completed':
        return Response({'detail': 'Complete the consultation before issuing its prescription.'}, status=409)
    follow_up = None
    if data.get('follow_up_date'):
        scheduled = timezone.make_aware(datetime.combine(
            data['follow_up_date'], data['follow_up_time']))
        if scheduled <= timezone.now():
            return Response({'detail': 'Follow-up time must be in the future.'}, status=400)
        consultation.farmer.__class__.objects.select_for_update().get(
            id=consultation.farmer_id)
        DoctorProfile.objects.select_for_update().get(user=request.user)
        follow_up = FollowUp.objects.filter(
            consultation=consultation, status='pending').first()
        conflict_owner = Q(doctor=request.user) | Q(
            consultation__farmer=consultation.farmer)
        if FollowUp.objects.filter(
            scheduled_date=data['follow_up_date'],
            scheduled_time=data['follow_up_time'], status='pending').filter(
                conflict_owner).exclude(id=follow_up.id if follow_up else None).exists():
            return Response({'detail': 'The doctor or farmer is busy at this follow-up time.'}, status=409)
        if Consultation.objects.filter(
            appointment_date=data['follow_up_date'],
            appointment_time=data['follow_up_time'],
            status__in=('requested', 'accepted', 'in_progress')).filter(
                Q(doctor=request.user) | Q(farmer=consultation.farmer)).exists():
            return Response({'detail': 'The doctor or farmer has a consultation at this time.'}, status=409)
    item = ClinicalPrescription.objects.create(
        consultation=consultation, doctor=request.user,
        dosage_notes=data.get('dosage_notes'), case_advice=data['case_advice'],
        follow_up_instructions=data.get('follow_up_instructions'), referred_to=data.get('referred_to'))
    PrescriptionItem.objects.bulk_create([PrescriptionItem(prescription=item, medicine_name=x['name'], dosage=x['dosage'], duration=x['duration'], instructions=x.get('notes')) for x in data['medicines']])
    if data.get('follow_up_date'):
        follow_values = {
            'doctor': request.user, 'scheduled_date': data['follow_up_date'],
            'scheduled_time': data['follow_up_time'],
            'notes': data.get('follow_up_notes') or data.get('follow_up_instructions')}
        if follow_up:
            for key, value in follow_values.items(): setattr(follow_up, key, value)
            follow_up.save()
        else:
            FollowUp.objects.create(consultation=consultation, **follow_values)
        _notify(consultation.farmer, 'Follow-up scheduled',
                f'Follow-up scheduled for {data["follow_up_date"]} at {data["follow_up_time"].strftime("%H:%M")}.',
                consultation, 'follow_up')
    _notify(consultation.farmer, 'Prescription added', f'{request.user.full_name} added a prescription.', consultation, 'prescription')
    from .prescription_pdf import deliver_prescription_email
    transaction.on_commit(lambda: deliver_prescription_email(item.id), robust=True)
    saved = ClinicalPrescription.objects.select_related('consultation__case_detail').prefetch_related('items').get(id=item.id)
    return Response(_prescription_row(saved), status=201)


@api_view(['GET', 'POST', 'PATCH'])
@permission_classes([IsDoctor])
@transaction.atomic
def followups(request):
    qs = FollowUp.objects.filter(consultation__doctor=request.user).select_related('consultation__farmer').order_by('scheduled_date')
    if request.method == 'GET': return Response({'follow_ups': [{'id': str(x.id), 'consultation_id': str(x.consultation_id), 'scheduled_date': x.scheduled_date.isoformat(), 'scheduled_time': x.scheduled_time.strftime('%H:%M') if x.scheduled_time else None, 'status': x.status, 'notes': x.notes, 'farmer_name': x.consultation.farmer.full_name} for x in qs]})
    if request.method == 'PATCH':
        item = get_object_or_404(qs, id=request.data.get('id')); new_status = request.data.get('status')
        if new_status not in ('pending', 'completed', 'missed'): return Response({'detail': 'Invalid follow-up status.'}, status=400)
        item.status = new_status; item.save(); return Response({'id': str(item.id), 'status': item.status})
    serializer = FollowUpSerializer(data=request.data); serializer.is_valid(raise_exception=True); data = serializer.validated_data
    consultation = get_object_or_404(
        Consultation.objects.select_for_update().select_related('farmer'),
        id=data.pop('consultation_id'), doctor=request.user)
    scheduled = timezone.make_aware(datetime.combine(
        data['scheduled_date'], data['scheduled_time']))
    if scheduled <= timezone.now():
        return Response({'detail': 'Follow-up time must be in the future.'}, status=400)
    consultation.farmer.__class__.objects.select_for_update().get(
        id=consultation.farmer_id)
    DoctorProfile.objects.select_for_update().get(user=request.user)
    existing = FollowUp.objects.filter(
        consultation=consultation, status='pending').first()
    owner_conflict = Q(doctor=request.user) | Q(consultation__farmer=consultation.farmer)
    if FollowUp.objects.filter(
        scheduled_date=data['scheduled_date'], scheduled_time=data['scheduled_time'],
        status='pending').filter(owner_conflict).exclude(
            id=existing.id if existing else None).exists():
        return Response({'detail': 'The doctor or farmer already has a follow-up at this time.'}, status=409)
    if Consultation.objects.filter(
        appointment_date=data['scheduled_date'], appointment_time=data['scheduled_time'],
        status__in=('requested', 'accepted', 'in_progress')).filter(
            Q(doctor=request.user) | Q(farmer=consultation.farmer)).exists():
        return Response({'detail': 'The doctor or farmer already has a consultation at this time.'}, status=409)
    try:
        with transaction.atomic():
            if existing:
                existing.scheduled_date = data['scheduled_date']
                existing.scheduled_time = data['scheduled_time']
                existing.notes = data.get('notes', existing.notes)
                existing.doctor = request.user
                existing.save()
                item = existing
            else:
                item = FollowUp.objects.create(
                    consultation=consultation, doctor=request.user, **data)
    except IntegrityError:
        return Response(
            {'detail': 'This follow-up slot was reserved by another request.'},
            status=409)
    case = CaseDetail.objects.filter(consultation=consultation).first()
    if case: case.case_status = 'follow_up'; case.save()
    _notify(consultation.farmer, 'Follow-up scheduled', f'Follow-up scheduled for {item.scheduled_date} at {item.scheduled_time.strftime("%H:%M")}.', consultation, 'follow_up')
    return Response({'id': str(item.id), 'scheduled_date': item.scheduled_date.isoformat(), 'scheduled_time': item.scheduled_time.strftime('%H:%M')}, status=201 if not existing else 200)


@api_view(['GET', 'POST', 'DELETE'])
@permission_classes([IsDoctor])
@transaction.atomic
def availability(request):
    qs = AvailabilitySlot.objects.filter(doctor=request.user, is_active=True).order_by('weekday', 'start_time')
    if request.method == 'GET':
        return Response({'slots': [{'id': str(x.id), 'weekday': x.weekday, 'start_time': x.start_time.strftime('%H:%M'), 'end_time': x.end_time.strftime('%H:%M'), 'mode': x.mode} for x in qs]})
    if request.method == 'DELETE':
        item = get_object_or_404(qs, id=request.data.get('id')); item.is_active = False; item.save(update_fields=['is_active'])
        return Response(status=204)
    # Serialize schedule edits for this doctor so simultaneous submissions
    # cannot both pass the overlap check.
    request.user.__class__.objects.select_for_update().get(id=request.user.id)
    serializer = AvailabilitySlotSerializer(data=request.data); serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    if qs.filter(weekday=data['weekday'], start_time__lt=data['end_time'], end_time__gt=data['start_time']).exists():
        return Response({'detail': 'This availability slot overlaps an existing slot.'}, status=409)
    item = AvailabilitySlot.objects.create(doctor=request.user, **data)
    return Response({'id': str(item.id)}, status=201)


@api_view(['GET', 'POST'])
@permission_classes([IsDoctor])
def earnings(request):
    qs = DoctorEarning.objects.filter(doctor=request.user).select_related('consultation__farmer').order_by('-created_at')
    if request.method == 'POST':
        serializer = PayoutSerializer(data=request.data); serializer.is_valid(raise_exception=True); amount = serializer.validated_data['amount']
        available = qs.filter(payout_status='pending').aggregate(v=Sum('net_amount'))['v'] or 0
        if amount > available: return Response({'detail': 'Amount exceeds available balance.'}, status=400)
        item = PayoutRequest.objects.create(doctor=request.user, amount=amount); return Response({'id': str(item.id), 'status': item.status}, status=201)
    consultations = Consultation.objects.filter(doctor=request.user, rating__isnull=False).select_related('farmer')
    totals = qs.aggregate(gross=Sum('gross_amount'), platform=Sum('platform_fee'), net=Sum('net_amount'))
    type_breakdown = qs.values('consultation__mode', 'consultation__urgency_level').annotate(
        consultation_count=Count('id'), gross=Sum('gross_amount'),
        platform=Sum('platform_fee'), net=Sum('net_amount')).order_by(
            'consultation__mode', 'consultation__urgency_level')
    return Response({'earnings': [{'id': str(x.id), 'farmer_name': x.consultation.farmer.full_name, 'case_id': str(x.consultation_id), 'amount': float(x.net_amount), 'gross_amount': float(x.gross_amount), 'platform_fee': float(x.platform_fee), 'date': x.created_at.isoformat(), 'payment_received': True, 'payment_received_at': x.created_at.isoformat(), 'is_paid': x.payout_status == 'paid', 'payout_status': x.payout_status, 'description': f'{x.consultation.mode.title()} {x.consultation.urgency_level} consultation'} for x in qs],
        'summary': {'consultations_handled': qs.count(), 'gross_amount': float(totals['gross'] or 0), 'platform_charge': float(totals['platform'] or 0), 'net_amount': float(totals['net'] or 0),
                    'by_type': [{'mode': x['consultation__mode'], 'urgency': x['consultation__urgency_level'], 'consultation_count': x['consultation_count'], 'gross_amount': float(x['gross'] or 0), 'platform_charge': float(x['platform'] or 0), 'net_amount': float(x['net'] or 0)} for x in type_breakdown]},
        'ratings': [{'id': str(x.id), 'farmer_name': x.farmer.full_name, 'rating': float(x.rating), 'review': x.review_text, 'date': (x.rated_at or x.updated_at).isoformat()} for x in consultations]})


@api_view(['GET'])
@permission_classes([IsDoctor])
def conversations(request):
    qs = Conversation.objects.filter(Q(participant_one=request.user) | Q(participant_two=request.user)).select_related('participant_one', 'participant_two', 'consultation').order_by('-last_message_at')
    rows=[]
    for x in qs:
        other=x.participant_two if x.participant_one_id==request.user.id else x.participant_one
        messages=x.messages.order_by('sent_at'); rows.append({'id':str(x.id),'farmer_name':other.full_name,'farm_name':_farm_name(other),'case_id':str(x.consultation_id) if x.consultation_id else None,'last_message':messages.last().content if messages.exists() else None,'last_message_at':(x.last_message_at or x.created_at).isoformat(),'unread_count':messages.exclude(sender=request.user).filter(is_read=False).count(),'messages':[{'id':str(m.id),'from_doctor':m.sender_id==request.user.id,'content':m.content or m.file_url or '','type':m.message_type,'sent_at':m.sent_at.isoformat()} for m in messages]})
    return Response({'conversations':rows})


@api_view(['POST', 'PATCH'])
@permission_classes([IsDoctor])
def conversation_detail(request, conversation_id):
    item=get_object_or_404(Conversation.objects.filter(Q(participant_one=request.user)|Q(participant_two=request.user)),id=conversation_id)
    if request.method=='PATCH': item.messages.exclude(sender=request.user).filter(is_read=False).update(is_read=True); return Response({'unread_count':0})
    serializer=MessageSerializer(data=request.data); serializer.is_valid(raise_exception=True)
    message=Message.objects.create(conversation=item,sender=request.user,**serializer.validated_data); item.last_message_at=message.sent_at; item.save()
    other=item.participant_two if item.participant_one_id==request.user.id else item.participant_one; _notify(other,'New message',f'New message from {request.user.full_name}.',item,'conversation')
    payload = {'id': str(message.id), 'conversation_id': str(item.id), 'sender_id': str(request.user.id),
               'content': message.content or message.file_url or '', 'message_type': message.message_type,
               'file_url': message.file_url, 'is_read': False, 'sent_at': message.sent_at.isoformat()}
    emit_to_conversation(item.id, 'message_created', payload)
    return Response(payload, status=201)


# ── video consultations (Jitsi room; no native SDK) ──────────────────────────

def _video_room(consultation):
    return consultation.video_room or f'featherflow-vet-{consultation.id.hex[:18]}'


def _video_state(consultation):
    room = _video_room(consultation)
    active = bool(consultation.video_started_at and not consultation.video_ended_at)
    return {
        'room': room,
        'room_url': f'{settings.JITSI_BASE_URL}/{room}',
        'active': active,
        'started_at': consultation.video_started_at.isoformat() if consultation.video_started_at else None,
        'ended_at': consultation.video_ended_at.isoformat() if consultation.video_ended_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsDoctor])
@transaction.atomic
def video(request, appointment_id):
    item = get_object_or_404(
        Consultation.objects.select_for_update(), id=appointment_id, doctor=request.user)
    if request.method == 'GET':
        return Response(_video_state(item))
    if item.mode != 'online':
        return Response({'detail': 'Video calls are only for online consultations.'}, status=409)
    if item.status not in ('accepted', 'in_progress'):
        return Response({'detail': f'Cannot start a video call for a {item.status} consultation.'}, status=409)
    action = request.data.get('action', 'start')
    conversation = Conversation.objects.filter(
        Q(participant_one=item.farmer, participant_two=item.doctor)
        | Q(participant_one=item.doctor, participant_two=item.farmer)).first()
    if action == 'end':
        item.video_ended_at = timezone.now()
        item.save(update_fields=['video_ended_at', 'updated_at'])
        if conversation:
            emit_to_conversation(conversation.id, 'video_call', {'state': 'ended', 'consultation_id': str(item.id)})
        return Response(_video_state(item))

    item.video_room = _video_room(item)
    item.video_started_at = timezone.now()
    item.video_ended_at = None
    if item.status == 'accepted':
        item.status = 'in_progress'
    item.save(update_fields=['video_room', 'video_started_at', 'video_ended_at', 'status', 'updated_at'])
    state = _video_state(item)
    _notify(item.farmer, 'Video call started',
            f'{request.user.full_name or request.user.email} started your video consultation. Tap to join.', item)
    if conversation:
        emit_to_conversation(conversation.id, 'video_call', {'state': 'started', 'consultation_id': str(item.id), **state})
    return Response(state)


# ── consultation disputes (doctor side) ─────────────────────────────────────

def _dispute_row(d):
    return {
        'id': str(d.id), 'consultation_id': str(d.consultation_id),
        'raised_by_role': d.raised_role,
        'raised_by': d.raised_by.full_name or d.raised_by.email,
        'category': d.category, 'description': d.description,
        'status': d.status, 'resolution': d.resolution,
        'created_at': d.created_at.isoformat() if d.created_at else None,
        'resolved_at': d.resolved_at.isoformat() if d.resolved_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsDoctor])
@transaction.atomic
def disputes(request):
    if request.method == 'GET':
        qs = ConsultationDispute.objects.filter(
            consultation__doctor=request.user).select_related('raised_by').order_by('-created_at')
        return Response({'disputes': [_dispute_row(d) for d in qs]})

    consultation = get_object_or_404(
        Consultation, id=request.data.get('consultation_id'), doctor=request.user)
    category = request.data.get('category')
    description = str(request.data.get('description', '')).strip()
    valid = {c for c, _ in ConsultationDispute.CATEGORY_CHOICES}
    if category not in valid:
        return Response({'detail': f'category must be one of {sorted(valid)}.'}, status=400)
    if len(description) < 10:
        return Response({'detail': 'Describe the issue in at least 10 characters.'}, status=400)
    now = timezone.now()
    dispute = ConsultationDispute.objects.create(
        consultation=consultation, raised_by=request.user, raised_role='doctor',
        category=category, description=description, status='open', created_at=now, updated_at=now)
    _notify_doctor_admins('New consultation dispute',
                          f'A doctor raised a {category.replace("_", " ")} dispute on a consultation.',
                          dispute.id)
    return Response(_dispute_row(dispute), status=201)


def _notify_doctor_admins(title, body, reference_id):
    from users.models import User

    for admin in User.objects.filter(
            roles__name__in=['admin_doctor', 'admin_operations', 'admin_super', 'admin']).distinct():
        Notification.objects.create(
            user=admin, title=title, body=body, notification_type='alert',
            reference_id=reference_id, reference_type='consultation_dispute')


# ── prescription email resend ──────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsDoctor])
def resend_prescription_email(request, prescription_id):
    prescription = get_object_or_404(
        ClinicalPrescription, id=prescription_id, doctor=request.user)
    if not prescription.consultation.farmer.email:
        return Response({'detail': 'This farmer has no email address on file.'}, status=409)
    from .prescription_pdf import deliver_prescription_email

    deliver_prescription_email(prescription.id)
    prescription.refresh_from_db()
    return Response({
        'email_sent_at': prescription.email_sent_at.isoformat() if prescription.email_sent_at else None,
        'email_error': prescription.email_error,
    })
