"""Copy the JSON-backed pharmacy catalogue (backend_admin_records module
``pharmacy-products``) into the real ``pharmacy_catalogue_medicines`` table.

Idempotent: rows are matched on (pharmacy_user, legacy_record_id), so re-running
updates in place and never duplicates. The source JSON records are left intact
as a fallback during the transition.

    python manage.py migrate_pharmacy_catalogue --dry-run
    python manage.py migrate_pharmacy_catalogue
"""

from datetime import date, datetime, timedelta

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from audit.models import AdminPanelRecord
from pharmacy.models import PharmacyMedicine
from users.models import User

# Legacy category -> new relational category. The old catalogue only had four
# buckets; anything ambiguous lands in 'other' for a pharmacist to refine.
CATEGORY_MAP = {
    'medicines': 'other',
    'vaccines': 'vaccine',
    'supplements': 'feed_supplement',
    'equipment': 'equipment',
}
VALID_UNITS = {'tablet', 'capsule', 'ml', 'gram', 'kg', 'piece', 'pack', 'bottle'}
UNIT_MAP = {'vial': 'bottle', 'unit': 'piece', 'box': 'pack', 'strip': 'pack'}


def _parse_date(value):
    if isinstance(value, date):
        return value
    for fmt in ('%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%S.%f'):
        try:
            return datetime.strptime(str(value)[:len(fmt) + 6], fmt).date()
        except (TypeError, ValueError):
            continue
    try:
        return datetime.fromisoformat(str(value)).date()
    except (TypeError, ValueError):
        return None


class Command(BaseCommand):
    help = 'Migrate the JSON pharmacy catalogue into pharmacy_catalogue_medicines.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true',
                            help='Report what would change without writing.')

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        records = list(AdminPanelRecord.objects.filter(module='pharmacy-products'))
        approved_ids = {
            r.record_id for r in AdminPanelRecord.objects.filter(module='medicines')
            if (r.payload or {}).get('status') == 'Approved'
        }

        created = updated = skipped = 0
        user_cache = {}

        with transaction.atomic():
            for record in records:
                payload = record.payload or {}
                legacy_id = str(payload.get('id') or record.record_id)
                owner_id = str(payload.get('owner_id') or '')

                if owner_id not in user_cache:
                    user_cache[owner_id] = User.objects.filter(pk=owner_id).first() if owner_id else None
                pharmacy_user = user_cache[owner_id]
                if pharmacy_user is None:
                    self.stderr.write(f'  skip {legacy_id}: owner {owner_id!r} not found')
                    skipped += 1
                    continue

                expiry = _parse_date(payload.get('expiry_date'))
                if expiry is None:
                    expiry = timezone.now().date() + timedelta(days=365)
                    self.stderr.write(f'  {legacy_id}: unparseable expiry, defaulting to +365d')

                legacy_category = str(payload.get('category') or '').lower()
                category = CATEGORY_MAP.get(legacy_category, 'other')
                prescription_required = legacy_category == 'medicines'

                raw_unit = str(payload.get('unit') or 'piece').lower()
                unit = raw_unit if raw_unit in VALID_UNITS else UNIT_MAP.get(raw_unit, 'piece')

                try:
                    price = round(float(payload.get('price') or 0), 2)
                except (TypeError, ValueError):
                    price = 0
                try:
                    stock = int(payload.get('stock_count') or payload.get('stock_quantity') or 0)
                except (TypeError, ValueError):
                    stock = 0

                # OTC auto-approves; prescription items inherit the legacy
                # approval mirror (default to not-approved / pending review).
                is_approved = (not prescription_required) or (legacy_id in approved_ids)

                defaults = {
                    'pharmacy_user': pharmacy_user,
                    'name': str(payload.get('name') or 'Unnamed medicine'),
                    'generic_name': payload.get('generic_name') or None,
                    'manufacturer': str(payload.get('manufacturer') or ''),
                    'category': category,
                    'prescription_required': prescription_required,
                    'price': price,
                    'stock_quantity': stock,
                    'unit': unit,
                    'pack_size': str(payload.get('pack_size') or ''),
                    'description': payload.get('description') or None,
                    'dosage_instructions': payload.get('dosage_instructions') or None,
                    'storage_instructions': payload.get('storage_instructions') or None,
                    'cold_chain_required': legacy_category == 'vaccines',
                    'expiry_date': expiry,
                    'batch_number': payload.get('batch_number') or None,
                    'images': payload.get('images') if isinstance(payload.get('images'), list) else [],
                    'is_active': payload.get('is_active', True) is not False,
                    'is_approved': is_approved,
                }

                existing = PharmacyMedicine.objects.filter(
                    pharmacy_user=pharmacy_user, legacy_record_id=legacy_id,
                ).first()

                now = timezone.now()
                if existing:
                    if dry_run:
                        updated += 1
                        continue
                    for field, value in defaults.items():
                        setattr(existing, field, value)
                    existing.updated_at = now
                    existing.save()
                    updated += 1
                else:
                    if dry_run:
                        created += 1
                        continue
                    PharmacyMedicine.objects.create(
                        legacy_record_id=legacy_id, created_at=now, updated_at=now,
                        **defaults,
                    )
                    created += 1

            if dry_run:
                transaction.set_rollback(True)

        prefix = '[dry-run] ' if dry_run else ''
        self.stdout.write(self.style.SUCCESS(
            f'{prefix}{len(records)} source records -> '
            f'created {created}, updated {updated}, skipped {skipped}.'
        ))
