"""Retention job (F-030): keep growth bounded without deleting audit evidence.

    python manage.py prune_old_data [--notification-days 90] [--dry-run]

* read notifications older than N days are deleted (unread ones are kept);
* expired / blacklisted JWT rows are flushed (simplejwt `flushexpiredtokens`);
* activity_logs is append-only by design and is NEVER touched.
"""
from datetime import timedelta

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from notifications.models import Notification


class Command(BaseCommand):
    help = 'Delete old read notifications and flush expired JWT tokens.'

    def add_arguments(self, parser):
        parser.add_argument('--notification-days', type=int, default=90)
        parser.add_argument('--dry-run', action='store_true')

    def handle(self, *args, **opts):
        cutoff = timezone.now() - timedelta(days=opts['notification_days'])
        qs = Notification.objects.filter(is_read=True, created_at__lt=cutoff)
        n = qs.count()
        if opts['dry_run']:
            self.stdout.write(f'would delete {n} read notification(s) older than {opts["notification_days"]} days')
            return
        qs.delete()
        self.stdout.write(f'deleted {n} read notification(s)')
        try:
            call_command('flushexpiredtokens')
        except Exception as exc:  # token_blacklist app may be absent
            self.stdout.write(f'token flush skipped: {exc}')
