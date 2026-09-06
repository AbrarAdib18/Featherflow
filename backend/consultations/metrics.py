"""Doctor response-time + dispute metrics — shared by the doctor dashboard and
the admin doctor-oversight view (the ``admin_doctor`` role owns "response
times")."""

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
