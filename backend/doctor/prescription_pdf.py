from io import BytesIO

from django.conf import settings
from django.core.mail import EmailMessage
from django.utils import timezone
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from reportlab.lib import colors


def build_prescription_pdf(prescription):
    consultation = prescription.consultation
    case = getattr(consultation, 'case_detail', None)
    styles = getSampleStyleSheet()
    output = BytesIO()
    document = SimpleDocTemplate(
        output, pagesize=A4, rightMargin=18 * mm, leftMargin=18 * mm,
        topMargin=18 * mm, bottomMargin=18 * mm,
        title=f'Prescription {prescription.id}', author='Featherflow',
    )
    story = [
        Paragraph('Featherflow Veterinary Prescription', styles['Title']),
        Spacer(1, 8),
        Paragraph(f'<b>Doctor:</b> {prescription.doctor.full_name or prescription.doctor.email}', styles['BodyText']),
        Paragraph(f'<b>Farmer:</b> {consultation.farmer.full_name or consultation.farmer.email}', styles['BodyText']),
        Paragraph(f'<b>Consultation:</b> {consultation.appointment_date} at {consultation.appointment_time}', styles['BodyText']),
    ]
    if case:
        story.extend([
            Paragraph(f'<b>Farm:</b> {case.farm_name or "-"}', styles['BodyText']),
            Paragraph(f'<b>Flock:</b> {case.breed or "-"}, {case.flock_count or 0} birds, age {case.bird_age or "-"}', styles['BodyText']),
            Paragraph(f'<b>Symptoms:</b> {case.symptoms_description or "-"}', styles['BodyText']),
        ])
    story.extend([Spacer(1, 12), Paragraph('Medicines', styles['Heading2'])])
    rows = [['Medicine', 'Dosage', 'Duration', 'Instructions']]
    rows.extend([[x.medicine_name, x.dosage, x.duration, x.instructions or ''] for x in prescription.items.all()])
    table = Table(rows, colWidths=[42 * mm, 34 * mm, 28 * mm, 62 * mm], repeatRows=1)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E8F2FF')),
        ('GRID', (0, 0), (-1, -1), .4, colors.grey),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('PADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(table)
    sections = (
        ('Dosage notes', prescription.dosage_notes),
        ('Case advice', prescription.case_advice),
        ('Follow-up instructions', prescription.follow_up_instructions),
        ('Referral', prescription.referred_to),
    )
    for heading, value in sections:
        if value:
            story.extend([Spacer(1, 10), Paragraph(heading, styles['Heading3']), Paragraph(value, styles['BodyText'])])
    document.build(story)
    return output.getvalue()


def email_prescription(prescription_id):
    from .models import ClinicalPrescription

    prescription = ClinicalPrescription.objects.select_related(
        'doctor', 'consultation__farmer', 'consultation__case_detail',
    ).prefetch_related('items').get(id=prescription_id)
    farmer = prescription.consultation.farmer
    if not farmer.email:
        return False
    pdf = build_prescription_pdf(prescription)
    message = EmailMessage(
        subject='Your Featherflow consultation prescription',
        body=(f'Hello {farmer.full_name or "Farmer"},\n\n'
              'Your veterinarian has issued a prescription and case advice. '
              'The PDF is attached and is also available in Featherflow.'),
        from_email=settings.DEFAULT_FROM_EMAIL,
        to=[farmer.email],
    )
    message.attach(f'featherflow-prescription-{prescription.id}.pdf', pdf, 'application/pdf')
    return bool(message.send(fail_silently=False))


def deliver_prescription_email(prescription_id):
    from .models import ClinicalPrescription

    try:
        sent = email_prescription(prescription_id)
        ClinicalPrescription.objects.filter(id=prescription_id).update(
            email_sent_at=timezone.now() if sent else None,
            email_error=None if sent else 'The mail backend did not accept the message.',
        )
    except Exception as exc:  # The clinical record must survive provider outages.
        ClinicalPrescription.objects.filter(id=prescription_id).update(
            email_error=str(exc)[:2000])
