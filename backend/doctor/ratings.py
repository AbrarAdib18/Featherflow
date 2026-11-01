"""A doctor's rating: the one definition (DOCTOR_RATINGS_FIX.md).

The rating is the average of the 1–5 stars farmers gave on this doctor's
consultations, and the count is how many consultations were rated.
``DoctorProfile.rating`` is a stored copy of that average, which the farmer-
facing vet lists read. It is refreshed on every in-app rating and by
``manage.py recalculate_doctor_ratings`` after any out-of-band data change
(seeds, imports, merges). The doctor's own dashboard, profile and ratings page
always use the live values from :func:`rating_summary`, so they can't drift.
"""
from decimal import ROUND_HALF_UP, Decimal

from django.db.models import Avg, Count

from consultations.models import Consultation
from profiles.models import DoctorProfile


def rating_summary(doctor):
    rated = Consultation.objects.filter(doctor=doctor, rating__isnull=False)
    agg = rated.aggregate(average=Avg('rating'), count=Count('id'))
    count = agg['count'] or 0
    by_star = dict(rated.values_list('rating').annotate(n=Count('id')))
    return {
        'average': round(float(agg['average']), 2) if count else 0.0,
        'count': count,
        'distribution': {str(star): by_star.get(star, 0) for star in range(5, 0, -1)},
    }


def stored_value(summary):
    return Decimal(str(summary['average'])).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def refresh_stored_rating(doctor):
    """Recompute the stored DoctorProfile.rating from the consultations."""
    summary = rating_summary(doctor)
    DoctorProfile.objects.filter(user=doctor).update(rating=stored_value(summary))
    return summary
