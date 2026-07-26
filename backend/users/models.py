import uuid
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email must be set')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('account_status', 'active')

        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True')

        return self._create_user(email, password, **extra_fields)


class Role(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=50, unique=True)
    display_name = models.CharField(max_length=100, blank=True)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.display_name or self.name


class UserRole(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey('User', on_delete=models.CASCADE, related_name='user_roles')
    role = models.ForeignKey(Role, on_delete=models.CASCADE, related_name='user_roles')
    assigned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'role')

    def __str__(self):
        return f'{self.user.email} -> {self.role.name}'


class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = None
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20, unique=True, blank=True, null=True)
    full_name = models.CharField(max_length=150, blank=True)
    profile_photo_url = models.TextField(blank=True, null=True)
    date_of_birth = models.DateField(blank=True, null=True)
    present_address = models.TextField(blank=True)
    national_id_number = models.CharField(max_length=50, unique=True, blank=True, null=True)
    national_id_photo_url = models.TextField(blank=True, null=True)
    government_id_type = models.CharField(max_length=20, blank=True, null=True)
    selfie_verification_url = models.TextField(blank=True, null=True)
    preferred_language = models.CharField(max_length=20, default='en')
    emergency_contact_name = models.CharField(max_length=100, blank=True, null=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True, null=True)
    two_factor_secret = models.CharField(max_length=100, blank=True, null=True)
    two_factor_enabled = models.BooleanField(default=False)
    bank_mobile_payment_details = models.JSONField(blank=True, null=True)
    location_service_area = models.TextField(blank=True, null=True)
    consent_terms = models.BooleanField(default=False)
    consent_background_check = models.BooleanField(default=False)
    account_status = models.CharField(max_length=20, default='pending')
    is_verified = models.BooleanField(default=False)
    profile_data = models.JSONField(default=dict, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    roles = models.ManyToManyField(Role, through=UserRole, related_name='users', blank=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    objects = UserManager()

    def __str__(self):
        return self.email

    @property
    def role_names(self):
        return [role.name for role in self.roles.all()]
