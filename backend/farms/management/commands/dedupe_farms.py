"""Find (and optionally remove) duplicate farms.

A duplicate is two farms with the same natural key: the same farmer and the same
farm name (case-insensitive). Different-named farms of one farmer are legitimate
(the schema allows several) and are only reported, never touched.

Safety rules:
  * dry-run by default; nothing changes without --apply;
  * the survivor is the canonical farm (`farms.services.canonical_farm` order);
  * a duplicate is deleted ONLY if no row references it (workers, sheds,
    flocks, expenses, ... — every FK table is checked);
  * a duplicate that still has dependents is NEVER deleted or merged — it is
    reported for manual review.

    python manage.py dedupe_farms            # report
    python manage.py dedupe_farms --apply    # delete empty exact duplicates
"""
from collections import defaultdict

from django.core.management.base import BaseCommand
from django.db import transaction

from farms.models import Farm
from farms.services import FARM_ORDERING, dependent_counts


class Command(BaseCommand):
    help = 'Report / remove empty exact-duplicate farms (same farmer + same name).'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true', help='Delete empty exact duplicates.')

    def handle(self, *args, **opts):
        groups = defaultdict(list)
        by_farmer = defaultdict(list)
        for f in Farm.objects.select_related('farmer__user').order_by(*FARM_ORDERING):
            groups[(f.farmer_id, f.farm_name.strip().lower())].append(f)
            by_farmer[f.farmer_id].append(f)
        deleted = kept_for_review = 0
        for (_, name), farms in groups.items():
            if len(farms) < 2:
                continue
            keeper, dups = farms[0], farms[1:]
            who = keeper.farmer.user.email
            self.stdout.write(f'DUPLICATE  {who}  "{keeper.farm_name}"  keep {keeper.id}')
            for d in dups:
                deps = dependent_counts(d)
                if deps:
                    kept_for_review += 1
                    self.stdout.write(self.style.WARNING(
                        f'   REVIEW   {d.id} has dependents {deps} - NOT touched'))
                elif opts['apply']:
                    fid = d.id
                    with transaction.atomic():
                        d.delete()
                    deleted += 1
                    self.stdout.write(self.style.SUCCESS(f'   DELETED  {fid} (no dependents)'))
                else:
                    self.stdout.write(f'   would delete {d.id} (no dependents)')
        for fid, farms in by_farmer.items():
            names = {f.farm_name.strip().lower() for f in farms}
            if len(names) > 1:
                self.stdout.write(
                    f'INFO  {farms[0].farmer.user.email} owns {len(names)} differently named farms '
                    f'(legitimate, untouched): {sorted(f.farm_name for f in farms)}')
        self.stdout.write(f'done: deleted={deleted} needs_review={kept_for_review} apply={opts["apply"]}')
