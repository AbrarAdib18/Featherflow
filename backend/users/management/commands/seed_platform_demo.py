from datetime import date
from decimal import Decimal

from django.core.management.base import BaseCommand

from profiles.models import DoctorProfile
from users.models import Role, User, UserRole


PASSWORD = 'FeatherflowDemo@2026'


ACCOUNTS = [
    # Farmers
    ('farmer.rashed@example.com', '+8801700001101', 'Md. Rashed Karim', 'farmer', 'active', 'Savar, Dhaka', {'farm_name': 'Rashed Poultry Farm', 'farm_type': 'Broiler', 'flock_size': 4200, 'bio': 'Commercial broiler farmer with eight years of production experience.'}),
    ('farmer.nasima@example.com', '+8801700001102', 'Nasima Akter', 'farmer', 'active', 'Mymensingh Sadar', {'farm_name': 'Shapla Layer Farm', 'farm_type': 'Layer', 'flock_size': 2800, 'bio': 'Layer farmer focused on flock welfare and consistent egg production.'}),
    ('farmer.sojib@example.com', '+8801700001103', 'Sojib Mia', 'farmer', 'active', 'Cumilla Sadar', {'farm_name': 'Green Field Poultry', 'farm_type': 'Mixed', 'flock_size': 1600, 'bio': 'Smallholder poultry entrepreneur managing broiler and layer sheds.'}),
    # Delivery riders
    ('rider.arif@example.com', '+8801700001201', 'Arif Mahmud', 'delivery', 'active', 'Mirpur, Dhaka', {'vehicle_type': 'Motorcycle', 'vehicle_registration': 'DHAKA-METRO-HA-21-4587', 'service_area': 'Dhaka North', 'license_number': 'DL-DHK-220184', 'bio': 'Verified motorcycle rider covering pharmacy deliveries in Dhaka North.'}),
    ('rider.belal@example.com', '+8801700001202', 'Belal Hossain', 'delivery', 'active', 'Gazipur Sadar', {'vehicle_type': 'Motorcycle', 'vehicle_registration': 'GAZIPUR-HA-13-7742', 'service_area': 'Gazipur', 'license_number': 'DL-GAZ-198833', 'bio': 'Experienced last-mile delivery rider serving farms across Gazipur.'}),
    ('rider.tania@example.com', '+8801700001203', 'Tania Sultana', 'delivery', 'active', 'Uttara, Dhaka', {'vehicle_type': 'Scooter', 'vehicle_registration': 'DHAKA-METRO-HA-24-9031', 'service_area': 'Uttara and Tongi', 'license_number': 'DL-DHK-245901', 'bio': 'Medicine delivery specialist trained in cold-chain package handling.'}),
    # Pharmacy organizations/accounts
    ('pharmacy.greenvet@example.com', '+8801700001301', 'GreenVet Pharmacy', 'pharmacy', 'active', 'Dhanmondi, Dhaka', {'organization_name': 'GreenVet Pharmacy Ltd.', 'license_number': 'DGDA-VET-2024-0182', 'trade_license': 'TRAD/DCC/88421', 'pharmacist_in_charge': 'Mahfuzur Rahman', 'service_area': 'Dhaka', 'bio': 'Licensed veterinary pharmacy supplying vaccines and poultry medicines.'}),
    ('pharmacy.agrocare@example.com', '+8801700001302', 'AgroCare Veterinary Store', 'pharmacy', 'active', 'Rajshahi Sadar', {'organization_name': 'AgroCare Veterinary Store', 'license_number': 'DGDA-VET-2023-0714', 'trade_license': 'TRAD/RCC/39210', 'pharmacist_in_charge': 'Sharmin Jahan', 'service_area': 'Rajshahi', 'bio': 'Regional veterinary medicine and farm-supply organization.'}),
    ('pharmacy.poultrymed@example.com', '+8801700001303', 'PoultryMed Chattogram', 'pharmacy', 'active', 'Agrabad, Chattogram', {'organization_name': 'PoultryMed Chattogram', 'license_number': 'DGDA-VET-2025-0047', 'trade_license': 'TRAD/CCC/51008', 'pharmacist_in_charge': 'Javed Iqbal', 'service_area': 'Chattogram', 'bio': 'Veterinary pharmacy specializing in poultry vaccines and supplements.'}),
    # Researchers
    ('research.fariha@example.com', '+8801700001401', 'Fariha Tasnim', 'researcher', 'active', 'Dhaka', {'institution': 'Bangladesh Agricultural University', 'designation': 'Research Associate', 'research_area': 'Avian epidemiology', 'orcid': '0000-0002-1045-7781', 'bio': 'Research associate studying poultry disease surveillance and farm biosecurity.'}),
    ('research.mahmud@example.com', '+8801700001402', 'Mahmudul Hasan', 'researcher', 'active', 'Mymensingh', {'institution': 'Bangladesh Agricultural University', 'designation': 'Lecturer', 'research_area': 'Poultry nutrition', 'orcid': '0000-0003-4210-5624', 'bio': 'Academic researcher working on sustainable poultry-feed formulation.'}),
    ('research.sabiha@example.com', '+8801700001403', 'Sabiha Noor', 'researcher', 'active', 'Gazipur', {'institution': 'Bangladesh Livestock Research Institute', 'designation': 'Scientific Officer', 'research_area': 'Vaccine evaluation', 'orcid': '0000-0001-7752-9106', 'bio': 'Scientific officer researching vaccine response and flock immunity.'}),
    # Real backend team accounts
    ('ops.nusrat@example.com', '+8801700001501', 'Nusrat Jahan', 'admin_operations', 'active', 'Dhaka', {'department': 'Operations', 'bio': 'Operations administrator responsible for users, doctors and delivery.'}),
    ('finance.tanvir@example.com', '+8801700001502', 'Tanvir Hasan', 'admin_finance', 'active', 'Dhaka', {'department': 'Finance', 'bio': 'Finance administrator managing payments, subscriptions and refunds.'}),
    ('support.raisa@example.com', '+8801700001503', 'Raisa Ahmed', 'admin_support', 'active', 'Dhaka', {'department': 'Support', 'bio': 'Support administrator handling recovery, complaints and safety reviews.'}),
]


DOCTORS = [
    {
        'email': 'dr.samira.rahman@example.com', 'phone': '+8801700001601',
        'name': 'Dr. Samira Rahman', 'address': 'Uttara, Dhaka',
        'clinic_hospital_name': 'Uttara Avian Care Centre',
        'practice_address': 'Sector 7, Uttara, Dhaka', 'district': 'Dhaka',
        'latitude': Decimal('23.874200'), 'longitude': Decimal('90.397800'),
        'veterinary_degree': 'Doctor of Veterinary Medicine (DVM)',
        'university_name': 'Bangladesh Agricultural University',
        'graduation_year': 2016, 'license_number': 'BVC-DVM-2016-1842',
        'license_issuing_authority': 'Bangladesh Veterinary Council',
        'license_expiry_date': date(2028, 12, 31),
        'specialty': 'Avian Medicine and Surgery',
        'poultry_focus_area': 'Broiler respiratory disease and farm biosecurity',
        'years_of_experience': 9, 'consultation_mode': 'both',
        'service_fee': Decimal('900.00'),
    },
    {
        'email': 'dr.mahfuz.kabir@example.com', 'phone': '+8801700001602',
        'name': 'Dr. Mahfuz Kabir', 'address': 'Mymensingh Sadar',
        'clinic_hospital_name': 'Mymensingh Poultry Health Clinic',
        'practice_address': 'Charpara, Mymensingh', 'district': 'Mymensingh',
        'latitude': Decimal('24.747100'), 'longitude': Decimal('90.420300'),
        'veterinary_degree': 'Doctor of Veterinary Medicine (DVM)',
        'university_name': 'Chattogram Veterinary and Animal Sciences University',
        'graduation_year': 2014, 'license_number': 'BVC-DVM-2014-1296',
        'license_issuing_authority': 'Bangladesh Veterinary Council',
        'license_expiry_date': date(2029, 6, 30),
        'specialty': 'Poultry Pathology',
        'poultry_focus_area': 'Newcastle disease, coccidiosis and diagnostic pathology',
        'years_of_experience': 11, 'consultation_mode': 'both',
        'service_fee': Decimal('1100.00'),
    },
    {
        'email': 'dr.nabila.sultana@example.com', 'phone': '+8801700001603',
        'name': 'Dr. Nabila Sultana', 'address': 'Agrabad, Chattogram',
        'clinic_hospital_name': 'Chattogram Poultry Wellness',
        'practice_address': 'Agrabad Access Road, Chattogram', 'district': 'Chattogram',
        'latitude': Decimal('22.328600'), 'longitude': Decimal('91.812300'),
        'veterinary_degree': 'Doctor of Veterinary Medicine (DVM)',
        'university_name': 'Sylhet Agricultural University',
        'graduation_year': 2018, 'license_number': 'BVC-DVM-2018-2331',
        'license_issuing_authority': 'Bangladesh Veterinary Council',
        'license_expiry_date': date(2028, 9, 30),
        'specialty': 'Poultry Nutrition and Production Medicine',
        'poultry_focus_area': 'Layer nutrition, production loss and flock health planning',
        'years_of_experience': 7, 'consultation_mode': 'online',
        'service_fee': Decimal('800.00'),
    },
]


class Command(BaseCommand):
    help = 'Create idempotent, complete demo accounts for every Featherflow role.'

    def handle(self, *args, **options):
        for email, phone, name, role_name, status, address, profile in ACCOUNTS:
            role, _ = Role.objects.get_or_create(
                name=role_name,
                defaults={'display_name': role_name.replace('_', ' ').title()},
            )
            if role_name.startswith('admin_'):
                role.display_name = {
                    'admin_operations': 'Operations Admin',
                    'admin_finance': 'Finance Admin',
                    'admin_support': 'Support Agent',
                }[role_name]
                role.save(update_fields=['display_name'])
            user, _ = User.objects.update_or_create(
                email=email,
                defaults={
                    'phone': phone, 'full_name': name,
                    'present_address': address, 'date_of_birth': date(1992, 1, 15),
                    'preferred_language': 'en', 'consent_terms': True,
                    'consent_background_check': True, 'account_status': status,
                    'is_verified': True, 'profile_data': profile,
                    'is_staff': role_name.startswith('admin_'),
                },
            )
            user.set_password(PASSWORD)
            user.save()
            UserRole.objects.get_or_create(user=user, role=role)

        doctor_role, _ = Role.objects.get_or_create(
            name='doctor', defaults={'display_name': 'Doctor'})
        for item in DOCTORS:
            user, _ = User.objects.update_or_create(
                email=item['email'],
                defaults={
                    'phone': item['phone'], 'full_name': item['name'],
                    'present_address': item['address'], 'date_of_birth': date(1988, 5, 20),
                    'preferred_language': 'en', 'consent_terms': True,
                    'consent_background_check': True, 'account_status': 'pending',
                    'is_verified': False,
                    'profile_data': {'bio': item['poultry_focus_area']},
                },
            )
            user.set_password(PASSWORD)
            user.save()
            UserRole.objects.get_or_create(user=user, role=doctor_role)
            profile = {key: value for key, value in item.items()
                       if key not in {'email', 'phone', 'name', 'address'}}
            DoctorProfile.objects.update_or_create(
                user=user,
                defaults=profile | {
                    'cv_url': 'admin-seed/cv.pdf',
                    'council_registration_proof_url': 'admin-seed/bvc-registration.pdf',
                    'prescription_authority': True,
                    'emergency_on_call_availability': True,
                    'referral_network': 'District livestock office and partner diagnostic labs',
                    'consent_platform_guidelines': True,
                    'is_verified': False, 'is_available': False,
                },
            )

        self.stdout.write(self.style.SUCCESS(
            f'Seeded {len(ACCOUNTS)} role accounts and {len(DOCTORS)} pending doctors. '
            f'Demo password: {PASSWORD}'
        ))
