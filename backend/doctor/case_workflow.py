"""The doctor's Case page workflow. See DOCTOR_CASE_PAGE_FIX.md.

All case work happens on the individual Case page, driven by one derived
``stage``:

    awaiting_acceptance  consultation requested / reschedule proposed (accept it on Schedule first)
    open                 accepted or in progress, case not closed -> clinical fields editable, Close case
    closed               accepted or in progress, case closed     -> Mark as Complete (or Reopen)
    completed            consultation completed, no prescription  -> Issue prescription & advice
    prescribed           consultation completed, prescription issued
    ended                rejected / cancelled / no-show            -> read-only

The stage is computed here only, and both the API response and the edit
rules use it, so the Flutter page and the server can't disagree about what
is allowed.
"""
from django.db import transaction
from rest_framework import serializers

from audit.models import ActivityLog

from .models import CaseDetail, ConsultationNote

ACTIVE_CONSULTATION = ('accepted', 'in_progress')
ENDED_CONSULTATION = ('rejected', 'cancelled', 'no_show')

# consultation_notes columns (clinical record written by the doctor)
NOTE_FIELDS = ('diagnosis', 'treatment_plan', 'warnings', 'next_steps')
# consultation_case_details text columns the doctor may annotate
DETAIL_TEXT_FIELDS = ('feed_notes', 'vaccine_history', 'biosecurity_notes')
# Farmer intake data the doctor may correct (kept for API compatibility).
INTAKE_FIELDS = ('farm_name', 'bird_age', 'breed', 'flock_count', 'mortality_count', 'symptoms')
EDITABLE_FIELDS = NOTE_FIELDS + DETAIL_TEXT_FIELDS + INTAKE_FIELDS + ('disease_tags',)
# Clinical fields that must be filled in before a case can be closed: they
# are what the farmer receives as clinical results after completion.
REQUIRED_TO_CLOSE = ('diagnosis', 'treatment_plan')

TEXT_MAX = 5000
TAG_MAX = 60
TAGS_MAX = 20


class CaseWorkflowError(Exception):
    def __init__(self, detail, code, status=409, errors=None):
        super().__init__(detail)
        self.detail, self.code, self.status, self.errors = detail, code, status, errors or {}

    def payload(self):
        body = {'detail': self.detail, 'code': self.code}
        if self.errors:
            body['errors'] = self.errors
        return body


class CaseFieldsSerializer(serializers.Serializer):
    """Partial update of the doctor-editable case fields. Every field is
    optional; only the ones sent are changed."""

    consultation_id = serializers.UUIDField(required=False)
    diagnosis = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    treatment_plan = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    warnings = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    next_steps = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    feed_notes = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    vaccine_history = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    biosecurity_notes = serializers.CharField(required=False, allow_blank=True, max_length=TEXT_MAX, trim_whitespace=True)
    farm_name = serializers.CharField(required=False, allow_blank=True, max_length=150, trim_whitespace=True)
    bird_age = serializers.CharField(required=False, allow_blank=True, max_length=50, trim_whitespace=True)
    breed = serializers.CharField(required=False, allow_blank=True, max_length=100, trim_whitespace=True)
    flock_count = serializers.IntegerField(required=False, min_value=0)
    mortality_count = serializers.IntegerField(required=False, min_value=0)
    symptoms = serializers.ListField(child=serializers.CharField(max_length=200, trim_whitespace=True),
                                     required=False, max_length=30)
    disease_tags = serializers.ListField(
        child=serializers.CharField(max_length=TAG_MAX, trim_whitespace=True),
        required=False, max_length=TAGS_MAX)
    status = serializers.ChoiceField(choices=('open', 'in_progress', 'follow_up', 'closed'), required=False)

    def validate_disease_tags(self, tags):
        seen, clean = set(), []
        for tag in tags:
            if tag and tag.lower() not in seen:
                seen.add(tag.lower())
                clean.append(tag)
        return clean


def latest_note(consultation):
    return consultation.clinical_notes.order_by('-updated_at', '-created_at').first()


def case_stage(case, consultation=None, has_prescription=None):
    consultation = consultation or case.consultation
    status = consultation.status
    if status in ENDED_CONSULTATION:
        return 'ended'
    if status == 'completed':
        if has_prescription is None:
            has_prescription = consultation.clinical_prescriptions.exists()
        return 'prescribed' if has_prescription else 'completed'
    if status in ACTIVE_CONSULTATION:
        return 'closed' if case.case_status == 'closed' else 'open'
    return 'awaiting_acceptance'  # requested / reschedule_proposed


_STAGE_REFUSALS = {
    'awaiting_acceptance': ('Accept this consultation on the Schedule page before starting case work.',
                            'consultation_not_accepted'),
    'closed': ('This case is closed. Reopen it to edit the clinical fields.', 'case_closed'),
    'completed': ('This consultation is completed; its clinical record is final.', 'consultation_completed'),
    'prescribed': ('This consultation is completed; its clinical record is final.', 'consultation_completed'),
    'ended': ('This consultation was not carried out; the case is read-only.', 'consultation_ended'),
}


def _audit(actor, case, action, old, new, reason=None):
    ActivityLog.objects.create(
        user=actor, module='doctor_cases', action=action, action_type='edit',
        entity_type='consultation_case', entity_id=case.id,
        old_values=old or None, new_values=new or None, reason=reason)


@transaction.atomic
def update_case(case, actor, data):
    """Apply a validated partial update (fields and/or status) as ``actor``.

    Raises CaseWorkflowError for a change the current stage doesn't allow.
    Returns the refreshed case.
    """
    case = CaseDetail.objects.select_for_update().select_related('consultation').get(id=case.id)
    consultation = case.consultation
    stage = case_stage(case, consultation)
    new_status = data.get('status')
    fields = {k: v for k, v in data.items() if k in EDITABLE_FIELDS}
    if 'symptoms' in fields:
        fields['symptoms'] = [x for x in fields['symptoms'] if x]

    if new_status and new_status != 'closed' and stage == 'closed':
        # Reopen: the only change a closed case accepts (fields may come with it).
        pass
    elif fields or new_status:
        if stage != 'open':
            detail, code = _STAGE_REFUSALS[stage]
            raise CaseWorkflowError(detail, code)

    note = latest_note(consultation)
    current = {
        **{k: (getattr(note, k) if note else None) or '' for k in NOTE_FIELDS},
        **{k: getattr(case, k) or '' for k in DETAIL_TEXT_FIELDS + ('farm_name', 'bird_age', 'breed')},
        'flock_count': case.flock_count, 'mortality_count': case.mortality_count,
        'symptoms': [x for x in (case.symptoms_description or '').split('\n') if x.strip()],
        'disease_tags': list(case.disease_tags or []),
    }
    changed = {k: v for k, v in fields.items() if current.get(k) != v}

    if new_status == 'closed' and case.case_status != 'closed':
        after = {**current, **changed}
        missing = {k: 'Required before the case can be closed.' for k in REQUIRED_TO_CLOSE if not after[k]}
        if missing:
            raise CaseWorkflowError(
                'Enter a diagnosis and treatment plan before closing the case.',
                'case_incomplete', status=400, errors=missing)

    note_changes = {k: v for k, v in changed.items() if k in NOTE_FIELDS}
    if note_changes:
        if note:
            for key, value in note_changes.items():
                setattr(note, key, value)
            note.save()
        else:
            ConsultationNote.objects.create(
                consultation=consultation, doctor=actor,
                symptoms=case.symptoms_description,
                **{**{k: current[k] for k in NOTE_FIELDS}, **note_changes})
    for key, value in changed.items():
        if key == 'symptoms':
            case.symptoms_description = '\n'.join(value)
        elif key not in NOTE_FIELDS:
            setattr(case, key, value)
    old_status = case.case_status
    if new_status and new_status != old_status:
        case.case_status = new_status
    if changed or case.case_status != old_status:
        case.save()

    if changed:
        _audit(actor, case, 'case_fields_updated',
               {k: current[k] for k in changed}, changed)
    if case.case_status != old_status:
        action = {'closed': 'case_closed'}.get(case.case_status,
                                                'case_reopened' if old_status == 'closed' else 'case_status_changed')
        _audit(actor, case, action, {'case_status': old_status}, {'case_status': case.case_status})
    return case
