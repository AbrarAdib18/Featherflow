"""Delete signup uploads that were never claimed by a finished registration.

    python manage.py purge_orphan_signup_documents [--hours 24] [--dry-run]

An "orphan" is a ``SignupDocument`` row with ``user IS NULL`` (nobody completed
signup with it) older than the cutoff. Its file under ``private_media/`` is
removed too. Claimed documents are never touched. Safe to run from cron.
"""
from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta

from verification import documents as docs
from verification.models import SignupDocument


class Command(BaseCommand):
    help = 'Remove unclaimed signup document uploads older than N hours.'

    def add_arguments(self, parser):
        parser.add_argument('--hours', type=int, default=24,
                            help='Minimum age in hours before an unclaimed upload is purged (default 24).')
        parser.add_argument('--dry-run', action='store_true',
                            help='Report what would be deleted without deleting.')

    def handle(self, *args, **opts):
        cutoff = timezone.now() - timedelta(hours=opts['hours'])
        qs = SignupDocument.objects.filter(user__isnull=True, uploaded_at__lt=cutoff)
        total = qs.count()
        removed_files = 0

        for doc in qs.iterator():
            if opts['dry_run']:
                continue
            try:
                if doc.file_path and docs.private_storage.exists(doc.file_path):
                    docs.private_storage.delete(doc.file_path)
                    removed_files += 1
            except Exception as exc:  # noqa: BLE001
                self.stderr.write(f'  could not delete {doc.file_path}: {exc}')

        if not opts['dry_run']:
            qs.delete()

        verb = 'Would purge' if opts['dry_run'] else 'Purged'
        self.stdout.write(self.style.SUCCESS(
            f'{verb} {total} unclaimed signup document(s) older than {opts["hours"]}h '
            f'({removed_files} file(s) removed from disk).'))
