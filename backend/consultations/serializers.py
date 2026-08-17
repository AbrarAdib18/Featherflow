from datetime import date, timedelta

from rest_framework import serializers


class ConsultationModeField(serializers.ChoiceField):
    """Accept UI aliases while keeping one database representation."""

    def __init__(self, *, allow_both=False, **kwargs):
        choices = ('online', 'offline', 'both') if allow_both else ('online', 'offline')
        super().__init__(choices=choices, **kwargs)

    def to_internal_value(self, data):
        normalized = str(data).strip().lower().replace('_', '-').replace(' ', '-')
        if normalized in ('in-person', 'inperson', 'clinic-visit', 'field-visit'):
            normalized = 'offline'
        return super().to_internal_value(normalized)


class FarmerBookingSerializer(serializers.Serializer):
    doctor_id = serializers.UUIDField()
    farm_id = serializers.UUIDField()
    flock_id = serializers.UUIDField(required=False, allow_null=True)
    mode = ConsultationModeField()
    urgency = serializers.ChoiceField(choices=('routine', 'moderate', 'urgent', 'emergency'), default='routine')
    appointment_date = serializers.DateField()
    appointment_time = serializers.TimeField()
    symptoms = serializers.ListField(child=serializers.CharField(max_length=150), min_length=1)
    farmer_notes = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    mortality_count = serializers.IntegerField(required=False, min_value=0, default=0)
    bird_age_weeks = serializers.IntegerField(required=False, min_value=0)
    breed = serializers.CharField(required=False, allow_blank=True, max_length=100)
    flock_count = serializers.IntegerField(required=False, min_value=1)
    feed_notes = serializers.CharField(required=False, allow_blank=True)
    vaccine_history = serializers.CharField(required=False, allow_blank=True)
    biosecurity_notes = serializers.CharField(required=False, allow_blank=True)

    def validate_appointment_date(self, value):
        if value < date.today():
            raise serializers.ValidationError('Appointment date cannot be in the past.')
        if value > date.today() + timedelta(days=90):
            raise serializers.ValidationError('Appointments can be booked up to 90 days ahead.')
        return value

    def validate(self, attrs):
        if not attrs.get('flock_id'):
            missing = [key for key in ('bird_age_weeks', 'breed', 'flock_count')
                       if attrs.get(key) in (None, '')]
            if missing:
                raise serializers.ValidationError({key: 'Required when no flock is selected.' for key in missing})
        if attrs.get('mortality_count', 0) > attrs.get('flock_count', 10**12):
            raise serializers.ValidationError({'mortality_count': 'Mortality cannot exceed flock count.'})
        return attrs


class FarmerConsultationActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=('cancel', 'accept_reschedule', 'decline_reschedule', 'rate'))
    reason = serializers.CharField(required=False, allow_blank=True, max_length=1000)
    rating = serializers.IntegerField(required=False, min_value=1, max_value=5)
    review = serializers.CharField(required=False, allow_blank=True, max_length=2000)

    def validate(self, attrs):
        if attrs['action'] == 'rate' and 'rating' not in attrs:
            raise serializers.ValidationError({'rating': 'Rating is required.'})
        return attrs
