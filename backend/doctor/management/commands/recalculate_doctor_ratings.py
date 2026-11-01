"""Resync every doctor's stored rating with their actual consultation ratings
(DOCTOR_RATINGS_FIX.md).

The stored ``DoctorProfile.rating`` is kept current by the in-app rating flow,
but data changed any other way (seed commands, imports, a database merge) can
leave it stale: e.g. 0.00 stored while seven real ratings average 4.14.
Idempotent; only rows whose value actually changes are written.

Run:  python manage.py recalculate_doctor_ratings [--dry-run] [--email EMAIL ...]
"""
from django.core.management.base import BaseCommand

from doctor.ratings import rating_summary, stored_value
from profiles.models import DoctorProfile


class Command(BaseCommand):
    help = "Recompute every doctor's stored rating from their consultation ratings."

    def add_arguments(self, parser):
        parser.add_argument('--dry-run', action='store_true', help='Show changes without saving.')
        parser.add_argument('--email', nargs='+', help='Only these doctors (default: all).')

    def handle(self, *args, dry_run, email, **options):
        changed = 0
        profiles = DoctorProfile.objects.select_related('user').order_by('user__email')
        if email:
            profiles = profiles.filter(user__email__in=email)
        for profile in profiles:
            summary = rating_summary(profile.user)
            new = stored_value(summary)
            if profile.rating == new:
                continue
            changed += 1
            self.stdout.write(f'{profile.user.email}: {profile.rating} -> {new} '
                              f'({summary["count"]} rating(s))')
            if not dry_run:
                DoctorProfile.objects.filter(pk=profile.pk).update(rating=new)
        verb = 'would change' if dry_run else 'updated'
        self.stdout.write(self.style.SUCCESS(f'Done: {changed} doctor rating(s) {verb}.'))
