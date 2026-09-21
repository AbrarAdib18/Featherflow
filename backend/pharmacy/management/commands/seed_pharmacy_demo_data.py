"""Idempotent demo data for the pharmacy staff panel's Suppliers screen.

The catalogue (`pharmacy_catalogue_medicines`) and order bridge already carry
real/seeded data; `pharmacy_suppliers` was the one sub-table left empty with
no seeder, leaving the Suppliers screen with nothing to demo or test against.

Run:  backend/venv/Scripts/python.exe manage.py seed_pharmacy_demo_data

Safe to re-run: suppliers are get_or_create'd on (pharmacy_user, supplier_name),
so running this three times in a row creates the same rows, not duplicates.
"""
from django.core.management.base import BaseCommand
from django.utils import timezone

from pharmacy.models import PharmacySupplier
from users.models import User

DEMO_SUPPLIERS = [
    {
        'supplier_name': 'AgroVet Distributors Ltd.',
        'contact_person': 'Rafiqul Islam',
        'phone': '01711000001',
        'email': 'sales@agrovetdist.example.com',
        'address': 'Tejgaon Industrial Area, Dhaka',
        'products_supplied': 'Vaccines, antibiotics, vitamins',
        'payment_terms': 'Net 30',
    },
    {
        'supplier_name': 'Poultry Health Supplies',
        'contact_person': 'Nasrin Akter',
        'phone': '01711000002',
        'email': 'orders@poultryhealth.example.com',
        'address': 'Gazipur Sadar, Gazipur',
        'products_supplied': 'Feed supplements, disinfectants',
        'payment_terms': 'Cash on delivery',
    },
]


class Command(BaseCommand):
    help = 'Seed demo pharmacy suppliers for every pharmacy-role user (idempotent).'

    def handle(self, *args, **options):
        pharmacy_users = User.objects.filter(roles__name='pharmacy', account_status='active').distinct()
        if not pharmacy_users.exists():
            self.stdout.write(self.style.WARNING('No pharmacy users found — nothing to seed.'))
            return

        created_count = 0
        for pharmacy_user in pharmacy_users:
            for demo in DEMO_SUPPLIERS:
                _, created = PharmacySupplier.objects.get_or_create(
                    pharmacy_user=pharmacy_user, supplier_name=demo['supplier_name'],
                    defaults={
                        **{k: v for k, v in demo.items() if k != 'supplier_name'},
                        'is_active': True,
                        'created_at': timezone.now(),
                        'updated_at': timezone.now(),
                    },
                )
                if created:
                    created_count += 1

        self.stdout.write(self.style.SUCCESS(
            f'Seeded {created_count} new supplier row(s) across {pharmacy_users.count()} pharmacy user(s).'
        ))
