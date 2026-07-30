import uuid
from django.conf import settings
from django.db import models


class DoctorProfile(models.Model):
    MODE_CHOICES = [('online', 'Online'), ('offline', 'Offline'), ('both', 'Both')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='doctor_profile',
    )
    clinic_hospital_name = models.CharField(max_length=200)
    practice_address = models.TextField()
    district = models.CharField(max_length=100, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    veterinary_degree = models.CharField(max_length=100)
    university_name = models.CharField(max_length=200)
    graduation_year = models.PositiveIntegerField()
    license_number = models.CharField(max_length=100, unique=True)
    license_issuing_authority = models.CharField(max_length=150)
    license_expiry_date = models.DateField()
    specialty = models.CharField(max_length=150)
    poultry_focus_area = models.TextField(blank=True)
    years_of_experience = models.PositiveIntegerField()
    consultation_mode = models.CharField(max_length=10, choices=MODE_CHOICES)
    cv_url = models.TextField(blank=True)
    council_registration_proof_url = models.TextField()
    prescription_authority = models.BooleanField(default=False)
    emergency_on_call_availability = models.BooleanField(default=False)
    service_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    referral_network = models.TextField(blank=True)
    consent_platform_guidelines = models.BooleanField(default=False)
    is_verified = models.BooleanField(default=False)
    is_available = models.BooleanField(default=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    approved_by_admin = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='approved_doctor_profiles',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
