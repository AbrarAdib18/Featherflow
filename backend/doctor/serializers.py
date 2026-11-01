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
    feed_notes = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    vaccine_history = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    biosecurity_notes = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    diagnosis = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    treatment_plan = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    warnings = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    next_steps = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    status = serializers.ChoiceField(choices=('open', 'in_progress', 'follow_up', 'closed'), required=False)
    base_revision = serializers.IntegerField(required=False, min_value=0)  # optimistic-concurrency token (NF-6)


class PrescriptionSerializer(serializers.Serializer):
    consultation_id = serializers.UUIDField()
    medicines = serializers.ListField(child=serializers.DictField(), min_length=1, max_length=30)
    dosage_notes = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    case_advice = serializers.CharField(required=True, allow_blank=False, max_length=5000)
    follow_up_instructions = serializers.CharField(required=False, allow_blank=True, max_length=5000)
    referred_to = serializers.CharField(required=False, allow_blank=True, max_length=200)
    follow_up_date = serializers.DateField(required=False)
    follow_up_time = serializers.TimeField(required=False)
    follow_up_notes = serializers.CharField(required=False, allow_blank=True, max_length=5000)

    # clinical_prescription_items column limits.
    MEDICINE_LIMITS = {'name': 150, 'dosage': 100, 'duration': 50, 'notes': 2000}

    def validate_medicines(self, items):
        clean = []
        for item in items:
            row = {k: str(item.get(k) or '').strip() for k in self.MEDICINE_LIMITS}
            if not all(row[k] for k in ('name', 'dosage', 'duration')):
                raise serializers.ValidationError('Each medicine requires name, dosage and duration.')
            for key, limit in self.MEDICINE_LIMITS.items():
                if len(row[key]) > limit:
                    raise serializers.ValidationError(
                        f'Medicine {key} must be at most {limit} characters.')
            clean.append(row)
        return clean

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
    # Generated once per outgoing message and reused on retry (idempotency key).
    client_message_id = serializers.UUIDField(required=False, allow_null=True)

    def validate(self, attrs):
        if not attrs.get('content') and not attrs.get('file_url'):
            raise serializers.ValidationError('A message requires content or a file URL.')
        return attrs
