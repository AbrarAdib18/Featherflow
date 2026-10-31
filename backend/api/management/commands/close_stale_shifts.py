from django.core.management.base import BaseCommand

from api.admin_shifts import close_stale_shifts


class Command(BaseCommand):
    help = 'Close admin shifts left open longer than the 16 h cap (flagged, Super Admins notified).'

    def handle(self, *args, **opts):
        self.stdout.write(f'closed {close_stale_shifts()} stale shift(s)')
