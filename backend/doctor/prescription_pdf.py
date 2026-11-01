"""The prescription PDF (DOCTOR_PRESCRIPTION_PDF_EMAIL.md).

Built only from persisted records (prescription, its items, consultation,
case, farmer, doctor profile, pending follow-up). Every value is optional
except the prescription itself, and all user text is XML-escaped before it
reaches ReportLab's paragraph markup. A ``<`` or ``&`` in a medicine name used
to abort the whole PDF.

Storage, access and email live in ``doctor/prescriptions.py``.
"""
import textwrap
from datetime import datetime, timezone as dt_timezone
from io import BytesIO
from xml.sax.saxutils import escape

from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (KeepTogether, Paragraph, SimpleDocTemplate, Spacer,
                                Table, TableStyle)

BRAND = colors.HexColor('#01291E')       # FeatherFlow navigation green
ACCENT = colors.HexColor('#1DB584')
INK = colors.HexColor('#1A1A1A')
MUTED = colors.HexColor('#5F6B66')
RULE = colors.HexColor('#D9E2DE')
ZEBRA = colors.HexColor('#F4F8F6')

DISCLAIMER = ('Issued by the named veterinarian through FeatherFlow. Use medicines only as '
              'directed, observe withdrawal periods, and contact your veterinarian if the '
              'flock does not improve.')


def _get(obj, path, default=None):
    """``_get(p, 'consultation.case_detail.farm_name')``; missing → default.
    Related-object lookups that raise (e.g. no profile row) count as missing."""
    for part in path.split('.'):
        if obj is None:
            return default
        try:
            obj = getattr(obj, part)
        except Exception:
            return default
    return default if obj is None else obj


def _text(value):
    """User text → safe paragraph markup (escaped, newlines kept)."""
    return escape(str(value)).replace('\n', '<br/>')


def _local(value):
    if not isinstance(value, datetime):
        return value
    if timezone.is_naive(value):  # timestamp columns hold UTC wall-clock
        value = value.replace(tzinfo=dt_timezone.utc)
    return timezone.localtime(value)


def _when(value, fmt='%d %b %Y, %I:%M %p'):
    value = _local(value)
    return value.strftime(fmt) if value else ''


def doctor_display_name(user):
    """'Dr. Samira Rahman' — never 'Dr. Dr. …'."""
    name = str(_get(user, 'full_name') or _get(user, 'email') or 'Veterinarian').strip()
    return name if name.lower().startswith(('dr.', 'dr ')) else f'Dr. {name}'


def reference_for(prescription):
    """Stable reference printed on the PDF (matches the SQL backfill)."""
    stored = _get(prescription, 'reference_number')
    if stored:
        return stored
    created = _local(_get(prescription, 'created_at')) or timezone.localtime()
    ident = str(_get(prescription, 'id', '')).replace('-', '')[:8].upper()
    return f'RX-{created:%Y%m%d}-{ident}'


def _styles():
    base = getSampleStyleSheet()
    return {
        'body': ParagraphStyle('body', parent=base['BodyText'], fontSize=9.5, leading=13, textColor=INK),
        'small': ParagraphStyle('small', parent=base['BodyText'], fontSize=8, leading=10, textColor=MUTED),
        'label': ParagraphStyle('label', parent=base['BodyText'], fontSize=7.5, leading=9,
                                textColor=MUTED, fontName='Helvetica-Bold'),
        'h2': ParagraphStyle('h2', parent=base['Heading2'], fontSize=11.5, leading=14,
                             textColor=BRAND, spaceBefore=10, spaceAfter=4),
        'brand': ParagraphStyle('brand', parent=base['Title'], fontSize=17, leading=20,
                                textColor=colors.white, alignment=0),
        'brandsub': ParagraphStyle('brandsub', parent=base['BodyText'], fontSize=9,
                                   textColor=colors.white),
        'brandright': ParagraphStyle('brandright', parent=base['BodyText'], fontSize=9,
                                     leading=12, textColor=colors.white, alignment=TA_RIGHT),
        'cell': ParagraphStyle('cell', parent=base['BodyText'], fontSize=9, leading=11.5, textColor=INK),
        'cellhead': ParagraphStyle('cellhead', parent=base['BodyText'], fontSize=8.5, leading=10,
                                   textColor=colors.white, fontName='Helvetica-Bold'),
    }


def _detail_block(title, rows, s):
    lines = [Paragraph(title.upper(), s['label'])]
    for label, value in rows:
        if value not in (None, ''):
            lines.append(Paragraph(f'<b>{escape(label)}:</b> {_text(value)}', s['body']))
    return lines


def build_prescription_pdf(prescription):
    s = _styles()
    consultation = _get(prescription, 'consultation')
    case = _get(consultation, 'case_detail')
    doctor = _get(prescription, 'doctor')
    profile = _get(doctor, 'doctor_profile')
    farmer = _get(consultation, 'farmer')
    reference = reference_for(prescription)
    issued = _get(prescription, 'created_at')
    generated = timezone.localtime()
    farm_name = _get(case, 'farm_name') or _get(farmer, 'farmer_profile.farm_name')

    output = BytesIO()
    document = SimpleDocTemplate(
        output, pagesize=A4, rightMargin=16 * mm, leftMargin=16 * mm,
        topMargin=14 * mm, bottomMargin=22 * mm,
        title=f'Prescription {reference}', author='FeatherFlow',
        subject='Veterinary prescription')
    width = A4[0] - 32 * mm

    header = Table([[
        [Paragraph('FeatherFlow', s['brand']), Paragraph('Veterinary Prescription', s['brandsub'])],
        Paragraph(f'<b>Reference</b><br/>{escape(reference)}<br/><b>Date</b><br/>'
                  f'{escape(_when(issued, "%d %b %Y") or generated.strftime("%d %b %Y"))}',
                  s['brandright']),
    ]], colWidths=[width * 0.62, width * 0.38])
    header.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), BRAND),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 10), ('RIGHTPADDING', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 9), ('BOTTOMPADDING', (0, 0), (-1, -1), 9),
    ]))

    doctor_lines = _detail_block('Prescribed by', [
        ('Name', doctor_display_name(doctor)),
        ('Qualification', _get(profile, 'veterinary_degree')),
        ('Specialty', _get(profile, 'specialty')),
        ('Licence', ' · '.join(x for x in (_get(profile, 'license_number'),
                                           _get(profile, 'license_issuing_authority')) if x)),
        ('Clinic', _get(profile, 'clinic_hospital_name')),
    ], s)
    appointment = ' '.join(x for x in (
        _get(consultation, 'appointment_date') and _get(consultation, 'appointment_date').strftime('%d %b %Y'),
        _get(consultation, 'appointment_time') and _get(consultation, 'appointment_time').strftime('%I:%M %p'),
    ) if x)
    mode = {'online': 'Online', 'offline': 'In-person'}.get(_get(consultation, 'mode'), '')
    patient_lines = _detail_block('Issued to', [
        ('Farmer', _get(farmer, 'full_name') or _get(farmer, 'email')),
        ('Farm', farm_name),
        ('Flock', ', '.join(x for x in (
            _get(case, 'breed'),
            f'{_get(case, "flock_count")} birds' if _get(case, 'flock_count') else '',
            f'age {_get(case, "bird_age")}' if _get(case, 'bird_age') else '') if x)),
        ('Consultation', ' · '.join(x for x in (appointment, mode) if x)),
        ('Case ref.', str(_get(case, 'id', ''))[:8].upper() or None),
    ], s)
    parties = Table([[doctor_lines, patient_lines]], colWidths=[width / 2] * 2)
    parties.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOX', (0, 0), (0, 0), .6, RULE), ('BOX', (1, 0), (1, 0), .6, RULE),
        ('LEFTPADDING', (0, 0), (-1, -1), 8), ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 7), ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
    ]))

    story = [header, Spacer(1, 10), parties]

    note = None
    notes = _get(consultation, 'clinical_notes')
    if notes is not None:
        try:
            note = notes.order_by('-updated_at', '-created_at').first()
        except Exception:
            note = None
    if note is not None and (_get(note, 'diagnosis') or '').strip():
        story += [Paragraph('Diagnosis', s['h2']), Paragraph(_text(note.diagnosis), s['body'])]

    story.append(Paragraph('Prescribed medicines', s['h2']))
    items = list(_get(prescription, 'items').all()) if _get(prescription, 'items') else []
    rows = [[Paragraph(h, s['cellhead']) for h in ('#', 'Medicine', 'Dosage', 'Duration', 'Instructions')]]
    for i, item in enumerate(items, 1):
        rows.append([Paragraph(str(i), s['cell'])] + [
            Paragraph(_text(_get(item, field) or '—'), s['cell'])
            for field in ('medicine_name', 'dosage', 'duration', 'instructions')])
    if not items:
        rows.append(['', Paragraph('No medicines listed.', s['cell']), '', '', ''])
    table = Table(rows, colWidths=[8 * mm, width * 0.27, width * 0.18, width * 0.15,
                                   width - 8 * mm - width * 0.60], repeatRows=1)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), BRAND),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, ZEBRA]),
        ('LINEBELOW', (0, 0), (-1, -1), .4, RULE),
        ('BOX', (0, 0), (-1, -1), .6, RULE),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 5), ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 4), ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    story.append(table)

    follow_up = None
    follow_ups = _get(consultation, 'follow_ups')
    if follow_ups is not None:
        try:
            follow_up = follow_ups.filter(status='pending').order_by('scheduled_date').first()
        except Exception:
            follow_up = None
    follow_up_when = None
    if follow_up is not None:
        follow_up_when = follow_up.scheduled_date.strftime('%A, %d %b %Y')
        if follow_up.scheduled_time:
            follow_up_when += follow_up.scheduled_time.strftime(' at %I:%M %p')

    for heading, value in (
        ('Case advice', _get(prescription, 'case_advice')),
        ('Dosage notes', _get(prescription, 'dosage_notes')),
        ('Follow-up instructions', _get(prescription, 'follow_up_instructions')),
        ('Follow-up appointment', follow_up_when),
        ('Referral', _get(prescription, 'referred_to')),
    ):
        if value and str(value).strip():
            story += [Paragraph(heading, s['h2']), Paragraph(_text(value), s['body'])]

    signature = Table([[
        '',
        [Spacer(1, 18),
         Paragraph('_' * 34, s['small']),
         Paragraph(f'<b>{escape(doctor_display_name(doctor))}</b>', s['body']),
         Paragraph(escape(' · '.join(x for x in (_get(profile, 'veterinary_degree'),
                                                 _get(profile, 'license_number')) if x)), s['small']),
         Paragraph(f'Issued electronically on {escape(_when(issued) or generated.strftime("%d %b %Y, %I:%M %p"))}',
                   s['small'])],
    ]], colWidths=[width * 0.5, width * 0.5])
    story += [Spacer(1, 16), KeepTogether(signature)]

    footer_text = f'{reference} · Generated {generated:%d %b %Y, %I:%M %p} ({generated.tzname()})'

    def decorate(canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(RULE)
        canvas.line(16 * mm, 16 * mm, A4[0] - 16 * mm, 16 * mm)
        canvas.setFont('Helvetica', 7)
        canvas.setFillColor(MUTED)
        for i, line in enumerate(textwrap.wrap(DISCLAIMER, 130)[:2]):
            canvas.drawString(16 * mm, (12.5 - 3.4 * i) * mm, line)
        canvas.drawString(16 * mm, 5.7 * mm, footer_text)
        canvas.drawRightString(A4[0] - 16 * mm, 5.7 * mm, f'Page {doc.page}')
        canvas.restoreState()

    document.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return output.getvalue()
