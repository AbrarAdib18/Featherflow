"""Deprecated alias — kept only for backward compatibility with anything
still invoking this name. All real seeding logic now lives in
``seed_feed_marketplace_demo`` (expanded: 4 companies with images, 25
products across every required category with generated images, 6 orders
across the full status range). See that command for details.

Run:  python manage.py seed_feed_demo_data [--reset]
"""
from django.core.management import call_command
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = 'Deprecated alias for seed_feed_marketplace_demo — see that command.'

    def add_arguments(self, parser):
        parser.add_argument('--reset', action='store_true')

    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING(
            'seed_feed_demo_data is now an alias for seed_feed_marketplace_demo.'))
        call_command('seed_feed_marketplace_demo', reset=options['reset'])
