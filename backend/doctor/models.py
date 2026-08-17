import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone

from consultations.models import Consultation
from farms.models import Flock


class CaseDetail(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    consultation = models.OneToOneField(Consultation, models.DO_NOTHING, related_name='case_detail')
    flock = models.ForeignKey(Flock, models.DO_NOTHING, null=True, blank=True)
    farm_name = models.CharField(max_length=150, blank=True, null=True)
    farmer_name = models.CharField(max_length=150)
    bird_age = models.CharField(max_length=50, blank=True, null=True)
    breed = models.CharField(max_length=100, blank=True, null=True)
    flock_count = models.IntegerField(blank=True, null=True)
    mortality_count = models.IntegerField(blank=True, null=True)
    feed_notes = models.TextField(blank=True, null=True)
    vaccine_history = models.TextField(blank=True, null=True)
    biosecurity_notes = models.TextField(blank=True, null=True)
    symptoms_description = models.TextField(blank=True, null=True)
    farmer_notes = models.TextField(blank=True, null=True)
    disease_tags = models.JSONField(default=list, blank=True)
    case_status = models.CharField(max_length=20, default='open')
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'consultation_case_details'


class ConsultationNote(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    consultation = models.ForeignKey(Consultation, models.DO_NOTHING, related_name='clinical_notes')
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    symptoms = models.TextField(blank=True, null=True)
    diagnosis = models.TextField()
    treatment_plan = models.TextField()
    warnings = models.TextField(blank=True, null=True)
    next_steps = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'consultation_notes'


class ClinicalPrescription(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    consultation = models.ForeignKey(Consultation, models.DO_NOTHING, related_name='clinical_prescriptions')
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    dosage_notes = models.TextField(blank=True, null=True)
    case_advice = models.TextField(blank=True, null=True)
    follow_up_instructions = models.TextField(blank=True, null=True)
    referred_to = models.CharField(max_length=200, blank=True, null=True)
    email_sent_at = models.DateTimeField(blank=True, null=True)
    email_error = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'clinical_prescriptions'


class PrescriptionItem(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    prescription = models.ForeignKey(ClinicalPrescription, models.DO_NOTHING, related_name='items')
    medicine_name = models.CharField(max_length=150)
    dosage = models.CharField(max_length=100)
    duration = models.CharField(max_length=50)
    instructions = models.TextField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'clinical_prescription_items'


class FollowUp(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    consultation = models.ForeignKey(Consultation, models.DO_NOTHING, related_name='follow_ups')
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='doctor_follow_ups')
    scheduled_date = models.DateField()
    scheduled_time = models.TimeField(blank=True, null=True)
    status = models.CharField(max_length=15, default='pending')
    notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'follow_ups'


class DoctorEarning(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='doctor_earnings')
    consultation = models.OneToOneField(Consultation, models.DO_NOTHING, related_name='doctor_earning')
    gross_amount = models.DecimalField(max_digits=12, decimal_places=2)
    platform_fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    net_amount = models.DecimalField(max_digits=12, decimal_places=2)
    payout_status = models.CharField(max_length=15, default='pending')
    payout_date = models.DateField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'doctor_earnings'


class PayoutRequest(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='doctor_payout_requests')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(max_length=15, default='requested')
    requested_at = models.DateTimeField(default=timezone.now)
    processed_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'doctor_payout_requests'


class AvailabilitySlot(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    doctor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='doctor_availability_slots')
    weekday = models.PositiveSmallIntegerField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    mode = models.CharField(max_length=10, default='online')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'doctor_availability_slots'


class ConsultationStatusHistory(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    consultation = models.ForeignKey(Consultation, models.DO_NOTHING, related_name='status_history')
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    from_status = models.CharField(max_length=25)
    to_status = models.CharField(max_length=25)
    reason = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'consultation_status_history'


class Conversation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    participant_one = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='+')
    participant_two = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='+')
    consultation = models.ForeignKey(Consultation, models.DO_NOTHING, blank=True, null=True)
    last_message_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'conversations'


class Message(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    conversation = models.ForeignKey(Conversation, models.DO_NOTHING, related_name='messages')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING)
    content = models.TextField(blank=True, null=True)
    message_type = models.CharField(max_length=10, default='text')
    file_url = models.TextField(blank=True, null=True)
    is_read = models.BooleanField(default=False)
    sent_at = models.DateTimeField(default=timezone.now)

    class Meta:
        managed = False
        db_table = 'messages'
