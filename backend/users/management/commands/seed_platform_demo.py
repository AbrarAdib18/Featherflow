"""Idempotent demo accounts for every Featherflow role, each with the real
role-profile row(s) its dashboard needs and a realistic verification/approval
state so the signup + approval flows can be exercised end to end by hand.

Run:  python manage.py seed_platform_demo
Safe to re-run — rows are matched on email / user and updated in place.

Demo password (all accounts): FeatherflowDemo@2026
"""
from datetime import date
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from farms.models import Farm
from pharmacy.models import PharmacyMedicine
from profiles.models import (
    AdminProfile, DeliveryProfile, DoctorProfile, FarmerProfile,
    PharmacyOrganization, ResearcherProfile,
)
from tax.models import TaxPayment, TaxProfile
from users.models import Role, User, UserRole


PASSWORD = 'FeatherflowDemo@2026'


def _user(email, phone, name, address, status='active', verified=True, dob=date(1990, 1, 15)):
    now = timezone.now()
    user, _ = User.objects.update_or_create(
        email=email,
        defaults={
            'phone': phone, 'full_name': name, 'present_address': address,
            'date_of_birth': dob, 'preferred_language': 'en',
            'consent_terms': True, 'consent_background_check': True,
            'account_status': status, 'is_verified': verified,
            # Demo accounts skip the OTP step so they can be signed into directly.
            'email_verified_at': now, 'phone_verified_at': now,
        },
    )
    user.set_password(PASSWORD)
    user.save()
    return user


def _role(user, role_name, panel=None):
    role, _ = Role.objects.get_or_create(
        name=role_name,
        defaults={'panel_type': panel or ('admin' if role_name.startswith('admin') else role_name)},
    )
    UserRole.objects.get_or_create(user=user, role=role)
    return role


class Command(BaseCommand):
    help = 'Create idempotent, complete demo accounts for every Featherflow role.'

    @transaction.atomic
    def handle(self, *args, **options):
        made = []

        # ── Farmers (active) ───────────────────────────────────────────────
        farmers = [
            ('farmer.rashed@example.com', '+8801711000101', 'Md. Rashed Karim', 'Savar, Dhaka',
             'Rashed Poultry Farm', 'broiler', 4200),
            ('farmer.nasima@example.com', '+8801711000102', 'Nasima Akter', 'Mymensingh Sadar',
             'Shapla Layer Farm', 'layer', 2800),
        ]
        for email, phone, name, addr, farm_name, farm_type, birds in farmers:
            u = _user(email, phone, name, addr)
            _role(u, 'farmer')
            fp, _ = FarmerProfile.objects.update_or_create(
                user=u,
                defaults={
                    'farm_name': farm_name, 'owner_name': name,
                    'farm_location': addr, 'farm_address': addr,
                    'farm_type': farm_type, 'number_of_birds': birds,
                    'years_in_farming': 8, 'experience_level': 'expert',
                    'number_of_active_workers': 4, 'consent_data_collection': True,
                    'farm_photos': [],
                },
            )
            Farm.objects.get_or_create(
                farmer=fp, farm_name=farm_name,
                defaults={'farm_type': farm_type, 'location': addr, 'address': addr,
                          'is_active': True},
            )

            # Tax profile + a couple of recorded payments so the Tax screen has
            # a realistic estimate and history. Poultry sales are agricultural
            # income, so income tax comes out at zero (agri + threshold exemption).
            TaxProfile.objects.update_or_create(
                user=u,
                defaults={
                    'land_area': 50, 'land_unit': 'katha', 'land_use': 'agricultural',
                    'location': 'rural', 'income_type': 'agricultural',
                    'exemptions': 0, 'rebates': 0, 'is_senior': False,
                    'district': addr.split(',')[-1].strip() or addr,
                    'vehicles': [{'type': 'motorcycle', 'count': 1},
                                 {'type': 'van', 'count': 1}],
                },
            )
            this_year = date.today().year
            for tax_type, amount, ref in (('land', 5000, 'CH-LAND-DEMO'),
                                          ('vehicle', 2000, 'CH-VEH-DEMO')):
                TaxPayment.objects.get_or_create(
                    user=u, tax_type=tax_type, reference_number=ref,
                    defaults={'amount': amount,
                              'payment_date': date(this_year, 2, 15),
                              'notes': 'Demo payment (seed_platform_demo).'},
                )
            made.append(f'farmer  {email}  (active, tax profile + 2 payments)')

        # ── Doctors: one verified/active, one pending ─────────────────────
        doctors = [
            ('dr.samira.rahman@example.com', '+8801711000201', 'Dr. Samira Rahman', 'Uttara, Dhaka',
             'active', True, 'BVC-DEMO-0001'),
            ('dr.pending.kabir@example.com', '+8801711000202', 'Dr. Mahfuz Kabir', 'Mymensingh Sadar',
             'pending', False, 'BVC-DEMO-0002'),
        ]
        for email, phone, name, addr, status, verified, lic in doctors:
            u = _user(email, phone, name, addr, status=status, verified=verified)
            _role(u, 'doctor')
            DoctorProfile.objects.update_or_create(
                user=u,
                defaults={
                    'clinic_hospital_name': f'{name.split()[-1]} Avian Care',
                    'practice_address': addr,
                    'latitude': Decimal('23.8741'), 'longitude': Decimal('90.3983'),
                    'veterinary_degree': 'Doctor of Veterinary Medicine (DVM)',
                    'university_name': 'Bangladesh Agricultural University',
                    'graduation_year': 2016, 'license_number': lic,
                    'license_issuing_authority': 'Bangladesh Veterinary Council',
                    'license_expiry_date': date(2029, 12, 31),
                    'specialty': 'Avian Medicine', 'poultry_focus_area': 'Broiler respiratory disease',
                    'years_of_experience': 9, 'consultation_mode': 'both',
                    'council_registration_proof_url': 'admin-seed/bvc-registration.pdf',
                    'cv_url': 'admin-seed/cv.pdf', 'service_fee': Decimal('900.00'),
                    'consent_platform_guidelines': True,
                    'is_verified': verified, 'is_available': verified,
                },
            )
            made.append(f'doctor  {email}  ({status})')

        # ── Pharmacies: one verified, one pending ─────────────────────────
        pharmacies = [
            ('pharmacy.greenvet@example.com', '+8801711000301', 'GreenVet Pharmacy', 'Dhanmondi, Dhaka',
             'active', True, 'DGDA-DEMO-0001'),
            ('pharmacy.pending.agrocare@example.com', '+8801711000302', 'AgroCare Veterinary Store',
             'Rajshahi Sadar', 'pending', False, 'DGDA-DEMO-0002'),
        ]
        for email, phone, name, addr, status, verified, reg in pharmacies:
            u = _user(email, phone, name, addr, status=status, verified=verified)
            _role(u, 'pharmacy')
            PharmacyOrganization.objects.update_or_create(
                user=u,
                defaults={
                    'business_name': f'{name} Ltd.', 'authorized_contact_person': 'Mahfuzur Rahman',
                    'business_registration_number': reg, 'trade_license_url': 'admin-seed/trade-license.pdf',
                    'tax_vat_tin_number': 'TIN-DEMO-0001', 'business_address': addr,
                    'number_of_pharmacists': 3, 'responsible_pharmacist_name': 'Mahfuzur Rahman',
                    'is_verified': verified,
                },
            )
            made.append(f'pharmacy  {email}  ({status})')

            # An approved catalogue so the pharmacy dashboard, the farmer
            # marketplace and the admin pharmacy-oversight screens have real
            # products to show. Only for the verified pharmacy. Matched on
            # (pharmacy_user, legacy_record_id) so re-running never duplicates.
            if verified:
                catalogue = [
                    ('PH-DEMO-01', 'Amoxivet 500', 'Amoxicillin', 'antibiotic', True,
                     Decimal('12.50'), 480, 'tablet', "10x10 blister"),
                    ('PH-DEMO-02', 'Newcastle LaSota Vaccine', 'ND LaSota strain', 'vaccine', True,
                     Decimal('320.00'), 60, 'bottle', "1000 doses/vial"),
                    ('PH-DEMO-03', 'Coxi-Stop Solution', 'Amprolium 20%', 'antiparasitic', False,
                     Decimal('185.00'), 90, 'bottle', "1 litre"),
                    ('PH-DEMO-04', 'PoultryVit AD3E', 'Vitamin AD3E', 'vitamin', False,
                     Decimal('240.00'), 140, 'bottle', "1 litre"),
                    ('PH-DEMO-05', 'Virocid Disinfectant', 'Glutaraldehyde blend', 'disinfectant', False,
                     Decimal('550.00'), 40, 'bottle', "5 litre"),
                    ('PH-DEMO-06', 'Broiler Booster Premix', 'Multi-enzyme premix', 'feed_supplement', False,
                     Decimal('95.00'), 200, 'kg', "25 kg sack"),
                ]
                _pnow = timezone.now()
                for ref, mname, generic, cat, rx, price, qty, unit, pack in catalogue:
                    PharmacyMedicine.objects.update_or_create(
                        pharmacy_user=u, legacy_record_id=ref,
                        defaults={
                            'created_at': _pnow, 'updated_at': _pnow,
                            'name': mname, 'generic_name': generic,
                            'manufacturer': 'Featherflow Demo Labs', 'category': cat,
                            'prescription_required': rx, 'price': price,
                            'stock_quantity': qty, 'unit': unit, 'pack_size': pack,
                            'description': f'{mname} — demo catalogue item.',
                            'expiry_date': date(date.today().year + 1, 6, 30),
                            'batch_number': f'B-{ref}',
                            'is_active': True, 'is_approved': True,
                        },
                    )
                made.append(f'  + {len(catalogue)} approved catalogue medicines for {email}')

        # ── Delivery riders: one approved, one pending ────────────────────
        riders = [
            ('rider.arif@example.com', '+8801711000401', 'Arif Mahmud', 'Mirpur, Dhaka',
             'active', 'DL-DEMO-0001', True),
            ('rider.pending.belal@example.com', '+8801711000402', 'Belal Hossain', 'Gazipur Sadar',
             'pending', 'DL-DEMO-0002', False),
        ]
        approver = User.objects.filter(roles__name='admin_super').first()
        for email, phone, name, addr, status, lic, approved in riders:
            u = _user(email, phone, name, addr, status=status, verified=(status == 'active'))
            _role(u, 'delivery')
            DeliveryProfile.objects.update_or_create(
                user=u,
                defaults={
                    'drivers_license_number': lic, 'license_class': 'B',
                    'license_expiry_date': date(2030, 6, 30),
                    'license_photo_url': 'admin-seed/license.jpg',
                    'area_coverage': addr,
                    'availability_schedule': {'description': 'Weekdays 9-6',
                                              'vehicle': {'type': 'Motorcycle',
                                                          'registration': f'DHAKA-{lic[-6:]}'}},
                    'current_status': 'offline',
                    'approved_by_admin': approver if approved else None,
                },
            )
            made.append(f'delivery  {email}  ({status})')

        # ── Researchers: one verified, one pending ────────────────────────
        researchers = [
            ('research.fariha@example.com', '+8801711000501', 'Fariha Tasnim', 'Dhaka',
             'active', True),
            ('research.pending.mahmud@example.com', '+8801711000502', 'Mahmudul Hasan', 'Mymensingh',
             'pending', False),
        ]
        for email, phone, name, addr, status, verified in researchers:
            u = _user(email, phone, name, addr, status=status, verified=verified)
            _role(u, 'researcher')
            ResearcherProfile.objects.update_or_create(
                user=u,
                defaults={
                    'institution_name': 'Bangladesh Agricultural University',
                    'institutional_email': email, 'department': 'Poultry Science',
                    'highest_degree': 'PhD', 'field_of_study': 'Avian epidemiology',
                    'university_name': 'Bangladesh Agricultural University',
                    'graduation_year': 2016, 'cv_url': 'admin-seed/cv.pdf',
                    'areas_of_expertise': ['Disease surveillance', 'Biosecurity'],
                    'years_of_research_experience': 7, 'research_role_type': 'disease',
                    'conflict_of_interest_declaration': True, 'publication_consent': True,
                    'ip_agreement': True, 'is_verified': verified,
                },
            )
            made.append(f'researcher  {email}  ({status})')

        # ── Admins: super + one per tier, all approved/active, plus one pending
        admins = [
            ('admin.super@example.com', '+8801711000601', 'Owner Admin', 'admin_super', 'super', 'approved', True),
            ('ops.nusrat@example.com', '+8801711000602', 'Nusrat Jahan', 'admin_operations', 'operations', 'approved', True),
            ('finance.tanvir@example.com', '+8801711000603', 'Tanvir Hasan', 'admin_finance', 'finance', 'approved', True),
            ('support.raisa@example.com', '+8801711000604', 'Raisa Ahmed', 'admin_support', 'support', 'approved', True),
            ('admin.pending@example.com', '+8801711000605', 'Applicant Admin', 'admin_support', 'support', 'pending', False),
        ]
        for email, phone, name, role_name, sub_role, approval, active in admins:
            status = 'active' if approval == 'approved' else 'pending'
            u = _user(email, phone, name, 'Dhaka', status=status, verified=active)
            _role(u, role_name, panel='admin')
            role_obj = Role.objects.filter(name=role_name).first()
            AdminProfile.objects.update_or_create(
                user=u,
                defaults={
                    'job_title': name, 'department': sub_role.title(),
                    'start_date': date(2025, 1, 1), 'employment_type': 'full_time',
                    'admin_sub_role': sub_role, 'admin_role': role_obj,
                    'access_level_requested': sub_role,
                    'tech_skill_level': 'advanced',
                    'confidentiality_agreement_accepted': True,
                    'background_check_consent': True,
                    'internal_approval_by_founder_hr': approval == 'approved',
                    'approval_status': approval, 'is_active': active,
                    'hourly_rate': Decimal('0.00') if sub_role == 'super' else Decimal('450.00'),
                },
            )
            made.append(f'{role_name}  {email}  ({approval})')

        self.stdout.write(self.style.SUCCESS(
            'Seeded demo accounts:\n  ' + '\n  '.join(made)
            + f'\n\nAll accounts share the password: {PASSWORD}'
        ))
