"""Create the missing PharmacySale / PharmacyCommission rows for pharmacy orders that were delivered through the
proof-approval workflow (F-005) before that path wrote them. Idempotent: `create_pharmacy_sale_and_commission`
uses get_or_create on the unique order reference, so re-running (or running over orders that already have rows)
changes nothing.

    python manage.py backfill_pharmacy_sales --dry-run     # list what would be created
    python manage.py backfill_pharmacy_sales
"""
from django.core.management.base import BaseCommand

from audit.models import AdminPanelRecord
from pharmacy.models import PharmacySale
from pharmacy.services import create_pharmacy_sale_and_commission


class Command(BaseCommand):
    help = 'Backfill pharmacy sales/commissions for delivered pharmacy orders that have none.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true')

    def handle(self, *args, **options):
        have = set(PharmacySale.objects.values_list('order_reference', flat=True))
        todo, created = [], 0
        for rec in AdminPanelRecord.objects.filter(module='pharmacy-orders'):
            p = rec.payload or {}
            if p.get('status') == 'delivered' and p.get('id') and str(p['id']) not in have:
                todo.append(p)
        for p in todo:
            if options['dry_run']:
                self.stdout.write(f"would create sale for {p.get('id')} ({p.get('total_amount')})")
            elif create_pharmacy_sale_and_commission(p) is not None:
                created += 1
        self.stdout.write(self.style.SUCCESS(
            f"{'would create' if options['dry_run'] else 'created'} {len(todo) if options['dry_run'] else created} sale(s); "
            f"{len(have)} already existed"))
