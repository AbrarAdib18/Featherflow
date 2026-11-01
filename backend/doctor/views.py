from datetime import date, datetime

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Count, F, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from consultations.models import Consultation, ConsultationDispute
from consultations.metrics import dispute_counts, response_time_stats
from messaging.chat import (ClientMessageIdConflict, aware_utc, deliver_message, iso_utc,
                           message_payload, ordered_messages)
from messaging.realtime import emit_to_conversation
from notifications.models import Notification
from profiles.models import DoctorProfile, FarmerProfile

from .models import (
    AvailabilitySlot, CaseDetail, ClinicalPrescription, Conversation,
    DoctorEarning, FollowUp, Message, PayoutRequest, PrescriptionItem,
)
from .prescriptions import delivery_fields
from .ratings import rating_summary
from .case_workflow import (CaseFieldsSerializer, CaseWorkflowError, case_stage,
                            latest_note, update_case)
from .permissions import IsDoctor
from .serializers import (
    AppointmentActionSerializer, AvailabilitySlotSerializer, FollowUpSerializer,
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
        # Null for an open-ended request: the farmer named no preferred slot and
        # the doctor proposes one when accepting.
        'scheduled_at': (f'{item.appointment_date.isoformat()}T{item.appointment_time.strftime("%H:%M:%S")}'
                         if item.appointment_date and item.appointment_time else None),
        'has_preferred_slot': bool(item.appointment_date and item.appointment_time),
        'mode': item.mode, 'status': 'pending' if item.status == 'requested' else item.status,
        'urgency': item.urgency_level, 'is_urgent': item.urgency_level in ('urgent', 'emergency'),
        'case_id': str(case.id) if case else None, 'fee': float(item.consultation_fee or 0),
        'proposed_date': item.proposed_date.isoformat() if item.proposed_date else None,
        'proposed_time': item.proposed_time.strftime('%H:%M') if item.proposed_time else None,
        'decision_reason': item.decision_reason,
        # When the farmer submitted it — an open-ended request has no slot, so
        # this is the only time it has. Naive UTC column, returned aware (same
        # convention as notifications/serializers.py).
        'requested_at': _aware_iso(item.created_at),
    }


def _aware_iso(dt):
    if dt is None:
        return None
    if timezone.is_naive(dt):
        from datetime import timezone as _tz
        dt = dt.replace(tzinfo=_tz.utc)
    return dt.isoformat()


def _prescription_row(item):
    # a consultation can legitimately have no case-detail row (e.g. seeded / legacy data): that used to 500
    # AFTER the prescription transaction, so the doctor saw an error and nothing was saved
    case = getattr(item.consultation, 'case_detail', None)
    return {
        'id': str(item.id), 'consultation_id': str(item.consultation_id),
        'case_id': str(case.id) if case else None,
        'medicines': [{'name': x.medicine_name, 'dosage': x.dosage, 'duration': x.duration, 'notes': x.instructions} for x in item.items.all()],
        'dosage_notes': item.dosage_notes, 'case_advice': item.case_advice,
        'follow_up_instructions': item.follow_up_instructions,
        'referred_to': item.referred_to, 'created_at': iso_utc(item.created_at),
        'pdf_url': f'/api/consultations/prescriptions/{item.id}/pdf/',
        'email_sent_at': iso_utc(item.email_sent_at) if item.email_sent_at else None,
        **delivery_fields(item),
    }


def _case_row(case):
    consultation = case.consultation
    note = latest_note(consultation)
    prescriptions = list(consultation.clinical_prescriptions.prefetch_related('items').order_by('-created_at'))
    prescription = prescriptions[0] if prescriptions else None
    follow_up = consultation.follow_ups.filter(status='pending').order_by('scheduled_date').first()
    symptoms = [x.strip() for x in (case.symptoms_description or '').split('\n') if x.strip()]
    try:
        age = int(''.join(c for c in (case.bird_age or '') if c.isdigit()) or 0)
    except ValueError:
        age = 0
    stage = case_stage(case, consultation, has_prescription=bool(prescriptions))
    return {
        'id': str(case.id), 'appointment_id': str(consultation.id),
        'farmer_name': case.farmer_name or consultation.farmer.full_name or consultation.farmer.email,
        'farm_name': case.farm_name or _farm_name(consultation.farmer), 'flock_size': case.flock_count or 0,
        'bird_age_weeks': age, 'breed': case.breed or '', 'mortality_count': case.mortality_count or 0,
        'symptoms': symptoms, 'diagnosis': note.diagnosis if note else None,
        'treatment_plan': note.treatment_plan if note else None, 'disease_tags': case.disease_tags or [],
        'urgency': consultation.urgency_level, 'status': case.case_status,
        # Case page workflow (doctor/case_workflow.py): what the page shows
        # and what the server will accept for this case right now.
        'stage': stage, 'editable': stage == 'open',
        'consultation_status': consultation.status, 'mode': consultation.mode,
        'scheduled_at': (f'{consultation.appointment_date.isoformat()}T{consultation.appointment_time.strftime("%H:%M:%S")}'
                         if consultation.appointment_date and consultation.appointment_time else None),
        'updated_at': iso_utc(max(aware_utc(x) for x in (case.updated_at, note.updated_at if note else None) if x)),
        'feed_notes': case.feed_notes, 'vaccine_history': case.vaccine_history,
        'farmer_notes': case.farmer_notes,
        'biosecurity_notes': case.biosecurity_notes, 'warnings': note.warnings if note else None,
        'next_steps': note.next_steps if note else None, 'created_at': case.created_at.isoformat(),
        'follow_up_date': (f'{follow_up.scheduled_date.isoformat()}T'
                           f'{follow_up.scheduled_time.strftime("%H:%M:%S")}'
                           if follow_up and follow_up.scheduled_time else
                           follow_up.scheduled_date.isoformat() if follow_up else None),
        'prescription': _prescription_row(prescription) if prescription else None,
        'prescription_count': len(prescriptions),
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
    ratings = rating_summary(request.user)
    return Response({'profile': _profile_row(profile, ratings), 'summary': {
        'total_clients': qs.values('farmer_id').distinct().count(), 'today_appointments': today_items.count(),
        # Case work not finished: accepted / in-progress consultations (open, or
        # closed and awaiting "Mark as Complete").
        'active_cases': cases.filter(consultation__status__in=('accepted', 'in_progress')).count(),
        # Completed = the consultation was marked complete. A closed case is
        # still awaiting "Mark as Complete" on its Case page.
        'completed_cases': cases.filter(consultation__status='completed').count(),
        'urgent_requests': qs.filter(status='requested', urgency_level__in=('urgent', 'emergency')).count(),
        'unread_messages': unread, 'pending_follow_ups': followups.count(),
        # Live from the consultations (doctor/ratings.py), never the stored copy.
        'rating': ratings['average'], 'total_ratings': ratings['count'],
        'gross_earnings': float(earnings.aggregate(v=Sum('gross_amount'))['v'] or 0),
        'monthly_gross_earnings': float(earnings.filter(created_at__year=date.today().year, created_at__month=date.today().month).aggregate(v=Sum('gross_amount'))['v'] or 0),
        'monthly_earnings': float(earnings.filter(created_at__year=date.today().year, created_at__month=date.today().month).aggregate(v=Sum('net_amount'))['v'] or 0),
        'pending_earnings': float(earnings.filter(payout_status='pending').aggregate(v=Sum('net_amount'))['v'] or 0),
        'response_time': response_time_stats(request.user),
        'open_disputes': dispute_counts(request.user)['open'],
        # Authoritative per-status counts, one aggregate query over the same
        # `doctor=request.user` queryset the request queue uses. `requested`
        # includes open-ended requests (no appointment_date), which no counter
        # covered before. See DOCTOR_CONSULTATION_QUEUE_FIX.md.
        'pending_requests': qs.filter(status='requested').count(),
        'consultation_counts': dict(qs.values_list('status').annotate(n=Count('id'))),
    }, 'today_appointments': [_appointment_row(x) for x in today_items],
       'pending_follow_ups': [{'id': str(x.id), 'consultation_id': str(x.consultation_id), 'scheduled_date': x.scheduled_date.isoformat(), 'scheduled_time': x.scheduled_time.strftime('%H:%M') if x.scheduled_time else None, 'farmer_name': x.consultation.farmer.full_name} for x in followups[:10]]})


def _profile_row(p, ratings=None):
    # Rating and count from the same live query (doctor/ratings.py): the stored
    # DoctorProfile.rating could be stale (0.00 while 7 real ratings existed).
    ratings = ratings or rating_summary(p.user)
    return {'id': str(p.user_id), 'profile_id': str(p.id), 'name': p.user.full_name, 'email': p.user.email,
            'phone': p.user.phone, 'specialty': p.specialty, 'license_no': p.license_number,
            'rating': ratings['average'], 'total_ratings': ratings['count'],
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
    if request.query_params.get('scope') == 'schedule':
        # The Schedule page: incoming requests and upcoming appointments only.
        # Completed / closed / ended consultations are case history and live
        # on the Case pages. See DOCTOR_SCHEDULE_PAGE_AUDIT.md.
        requests = [_appointment_row(x) for x in qs.filter(status__in=SCHEDULE_REQUEST_STATUSES)]
        upcoming = [_appointment_row(x) for x in qs.filter(status__in=SCHEDULE_UPCOMING_STATUSES)]
        return Response({'requests': requests, 'upcoming': upcoming, 'appointments': requests + upcoming})
    if request.query_params.get('status'): qs = qs.filter(status=request.query_params['status'].replace('pending', 'requested'))
    return Response({'appointments': [_appointment_row(x) for x in qs]})


# Mirrored by DoctorAppointment.scheduleSection in Flutter.
SCHEDULE_REQUEST_STATUSES = ('requested', 'reschedule_proposed')
SCHEDULE_UPCOMING_STATUSES = ('accepted', 'in_progress')


@api_view(['POST'])
@permission_classes([IsDoctor])
@transaction.atomic
def appointment_action(request, appointment_id):
    serializer = AppointmentActionSerializer(data=request.data); serializer.is_valid(raise_exception=True)
    item = get_object_or_404(
        Consultation.objects.select_for_update(), id=appointment_id, doctor=request.user,
    )
    action = serializer.validated_data['action']
    if action == 'complete' and item.status == 'completed':
        # Idempotent: a repeated "Mark as Complete" (double tap, retry after a
        # lost response) returns the completed row without re-running the
        # history/receipt/notification side effects.
        return Response({**_appointment_row(item), 'already_completed': True})
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
    owned = CaseDetail.objects.filter(consultation__doctor=request.user).select_related('consultation__farmer')
    if request.method == 'GET':
        if case_id:  # the Case page's own reload
            return Response(_case_row(get_object_or_404(owned, id=case_id)))
        return Response({'cases': [_case_row(x) for x in owned.order_by('-created_at')]})
    # Partial update: only the fields sent are changed (this used to blank
    # every omitted clinical field). Stage rules: doctor/case_workflow.py.
    serializer = CaseFieldsSerializer(data=request.data)
    if not serializer.is_valid():
        return Response({'detail': 'Some case fields are invalid.', 'code': 'invalid',
                         'errors': {k: ' '.join(str(m) for m in v) if isinstance(v, list) else str(v)
                                    for k, v in serializer.errors.items()}}, status=400)
    data = dict(serializer.validated_data)
    consultation_id = data.pop('consultation_id', None)
    if case_id:
        case = get_object_or_404(owned, id=case_id)
        if consultation_id and case.consultation_id != consultation_id:
            return Response({'detail': 'consultation_id does not match this case.'}, status=400)
    else:
        if not consultation_id:
            return Response({'detail': 'consultation_id is required.',
                             'errors': {'consultation_id': 'Required.'}}, status=400)
        consultation = get_object_or_404(Consultation, id=consultation_id, doctor=request.user)
        case = CaseDetail.objects.filter(consultation=consultation).first() or CaseDetail.objects.create(
            consultation=consultation, farmer_name=consultation.farmer.full_name or consultation.farmer.email,
            farm_name=_farm_name(consultation.farmer), case_status='open')
    try:
        case = update_case(case, request.user, data)
    except CaseWorkflowError as error:
        return Response(error.payload(), status=error.status)
    return Response(_case_row(case), status=status.HTTP_201_CREATED if request.method == 'POST' else 200)


@api_view(['GET', 'POST'])
@permission_classes([IsDoctor])
def prescriptions(request):
    if request.method == 'GET':
        qs = ClinicalPrescription.objects.filter(doctor=request.user).select_related('consultation__case_detail', 'doctor').prefetch_related('items').order_by('-created_at')
        return Response({'prescriptions': [_prescription_row(x) for x in qs]})
    # Eligibility: an active doctor (IsDoctor) prescribing for a consultation
    # assigned to them that has been completed. `DoctorProfile.
    # prescription_authority` is NOT a gate at this product stage: no signup
    # or admin path ever set it, so it blocked every real doctor. It is kept
    # for a future compliance approval. See DOCTOR_PRESCRIPTION_AUTHORITY_AUDIT.md.
    serializer = PrescriptionSerializer(data=request.data)
    if not serializer.is_valid():
        return Response({'detail': 'Some prescription fields are invalid.', 'code': 'invalid',
                         'errors': {k: ' '.join(str(m) for m in v) if isinstance(v, list) else str(v)
                                    for k, v in serializer.errors.items()}}, status=400)
    result = _create_prescription(request, dict(serializer.validated_data))
    if isinstance(result, Response):
        return result
    # Committed: the prescription stands whatever happens to the PDF or SMTP.
    from .prescriptions import issue_documents
    issue_documents(result.id)
    saved = ClinicalPrescription.objects.select_related('consultation__case_detail', 'doctor').prefetch_related('items').get(id=result.id)
    return Response(_prescription_row(saved), status=201)


@transaction.atomic
def _create_prescription(request, data):
    """The prescription, its medicines and follow-up, in one transaction.
    Returns the prescription, or a refusal Response (nothing written)."""
    consultation = Consultation.objects.select_for_update().filter(id=data.pop('consultation_id')).first()
    if consultation is None or consultation.doctor_id != request.user.id:
        # Same answer for "no such consultation" and "not yours".
        return Response({'detail': 'Consultation not found.', 'code': 'not_found'}, status=404)
    if consultation.status != 'completed':
        return Response({'detail': 'Complete the consultation before issuing its prescription.',
                         'code': 'consultation_not_completed'}, status=409)
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
    from .prescription_pdf import reference_for
    item.reference_number = reference_for(item)
    item.save(update_fields=['reference_number'])
    _notify(consultation.farmer, 'Prescription added', f'{request.user.full_name} added a prescription.', consultation, 'prescription')
    return item


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
    consultations = Consultation.objects.filter(doctor=request.user, rating__isnull=False).select_related('farmer').order_by(
        F('rated_at').desc(nulls_last=True), '-updated_at')  # newest review first
    totals = qs.aggregate(gross=Sum('gross_amount'), platform=Sum('platform_fee'), net=Sum('net_amount'))
    type_breakdown = qs.values('consultation__mode', 'consultation__urgency_level').annotate(
        consultation_count=Count('id'), gross=Sum('gross_amount'),
        platform=Sum('platform_fee'), net=Sum('net_amount')).order_by(
            'consultation__mode', 'consultation__urgency_level')
    return Response({'earnings': [{'id': str(x.id), 'farmer_name': x.consultation.farmer.full_name, 'case_id': str(x.consultation_id), 'amount': float(x.net_amount), 'gross_amount': float(x.gross_amount), 'platform_fee': float(x.platform_fee), 'date': x.created_at.isoformat(), 'payment_received': True, 'payment_received_at': x.created_at.isoformat(), 'is_paid': x.payout_status == 'paid', 'payout_status': x.payout_status, 'description': f'{x.consultation.mode.title()} {x.consultation.urgency_level} consultation'} for x in qs],
        'summary': {'consultations_handled': qs.count(), 'gross_amount': float(totals['gross'] or 0), 'platform_charge': float(totals['platform'] or 0), 'net_amount': float(totals['net'] or 0),
                    'by_type': [{'mode': x['consultation__mode'], 'urgency': x['consultation__urgency_level'], 'consultation_count': x['consultation_count'], 'gross_amount': float(x['gross'] or 0), 'platform_charge': float(x['platform'] or 0), 'net_amount': float(x['net'] or 0)} for x in type_breakdown]},
        'ratings': [{'id': str(x.id), 'farmer_name': x.farmer.full_name, 'rating': float(x.rating), 'review': x.review_text, 'date': (x.rated_at or x.updated_at).isoformat()} for x in consultations],
        # Average, count and per-star counts of exactly the ratings listed above.
        'rating_summary': rating_summary(request.user)})


@api_view(['GET'])
@permission_classes([IsDoctor])
def conversations(request):
    qs = Conversation.objects.filter(Q(participant_one=request.user) | Q(participant_two=request.user)).select_related('participant_one', 'participant_two', 'consultation').order_by('-last_message_at')
    rows=[]
    for x in qs:
        other=x.participant_two if x.participant_one_id==request.user.id else x.participant_one
        messages=ordered_messages(x); rows.append({'id':str(x.id),'farmer_name':other.full_name,'farm_name':_farm_name(other),'case_id':str(x.consultation_id) if x.consultation_id else None,'last_message':messages.last().content if messages.exists() else None,'last_message_at':iso_utc(x.last_message_at or x.created_at),'unread_count':messages.exclude(sender=request.user).filter(is_read=False).count(),'messages':[{**message_payload(m, request.user.id),'from_doctor':m.sender_id==request.user.id} for m in messages]})
    return Response({'conversations':rows})


@api_view(['POST', 'PATCH'])
@permission_classes([IsDoctor])
def conversation_detail(request, conversation_id):
    item=get_object_or_404(Conversation.objects.filter(Q(participant_one=request.user)|Q(participant_two=request.user)),id=conversation_id)
    if request.method=='PATCH': item.messages.exclude(sender=request.user).filter(is_read=False).update(is_read=True); return Response({'unread_count':0})
    serializer=MessageSerializer(data=request.data); serializer.is_valid(raise_exception=True)
    try:
        message, created = deliver_message(item, request.user, **serializer.validated_data)
    except ClientMessageIdConflict:
        return Response({'detail': 'This client_message_id was already used in another conversation.'}, status=409)
    payload = message_payload(message)
    if created:  # a replayed send was already broadcast once
        emit_to_conversation(item.id, 'message_created', payload)
    return Response({**payload, 'from_me': True, 'from_doctor': True}, status=201 if created else 200)


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
        # Goes through record_transition (not a bare status write) so this
        # accepted->in_progress path logs a ConsultationStatusHistory row
        # like every other transition, including the equivalent 'start'
        # action in appointment_action below.
        record_transition(item, request.user, 'in_progress')
    else:
        item.save(update_fields=['video_room', 'video_started_at', 'video_ended_at', 'updated_at'])
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
    from .prescriptions import deliver_email

    # Deliberate resend by the prescribing doctor (sends even after a success;
    # the app offers it only for a failed delivery). A send already in flight
    # is not duplicated.
    deliver_email(prescription.id, deliberate=True)
    prescription.refresh_from_db()
    return Response({
        'email_sent_at': iso_utc(prescription.email_sent_at) if prescription.email_sent_at else None,
        'email_error': prescription.email_error,
        **delivery_fields(prescription),
    })
