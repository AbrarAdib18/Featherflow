"""Seed the platform's default age-based feeding guidelines (Priority 4).

Idempotent — matches on (bird_type, min_age_days, max_age_days) and updates
in place rather than duplicating. General reference guidance only; not
veterinary or nutritional advice for any specific flock (see
FeedingGuideline's model docstring).

Run:  python manage.py seed_feeding_guidelines
"""
from django.core.management.base import BaseCommand

from feed.models import FeedingGuideline

GUIDELINES = [
    # bird_type, min_age, max_age, stage_label, feed_type_label, g/bird/day, freq/day, guidance
    ('broiler', 0, 10, 'Starter (0-10 days)', 'Starter crumble, ~22-24% protein', 15, 4,
     'Feed little and often. Ensure constant access to clean water and warmth (brooding).'),
    ('broiler', 11, 24, 'Grower (11-24 days)', 'Grower pellet/crumble, ~20-22% protein', 60, 3,
     'Increase feeder space as birds grow. Watch for even growth across the flock.'),
    ('broiler', 25, 42, 'Finisher (25-42 days)', 'Finisher pellet, ~18-20% protein', 120, 2,
     'Monitor feed conversion; reduce lighting stress near market weight.'),

    ('layer', 0, 42, 'Chick (0-6 weeks)', 'Chick starter mash, ~20% protein', 20, 3,
     'Focus on frame development, not early egg production.'),
    ('layer', 43, 126, 'Grower (6-18 weeks)', 'Grower/developer mash, ~16% protein', 55, 2,
     'Controlled feeding to reach target body weight before lay.'),
    ('layer', 127, 3650, 'Layer (18+ weeks)', 'Layer mash/pellet, ~16-18% protein, added calcium', 110, 2,
     'Increase calcium as lay begins; monitor egg shell quality.'),

    ('chick', 0, 21, 'Brooding (0-3 weeks)', 'Chick starter crumble', 12, 4,
     'Keep brooder temperature warm and reduce gradually; feed close to the heat source.'),

    ('breeder', 0, 126, 'Rearing (0-18 weeks)', 'Breeder rearing feed, controlled ration', 50, 2,
     'Controlled feeding is critical to avoid over-conditioning before breeding age.'),
    ('breeder', 127, 3650, 'Breeding (18+ weeks)', 'Breeder layer feed, balanced vitamins/minerals', 150, 2,
     'Balance nutrition for fertility and hatchability, not just egg count.'),
]


class Command(BaseCommand):
    help = 'Seed default age-based feeding guidelines (idempotent).'

    def handle(self, *args, **options):
        created = updated = 0
        for bird_type, min_age, max_age, stage, feed_label, grams, freq, guidance in GUIDELINES:
            obj, was_created = FeedingGuideline.objects.update_or_create(
                bird_type=bird_type, min_age_days=min_age, max_age_days=max_age,
                defaults={
                    'stage_label': stage, 'feed_type_label': feed_label,
                    'recommended_grams_per_bird_per_day': grams,
                    'frequency_per_day': freq, 'guidance_text': guidance, 'is_active': True,
                },
            )
            created += was_created
            updated += not was_created
        self.stdout.write(self.style.SUCCESS(
            f'Feeding guidelines: {created} created, {updated} updated (total {len(GUIDELINES)}).'))
