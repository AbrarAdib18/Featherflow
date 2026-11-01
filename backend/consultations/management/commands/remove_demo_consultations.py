"""Remove seeded demo consultations, their ratings and their scripted chats
(DOCTOR_RATINGS_FIX.md).

Older versions of ``seed_farmer_demo_data`` and ``seed_demo_data_for_phone``
created consultations directly with ``Consultation.objects.create``: one per
status, with fake 4–5 star ratings and the canned review "Very helpful, clear
guidance on treatment.", plus scripted doctor<->farmer chats. Those fake ratings
were counted in doctors' real ratings.

A seeded consultation is recognised by what a real one always has and a seeded
one never has: every booking made through the app creates a case
(``consultation_case_details``, see consultations/booking.py), and every
status change made through the app writes ``consultation_status_history``.
A consultation with neither is a seed row. Conversations attached to those
consultations (and their messages) are removed with them.

Dry run by default.  Run:  python manage.py remove_demo_consultations [--apply] [--farmer EMAIL]
Afterwards run ``recalculate_doctor_ratings``.
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Exists, OuterRef

from consultations.models import Consultation
from doctor.models import CaseDetail, ConsultationStatusHistory, Conversation, Message


def seeded_consultations():
    return (Consultation.objects
            .annotate(has_case=Exists(CaseDetail.objects.filter(consultation=OuterRef('pk'))),
                      has_history=Exists(ConsultationStatusHistory.objects.filter(consultation=OuterRef('pk'))))
            .filter(has_case=False, has_history=False))


class Command(BaseCommand):
    help = 'Delete seeded demo consultations, their ratings and scripted chats.'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true', help='Delete (default is a dry run).')
        parser.add_argument('--farmer', help="Only this farmer's consultations (default: all).")

    def handle(self, *args, apply, farmer, **options):
        rows = seeded_consultations()
        if farmer:
            rows = rows.filter(farmer__email=farmer)
        rows = list(rows.select_related('farmer', 'doctor').order_by('created_at'))
        conversations = Conversation.objects.filter(consultation__in=[c.pk for c in rows])
        messages = Message.objects.filter(conversation__in=conversations)
        for c in rows:
            self.stdout.write(f'{c.id}  {c.created_at:%Y-%m-%d %H:%M}  {c.doctor.email} <- {c.farmer.email}  '
                              f'{c.status}  rating={c.rating}')
        self.stdout.write(f'{len(rows)} seeded consultation(s), {conversations.count()} conversation(s), '
                          f'{messages.count()} message(s).')
        if not apply:
            self.stdout.write('Dry run: nothing deleted. Re-run with --apply.')
            return
        with transaction.atomic():
            deleted_messages = messages.delete()[0]
            deleted_conversations = conversations.delete()[0]
            deleted = Consultation.objects.filter(pk__in=[c.pk for c in rows]).delete()[0]
        self.stdout.write(self.style.SUCCESS(
            f'Deleted {deleted} consultation(s), {deleted_conversations} conversation(s), '
            f'{deleted_messages} message(s). Now run: python manage.py recalculate_doctor_ratings'))
