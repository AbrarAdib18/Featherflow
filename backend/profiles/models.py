import uuid
from django.conf import settings
from django.db import models


class FarmerProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='farmer_profile')
    farm_name = models.CharField(max_length=150)
    owner_name = models.CharField(max_length=150)
    farm_location = models.TextField()
    farm_address = models.TextField()
    farm_type = models.CharField(max_length=20, blank=True, null=True)
    number_of_birds = models.IntegerField(blank=True, null=True)
    farm_registration_number = models.CharField(max_length=100, blank=True, null=True)
    years_in_farming = models.IntegerField(blank=True, null=True)
    experience_level = models.CharField(max_length=20, blank=True, null=True)
    primary_diseases_faced = models.TextField(blank=True, null=True)
    feed_type = models.CharField(max_length=100, blank=True, null=True)
    feed_sourcing_method = models.TextField(blank=True, null=True)
    existing_vet_consultant = models.CharField(max_length=150, blank=True, null=True)
    farm_photos = models.JSONField(blank=True, null=True)
    number_of_active_workers = models.IntegerField(blank=True, null=True)
    consent_data_collection = models.BooleanField(default=False)
    approved_by_admin = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='approved_farmer_profiles',
        blank=True, null=True,
    )
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'farmer_profiles'


class DoctorProfile(models.Model):
    MODE_CHOICES = [('online', 'Online'), ('offline', 'Offline'), ('both', 'Both')]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='doctor_profile')
    clinic_hospital_name = models.CharField(max_length=200)
    practice_address = models.TextField()
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    veterinary_degree = models.CharField(max_length=100)
    university_name = models.CharField(max_length=200)
    graduation_year = models.PositiveIntegerField()
    license_number = models.CharField(max_length=100, unique=True)
    license_issuing_authority = models.CharField(max_length=150)
    license_expiry_date = models.DateField()
    specialty = models.CharField(max_length=150)
    poultry_focus_area = models.TextField(blank=True, null=True)
    years_of_experience = models.PositiveIntegerField()
    consultation_mode = models.CharField(max_length=10, choices=MODE_CHOICES, blank=True, null=True)
    cv_url = models.TextField(blank=True, null=True)
    council_registration_proof_url = models.TextField()
    prescription_authority = models.BooleanField(default=False, blank=True, null=True)
    emergency_on_call_availability = models.BooleanField(default=False, blank=True, null=True)
    service_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    referral_network = models.TextField(blank=True, null=True)
    consent_platform_guidelines = models.BooleanField(default=False)
    is_verified = models.BooleanField(default=False, blank=True, null=True)
    is_available = models.BooleanField(default=True, blank=True, null=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=0, blank=True, null=True)
    approved_by_admin = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING, null=True, blank=True,
        related_name='approved_doctor_profiles',
    )
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'doctor_profiles'


class AdminProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='admin_profile')
    account_id_number = models.CharField(max_length=50, blank=True, null=True)
    job_title = models.CharField(max_length=100)
    department = models.CharField(max_length=100)
    reporting_manager = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='managed_admin_profiles', blank=True, null=True)
    work_location = models.CharField(max_length=150, blank=True, null=True)
    employment_type = models.CharField(max_length=20, blank=True, null=True)
    start_date = models.DateField()
    admin_sub_role = models.CharField(max_length=20, blank=True, null=True)
    tech_skill_level = models.CharField(max_length=20, blank=True, null=True)
    confidentiality_agreement_accepted = models.BooleanField(default=False)
    background_check_consent = models.BooleanField(default=False)
    cv_url = models.TextField(blank=True, null=True)
    previous_experience = models.TextField(blank=True, null=True)
    approved_by_admin = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='approved_admin_profiles', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'admin_profiles'


class DeliveryProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='delivery_profile')
    drivers_license_number = models.CharField(max_length=100, unique=True)
    license_class = models.CharField(max_length=50)
    license_expiry_date = models.DateField()
    license_photo_url = models.TextField()
    proof_of_work_url = models.TextField(blank=True, null=True)
    prior_delivery_experience = models.TextField(blank=True, null=True)
    area_coverage = models.TextField(blank=True, null=True)
    availability_schedule = models.JSONField(blank=True, null=True)
    is_online = models.BooleanField(default=False, blank=True, null=True)
    current_status = models.CharField(max_length=20, default='offline', blank=True, null=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=0, blank=True, null=True)
    total_deliveries = models.IntegerField(default=0, blank=True, null=True)
    approved_by_admin = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='approved_delivery_profiles', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'delivery_profiles'


class PharmacyOrganization(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='pharmacy_organization')
    business_name = models.CharField(max_length=200)
    authorized_contact_person = models.CharField(max_length=150)
    business_registration_number = models.CharField(max_length=100, unique=True)
    trade_license_url = models.TextField()
    tax_vat_tin_number = models.CharField(max_length=100)
    business_address = models.TextField()
    warehouse_address = models.TextField(blank=True, null=True)
    number_of_pharmacists = models.IntegerField(default=0, blank=True, null=True)
    responsible_pharmacist_name = models.CharField(max_length=150, blank=True, null=True)
    is_verified = models.BooleanField(default=False, blank=True, null=True)
    approved_by_admin = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='approved_pharmacy_organizations', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'pharmacy_organizations'


class ResearcherProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='researcher_profile')
    institution_name = models.CharField(max_length=200)
    institutional_email = models.EmailField(max_length=255)
    department = models.CharField(max_length=150)
    highest_degree = models.CharField(max_length=100)
    field_of_study = models.CharField(max_length=150)
    university_name = models.CharField(max_length=200)
    graduation_year = models.IntegerField()
    cv_url = models.TextField()
    publications_portfolio_url = models.TextField(blank=True, null=True)
    areas_of_expertise = models.JSONField(default=list, blank=True, null=True)
    years_of_research_experience = models.IntegerField()
    poultry_specific_experience = models.TextField(blank=True, null=True)
    research_role_type = models.CharField(max_length=20, blank=True, null=True)
    ethics_certificate_url = models.TextField(blank=True, null=True)
    conflict_of_interest_declaration = models.BooleanField(default=False)
    publication_consent = models.BooleanField(default=False)
    ip_agreement = models.BooleanField(default=False)
    reference_name = models.CharField(max_length=150, blank=True, null=True)
    reference_title = models.CharField(max_length=150, blank=True, null=True)
    reference_email = models.EmailField(max_length=255, blank=True, null=True)
    is_verified = models.BooleanField(default=False, blank=True, null=True)
    approved_by_admin = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, related_name='approved_researcher_profiles', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    class Meta:
        managed = False
        db_table = 'researcher_profiles'
