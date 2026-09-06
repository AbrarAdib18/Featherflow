from datetime import datetime, timedelta

from django.db import IntegrityError, transaction
from django.db.models import Q
from rest_framework.exceptions import ValidationError

from doctor.models import (AvailabilitySlot, ConsultationStatusHistory,
                           Conversation, FollowUp)
from notifications.models import Notification

from .booking import BLOCKING_STATUSES
from .models import Consultation


def notify(user, title, body, item, reference_type='consultation'):
    Notification.objects.create(
        user=user, title=title, body=body, notification_type='reminder',
        reference_id=item.id, reference_type=reference_type,
    )


def record_transition(item, actor, to_status, reason=''):
    old = item.status
    item.status = to_status
    item.decision_reason = reason or None
    item.save()
    ConsultationStatusHistory.objects.create(
        consultation=item, actor=actor, from_status=old,
        to_status=to_status, reason=reason or None,
    )


def get_or_create_conversation(item):
    first, second = sorted((item.farmer, item.doctor), key=lambda user: str(user.id))
    conversation = Conversation.objects.filter(
        participant_one=first, participant_two=second,
    ).first()
    if conversation:
        if conversation.consultation_id != item.id:
            conversation.consultation = item
            conversation.save(update_fields=['consultation'])
        return conversation, False
    try:
        # The nested transaction creates a savepoint. If two accept requests race,
        # the database pair index chooses one conversation and this transaction can
        # safely recover the winner without leaving its caller's transaction broken.
        with transaction.atomic():
            conversation = Conversation.objects.create(
                participant_one=first, participant_two=second, consultation=item,
            )
        return conversation, True
    except IntegrityError:
        conversation = Conversation.objects.get(
            participant_one=first, participant_two=second,
        )
        if conversation.consultation_id != item.id:
            conversation.consultation = item
            conversation.save(update_fields=['consultation'])
        return conversation, False


def ensure_slot_available(item, target_date, target_time):
    if Consultation.objects.filter(
        doctor=item.doctor, appointment_date=target_date,
        appointment_time=target_time, status__in=BLOCKING_STATUSES,
    ).exclude(id=item.id).exists():
        raise ValidationError({'appointment_time': 'This doctor slot is no longer available.'})
    if FollowUp.objects.filter(
        scheduled_date=target_date, scheduled_time=target_time,
        status='pending').filter(
            Q(doctor=item.doctor) | Q(consultation__farmer=item.farmer)).exists():
        raise ValidationError({
            'appointment_time': 'The doctor or farmer has a follow-up at this time.'})


def ensure_published_availability(item, target_date, target_time):
    end_time = (datetime.combine(target_date, target_time) + timedelta(minutes=30)).time()
    if not AvailabilitySlot.objects.filter(
        doctor=item.doctor, weekday=target_date.weekday(), mode=item.mode,
        is_active=True, start_time__lte=target_time, end_time__gte=end_time,
    ).exists():
        raise ValidationError({
            'appointment_time': "The proposed time is outside this doctor's published availability."
        })


@transaction.atomic
def accept_consultation(item, actor):
    if item.status != 'requested':
        raise ValidationError({'status': 'Only requested consultations can be accepted.'})
    ensure_slot_available(item, item.appointment_date, item.appointment_time)
    record_transition(item, actor, 'accepted')
    conversation, created = get_or_create_conversation(item)
    notify(item.farmer, 'Consultation accepted',
           f'{item.doctor.full_name or item.doctor.email} accepted your consultation.', item)
    notify(item.doctor, 'Consultation chat ready',
           f'Private chat with {item.farmer.full_name or item.farmer.email} is ready.', conversation, 'conversation')
    return conversation, created
