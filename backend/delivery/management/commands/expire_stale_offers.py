from django.core.management.base import BaseCommand

from delivery.offers import sweep_stale_offers


class Command(BaseCommand):
    help = 'Release delivery offers nobody answered within the offer window (safe to run from cron).'

    def handle(self, *args, **opts):
        self.stdout.write(f'released {sweep_stale_offers()} stale offer(s)')
