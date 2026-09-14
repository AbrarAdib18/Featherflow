"""One-time data migration: move files uploaded before the private-storage
migration (SECURITY_HARDENING_REPORT.md finding C2) off public ``MEDIA_ROOT``
and onto the private, signed-token, access-controlled storage system, then
rewrite every stored reference to the new URL.

    python manage.py migrate_legacy_public_uploads [--dry-run]

Covers every field that used to be written by ``default_storage`` before this
pass's fix: disease-scan images (``ml.DiseaseScan.image_urls``), delivery
proof-of-delivery photos (``delivery.DeliveryOrder.proof_of_delivery_url``),
prescription images (``AdminPanelRecord`` payload, module=``pharmacy-orders``),
and financial receipts / farm photos (``expenses.Expense/Revenue.receipt_url``,
``tax.TaxPayment.receipt_url``, ``profiles.FarmerProfile.farm_photos``).

Idempotent and safe to re-run: only rows whose URL still contains ``/media/``
are touched; already-migrated rows (pointing at
``/registration-documents/<token>/``) are left alone. A row whose referenced
file is missing from disk (a dangling reference — no worse off than before,
since it already 404s) is skipped with a warning, not modified.
"""
import re

from django.conf import settings
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand

from verification import documents as docs


def _relpath(url):
    """Public URL -> path relative to MEDIA_ROOT, or None if not a /media/ URL."""
    match = re.search(r'/media/(.+?)/?$', url or '')
    return match.group(1) if match else None


class Command(BaseCommand):
    help = 'Migrate pre-existing public-media uploads to private storage.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true',
                            help='Report what would change without changing it.')

    def handle(self, *args, **opts):
        dry = opts['dry_run']
        total_migrated = 0
        total_missing = 0

        total_migrated += self._migrate_disease_scans(dry)
        total_migrated += self._migrate_delivery_proofs(dry)
        total_migrated += self._migrate_prescription_orders(dry)
        m, missing = self._migrate_receipt_field('expenses', 'Expense', 'receipt_url', 'receipts', dry)
        total_migrated += m
        total_missing += missing
        m, missing = self._migrate_receipt_field('expenses', 'Revenue', 'receipt_url', 'receipts', dry)
        total_migrated += m
        total_missing += missing
        m, missing = self._migrate_receipt_field('tax', 'TaxPayment', 'receipt_url', 'tax-receipts', dry)
        total_migrated += m
        total_missing += missing

        verb = 'Would migrate' if dry else 'Migrated'
        self.stdout.write(self.style.SUCCESS(
            f'{verb} {total_migrated} file(s) to private storage.'))
        if total_missing:
            self.stdout.write(self.style.WARNING(
                f'{total_missing} referenced file(s) were already missing from disk — '
                f'left the (already-broken) URL as-is.'))

    def _move_to_private(self, url, kind, owner, dry):
        """Returns the new URL, or None if the file couldn't be found/moved."""
        rel = _relpath(url)
        if rel is None or not default_storage.exists(rel):
            return None
        if dry:
            return f'[dry-run would migrate] {rel}'
        with default_storage.open(rel, 'rb') as fh:
            file_bytes = fh.read()
        ext = rel.rsplit('.', 1)[-1].lower() if '.' in rel else 'jpg'
        content_type = f'image/{"jpeg" if ext == "jpg" else ext}'
        new_rel, token = docs.store(file_bytes, ext, kind, content_type, rel.rsplit('/', 1)[-1])
        if owner is not None:
            docs.claim(token, owner, document_type=kind)
        default_storage.delete(rel)
        return f'{settings.PUBLIC_BASE_URL}/api/auth/registration-documents/{token}/'

    def _migrate_disease_scans(self, dry):
        from ml.models import DiseaseScan
        migrated = 0
        for scan in DiseaseScan.objects.exclude(image_urls=[]).iterator():
            new_urls = []
            changed = False
            for url in scan.image_urls:
                if '/media/' not in url:
                    new_urls.append(url)
                    continue
                new_url = self._move_to_private(url, 'disease_scan', scan.user, dry)
                if new_url is None:
                    self.stderr.write(f'  [disease-scan {scan.id}] file missing on disk: {url}')
                    new_urls.append(url)
                else:
                    new_urls.append(new_url)
                    changed = True
                    migrated += 1
            if changed and not dry:
                scan.image_urls = new_urls
                scan.save(update_fields=['image_urls'])
        return migrated

    def _migrate_delivery_proofs(self, dry):
        from delivery.models import DeliveryOrder
        migrated = 0
        qs = DeliveryOrder.objects.exclude(proof_of_delivery_url='').exclude(
            proof_of_delivery_url__isnull=True)
        for order in qs.iterator():
            url = order.proof_of_delivery_url
            if '/media/' not in url:
                continue
            owner = order.delivery_person.user if order.delivery_person_id else None
            new_url = self._move_to_private(url, 'delivery_proof', owner, dry)
            if new_url is None:
                self.stderr.write(f'  [delivery order {order.id}] file missing on disk: {url}')
                continue
            migrated += 1
            if not dry:
                order.proof_of_delivery_url = new_url
                order.save(update_fields=['proof_of_delivery_url'])
        return migrated

    def _migrate_prescription_orders(self, dry):
        from audit.models import AdminPanelRecord
        from users.models import User
        migrated = 0
        qs = AdminPanelRecord.objects.filter(module='pharmacy-orders')
        for record in qs.iterator():
            url = record.payload.get('prescription_image') or ''
            if '/media/' not in url:
                continue
            farmer_id = record.payload.get('farmer_id')
            owner = User.objects.filter(pk=farmer_id).first() if farmer_id else None
            new_url = self._move_to_private(url, 'prescription', owner, dry)
            if new_url is None:
                self.stderr.write(f'  [order {record.record_id}] file missing on disk: {url}')
                continue
            migrated += 1
            if not dry:
                record.payload['prescription_image'] = new_url
                record.save(update_fields=['payload'])
        return migrated

    def _migrate_receipt_field(self, app_label, model_name, field, kind, dry):
        from django.apps import apps
        model = apps.get_model(app_label, model_name)
        migrated = 0
        missing = 0
        qs = model.objects.exclude(**{field: ''}).exclude(**{f'{field}__isnull': True})
        for row in qs.iterator():
            url = getattr(row, field)
            if '/media/' not in url:
                continue
            owner = self._owner_of(row)
            new_url = self._move_to_private(url, kind, owner, dry)
            if new_url is None:
                self.stderr.write(f'  [{model_name} {row.pk}] file missing on disk: {url}')
                missing += 1
                continue
            migrated += 1
            if not dry:
                setattr(row, field, new_url)
                row.save(update_fields=[field])
        return migrated, missing

    def _owner_of(self, row):
        """Best-effort resolve the User who should own a receipt row."""
        for path in ('farm.farmer.user', 'user'):
            obj = row
            try:
                for attr in path.split('.'):
                    obj = getattr(obj, attr)
                if obj is not None:
                    return obj
            except AttributeError:
                continue
        return None
