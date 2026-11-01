"""Retry prescription emails that are owed (DOCTOR_PRESCRIPTION_PDF_EMAIL.md).

Picks prescriptions whose email is ``failed``, never attempted (``pending``),
or stuck in ``sending`` longer than ``STALE_SENDING`` (the process died mid
send), with fewer than ``--max-attempts`` attempts. A ``sent`` prescription is
never selected, and each send is claimed under a row lock, so re-running this
(or running it while the app is sending) cannot email a farmer twice.

Run:  python manage.py retry_prescription_emails [--max-attempts 5] [--dry-run]
Schedule it (cron / Task Scheduler) every 15–30 minutes in production.
"""
from django.core.management.base import BaseCommand

from doctor.prescription_pdf import reference_for
from doctor.prescriptions import MAX_AUTOMATIC_ATTEMPTS, deliver_email, retry_candidates


class Command(BaseCommand):
    help = 'Retry prescription PDF emails that failed or were never sent.'

    def add_arguments(self, parser):
        parser.add_argument('--max-attempts', type=int, default=MAX_AUTOMATIC_ATTEMPTS,
                            help='Skip prescriptions already attempted this many times.')
        parser.add_argument('--dry-run', action='store_true', help='List what would be retried.')

    def handle(self, *args, max_attempts, dry_run, **options):
        candidates = list(retry_candidates(max_attempts))
        if not candidates:
            self.stdout.write('No prescription emails to retry.')
            return
        sent = failed = skipped = 0
        for p in candidates:
            label = f'{reference_for(p)} ({p.email_status}, {p.email_attempts} attempt(s))'
            if dry_run:
                self.stdout.write(f'would retry {label}')
                continue
            result = deliver_email(p.id)
            if result == 'sent':
                sent += 1
            elif result == 'failed':
                failed += 1
            else:
                skipped += 1  # claimed by a concurrent send, or already sent
            self.stdout.write(f'{label} -> {result}')
        if not dry_run:
            self.stdout.write(self.style.SUCCESS(
                f'Done: {sent} sent, {failed} failed, {skipped} skipped.'))
