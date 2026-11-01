"""Farm lookup rules shared by the farmer panel and the seed commands.

The `farms` table has no uniqueness rule beyond its primary key, and a farmer
may own several farms. Anything that needs "the" farm of a farmer must pick one
*deterministically*; this is that rule (active first, then oldest, NULL
`created_at` last, then id), identical to what `workers.views.farm_for` always
used.
"""
from django.utils import timezone

from .models import Farm

FARM_ORDERING = ('-is_active', 'created_at', 'id')


def canonical_farm(profile):
    """The farmer's primary farm, or None when they own none."""
    return Farm.objects.filter(farmer=profile).order_by(*FARM_ORDERING).first()


def ensure_farm(profile, *, farm_name, farm_type, location, address):
    """Return (farm, created). Never creates a second farm when the farmer
    already owns one; never modifies an existing farm."""
    farm = canonical_farm(profile)
    if farm is not None:
        return farm, False
    now = timezone.now()
    farm = Farm.objects.create(
        farmer=profile, farm_name=farm_name, farm_type=farm_type, location=location,
        address=address, is_active=True, created_at=now, updated_at=now)
    return farm, True


def dependent_counts(farm):
    """{table: rows} of every row that references this farm (all FK tables)."""
    from django.db import connection
    counts = {}
    with connection.cursor() as cur:
        cur.execute(
            """SELECT k.conrelid::regclass::text, a.attname
                 FROM pg_constraint k
                 JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
                WHERE k.confrelid = 'farms'::regclass AND k.contype = 'f'""")
        for table, column in cur.fetchall():
            cur.execute(f'SELECT count(*) FROM "{table}" WHERE "{column}" = %s', [farm.pk])
            n = cur.fetchone()[0]
            if n:
                counts[table] = n
    return counts
