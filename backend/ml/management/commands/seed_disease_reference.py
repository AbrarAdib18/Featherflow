"""Populate the ``diseases`` reference table from ``ml/content.py`` so every
class the detection model can output has a card with symptoms and first-aid
advice. Idempotent — safe to re-run after editing the advice.

    backend/venv/Scripts/python.exe manage.py seed_disease_reference
"""
from django.core.management.base import BaseCommand

from ml import content
from ml.models import DiseaseRef


class Command(BaseCommand):
    help = 'Upsert the diseases reference table from ml/content.py.'

    def handle(self, *args, **options):
        seen, created, updated = set(), 0, 0
        for raw_label, meta in content.CLASS_META.items():
            if meta is None:
                continue
            name = meta['label']  # includes "Healthy" (severity NULL)
            if name in seen:
                continue
            seen.add(name)
            defaults = dict(
                description=meta['description'],
                symptoms=meta['symptoms'],
                what_to_do='\n'.join(meta['what_to_do']),
                what_not_to_do='\n'.join(meta['what_not_to_do']),
                prevention_tips='\n'.join(meta['prevention']),
                severity_level=content.DB_SEVERITY[meta['severity']],
                requires_immediate_vet=meta['requires_immediate_vet'],
            )
            _, was_created = DiseaseRef.objects.update_or_create(
                name=name, defaults=defaults)
            created += was_created
            updated += (not was_created)

        self.stdout.write(self.style.SUCCESS(
            f'diseases reference: {created} created, {updated} updated '
            f'({len(seen)} total classes).'))
