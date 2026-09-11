import re
from datetime import date

from rest_framework import serializers
from rest_framework.exceptions import APIException
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from users.models import Role, User
from profiles.models import (
    AdminProfile, DeliveryProfile, DoctorProfile, FarmerProfile,
    PharmacyOrganization, ResearcherProfile,
)
from farms.models import Farm


class DuplicateAccount(APIException):
    status_code = 409
    default_detail = 'An account with those details already exists.'
    default_code = 'duplicate_account'


# Roles that a member of the public may pick on the signup screen.
PUBLIC_ROLES = {'farmer', 'doctor', 'delivery', 'pharmacy', 'researcher', 'admin'}

# Farmer self-activates; every professional/staff role lands in review.
IMMEDIATE_ACTIVE_ROLES = {'farmer'}

# Required ``role_data`` keys per role, with human labels for the error message.
# Documents (council proof, CV, trade licence, license photo …) are intentionally
# NOT required here — they are captured as uploads and finished during the
# admin-verification / profile-completion step while the account is pending.
REQUIRED_ROLE_FIELDS = {
    'farmer': {
        'farm_name': 'Farm name',
        'farm_location': 'Farm location',
    },
    'doctor': {
        'clinic_name': 'Clinic / hospital name',
        'practice_address': 'Practice address',
        'degree': 'Veterinary degree',
        'university': 'University name',
        'graduation_year': 'Graduation year',
        'license_number': 'License / registration number',
        'issuing_authority': 'License issuing authority',
        'license_expiry': 'License expiry date',
        'specialty': 'Specialty / focus area',
        'years_experience': 'Years of experience',
    },
    'pharmacy': {
        'business_name': 'Business / organization name',
        'contact_person': 'Authorized contact person',
        'business_reg_number': 'Business registration number',
        'tax_number': 'Tax / VAT / TIN number',
        'business_address': 'Business address',
    },
    'delivery': {
        'license_number': "Driver's license number",
        'license_class': 'License class',
        'license_expiry': 'License expiry date',
        'vehicle_type': 'Vehicle type',
        'vehicle_registration': 'Vehicle registration number',
        'area_coverage': 'Area coverage',
    },
    'researcher': {
        'institution': 'Institution / company name',
        'department': 'Department',
        'degree': 'Highest academic degree',
        'field_of_study': 'Field of study',
        'university': 'University name',
        'graduation_year': 'Graduation year',
        'years_experience': 'Years of research experience',
        'areas_of_expertise': 'Areas of expertise',
    },
    'admin': {
        'job_title': 'Job title',
        'department': 'Department',
        'start_date': 'Start date',
        'access_level': 'Access level requested',
    },
}

_PHONE_SEPARATORS = re.compile(r'[\s\-().]')
_BD_MOBILE = re.compile(r'^\+8801[3-9]\d{8}$')

# role -> [(SignupDocument.document_type, role_data key that carries the URL)].
# The profile-photo URL is lifted onto ``role_data['profile_photo_url']`` by the
# frontend/register() before it reaches here.
_ROLE_DOCUMENT_FIELDS = {
    'farmer': [('profile_photo', 'profile_photo_url')],
    'doctor': [
        ('profile_photo', 'profile_photo_url'),
        ('council_proof', 'council_registration_proof_url'),
        ('cv', 'cv_url'),
    ],
    'pharmacy': [
        ('profile_photo', 'profile_photo_url'),
        ('trade_license', 'trade_license'),
        ('business_registration_cert', 'business_registration_cert_url'),
        ('responsible_pharmacist_cert', 'responsible_pharmacist_cert_url'),
    ],
    'delivery': [
        ('profile_photo', 'profile_photo_url'),
        ('license_photo', 'license_photo_url'),
        ('vehicle_photo', 'vehicle_photo_url'),
        ('proof_of_work', 'proof_of_right_to_work'),
    ],
    'researcher': [
        ('profile_photo', 'profile_photo_url'),
        ('cv', 'cv_url'),
        ('ethics_certificate', 'ethics_certificate_url'),
        ('publications', 'publications'),
    ],
    'admin': [
        ('profile_photo', 'profile_photo_url'),
        ('cv', 'cv_url'),
    ],
}


def _claim_signup_documents(user, role_name, role_data):
    """Link every uploaded file referenced in ``role_data`` to the new account
    (creates ``signup_documents`` rows). Runs inside the registration's atomic
    block: a genuine DB failure rolls the whole signup back; an unparseable
    token is skipped."""
    from verification import documents as docs

    for doc_type, key in _ROLE_DOCUMENT_FIELDS.get(role_name, []):
        docs.claim(role_data.get(key), user, document_type=doc_type)

    for photo in (role_data.get('farm_photos') or []):
        docs.claim(photo, user, document_type='farm_photo')


def normalize_email(value):
    return (value or '').strip().lower()


def normalize_name(value):
    # Collapse internal whitespace and strip the ends.
    return re.sub(r'\s+', ' ', (value or '')).strip()


def normalize_bd_phone(value):
    """Return a canonical ``+8801XXXXXXXXX`` string or raise ValidationError."""
    raw = _PHONE_SEPARATORS.sub('', str(value or ''))
    if raw.startswith('00'):
        raw = '+' + raw[2:]
    if raw.startswith('880'):
        raw = '+' + raw
    elif raw.startswith('01'):
        raw = '+88' + raw
    elif raw.startswith('1') and len(raw) == 10:
        raw = '+880' + raw
    if not _BD_MOBILE.match(raw):
        raise serializers.ValidationError(
            'Enter a valid Bangladesh mobile number, e.g. +8801712345678.')
    return raw


class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    password2 = serializers.CharField(write_only=True)
    role = serializers.CharField(required=False, default='farmer')
    role_data = serializers.JSONField(required=False, default=dict)

    class Meta:
        model = User
        fields = [
            'email', 'phone', 'full_name', 'date_of_birth', 'present_address',
            'national_id_number', 'government_id_type', 'consent_terms',
            'consent_background_check', 'preferred_language', 'emergency_contact_name',
            'emergency_contact_phone', 'password', 'password2', 'role', 'role_data'
        ]
        extra_kwargs = {
            # Uniqueness is enforced explicitly in ``validate`` so we can return
            # a 409 with a field-specific message instead of a generic 400.
            'email': {'validators': []},
            'phone': {'validators': []},
            'national_id_number': {'validators': []},
        }

    # ── field-level normalisation ──────────────────────────────────────────
    def validate_email(self, value):
        value = normalize_email(value)
        if not value:
            raise serializers.ValidationError('Email is required.')
        return value

    def validate_full_name(self, value):
        value = normalize_name(value)
        if len(value) < 2:
            raise serializers.ValidationError('Enter your full name.')
        if len(value) > 120:
            raise serializers.ValidationError('Name is too long (max 120 characters).')
        return value

    def validate_phone(self, value):
        return normalize_bd_phone(value)

    def validate_present_address(self, value):
        value = (value or '').strip()
        if len(value) < 4:
            raise serializers.ValidationError('Enter your present address.')
        return value

    def validate_role(self, value):
        value = (value or 'farmer').strip().lower()
        if value not in PUBLIC_ROLES:
            raise serializers.ValidationError(
                f'Unsupported role. Choose one of: {", ".join(sorted(PUBLIC_ROLES))}.')
        return value

    def validate_consent_terms(self, value):
        if not value:
            raise serializers.ValidationError(
                'You must accept the Terms of Service and Privacy Policy.')
        return True

    # ── object-level ──────────────────────────────────────────────────────
    def validate(self, attrs):
        errors = {}

        if attrs.get('password') != attrs.get('password2'):
            errors['password2'] = ['Passwords do not match.']

        # Password strength — Django validators are authoritative.
        stub = User(
            email=attrs.get('email', ''), full_name=attrs.get('full_name', ''),
            phone=attrs.get('phone', ''),
        )
        try:
            validate_password(attrs.get('password') or '', user=stub)
        except DjangoValidationError as exc:
            errors['password'] = list(exc.messages)

        # Duplicate email / phone / NID → 409.
        email = attrs.get('email')
        phone = attrs.get('phone')
        nid = (attrs.get('national_id_number') or '').strip() or None
        if email and User.objects.filter(email__iexact=email).exists():
            raise DuplicateAccount({'email': 'An account with this email already exists.'})
        if phone and User.objects.filter(phone=phone).exists():
            raise DuplicateAccount({'phone': 'An account with this phone number already exists.'})
        if nid and User.objects.filter(national_id_number=nid).exists():
            raise DuplicateAccount({'national_id_number': 'An account with this ID number already exists.'})
        attrs['national_id_number'] = nid

        # Required role-specific fields (reject blank / whitespace-only).
        role = attrs.get('role', 'farmer')
        role_data = attrs.get('role_data') or {}
        if not isinstance(role_data, dict):
            errors['role_data'] = ['role_data must be an object.']
            role_data = {}
        missing = {}
        for key, label in REQUIRED_ROLE_FIELDS.get(role, {}).items():
            raw = role_data.get(key)
            if raw is None or (isinstance(raw, str) and not raw.strip()) or \
                    (isinstance(raw, (list, dict)) and len(raw) == 0):
                missing[key] = f'{label} is required.'
        if missing:
            errors['role_data'] = missing

        if errors:
            raise serializers.ValidationError(errors)

        attrs['role_data'] = {
            k: (v.strip() if isinstance(v, str) else v) for k, v in role_data.items()
        }
        return attrs

    # ── creation ─────────────────────────────────────────────────────────
    @transaction.atomic
    def create(self, validated_data):
        role_name = validated_data.pop('role', 'farmer')
        role_data = validated_data.pop('role_data', {})
        validated_data.pop('password2')
        password = validated_data.pop('password')

        def integer(value, field, default=None, required=False):
            if value in (None, ''):
                if required:
                    raise serializers.ValidationError({'role_data': {field: f'{field} must be a number.'}})
                return default
            try:
                return int(float(value))
            except (TypeError, ValueError):
                raise serializers.ValidationError({'role_data': {field: f'{field} must be a whole number.'}})

        def decimal(value, field, default=None):
            if value in (None, ''):
                return default
            try:
                return round(float(value), 2)
            except (TypeError, ValueError):
                raise serializers.ValidationError({'role_data': {field: f'{field} must be a number.'}})

        def parsed_date(value, field, default=None):
            if not value:
                return default
            try:
                return date.fromisoformat(str(value)[:10])
            except (TypeError, ValueError):
                raise serializers.ValidationError({'role_data': {field: f'{field} must be a valid date.'}})

        initial_status = 'active' if role_name in IMMEDIATE_ACTIVE_ROLES else 'pending'

        user = User.objects.create_user(
            email=validated_data['email'],
            password=password,
            phone=validated_data['phone'],
            full_name=validated_data['full_name'],
            present_address=validated_data['present_address'],
            date_of_birth=validated_data.get('date_of_birth'),
            national_id_number=validated_data.get('national_id_number'),
            government_id_type=validated_data.get('government_id_type') or None,
            profile_photo_url=role_data.get('profile_photo_url') or None,
            preferred_language=validated_data.get('preferred_language') or 'en',
            emergency_contact_name=validated_data.get('emergency_contact_name') or '',
            emergency_contact_phone=validated_data.get('emergency_contact_phone') or '',
            consent_terms=True,
            consent_background_check=bool(validated_data.get('consent_background_check', False)),
            account_status=initial_status,
            is_verified=False,
        )

        role, _ = Role.objects.get_or_create(
            name=role_name,
            defaults={'panel_type': role_name if role_name != 'admin' else 'admin'},
        )
        user.roles.add(role)

        if role_name == 'farmer':
            self._create_farmer(user, role_data)
        elif role_name == 'doctor':
            self._create_doctor(user, role_data, integer, decimal, parsed_date)
        elif role_name == 'delivery':
            self._create_delivery(user, role_data, parsed_date)
        elif role_name == 'pharmacy':
            self._create_pharmacy(user, role_data, integer)
        elif role_name == 'researcher':
            self._create_researcher(user, role_data, integer)
        elif role_name == 'admin':
            self._create_admin(user, role, role_data, parsed_date)

        # Persist the link between the account and every file it uploaded during
        # signup. Inside this atomic block, so a failure rolls the signup back.
        _claim_signup_documents(user, role_name, role_data)

        return user

    # ── per-role profile builders ────────────────────────────────────────
    def _create_farmer(self, user, rd):
        farmer_profile, _ = FarmerProfile.objects.update_or_create(
            user=user,
            defaults={
                'farm_name': rd.get('farm_name') or f"{user.full_name}'s Farm",
                'owner_name': rd.get('owner_name') or rd.get('farm_owner') or user.full_name,
                'farm_location': rd.get('farm_location') or user.present_address,
                'farm_address': rd.get('farm_address') or rd.get('farm_location') or user.present_address,
                'farm_type': str(rd.get('farm_type', 'mixed')).lower(),
                'number_of_birds': _opt_int(rd.get('number_of_birds') or rd.get('bird_count')),
                'farm_registration_number': rd.get('farm_registration_number') or rd.get('farm_registration') or None,
                'years_in_farming': _opt_int(rd.get('years_in_farming')),
                'experience_level': str(rd.get('experience_level', '')).lower() or None,
                'primary_diseases_faced': rd.get('primary_diseases_faced') or rd.get('primary_disease') or None,
                'feed_type': rd.get('feed_type') or None,
                'feed_sourcing_method': rd.get('feed_sourcing_method') or None,
                'existing_vet_consultant': rd.get('existing_vet_consultant') or rd.get('vet_contact') or None,
                'farm_photos': rd.get('farm_photos', []) or [],
                'number_of_active_workers': _opt_int(rd.get('number_of_active_workers') or rd.get('active_workers')),
                'consent_data_collection': bool(rd.get('consent_data_collection', rd.get('consent', True))),
            },
        )
        Farm.objects.get_or_create(
            farmer=farmer_profile,
            farm_name=farmer_profile.farm_name,
            defaults={
                'farm_type': farmer_profile.farm_type or 'mixed',
                'location': farmer_profile.farm_location,
                'address': farmer_profile.farm_address,
                'registration_number': farmer_profile.farm_registration_number,
                'is_active': True,
            },
        )

    def _create_doctor(self, user, rd, integer, decimal, parsed_date):
        expiry = parsed_date(rd.get('license_expiry'), 'license_expiry')
        DoctorProfile.objects.update_or_create(
            user=user,
            defaults={
                'clinic_hospital_name': rd.get('clinic_name') or rd.get('workplace'),
                'practice_address': rd.get('practice_address') or user.present_address,
                'latitude': rd.get('latitude'),
                'longitude': rd.get('longitude'),
                'veterinary_degree': rd.get('degree'),
                'university_name': rd.get('university'),
                'graduation_year': integer(rd.get('graduation_year'), 'graduation_year', required=True),
                'license_number': rd.get('license_number'),
                'license_issuing_authority': rd.get('issuing_authority'),
                'license_expiry_date': expiry,
                'specialty': rd.get('specialty'),
                'poultry_focus_area': rd.get('specialty', ''),
                'years_of_experience': integer(rd.get('years_experience'), 'years_experience', required=True),
                'consultation_mode': {'Online': 'online', 'Offline': 'offline', 'Field Visit': 'offline', 'Both': 'both'}.get(rd.get('consult_mode'), 'both'),
                'council_registration_proof_url': rd.get('council_registration_proof_url') or 'pending-upload',
                'cv_url': rd.get('cv_url') or None,
                'service_fee': decimal(rd.get('fees'), 'fees'),
                'consent_platform_guidelines': True,
                'is_verified': False,
                'is_available': False,
            },
        )

    def _create_delivery(self, user, rd, parsed_date):
        # No dedicated vehicle table — vehicle + banking detail ride on the
        # JSON columns that already exist.
        schedule = {
            'description': rd.get('availability', ''),
            'vehicle': {
                'type': rd.get('vehicle_type'),
                'registration': rd.get('vehicle_registration'),
                'insurance': rd.get('insurance_details') or None,
                'photo_url': rd.get('vehicle_photo_url') or None,
            },
        }
        if rd.get('banking_details') or rd.get('bank_account'):
            user.bank_mobile_payment_details = {
                **(user.bank_mobile_payment_details or {}),
                'settlement': rd.get('banking_details') or rd.get('bank_account'),
            }
            user.save(update_fields=['bank_mobile_payment_details'])
        DeliveryProfile.objects.update_or_create(
            user=user,
            defaults={
                'drivers_license_number': rd.get('license_number'),
                'license_class': rd.get('license_class'),
                'license_expiry_date': parsed_date(rd.get('license_expiry'), 'license_expiry'),
                'license_photo_url': rd.get('license_photo_url') or 'pending-upload',
                'proof_of_work_url': rd.get('proof_of_right_to_work') or None,
                'prior_delivery_experience': rd.get('prior_delivery_experience') or None,
                'area_coverage': rd.get('area_coverage'),
                'availability_schedule': schedule,
                'current_status': 'offline',
                'approved_by_admin': None,
            },
        )

    def _create_pharmacy(self, user, rd, integer):
        PharmacyOrganization.objects.update_or_create(
            user=user,
            defaults={
                'business_name': rd.get('business_name'),
                'authorized_contact_person': rd.get('contact_person'),
                'business_registration_number': rd.get('business_reg_number'),
                'trade_license_url': rd.get('trade_license') or 'pending-upload',
                'tax_vat_tin_number': rd.get('tax_number'),
                'business_address': rd.get('business_address'),
                'warehouse_address': rd.get('warehouse_address') or None,
                'number_of_pharmacists': integer(rd.get('number_of_pharmacists'), 'number_of_pharmacists', default=0),
                'responsible_pharmacist_name': rd.get('responsible_pharmacist') or None,
                'is_verified': False,
            },
        )

    def _create_researcher(self, user, rd, integer):
        expertise = rd.get('areas_of_expertise', '')
        if not isinstance(expertise, list):
            expertise = [item.strip() for item in str(expertise).split(',') if item.strip()]
        research_role = str(rd.get('research_role', '')).lower()
        allowed = {'nutrition', 'disease', 'genetics', 'welfare', 'growth', 'economics'}
        ResearcherProfile.objects.update_or_create(
            user=user,
            defaults={
                'institution_name': rd.get('institution'),
                'institutional_email': rd.get('institutional_email') or user.email,
                'department': rd.get('department'),
                'highest_degree': rd.get('degree'),
                'field_of_study': rd.get('field_of_study'),
                'university_name': rd.get('university'),
                'graduation_year': integer(rd.get('graduation_year'), 'graduation_year', required=True),
                'cv_url': rd.get('cv_url') or 'pending-upload',
                'ethics_certificate_url': rd.get('ethics_certificate_url') or None,
                'publications_portfolio_url': rd.get('publications') or None,
                'areas_of_expertise': expertise,
                'years_of_research_experience': integer(rd.get('years_experience'), 'years_experience', required=True),
                'poultry_specific_experience': rd.get('poultry_experience') or None,
                'research_role_type': research_role if research_role in allowed else None,
                'conflict_of_interest_declaration': bool(rd.get('conflict_declaration', True)),
                'publication_consent': bool(rd.get('publication_consent', True)),
                'ip_agreement': bool(rd.get('ip_agreement', True)),
                'reference_name': rd.get('reference_name') or None,
                'reference_title': rd.get('reference_title') or None,
                'reference_email': rd.get('reference_email') or None,
                'is_verified': False,
            },
        )

    def _create_admin(self, user, generic_role, rd, parsed_date):
        employment = str(rd.get('employment_type', 'full_time')).lower().replace('-', '_').replace(' ', '_')
        if employment not in {'full_time', 'part_time', 'contract'}:
            employment = 'full_time'
        valid_sub_roles = {'super', 'operations', 'finance', 'content', 'research',
                           'delivery', 'pharmacy', 'support', 'doctor', 'team'}
        requested = str(rd.get('access_level', 'support')).lower().replace(' admin', '').replace('-', '_').replace(' ', '_')
        sub_role = requested if requested in valid_sub_roles else 'support'
        # Self-registration can never mint a Super Admin.
        if sub_role == 'super':
            sub_role = 'operations'
        AdminProfile.objects.update_or_create(
            user=user,
            defaults={
                'account_id_number': rd.get('account_id') or None,
                'cv_url': rd.get('cv_url') or None,
                'job_title': rd.get('job_title'),
                'department': rd.get('department'),
                'work_location': rd.get('work_location') or None,
                'employment_type': employment,
                'start_date': parsed_date(rd.get('start_date'), 'start_date', default=date.today()),
                'admin_sub_role': sub_role,
                'access_level_requested': requested,
                'tech_skill_level': str(rd.get('tech_skills') or rd.get('basic_tech_skill_level') or 'intermediate').lower()[:20] or 'intermediate',
                'confidentiality_agreement_accepted': bool(rd.get('confidentiality_agreement', False)),
                'background_check_consent': bool(rd.get('background_consent', False)),
                'prior_admin_operations_experience': rd.get('prior_admin_operations_experience') or rd.get('prior_experience') or None,
                'previous_experience': rd.get('previous_work') or None,
                'internal_approval_by_founder_hr': False,
                'approval_status': 'pending',
                'is_active': False,
            },
        )
        specific_role = Role.objects.filter(name=f'admin_{sub_role}', panel_type='admin').first()
        if specific_role:
            user.roles.remove(generic_role)
            user.roles.add(specific_role)
        try:
            from notifications.models import Notification
            reviewers = User.objects.filter(
                roles__name__in=['admin_super', 'admin_operations']).distinct()
            for reviewer in reviewers:
                Notification.objects.create(
                    user=reviewer, title='New admin registration to review',
                    body=f'{user.full_name or user.email} requested {sub_role} admin access.',
                    notification_type='approval',
                )
        except Exception:
            pass


def _opt_int(value):
    try:
        return int(float(value)) if value not in (None, '') else None
    except (TypeError, ValueError):
        return None


class UserLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate_email(self, value):
        return normalize_email(value)


class UserSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()
    profile_data = serializers.SerializerMethodField()
    documents = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'phone', 'full_name', 'profile_photo_url',
            'date_of_birth', 'present_address', 'national_id_number',
            'government_id_type', 'preferred_language',
            'emergency_contact_name', 'emergency_contact_phone',
            'account_status', 'is_verified', 'date_joined', 'updated_at',
            'roles', 'profile_data', 'documents'
        ]

    def get_roles(self, obj):
        return [role.name for role in obj.roles.all()]

    def get_documents(self, obj):
        """Files the account uploaded during signup (from ``signup_documents``).

        Only computed for single-object responses (login / register / me /
        detail) — skipped in list responses to avoid an N+1 query.
        """
        if isinstance(self.parent, serializers.ListSerializer):
            return []
        try:
            from verification.models import SignupDocument
        except Exception:
            return []
        request = self.context.get('request')
        rows = SignupDocument.objects.filter(user=obj).order_by('document_type', 'created_at')
        out = []
        for d in rows:
            url = d.url_path
            out.append({
                'id': str(d.id),
                'document_type': d.document_type,
                'filename': d.original_filename or '',
                'content_type': d.content_type or '',
                'url': request.build_absolute_uri(url) if request else url,
                'is_verified': d.is_verified,
                'uploaded_at': d.uploaded_at.isoformat() if d.uploaded_at else None,
            })
        return out

    def get_profile_data(self, obj):
        role_profiles = (
            ('farmer_profile', FarmerProfile),
            ('doctor_profile', DoctorProfile),
            ('delivery_profile', DeliveryProfile),
            ('pharmacy_organization', PharmacyOrganization),
            ('researcher_profile', ResearcherProfile),
            ('admin_profile', AdminProfile),
        )
        for relation, model in role_profiles:
            try:
                profile = getattr(obj, relation)
            except model.DoesNotExist:
                continue
            data = {}
            for field in profile._meta.concrete_fields:
                if field.name in {'id', 'user', 'approved_by_admin', 'reporting_manager',
                                  'suspended_by'}:
                    continue
                if field.is_relation:
                    related_id = getattr(profile, field.attname, None)
                    if related_id is None:
                        data[field.name] = None
                        continue
                    related = getattr(profile, field.name, None)
                    data[field.name] = getattr(related, 'name', None) or str(related_id)
                    continue
                value = getattr(profile, field.name)
                if hasattr(value, 'isoformat'):
                    value = value.isoformat()
                data[field.name] = value
            return data
        return obj.profile_data
