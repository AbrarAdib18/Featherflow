"""Prescription PDF storage, access and email delivery
(DOCTOR_PRESCRIPTION_PDF_EMAIL.md).

* The PDF is generated once from persisted records and stored privately
  (``private_media/clinical_prescriptions/<id>.pdf``, outside MEDIA_URL). The
  stored file is what the farmer was emailed and what the endpoints serve.
* Email delivery state lives on the prescription row (one record per
  prescription): pending → sending → sent | failed. A send is claimed under a
  row lock, so concurrent triggers can't both send. Nothing re-sends a
  delivered email except a deliberate doctor resend.
* SMTP failures never roll back the prescription: delivery runs after the
  prescription transaction has committed and only ever updates delivery
  columns.
"""
import logging
from datetime import timedelta
from email.utils import make_msgid

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.mail import EmailMessage
from django.db import transaction
from django.utils import timezone

from messaging.chat import aware_utc, iso_utc
from verification.documents import private_storage

from .models import ClinicalPrescription
from .prescription_pdf import build_prescription_pdf, doctor_display_name, reference_for

log = logging.getLogger(__name__)

# A send stuck in `sending` this long (process died mid-send) may be retried.
STALE_SENDING = timedelta(minutes=15)
MAX_AUTOMATIC_ATTEMPTS = 5


def _load(prescription_id, lock=False):
    qs = ClinicalPrescription.objects.select_related(
        'doctor', 'consultation__farmer', 'consultation__case_detail').prefetch_related('items')
    if lock:
        qs = qs.select_for_update(of=('self',))
    return qs.get(id=prescription_id)


def can_view(prescription, user):
    """The consultation's farmer, the prescribing doctor, or an admin reviewer
    (the private-document policy in verification/documents.py)."""
    return bool(user and user.is_authenticated and (
        user.id in (prescription.doctor_id, prescription.consultation.farmer_id)
        or user.is_staff))


def safe_error(exc):
    """A delivery error safe to store and show: no credentials, bounded."""
    text = f'{type(exc).__name__}: {exc}'
    for secret in (settings.EMAIL_HOST_PASSWORD, settings.EMAIL_HOST_USER):
        if secret:
            text = text.replace(secret, '***')
    return text[:500]


def pdf_filename(prescription):
    return f'featherflow-prescription-{reference_for(prescription)}.pdf'


def is_valid_pdf(data):
    """A complete PDF: header at the start, end-of-file marker at the end."""
    return bool(data) and data.startswith(b'%PDF-') and b'%%EOF' in data[-1024:]


def ensure_pdf(prescription):
    """Bytes of the stored PDF, generating and storing it on first use.

    A stored file that is missing, truncated or corrupt is regenerated from the
    persisted prescription. Viewing never creates a prescription or sends an
    email."""
    if prescription.pdf_file and private_storage.exists(prescription.pdf_file):
        with private_storage.open(prescription.pdf_file, 'rb') as handle:
            stored = handle.read()
        if is_valid_pdf(stored):
            return stored
        log.warning('Prescription %s stored PDF is invalid; regenerating.', reference_for(prescription))
    try:
        pdf = build_prescription_pdf(prescription)
        if not is_valid_pdf(pdf):
            raise ValueError('The generated prescription PDF is incomplete.')
        key = f'clinical_prescriptions/{prescription.id}.pdf'
        if private_storage.exists(key):
            private_storage.delete(key)
        key = private_storage.save(key, ContentFile(pdf))
    except Exception as exc:
        ClinicalPrescription.objects.filter(id=prescription.id).update(pdf_error=safe_error(exc))
        raise
    now = timezone.now()
    ClinicalPrescription.objects.filter(id=prescription.id).update(
        pdf_file=key, pdf_generated_at=now, pdf_error=None)
    prescription.pdf_file, prescription.pdf_generated_at, prescription.pdf_error = key, now, None
    return pdf


def build_email(prescription, pdf):
    consultation = prescription.consultation
    farmer = consultation.farmer
    doctor = doctor_display_name(prescription.doctor)
    case = getattr(consultation, 'case_detail', None)
    farm = (case.farm_name if case and case.farm_name else '') or 'your farm'
    issued = timezone.localtime(aware_utc(prescription.created_at)).strftime('%d %b %Y')
    reference = reference_for(prescription)
    body = (
        f'Dear {farmer.full_name or "Farmer"},\n\n'
        f'{doctor} has issued a prescription for farm "{farm}".\n\n'
        f'Prescription date: {issued}\n'
        f'Reference: {reference}\n\n'
        'Please open the attached PDF for the medicines, dosage and advice. You can also '
        'view it any time in the FeatherFlow app under Find Vet → My Consultations.\n\n'
        'If your birds do not improve, contact your veterinarian through FeatherFlow.\n\n'
        '— FeatherFlow\n'
        'This is an automated message; please do not reply.\n'
    )
    domain = (settings.DEFAULT_FROM_EMAIL.rsplit('@', 1)[-1].strip(' >') or 'featherflow.local')
    message = EmailMessage(
        subject=f'Your prescription from {doctor} – FeatherFlow',
        body=body, from_email=settings.DEFAULT_FROM_EMAIL, to=[farmer.email],
        headers={'Message-ID': make_msgid(domain=domain)})
    message.attach(pdf_filename(prescription), pdf, 'application/pdf')
    return message


def _claim(prescription_id, deliberate):
    """Lock the row and mark an attempt. Returns the prescription to send, or
    None when this call must not send (already sent / another send running)."""
    with transaction.atomic():
        p = _load(prescription_id, lock=True)
        now = timezone.now()
        if p.email_status == 'sent' and not deliberate:
            return None
        last = aware_utc(p.email_last_attempt_at)
        if p.email_status == 'sending' and last and now - last < STALE_SENDING:
            return None
        p.email_status = 'sending'
        p.email_attempts += 1
        p.email_last_attempt_at = now
        p.email_recipient = p.consultation.farmer.email or None
        p.save(update_fields=['email_status', 'email_attempts', 'email_last_attempt_at', 'email_recipient'])
        return p


def deliver_email(prescription_id, *, deliberate=False):
    """Email the stored PDF to the consultation farmer. Returns the final
    ``email_status``. Never raises: a provider outage is recorded, not thrown."""
    p = _claim(prescription_id, deliberate)
    if p is None:
        return ClinicalPrescription.objects.values_list('email_status', flat=True).get(id=prescription_id)
    reference = reference_for(p)
    try:
        if not p.email_recipient:
            raise ValueError('The farmer has no email address on file.')
        pdf = ensure_pdf(p)
        message = build_email(p, pdf)
        if not message.send(fail_silently=False):
            raise RuntimeError('The mail server did not accept the message.')
    except Exception as exc:
        error = safe_error(exc)
        ClinicalPrescription.objects.filter(id=p.id).update(email_status='failed', email_error=error)
        log.warning('Prescription %s email failed (attempt %s): %s', reference, p.email_attempts, error)
        return 'failed'
    ClinicalPrescription.objects.filter(id=p.id).update(
        email_status='sent', email_sent_at=timezone.now(), email_error=None,
        email_message_id=message.extra_headers.get('Message-ID'))
    log.info('Prescription %s emailed (attempt %s).', reference, p.email_attempts)
    return 'sent'


def issue_documents(prescription_id):
    """After a prescription commits: generate + store its PDF, then email it.
    Failures are recorded on the row and never propagate."""
    try:
        ensure_pdf(_load(prescription_id))
    except Exception as exc:  # recorded in pdf_error; retried on first view / email
        log.warning('Prescription %s PDF generation failed: %s', prescription_id, safe_error(exc))
    deliver_email(prescription_id)


def retry_candidates(max_attempts=MAX_AUTOMATIC_ATTEMPTS):
    """Prescriptions whose email is owed: failed / never attempted / stuck in
    `sending`. Never a delivered one."""
    stale = timezone.now() - STALE_SENDING
    qs = ClinicalPrescription.objects.filter(email_attempts__lt=max_attempts)
    return (qs.filter(email_status__in=('failed', 'pending'))
            | qs.filter(email_status='sending', email_last_attempt_at__lt=stale)).order_by('created_at')


def delivery_fields(p):
    """Prescription delivery state for API rows (no storage path, no secrets)."""
    return {
        'reference_number': reference_for(p),
        'issued_at': iso_utc(p.created_at),
        'doctor_name': doctor_display_name(p.doctor),
        'pdf_available': bool(p.pdf_file),
        'pdf_generated_at': iso_utc(p.pdf_generated_at) if p.pdf_generated_at else None,
        'email_status': p.email_status,
        'email_recipient': p.email_recipient,
        'email_attempts': p.email_attempts,
        'email_last_attempt_at': iso_utc(p.email_last_attempt_at) if p.email_last_attempt_at else None,
        'email_error': p.email_error if p.email_status == 'failed' else None,
    }
