from datetime import date, datetime, timedelta
from decimal import Decimal

from rest_framework import serializers
from consultations.serializers import ConsultationModeField


class AppointmentActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=('accept', 'reject', 'reschedule', 'start', 'complete', 'no_show'))
    appointment_date = serializers.DateField(required=False)
    appointment_time = serializers.TimeField(required=False)
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)

    def validate(self, attrs):
        if attrs['action'] == 'reschedule' and not {'appointment_date', 'appointment_time'} <= attrs.keys():
            raise serializers.ValidationError('appointment_date and appointment_time are required.')
        return attrs


class CaseSerializer(serializers.Serializer):
    consultation_id = serializers.UUIDField()
    farm_name = serializers.CharField(required=False, allow_blank=True)
    flock_id = serializers.UUIDField(required=False, allow_null=True)
    bird_age = serializers.CharField(required=False, allow_blank=True)
    breed = serializers.CharField(required=False, allow_blank=True)
    flock_count = serializers.IntegerField(required=False, min_value=0)
    mortality_count = serializers.IntegerField(required=False, min_value=0)
    symptoms = serializers.ListField(child=serializers.CharField(), required=False)
    disease_tags = serializers.ListField(child=serializers.CharField(), required=False)
    feed_notes = serializers.CharField(required=False, allow_blank=True)
    vaccine_history = serializers.CharField(required=False, allow_blank=True)
    biosecurity_notes = serializers.CharField(required=False, allow_blank=True)
    diagnosis = serializers.CharField(required=False, allow_blank=True)
    treatment_plan = serializers.CharField(required=False, allow_blank=True)
    warnings = serializers.CharField(required=False, allow_blank=True)
    next_steps = serializers.CharField(required=False, allow_blank=True)
    status = serializers.ChoiceField(choices=('open', 'in_progress', 'follow_up', 'closed'), required=False)


class PrescriptionSerializer(serializers.Serializer):
    consultation_id = serializers.UUIDField()
    medicines = serializers.ListField(child=serializers.DictField(), min_length=1)
    dosage_notes = serializers.CharField(required=False, allow_blank=True)
    case_advice = serializers.CharField(required=True, allow_blank=False)
    follow_up_instructions = serializers.CharField(required=False, allow_blank=True)
    referred_to = serializers.CharField(required=False, allow_blank=True)
    follow_up_date = serializers.DateField(required=False)
    follow_up_time = serializers.TimeField(required=False)
    follow_up_notes = serializers.CharField(required=False, allow_blank=True)

    def validate_medicines(self, items):
        for item in items:
            if not all(str(item.get(k, '')).strip() for k in ('name', 'dosage', 'duration')):
                raise serializers.ValidationError('Each medicine requires name, dosage and duration.')
        return items

    def validate(self, attrs):
        if bool(attrs.get('follow_up_date')) != bool(attrs.get('follow_up_time')):
            raise serializers.ValidationError(
                'follow_up_date and follow_up_time must be provided together.')
        return attrs


class FollowUpSerializer(serializers.Serializer):
    consultation_id = serializers.UUIDField()
    scheduled_date = serializers.DateField()
    scheduled_time = serializers.TimeField()
    notes = serializers.CharField(required=False, allow_blank=True)


class ProfileSerializer(serializers.Serializer):
    availability = serializers.ChoiceField(choices=('available', 'busy', 'offline'), required=False)
    specialty = serializers.CharField(required=False)
    poultry_focus_area = serializers.CharField(required=False, allow_blank=True)
    consultation_mode = ConsultationModeField(allow_both=True, required=False)
    service_fee = serializers.DecimalField(max_digits=10, decimal_places=2, required=False, min_value=Decimal('0'))
    emergency_on_call_availability = serializers.BooleanField(required=False)
    practice_address = serializers.CharField(required=False)


class PayoutSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=Decimal('0.01'))


class AvailabilitySlotSerializer(serializers.Serializer):
    weekday = serializers.IntegerField(min_value=0, max_value=6)
    start_time = serializers.TimeField()
    end_time = serializers.TimeField()
    mode = ConsultationModeField(default='online')

    def validate(self, attrs):
        if attrs['start_time'] >= attrs['end_time']:
            raise serializers.ValidationError('end_time must be after start_time.')
        start = datetime.combine(date.today(), attrs['start_time'])
        end = datetime.combine(date.today(), attrs['end_time'])
        if end - start < timedelta(minutes=30):
            raise serializers.ValidationError(
                'Availability must include at least one 30-minute consultation.'
            )
        return attrs


class MessageSerializer(serializers.Serializer):
    content = serializers.CharField(required=False, allow_blank=True)
    message_type = serializers.ChoiceField(choices=('text', 'image', 'file'), default='text')
    file_url = serializers.URLField(required=False, allow_blank=True)

    def validate(self, attrs):
        if not attrs.get('content') and not attrs.get('file_url'):
            raise serializers.ValidationError('A message requires content or a file URL.')
        return attrs
