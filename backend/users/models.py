import uuid

from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.hashers import check_password, make_password
from django.db import models


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email must be set')
        user = self.model(email=self.normalize_email(email), **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('account_status', 'active')
        extra_fields.setdefault('is_verified', True)
        return self._create_user(email, password, **extra_fields)


class Role(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=50, unique=True)
    panel_type = models.CharField(max_length=20, blank=True, null=True)
    description = models.TextField(blank=True, null=True)
    permissions = models.JSONField(default=dict, blank=True)
    tier_level = models.SmallIntegerField(blank=True, null=True)
    is_system = models.BooleanField(default=False)
    hourly_rate_range_min = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    hourly_rate_range_max = models.DecimalField(max_digits=10, decimal_places=2, blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'roles'

    @property
    def display_name(self):
        # Admin roles read better without the "admin_" prefix ("Finance Admin").
        if self.name.startswith('admin_'):
            return self.name[len('admin_'):].replace('_', ' ').title() + ' Admin'
        return self.name.replace('_', ' ').title()

    def __str__(self):
        return self.display_name


class User(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(max_length=255, unique=True)
    phone = models.CharField(max_length=20, unique=True)
    password = models.CharField(max_length=255, db_column='password_hash')
    full_name = models.CharField(max_length=150)
    profile_photo_url = models.TextField(blank=True, null=True)
    date_of_birth = models.DateField()
    present_address = models.TextField()
    national_id_number = models.CharField(max_length=50, unique=True, blank=True, null=True)
    national_id_photo_url = models.TextField(blank=True, null=True)
    government_id_type = models.CharField(max_length=10, blank=True, null=True)
    selfie_verification_url = models.TextField(blank=True, null=True)
    preferred_language = models.CharField(max_length=10, default='en', blank=True, null=True)
    emergency_contact_name = models.CharField(max_length=100, blank=True, null=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True, null=True)
    two_factor_secret = models.CharField(max_length=100, blank=True, null=True)
    two_factor_enabled = models.BooleanField(default=False, blank=True, null=True)
    bank_mobile_payment_details = models.JSONField(blank=True, null=True)
    location_service_area = models.TextField(blank=True, null=True)
    consent_terms = models.BooleanField(default=False)
    consent_background_check = models.BooleanField(default=False, blank=True, null=True)
    account_status = models.CharField(max_length=20, default='pending', blank=True, null=True)
    is_verified = models.BooleanField(default=False, blank=True, null=True)
    # Contact ownership — set when the account owner confirms an OTP for that
    # channel (see verification/). Distinct from ``is_verified`` (admin review).
    email_verified_at = models.DateTimeField(blank=True, null=True)
    phone_verified_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)
    roles = models.ManyToManyField(
        Role, through='UserRole', through_fields=('user', 'role'), related_name='users'
    )

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['phone', 'full_name', 'date_of_birth', 'present_address', 'consent_terms']
    objects = UserManager()

    class Meta:
        managed = False
        db_table = 'users'

    @property
    def is_authenticated(self):
        return True

    @property
    def is_anonymous(self):
        return False

    @property
    def is_active(self):
        return self.account_status == 'active'

    @property
    def email_verified(self):
        return self.email_verified_at is not None

    @property
    def phone_verified(self):
        return self.phone_verified_at is not None

    def mark_email_verified(self):
        from django.utils import timezone
        self.email_verified_at = timezone.now()
        self.save(update_fields=['email_verified_at', 'updated_at'])

    def mark_phone_verified(self):
        from django.utils import timezone
        self.phone_verified_at = timezone.now()
        self.save(update_fields=['phone_verified_at', 'updated_at'])

    @property
    def is_staff(self):
        return self.roles.filter(panel_type='admin').exists()

    @property
    def is_superuser(self):
        return self.roles.filter(name='admin_super').exists()

    @property
    def date_joined(self):
        return self.created_at

    @property
    def last_login(self):
        # featherflow_schema.sql intentionally has no login timestamp column.
        return None

    @property
    def profile_data(self):
        data = self.bank_mobile_payment_details or {}
        if not isinstance(data, dict):
            return {}
        return data.get('_backend_profile_data', {})

    @profile_data.setter
    def profile_data(self, value):
        data = dict(self.bank_mobile_payment_details or {})
        data['_backend_profile_data'] = value or {}
        self.bank_mobile_payment_details = data

    def set_password(self, raw_password):
        self.password = make_password(raw_password)

    def check_password(self, raw_password):
        return check_password(raw_password, self.password)

    def get_username(self):
        return self.email

    def get_session_auth_hash(self):
        return make_password(self.password, salt='session-auth-hash')

    def has_perm(self, perm, obj=None):
        return self.is_staff

    def has_module_perms(self, app_label):
        return self.is_staff

    def __str__(self):
        return self.email

    @property
    def role_names(self):
        return list(self.roles.values_list('name', flat=True))


class UserRole(models.Model):
    pk = models.CompositePrimaryKey('user_id', 'role_id')
    user = models.ForeignKey(User, models.DO_NOTHING, related_name='user_roles')
    role = models.ForeignKey(Role, models.DO_NOTHING, related_name='user_roles')
    assigned_at = models.DateTimeField(blank=True, null=True)
    assigned_by = models.ForeignKey(
        User, models.DO_NOTHING, db_column='assigned_by',
        related_name='roles_assigned', blank=True, null=True,
    )

    class Meta:
        managed = False
        db_table = 'user_roles'
        unique_together = (('user', 'role'),)

    def __str__(self):
        return f'{self.user.email} -> {self.role.name}'
