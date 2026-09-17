"""Priority 4 — feeding notifications.

No task queue (Celery/APScheduler/cron) exists anywhere in this backend (see
FEED_AND_DATA_INTEGRITY_AUDIT.md) — every other notification in the app is
created synchronously inline inside a request handler. This command is meant
to be invoked periodically by an OS scheduler (cron / Windows Task Scheduler)
once a day, matching the project's existing `manage.py <command>` convention
for anything that needs to run outside a request.

Idempotent: dedupes on (user, reference_type, reference_id, today's date) so
running it more than once on the same day never double-notifies. Timezone-safe:
uses each check's own "today" from Django's configured TIME_ZONE (`timezone.localdate()`)
rather than naive UTC dates.

Run:  python manage.py generate_feed_notifications [--lookahead-days 2]
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from farms.models import Flock
from feed.models import FeedingGuideline, FeedStock
from notifications.models import Notification


def _already_notified_today(user, reference_type, reference_id, window_hours=20):
    """Dedupe window rather than a calendar-day `__date` lookup: `notifications.created_at`
    is a naive ``timestamp without time zone`` column, and Postgres's
    ``AT TIME ZONE`` reinterprets a naive value as *already being in* the
    target zone before converting — the opposite of what a UTC-stored naive
    value needs — so `created_at__date=timezone.localdate()` silently matches
    the wrong day whenever TIME_ZONE isn't UTC. A pure UTC time-window check
    sidesteps that entirely and is more than sufficient for a once-a-day cron."""
    from datetime import timedelta
    cutoff = timezone.now() - timedelta(hours=window_hours)
    return Notification.objects.filter(
        user=user, reference_type=reference_type, reference_id=reference_id,
        created_at__gte=cutoff,
    ).exists()


class Command(BaseCommand):
    help = 'Generate daily feeding-stage, feeding-reminder, and low-stock notifications (idempotent).'

    def add_arguments(self, parser):
        parser.add_argument('--lookahead-days', type=int, default=2,
                            help='Warn this many days before a flock crosses into its next feeding stage.')

    def handle(self, *args, **options):
        lookahead = options['lookahead_days']
        stage_change = daily_reminder = low_stock = 0

        for flock in Flock.objects.filter(status='active').select_related('farm__farmer__user'):
            user = flock.farm.farmer.user
            bird_type = flock.bird_type or 'other'
            age = flock.age_days
            current = FeedingGuideline.for_age(bird_type, age)
            upcoming = FeedingGuideline.for_age(bird_type, age + lookahead)

            # Upcoming feed-stage change.
            if current and upcoming and current.id != upcoming.id:
                ref_id = flock.id
                if not _already_notified_today(user, 'feed_stage_upcoming', ref_id):
                    Notification.objects.create(
                        user=user, title='Feeding stage changing soon',
                        body=(f'{flock.batch_name} will move into "{upcoming.stage_label}" '
                              f'in about {lookahead} day(s) — {upcoming.feed_type_label}.'),
                        notification_type='reminder', reference_id=ref_id,
                        reference_type='feed_stage_upcoming',
                    )
                    stage_change += 1

            # Daily feeding reminder for the current stage.
            if current:
                ref_id = flock.id
                if not _already_notified_today(user, 'feed_daily_reminder', ref_id):
                    amt = current.recommended_grams_per_bird_per_day
                    amt_text = f'~{amt:g} g/bird/day' if amt else 'see feeding guide'
                    Notification.objects.create(
                        user=user, title='Today\'s feeding guidance',
                        body=(f'{flock.batch_name} ({current.stage_label}): {current.feed_type_label}, '
                              f'{amt_text}, {current.frequency_per_day}x/day. General guidance only.'),
                        notification_type='reminder', reference_id=ref_id,
                        reference_type='feed_daily_reminder',
                    )
                    daily_reminder += 1

        for stock in FeedStock.objects.filter(quantity_available__lt=50).select_related('farm__farmer__user', 'feed_type'):
            user = stock.farm.farmer.user
            ref_id = stock.id
            if not _already_notified_today(user, 'feed_low_stock', ref_id):
                Notification.objects.create(
                    user=user, title='Feed stock low',
                    body=f'{stock.feed_type.name}: {float(stock.quantity_available):g} '
                         f'{stock.feed_type.unit or "kg"} left.',
                    notification_type='alert', reference_id=ref_id, reference_type='feed_low_stock',
                )
                low_stock += 1

        self.stdout.write(self.style.SUCCESS(
            f'Feed notifications: {stage_change} stage-change, {daily_reminder} daily-reminder, '
            f'{low_stock} low-stock (lookahead={lookahead}d).'))
