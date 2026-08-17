from datetime import date

from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from users.models import Role, User
from profiles.models import (
    AdminProfile, DeliveryProfile, DoctorProfile, FarmerProfile,
    PharmacyOrganization, ResearcherProfile,
)
from farms.models import Farm


class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, validators=[validate_password])
    password2 = serializers.CharField(write_only=True)
    role = serializers.CharField(required=False, default='farmer')
    role_data = serializers.JSONField(required=False, default=dict)

    class Meta:
        model = User
        fields = [
            'email', 'phone', 'full_name', 'date_of_birth', 'present_address',
            'national_id_number', 'government_id_type', 'consent_terms',
            'consent_background_check', 'preferred_language', 'emergency_contact_name',
            'emergency_contact_phone', 'profile_data', 'password', 'password2', 'role', 'role_data'
        ]

    def validate(self, attrs):
        if attrs['password'] != attrs['password2']:
            raise serializers.ValidationError({'password': 'Passwords do not match.'})
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        role_name = validated_data.pop('role', 'farmer').lower()
        role_data = validated_data.pop('role_data', {})
        validated_data.pop('password2')
        password = validated_data.pop('password')

        def integer(value, default=0):
            try:
                return int(float(value))
            except (TypeError, ValueError):
                return default

        def decimal(value, default=0):
            try:
                return float(value)
            except (TypeError, ValueError):
                return default

        def parsed_date(value, default=None):
            try:
                return date.fromisoformat(str(value)[:10])
            except (TypeError, ValueError):
                return default or date.today()

        validated_data.pop('profile_data', None)

        national_id_number = validated_data.get('national_id_number')
        if not national_id_number:
            national_id_number = None

        user = User.objects.create_user(
            email=validated_data['email'],
            password=password,
            phone=validated_data.get('phone', ''),
            full_name=validated_data.get('full_name', ''),
            present_address=validated_data.get('present_address', ''),
            date_of_birth=validated_data.get('date_of_birth'),
            national_id_number=national_id_number,
            government_id_type=validated_data.get('government_id_type') or None,
            preferred_language=validated_data.get('preferred_language', 'en'),
            emergency_contact_name=validated_data.get('emergency_contact_name', ''),
            emergency_contact_phone=validated_data.get('emergency_contact_phone', ''),
            consent_terms=validated_data.get('consent_terms', False),
            consent_background_check=validated_data.get('consent_background_check', False),
            account_status='active',
        )

        role, _ = Role.objects.get_or_create(
            name=role_name,
            defaults={'panel_type': role_name if role_name in {'farmer', 'doctor', 'delivery', 'pharmacy', 'pharmacist', 'researcher', 'admin'} else 'admin'},
        )
        user.roles.add(role)
        if role_name == 'farmer':
            farmer_profile, _ = FarmerProfile.objects.update_or_create(
                user=user,
                defaults={
                    'farm_name': role_data.get('farm_name') or f"{user.full_name}'s Farm",
                    'owner_name': role_data.get('owner_name') or role_data.get('farm_owner') or user.full_name,
                    'farm_location': role_data.get('farm_location') or user.present_address,
                    'farm_address': role_data.get('farm_address') or role_data.get('farm_location') or user.present_address,
                    'farm_type': str(role_data.get('farm_type', 'mixed')).lower(),
                    'number_of_birds': role_data.get('number_of_birds') or role_data.get('bird_count') or None,
                    'farm_registration_number': role_data.get('farm_registration_number') or role_data.get('farm_registration') or None,
                    'years_in_farming': role_data.get('years_in_farming') or None,
                    'experience_level': str(role_data.get('experience_level', '')).lower() or None,
                    'primary_diseases_faced': role_data.get('primary_diseases_faced') or role_data.get('primary_disease') or None,
                    'feed_type': role_data.get('feed_type') or None,
                    'feed_sourcing_method': role_data.get('feed_sourcing_method') or None,
                    'existing_vet_consultant': role_data.get('existing_vet_consultant') or role_data.get('vet_contact') or None,
                    'farm_photos': role_data.get('farm_photos', []),
                    'number_of_active_workers': role_data.get('number_of_active_workers') or role_data.get('active_workers') or None,
                    'consent_data_collection': role_data.get('consent_data_collection', role_data.get('consent', True)),
                },
            )
            # Consultation booking selects farms from the farm-management
            # table, while registration details live on FarmerProfile. Keep
            # the primary farm represented in both places from day one.
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
        if role_name == 'doctor':
            expiry = parsed_date(role_data.get('license_expiry'), date.today().replace(year=date.today().year + 1))
            DoctorProfile.objects.update_or_create(
                user=user,
                defaults={
                    'clinic_hospital_name': role_data.get('clinic_name') or role_data.get('workplace') or 'Independent Veterinary Practice',
                    'practice_address': role_data.get('practice_address') or user.present_address or 'Location not provided',
                    'latitude': role_data.get('latitude'),
                    'longitude': role_data.get('longitude'),
                    'veterinary_degree': role_data.get('degree') or 'Veterinary degree',
                    'university_name': role_data.get('university') or 'Not provided',
                    'graduation_year': integer(role_data.get('graduation_year'), date.today().year),
                    'license_number': role_data.get('license_number') or f'PENDING-{user.id}',
                    'license_issuing_authority': role_data.get('issuing_authority') or 'Pending verification',
                    'license_expiry_date': expiry,
                    'specialty': role_data.get('specialty') or 'General Veterinary Medicine',
                    'poultry_focus_area': role_data.get('specialty', ''),
                    'years_of_experience': integer(role_data.get('years_experience')),
                    'consultation_mode': {'Online': 'online', 'Offline': 'offline', 'Field Visit': 'offline', 'Both': 'both'}.get(role_data.get('consult_mode'), 'both'),
                    'council_registration_proof_url': 'pending-review',
                    'service_fee': decimal(role_data.get('fees')),
                    'consent_platform_guidelines': True,
                    'is_verified': user.is_verified,
                    'is_available': user.account_status == 'active',
                },
            )
        if role_name == 'delivery':
            DeliveryProfile.objects.update_or_create(
                user=user,
                defaults={
                    'drivers_license_number': role_data.get('license_number') or f'PENDING-{user.id}',
                    'license_class': role_data.get('license_class') or 'Pending',
                    'license_expiry_date': parsed_date(role_data.get('license_expiry')),
                    'license_photo_url': role_data.get('license_photo_url') or 'pending-upload',
                    'proof_of_work_url': role_data.get('proof_of_right_to_work') or None,
                    'prior_delivery_experience': role_data.get('prior_delivery_experience') or None,
                    'area_coverage': role_data.get('area_coverage') or None,
                    'availability_schedule': {'description': role_data.get('availability', '')},
                    'current_status': 'offline',
                },
            )
        if role_name == 'pharmacy':
            PharmacyOrganization.objects.update_or_create(
                user=user,
                defaults={
                    'business_name': role_data.get('business_name') or user.full_name,
                    'authorized_contact_person': role_data.get('contact_person') or user.full_name,
                    'business_registration_number': role_data.get('business_reg_number') or f'PENDING-{user.id}',
                    'trade_license_url': role_data.get('trade_license') or 'pending-upload',
                    'tax_vat_tin_number': role_data.get('tax_number') or 'pending',
                    'business_address': role_data.get('business_address') or user.present_address,
                    'warehouse_address': role_data.get('warehouse_address') or None,
                    'number_of_pharmacists': integer(role_data.get('number_of_pharmacists')),
                    'responsible_pharmacist_name': role_data.get('responsible_pharmacist') or None,
                },
            )
        if role_name == 'researcher':
            expertise = role_data.get('areas_of_expertise', '')
            if not isinstance(expertise, list):
                expertise = [item.strip() for item in str(expertise).split(',') if item.strip()]
            research_role = str(role_data.get('research_role', '')).lower()
            allowed_research_roles = {'nutrition', 'disease', 'genetics', 'welfare', 'growth', 'economics'}
            ResearcherProfile.objects.update_or_create(
                user=user,
                defaults={
                    'institution_name': role_data.get('institution') or 'Not provided',
                    'institutional_email': role_data.get('institutional_email') or user.email,
                    'department': role_data.get('department') or 'Not provided',
                    'highest_degree': role_data.get('degree') or 'Not provided',
                    'field_of_study': role_data.get('field_of_study') or 'Not provided',
                    'university_name': role_data.get('university') or 'Not provided',
                    'graduation_year': integer(role_data.get('graduation_year'), date.today().year),
                    'cv_url': role_data.get('cv_url') or 'pending-upload',
                    'publications_portfolio_url': role_data.get('publications') or None,
                    'areas_of_expertise': expertise,
                    'years_of_research_experience': integer(role_data.get('years_experience')),
                    'poultry_specific_experience': role_data.get('poultry_experience') or None,
                    'research_role_type': research_role if research_role in allowed_research_roles else None,
                    'conflict_of_interest_declaration': role_data.get('conflict_declaration', True),
                    'publication_consent': role_data.get('publication_consent', True),
                    'ip_agreement': role_data.get('ip_agreement', True),
                    'reference_name': role_data.get('reference_name') or None,
                    'reference_title': role_data.get('reference_title') or None,
                    'reference_email': role_data.get('reference_email') or None,
                },
            )
        if role_name == 'admin':
            employment = str(role_data.get('employment_type', 'full_time')).lower().replace(' ', '_')
            if employment not in {'full_time', 'part_time', 'contract'}:
                employment = 'full_time'
            requested_sub_role = str(role_data.get('access_level', 'operations')).lower().replace(' ', '_')
            sub_role = requested_sub_role if requested_sub_role in {'super', 'operations', 'finance', 'content', 'research', 'delivery', 'pharmacy', 'support'} else 'operations'
            AdminProfile.objects.update_or_create(
                user=user,
                defaults={
                    'account_id_number': role_data.get('account_id') or None,
                    'job_title': role_data.get('job_title') or 'Administrator',
                    'department': role_data.get('department') or 'Operations',
                    'work_location': role_data.get('work_location') or None,
                    'employment_type': employment,
                    'start_date': parsed_date(role_data.get('start_date')),
                    'admin_sub_role': sub_role,
                    'tech_skill_level': 'intermediate',
                    'confidentiality_agreement_accepted': role_data.get('confidentiality_agreement', True),
                    'background_check_consent': role_data.get('background_consent', True),
                    'previous_experience': role_data.get('prior_experience') or role_data.get('previous_work') or None,
                },
            )
        return user


class UserLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)


class UserSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()
    profile_data = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'phone', 'full_name', 'profile_photo_url',
            'date_of_birth', 'present_address', 'national_id_number',
            'government_id_type', 'preferred_language',
            'emergency_contact_name', 'emergency_contact_phone',
            'account_status', 'is_verified', 'date_joined', 'updated_at',
            'roles', 'profile_data'
        ]

    def get_roles(self, obj):
        return [role.name for role in obj.roles.all()]

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
                if field.name in {'id', 'user', 'approved_by_admin', 'reporting_manager'}:
                    continue
                value = getattr(profile, field.name)
                if hasattr(value, 'isoformat'):
                    value = value.isoformat()
                data[field.name] = value
            return data
        return obj.profile_data
