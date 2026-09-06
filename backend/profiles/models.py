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
    MODE_CHOICES = [('online', 'Online'), ('offline', 'In-person'), ('both', 'Both')]
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
    availability_status = models.CharField(max_length=15, default='available', blank=True, null=True)
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
    # Admin Panel RBAC pass — role link + account lifecycle + approval workflow.
    admin_role = models.ForeignKey('users.Role', models.SET_NULL, db_column='admin_role_id', blank=True, null=True, related_name='admin_profiles')
    access_level_requested = models.CharField(max_length=30, blank=True, null=True)
    prior_admin_operations_experience = models.TextField(blank=True, null=True)
    internal_approval_by_founder_hr = models.BooleanField(default=False)
    strong_password_2fa_enabled = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    is_suspended = models.BooleanField(default=False)
    suspended_at = models.DateTimeField(blank=True, null=True)
    suspended_by = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='suspended_by', related_name='suspended_admin_profiles', blank=True, null=True)
    approval_status = models.CharField(max_length=15, default='approved')
    # Shift Timer + Hourly Payment (Super Admin = owner, rate 0, no shifts).
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    max_hours_per_week = models.IntegerField(blank=True, null=True)
    last_shift_start = models.DateTimeField(blank=True, null=True)
    pending_hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    pending_rate_effective_from = models.DateField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'admin_profiles'

    @property
    def is_on_shift(self):
        return self.shifts.filter(is_active=True).exists()

    def effective_hourly_rate(self, on_date=None):
        """The rate in force on ``on_date`` — a pending rate takes over once its
        effective Monday has passed."""
        import datetime as _dt
        on_date = on_date or _dt.date.today()
        if (self.pending_hourly_rate is not None and self.pending_rate_effective_from
                and on_date >= self.pending_rate_effective_from):
            return self.pending_hourly_rate
        return self.hourly_rate


class AdminShift(models.Model):
    """One work session for an hourly admin. Midnight-spanning shifts are kept
    as a single row; per-day / per-week hours are computed by overlap in the
    query layer (see api/admin_shifts.py) so both calendar days get credit."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    admin = models.ForeignKey(AdminProfile, models.CASCADE, db_column='admin_id', related_name='shifts')
    shift_date = models.DateField()
    start_time = models.DateTimeField()
    end_time = models.DateTimeField(blank=True, null=True)
    break_start = models.DateTimeField(blank=True, null=True)
    break_end = models.DateTimeField(blank=True, null=True)
    break_duration_minutes = models.IntegerField(default=0)
    total_hours = models.DecimalField(max_digits=6, decimal_places=2, default=0)
    is_active = models.BooleanField(default=True)
    auto_flagged = models.BooleanField(default=False)
    ended_by = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='ended_by',
                                 related_name='force_ended_shifts', blank=True, null=True)
    ip_address = models.CharField(max_length=45, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'admin_shifts'
        ordering = ['-start_time']

    @property
    def on_break(self):
        return self.break_start is not None and self.break_end is None


class AdminPayment(models.Model):
    STATUS = [('pending', 'Pending'), ('paid', 'Paid'), ('failed', 'Failed')]
    METHODS = [('cash', 'Cash'), ('bank_transfer', 'Bank transfer'), ('mobile_wallet', 'Mobile wallet')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    admin = models.ForeignKey(AdminProfile, models.CASCADE, db_column='admin_id', related_name='payments')
    period_start = models.DateField()
    period_end = models.DateField()
    total_hours = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    regular_hours = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    overtime_hours = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    overtime_rate = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_payment = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    payment_status = models.CharField(max_length=10, choices=STATUS, default='pending')
    payment_date = models.DateTimeField(blank=True, null=True)
    payment_method = models.CharField(max_length=20, choices=METHODS, blank=True, null=True)
    payment_reference = models.TextField(blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    generated_by = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='generated_by',
                                     related_name='generated_admin_payments', blank=True, null=True)
    paid_by = models.ForeignKey(settings.AUTH_USER_MODEL, models.DO_NOTHING, db_column='paid_by',
                                related_name='paid_admin_payments', blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'admin_payments'
        ordering = ['-period_start']
        unique_together = (('admin', 'period_start'),)


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
    current_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    current_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_updated_at = models.DateTimeField(blank=True, null=True)
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
