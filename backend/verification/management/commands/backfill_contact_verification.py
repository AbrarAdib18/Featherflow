"""Mark existing accounts as email/phone verified.

Email verification became a login gate after these accounts were created, so
without this backfill every pre-existing user would be locked out until they
completed an OTP. Run once after applying verification_extension.sql:

    python manage.py backfill_contact_verification            # all users
    python manage.py backfill_contact_verification --dry-run
    python manage.py backfill_contact_verification --created-before 2026-09-10
"""
from datetime import datetime

from django.core.management.base import BaseCommand
from django.utils import timezone

from users.models import User


class Command(BaseCommand):
    help = 'Backfill users.email_verified_at / phone_verified_at for existing accounts.'

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true')
        parser.add_argument('--created-before', default=None,
                            help='Only backfill users created strictly before this ISO date.')
        parser.add_argument('--email-only', action='store_true',
                            help='Do not touch phone_verified_at.')

    def handle(self, *args, **opts):
        qs = User.objects.all()
        if opts['created_before']:
            cutoff = datetime.fromisoformat(opts['created_before'])
            if timezone.is_naive(cutoff):
                cutoff = timezone.make_aware(cutoff)
            qs = qs.filter(created_at__lt=cutoff)

        pending_email = qs.filter(email_verified_at__isnull=True)
        pending_phone = qs.filter(phone_verified_at__isnull=True)
        n_email = pending_email.count()
        n_phone = 0 if opts['email_only'] else pending_phone.count()

        if opts['dry_run']:
            self.stdout.write(
                f'[dry-run] would set email_verified_at on {n_email} user(s)'
                + ('' if opts['email_only'] else f' and phone_verified_at on {n_phone}'))
            return

        now = timezone.now()
        pending_email.update(email_verified_at=now)
        if not opts['email_only']:
            pending_phone.update(phone_verified_at=now)
        self.stdout.write(self.style.SUCCESS(
            f'Backfilled email verification for {n_email} user(s)'
            + ('' if opts['email_only'] else f' and phone for {n_phone}') + '.'))
