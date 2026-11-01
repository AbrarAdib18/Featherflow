"""Idempotent consultation demo data for the seeded demo doctor.

Ensures the demo doctor (``dr.samira.rahman@example.com``, from
``seed_platform_demo``) has, in their real request queue:

  * one open-ended pending request ("Request any available time" — no date),
    the exact shape that never reached the doctor before the fix in
    DOCTOR_CONSULTATION_QUEUE_FIX.md, and
  * one dated pending request a few days out.

Requests are booked by the demo farmer (``farmer.rashed@example.com``)
through the same ``create_booking`` path and notifications the farmer API
uses — no hand-built rows, nothing rendered by the app from fixtures.

Idempotent: a kind that already has a pending request between this pair
(seeded or real) is left alone, so re-running never piles up duplicates and
never edits or deletes existing consultations. Only the two demo accounts
are touched; it refuses to run if they don't exist.

Run:  python manage.py seed_consultation_demo_data
"""
from datetime import time, timedelta

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from consultations.booking import create_booking
from consultations.models import Consultation
from consultations.serializers import FarmerBookingSerializer
from farms.models import Farm, Flock
from notifications.models import Notification
from profiles.models import DoctorProfile
from users.models import User

DOCTOR_EMAIL = 'dr.samira.rahman@example.com'
FARMER_EMAIL = 'farmer.rashed@example.com'


class Command(BaseCommand):
    help = 'Ensure the demo doctor has open-ended and dated pending consultation requests.'

    @transaction.atomic
    def handle(self, *args, **options):
        doctor = User.objects.filter(email=DOCTOR_EMAIL).first()
        farmer = User.objects.filter(email=FARMER_EMAIL).first()
        if not doctor or not farmer:
            raise CommandError('Demo accounts missing - run `python manage.py seed_platform_demo` first.')
        profile = DoctorProfile.objects.filter(user=doctor).first()
        farm = Farm.objects.filter(farmer__user=farmer, is_active=True).order_by('created_at').first()
        if not profile or not farm:
            raise CommandError('Demo doctor profile or farm missing - run `seed_platform_demo` first.')

        pending = Consultation.objects.filter(farmer=farmer, doctor=doctor, status='requested')
        made = []
        if not pending.filter(appointment_date__isnull=True).exists():
            made.append(self._book(farmer, doctor, profile, farm, {
                'urgency': 'urgent', 'symptoms': ['Coughing', 'Reduced feed intake'],
                'farmer_notes': 'Started two days ago in one shed. Any available time is fine.',
            }, 'open-ended'))
        if not pending.filter(appointment_date__isnull=False).exists():
            made.append(self._book(farmer, doctor, profile, farm, {
                'urgency': 'routine', 'symptoms': ['Routine vaccination review'],
                'appointment_date': (timezone.localdate() + timedelta(days=3)).isoformat(),
                'appointment_time': time(11, 0).strftime('%H:%M'),
            }, 'dated'))

        for line in made:
            self.stdout.write(self.style.SUCCESS(f'created {line}'))
        if not made:
            self.stdout.write('nothing to do - the demo doctor already has open-ended and dated pending requests')
        total = Consultation.objects.filter(doctor=doctor, status='requested').count()
        self.stdout.write(f'{DOCTOR_EMAIL}: {total} pending request(s) in the queue')

    def _book(self, farmer, doctor, profile, farm, extra, label):
        mode = 'online' if profile.consultation_mode in ('online', 'both') else 'offline'
        data = {'doctor_id': str(profile.id), 'farm_id': str(farm.id), 'mode': mode, **extra}
        flock = Flock.objects.filter(farm=farm, status='active').order_by('start_date').first()
        if flock:
            data['flock_id'] = str(flock.id)
        else:  # the booking rules require flock details when none is selected
            data.update({'bird_age_weeks': 4, 'breed': farm.farm_type or 'broiler',
                         'flock_count': 500})
        serializer = FarmerBookingSerializer(data=data)
        serializer.is_valid(raise_exception=True)
        item, _case = create_booking(farmer, serializer.validated_data)
        # Same notifications the farmer API sends on booking.
        Notification.objects.create(
            user=doctor, title='New consultation request',
            body=f'{farmer.full_name or farmer.email} requested an {item.urgency_level} {item.mode} consultation.',
            notification_type='reminder', reference_id=item.id, reference_type='consultation',
        )
        Notification.objects.create(
            user=farmer, title='Consultation requested',
            body=f'Your request with {doctor.full_name or doctor.email} was submitted.',
            notification_type='reminder', reference_id=item.id, reference_type='consultation',
        )
        return f'{label} request {item.id}'
