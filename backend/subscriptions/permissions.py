from django.db.models import Q
from django.utils import timezone

from .models import Subscription


def has_feature(user, feature_name):
    """True if the user has an active subscription whose plan unlocks
    feature_name (see subscription_plans.features_unlocked seed data)."""
    if not user or not user.is_authenticated:
        return False
    now = timezone.now()
    return Subscription.objects.filter(
        user=user, status='active', plan__features_unlocked__contains=[feature_name],
    ).filter(Q(expires_at__isnull=True) | Q(expires_at__gt=now)).exists()
