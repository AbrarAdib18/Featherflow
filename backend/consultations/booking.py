from datetime import datetime, timedelta

from django.db import IntegrityError, models, transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from doctor.models import AvailabilitySlot, CaseDetail, FollowUp
from farms.models import Farm, Flock
from profiles.models import DoctorProfile

from .models import Consultation


BLOCKING_STATUSES = ('requested', 'accepted', 'in_progress')
SLOT_MINUTES = 30


def _weekday(value):
    return value.weekday()


def validate_booking(user, data):
    profile = DoctorProfile.objects.select_related('user').filter(
        id=data['doctor_id'], user__account_status='active',
        user__user_roles__role__name='doctor',
    ).distinct().first()
    if not profile:
        raise ValidationError({'doctor_id': 'This doctor is unavailable.'})
    if not profile.is_available or profile.availability_status == 'offline':
        raise ValidationError({'doctor_id': 'This doctor is currently offline.'})
    if profile.consultation_mode not in ('both', data['mode']):
        raise ValidationError({'mode': f'This doctor does not offer {data["mode"]} consultations.'})
    if data['urgency'] == 'emergency' and not profile.emergency_on_call_availability:
        raise ValidationError({'urgency': 'This doctor is not accepting emergency requests.'})

    farm = Farm.objects.filter(id=data['farm_id'], farmer__user=user, is_active=True).first()
    if not farm:
        raise ValidationError({'farm_id': 'Select one of your active farms.'})
    flock = None
    if data.get('flock_id'):
        flock = Flock.objects.filter(id=data['flock_id'], farm=farm, status='active').first()
        if not flock:
            raise ValidationError({'flock_id': 'Select an active flock belonging to this farm.'})
        if data.get('mortality_count', 0) > flock.current_quantity:
            raise ValidationError({'mortality_count': 'Mortality cannot exceed the active flock count.'})

    scheduled = timezone.make_aware(datetime.combine(data['appointment_date'], data['appointment_time']))
    if scheduled <= timezone.now():
        raise ValidationError({'appointment_time': 'Appointment time must be in the future.'})
    end_time = (datetime.combine(data['appointment_date'], data['appointment_time']) + timedelta(minutes=SLOT_MINUTES)).time()
    available = AvailabilitySlot.objects.filter(
        doctor=profile.user, weekday=_weekday(data['appointment_date']), mode=data['mode'], is_active=True,
        start_time__lte=data['appointment_time'], end_time__gte=end_time,
    ).exists()
    if not available:
        raise ValidationError({'appointment_time': 'This time is outside the doctor’s published availability.'})
    return profile, farm, flock


@transaction.atomic
def create_booking(user, data):
    profile, farm, flock = validate_booking(user, data)
    user.__class__.objects.select_for_update().get(id=user.id)
    # Lock the doctor row so simultaneous requests are serialized even before
    # the PostgreSQL unique partial index performs the final conflict check.
    DoctorProfile.objects.select_for_update().get(id=profile.id)
    follow_up_conflict = FollowUp.objects.filter(
        scheduled_date=data['appointment_date'],
        scheduled_time=data['appointment_time'], status='pending',
    ).filter(models.Q(doctor=profile.user) | models.Q(consultation__farmer=user)).exists()
    if follow_up_conflict:
        raise ValidationError({'appointment_time': 'This time is reserved for a scheduled follow-up.'})
    if Consultation.objects.filter(
        doctor=profile.user, appointment_date=data['appointment_date'],
        appointment_time=data['appointment_time'], status__in=BLOCKING_STATUSES,
    ).exists():
        raise ValidationError({'appointment_time': 'This slot was just booked. Please choose another time.'})
    try:
        item = Consultation.objects.create(
            farmer=user, doctor=profile.user, mode=data['mode'], urgency_level=data['urgency'],
            appointment_date=data['appointment_date'], appointment_time=data['appointment_time'],
            consultation_fee=profile.service_fee,
        )
        case_values = initial_case_values(user, farm, flock, data)
        case = CaseDetail.objects.create(
            consultation=item, **case_values,
        )
    except IntegrityError as exc:
        raise ValidationError({'appointment_time': 'This slot was just booked. Please choose another time.'}) from exc
    return item, case


def initial_case_values(user, farm, flock, data):
    bird_age_weeks = (max(0, (data['appointment_date'] - flock.start_date).days // 7)
                      if flock else data['bird_age_weeks'])
    return {
        'flock': flock, 'farm_name': farm.farm_name,
        'farmer_name': user.full_name or user.email,
        'bird_age': f'{bird_age_weeks} weeks',
        'breed': (flock.breed or flock.bird_type or '') if flock else data['breed'],
        'flock_count': flock.current_quantity if flock else data['flock_count'],
        'mortality_count': data.get('mortality_count', 0),
        'feed_notes': data.get('feed_notes', ''),
        'vaccine_history': data.get('vaccine_history', ''),
        'biosecurity_notes': data.get('biosecurity_notes', ''),
        'symptoms_description': '\n'.join(data['symptoms']),
        'farmer_notes': data.get('farmer_notes', ''),
        'disease_tags': [], 'case_status': 'open',
    }


def available_times(profile, target_date, mode, farmer=None):
    slots = AvailabilitySlot.objects.filter(
        doctor=profile.user, weekday=_weekday(target_date), mode=mode, is_active=True,
    ).order_by('start_time')
    blocked = set(Consultation.objects.filter(
        doctor=profile.user, appointment_date=target_date, status__in=BLOCKING_STATUSES,
    ).values_list('appointment_time', flat=True))
    follow_up_owner = models.Q(doctor=profile.user)
    if farmer is not None:
        follow_up_owner |= models.Q(consultation__farmer=farmer)
    follow_up_query = FollowUp.objects.filter(
        scheduled_date=target_date, status='pending').filter(follow_up_owner)
    blocked.update(follow_up_query.values_list('scheduled_time', flat=True))
    result = []
    now = timezone.localtime()
    for slot in slots:
        cursor = datetime.combine(target_date, slot.start_time)
        end = datetime.combine(target_date, slot.end_time)
        while cursor + timedelta(minutes=SLOT_MINUTES) <= end:
            value = cursor.time()
            future = target_date > now.date() or value > now.time().replace(tzinfo=None)
            if future and value not in blocked:
                result.append(value.strftime('%H:%M'))
            cursor += timedelta(minutes=SLOT_MINUTES)
    return sorted(set(result))
