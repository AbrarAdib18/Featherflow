"""Demo/seed commands create accounts with publicly known passwords (including admin roles). They must never run
against a production database by accident (F-019 / credentials review)."""
import os

from django.conf import settings
from django.core.management.base import CommandError


def require_demo_environment(command_name):
    if settings.DEBUG or os.environ.get('ALLOW_DEMO_SEED') == '1':
        return
    raise CommandError(
        f'{command_name} creates demo accounts with well-known passwords and refuses to run while DEBUG is off. '
        'Set ALLOW_DEMO_SEED=1 only for a throw-away / staging database.')
