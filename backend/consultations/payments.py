import json
from decimal import Decimal, ROUND_HALF_UP

from django.conf import settings
from django.db import IntegrityError, transaction
from django.utils import timezone

from doctor.models import DoctorEarning
from notifications.models import Notification
from payments.models import Payment

from .models import Consultation


MONEY = Decimal('0.01')


def payment_breakdown(consultation):
    gross = Decimal(consultation.consultation_fee or 0).quantize(MONEY)
    threshold = Decimal(settings.CONSULTATION_PLATFORM_THRESHOLD)
    rate = Decimal(settings.CONSULTATION_PLATFORM_RATE)
    chargeable = max(Decimal('0'), gross - threshold)
    platform_charge = (chargeable * rate / Decimal('100')).quantize(
        MONEY, rounding=ROUND_HALF_UP)
    return gross, platform_charge, (gross - platform_charge).quantize(MONEY)


def receipt_row(payment, consultation, *, already_paid=False):
    try:
        credentials = json.loads(payment.notes or '{}')
    except (TypeError, ValueError):
        credentials = {}
    return {
        'id': str(payment.id), 'receipt_number': payment.transaction_id,
        'consultation_id': str(consultation.id), 'status': payment.status,
        'payment_method': payment.payment_method, 'currency': payment.currency,
        'gross_fee': float(payment.amount),
        'platform_charge': float(payment.platform_charge),
        'doctor_net_amount': float(payment.net_amount),
        'platform_threshold': float(Decimal(settings.CONSULTATION_PLATFORM_THRESHOLD)),
        'platform_rate_percent': float(Decimal(settings.CONSULTATION_PLATFORM_RATE)),
        'consultation_mode': consultation.mode,
        'urgency': consultation.urgency_level,
        'doctor_name': consultation.doctor.full_name or consultation.doctor.email,
        'farmer_name': consultation.farmer.full_name or consultation.farmer.email,
        'appointment_date': consultation.appointment_date.isoformat(),
        'appointment_time': consultation.appointment_time.strftime('%H:%M'),
        'doctor_handled_sequence': credentials.get('doctor_handled_sequence'),
        'created_at': payment.created_at.isoformat() if payment.created_at else None,
        'paid_at': payment.confirmed_at.isoformat() if payment.confirmed_at else None,
        'already_paid': already_paid,
    }


def ensure_cash_receipt(consultation):
    payment = Payment.objects.filter(
        reference_id=consultation.id, payment_type='consultation',
        reference_type='consultation').first()
    if payment:
        if consultation.payment_id != payment.id:
            consultation.payment_id = payment.id
            consultation.save(update_fields=['payment_id'])
        return payment, False

    gross, platform_charge, net = payment_breakdown(consultation)
    handled_sequence = Consultation.objects.filter(
        doctor=consultation.doctor, status='completed',
        updated_at__lte=consultation.updated_at).count()
    notes = json.dumps({
        'consultation_mode': consultation.mode,
        'urgency': consultation.urgency_level,
        'doctor_handled_sequence': handled_sequence,
    })
    try:
        with transaction.atomic():
            payment = Payment.objects.create(
                user=consultation.farmer, amount=gross, currency='BDT',
                payment_method='cash', payment_type='consultation',
                reference_id=consultation.id, reference_type='consultation',
                status='pending', transaction_id=f'CASH-{consultation.id}',
                notes=notes, platform_charge=platform_charge, net_amount=net,
                created_at=timezone.now())
    except IntegrityError:
        payment = Payment.objects.get(
            reference_id=consultation.id, payment_type='consultation',
            reference_type='consultation')
        return payment, False
    consultation.payment_id = payment.id
    consultation.save(update_fields=['payment_id'])
    return payment, True


@transaction.atomic
def confirm_cash_payment(consultation, farmer):
    consultation = Consultation.objects.select_for_update().select_related(
        'doctor', 'farmer').get(id=consultation.id, farmer=farmer)
    payment, _ = ensure_cash_receipt(consultation)
    payment = Payment.objects.select_for_update().get(id=payment.id)
    if payment.status == 'completed':
        return payment, consultation, False
    payment.status = 'completed'
    payment.confirmed_at = timezone.now()
    payment.save(update_fields=['status', 'confirmed_at'])
    DoctorEarning.objects.update_or_create(
        consultation=consultation,
        defaults={
            'doctor': consultation.doctor, 'gross_amount': payment.amount,
            'platform_fee': payment.platform_charge,
            'net_amount': payment.net_amount, 'payout_status': 'pending',
        })
    Notification.objects.create(
        user=consultation.doctor, title='Cash payment confirmed',
        body=f'{farmer.full_name or farmer.email} marked consultation {consultation.id} as paid.',
        notification_type='system', reference_id=payment.id,
        reference_type='consultation_payment')
    Notification.objects.create(
        user=farmer, title='Payment receipt updated',
        body='Your consultation cash payment was recorded successfully.',
        notification_type='system', reference_id=payment.id,
        reference_type='consultation_payment')
    return payment, consultation, True
