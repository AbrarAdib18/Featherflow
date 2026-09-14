"""Doctor response-time + dispute metrics — shared by the doctor dashboard and
the admin doctor-oversight view (the ``admin_doctor`` role owns "response
times")."""

from django.db.models import Count

from doctor.models import ConsultationStatusHistory

from .models import ConsultationDispute, Consultation


def response_time_stats(doctor_user):
    """Minutes from a request being created to the doctor's first accept, over
    that doctor's history. Returns avg / fastest / slowest / sample size."""
    firsts = {}
    rows = ConsultationStatusHistory.objects.filter(
        consultation__doctor=doctor_user, to_status='accepted',
    ).select_related('consultation').order_by('created_at')
    for row in rows:
        firsts.setdefault(row.consultation_id, (row.consultation.created_at, row.created_at))

    minutes = []
    for created_at, accepted_at in firsts.values():
        if created_at and accepted_at:
            delta = (accepted_at - created_at).total_seconds() / 60
            if delta >= 0:
                minutes.append(round(delta, 1))

    pending = Consultation.objects.filter(doctor=doctor_user, status='requested').count()
    if not minutes:
        return {'avg_minutes': None, 'fastest_minutes': None, 'slowest_minutes': None,
                'sample_size': 0, 'pending_requests': pending}
    return {
        'avg_minutes': round(sum(minutes) / len(minutes), 1),
        'fastest_minutes': min(minutes),
        'slowest_minutes': max(minutes),
        'sample_size': len(minutes),
        'pending_requests': pending,
    }


def dispute_counts(doctor_user):
    qs = ConsultationDispute.objects.filter(consultation__doctor=doctor_user)
    return {
        'open': qs.filter(status__in=('open', 'under_review')).count(),
        'total': qs.count(),
    }


# ── bulk variants — same math as above, one page of doctors in ~3 queries
# instead of ~5 per doctor (PERFORMANCE_BASELINE.md PC3) ───────────────────

def bulk_response_time_stats(doctor_user_ids):
    """{doctor_user_id: response_time_stats(...)} for a whole page of doctors,
    computed from 2 queries total instead of 2 per doctor."""
    doctor_user_ids = list(doctor_user_ids)
    result = {
        uid: {'avg_minutes': None, 'fastest_minutes': None, 'slowest_minutes': None,
              'sample_size': 0, 'pending_requests': 0}
        for uid in doctor_user_ids
    }
    if not doctor_user_ids:
        return result

    firsts = {}  # consultation_id -> (doctor_id, created_at, accepted_at)
    rows = ConsultationStatusHistory.objects.filter(
        consultation__doctor_id__in=doctor_user_ids, to_status='accepted',
    ).select_related('consultation').order_by('created_at')
    for row in rows:
        firsts.setdefault(
            row.consultation_id,
            (row.consultation.doctor_id, row.consultation.created_at, row.created_at))

    minutes_by_doctor = {}
    for doctor_id, created_at, accepted_at in firsts.values():
        if created_at and accepted_at:
            delta = (accepted_at - created_at).total_seconds() / 60
            if delta >= 0:
                minutes_by_doctor.setdefault(doctor_id, []).append(round(delta, 1))

    pending_counts = dict(
        Consultation.objects.filter(doctor_id__in=doctor_user_ids, status='requested')
        .values('doctor_id').annotate(n=Count('id')).values_list('doctor_id', 'n'))

    for uid in doctor_user_ids:
        minutes = minutes_by_doctor.get(uid, [])
        pending = pending_counts.get(uid, 0)
        if not minutes:
            result[uid]['pending_requests'] = pending
            continue
        result[uid] = {
            'avg_minutes': round(sum(minutes) / len(minutes), 1),
            'fastest_minutes': min(minutes),
            'slowest_minutes': max(minutes),
            'sample_size': len(minutes),
            'pending_requests': pending,
        }
    return result


def bulk_dispute_counts(doctor_user_ids):
    """{doctor_user_id: dispute_counts(...)} for a whole page, 1 query total."""
    doctor_user_ids = list(doctor_user_ids)
    result = {uid: {'open': 0, 'total': 0} for uid in doctor_user_ids}
    if not doctor_user_ids:
        return result
    rows = (ConsultationDispute.objects
            .filter(consultation__doctor_id__in=doctor_user_ids)
            .values('consultation__doctor_id', 'status'))
    for row in rows:
        uid = row['consultation__doctor_id']
        result[uid]['total'] += 1
        if row['status'] in ('open', 'under_review'):
            result[uid]['open'] += 1
    return result
