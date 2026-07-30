from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from users.models import Role, User
from profiles.models import DoctorProfile


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

    def create(self, validated_data):
        role_name = validated_data.pop('role', 'farmer').lower()
        role_data = validated_data.pop('role_data', {})
        validated_data.pop('password2')
        password = validated_data.pop('password')

        profile_payload = validated_data.pop('profile_data', {}) or {}
        if role_data:
            profile_payload.update(role_data)

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
            government_id_type=validated_data.get('government_id_type', ''),
            preferred_language=validated_data.get('preferred_language', 'en'),
            emergency_contact_name=validated_data.get('emergency_contact_name', ''),
            emergency_contact_phone=validated_data.get('emergency_contact_phone', ''),
            consent_terms=validated_data.get('consent_terms', False),
            consent_background_check=validated_data.get('consent_background_check', False),
            account_status='active',
            profile_data=profile_payload,
        )

        role, _ = Role.objects.get_or_create(
            name=role_name,
            defaults={'display_name': role_name.title()},
        )
        user.roles.add(role)
        if role_name == 'doctor':
            from datetime import date
            def number(value, default=0):
                try:
                    return float(value)
                except (TypeError, ValueError):
                    return default
            expiry = role_data.get('license_expiry')
            try:
                expiry = date.fromisoformat(str(expiry)[:10])
            except (TypeError, ValueError):
                expiry = date.today().replace(year=date.today().year + 1)
            DoctorProfile.objects.update_or_create(
                user=user,
                defaults={
                    'clinic_hospital_name': role_data.get('clinic_name') or role_data.get('workplace') or 'Independent Veterinary Practice',
                    'practice_address': role_data.get('practice_address') or user.present_address or 'Location not provided',
                    'district': role_data.get('district', ''),
                    'latitude': role_data.get('latitude'),
                    'longitude': role_data.get('longitude'),
                    'veterinary_degree': role_data.get('degree') or 'Veterinary degree',
                    'university_name': role_data.get('university') or 'Not provided',
                    'graduation_year': int(number(role_data.get('graduation_year'), date.today().year)),
                    'license_number': role_data.get('license_number') or f'PENDING-{user.id}',
                    'license_issuing_authority': role_data.get('issuing_authority') or 'Pending verification',
                    'license_expiry_date': expiry,
                    'specialty': role_data.get('specialty') or 'General Veterinary Medicine',
                    'poultry_focus_area': role_data.get('specialty', ''),
                    'years_of_experience': int(number(role_data.get('years_experience'))),
                    'consultation_mode': {'Online': 'online', 'Offline': 'offline', 'Field Visit': 'offline', 'Both': 'both'}.get(role_data.get('consult_mode'), 'both'),
                    'council_registration_proof_url': 'pending-review',
                    'service_fee': number(role_data.get('fees')),
                    'consent_platform_guidelines': True,
                    'is_verified': user.is_verified,
                    'is_available': user.account_status == 'active',
                },
            )
        return user


class UserLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)


class UserSerializer(serializers.ModelSerializer):
    roles = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'phone', 'full_name', 'profile_photo_url',
            'date_of_birth', 'present_address', 'national_id_number',
            'government_id_type', 'preferred_language',
            'emergency_contact_name', 'emergency_contact_phone',
            'account_status', 'is_verified', 'date_joined', 'updated_at', 'roles', 'profile_data'
        ]

    def get_roles(self, obj):
        return [role.name for role in obj.roles.all()]
