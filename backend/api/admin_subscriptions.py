"""Subscription Plans management — real `SubscriptionPlan` rows, not the
generic seed/AdminPanelRecord store `subscription-plans` used to fall
through to (see FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md).

Gated on the `subscriptions` permission module; plan mutation specifically
requires the `manage` action (`subscriptions.manage`).
"""
from decimal import Decimal, InvalidOperation

from django.db import IntegrityError
from django.db.models import Count
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from subscriptions.models import Subscription, SubscriptionPlan

from api.admin_rbac import IsAdminUser, can_perform_action

ALLOWED_CURRENCIES = {'BDT', 'USD'}


def _audit(request, action, action_type, target_id, old=None, new=None):
    ActivityLog.objects.create(
        user=request.user, module='subscription-plans', action=action, action_type=action_type,
        entity_type='subscription_plan', entity_id=None, old_values=old, new_values=new,
        ip_address=(request.META.get('HTTP_X_FORWARDED_FOR') or request.META.get('REMOTE_ADDR')),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
        reason=f'plan_id={target_id}',
    )


def _plan_json(plan, subscriber_counts):
    return {
        'id': plan.id,
        'name': plan.name,
        'features': plan.features_unlocked or [],
        'billing_interval': plan.billing_interval,
        'duration_days': plan.duration_days,
        'price': float(plan.price),
        'currency': plan.currency,
        'is_active': plan.is_active,
        'subscriber_count': subscriber_counts.get(plan.id, 0),
        'disease_scan_limit': plan.disease_scan_limit,
        'created_at': plan.created_at.isoformat() if plan.created_at else None,
        'updated_at': plan.updated_at.isoformat() if plan.updated_at else None,
    }


def _validate_plan_payload(data, *, existing=None):
    errors = {}
    name = str(data.get('name', existing.name if existing else '')).strip()
    if not name:
        errors['name'] = 'A plan name is required.'
    elif SubscriptionPlan.objects.filter(name__iexact=name).exclude(
            pk=existing.pk if existing else None).exists():
        errors['name'] = 'A plan with this name already exists.'

    try:
        price = Decimal(str(data.get('price', existing.price if existing else '0')))
        if price < 0:
            errors['price'] = 'price cannot be negative.'
    except (InvalidOperation, TypeError, ValueError):
        errors['price'] = 'price must be a number.'
        price = None

    currency = str(data.get('currency', existing.currency if existing else 'BDT')).upper()
    if currency not in ALLOWED_CURRENCIES:
        errors['currency'] = f'currency must be one of {sorted(ALLOWED_CURRENCIES)}.'

    duration_days = data.get('duration_days', existing.duration_days if existing else None)
    if duration_days not in (None, ''):
        try:
            duration_days = int(duration_days)
            if duration_days <= 0:
                errors['duration_days'] = 'duration_days must be a positive integer.'
        except (TypeError, ValueError):
            errors['duration_days'] = 'duration_days must be an integer (or omitted for one-time).'
    else:
        duration_days = None

    return errors, {
        'name': name, 'price': price, 'currency': currency, 'duration_days': duration_days,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def subscription_plans_list(request):
    if not can_perform_action(request.user, 'subscriptions', 'view' if request.method == 'GET' else 'manage'):
        return Response({'detail': 'You cannot manage subscription plans.'}, status=403)

    if request.method == 'POST':
        errors, cleaned = _validate_plan_payload(request.data)
        if errors:
            return Response({'detail': 'Invalid plan data.', 'errors': errors}, status=400)
        features = request.data.get('features_unlocked') or request.data.get('features') or []
        if not isinstance(features, list):
            return Response({'detail': 'features_unlocked must be a list.'}, status=400)
        try:
            plan = SubscriptionPlan.objects.create(
                name=cleaned['name'], price=cleaned['price'], currency=cleaned['currency'],
                duration_days=cleaned['duration_days'], features_unlocked=features,
                disease_scan_limit=request.data.get('disease_scan_limit'),
                is_active=True, created_at=timezone.now(), updated_at=timezone.now(),
            )
        except IntegrityError:
            return Response({'detail': 'A plan with this name already exists.'}, status=409)
        _audit(request, f'Created plan "{plan.name}"', 'create', plan.id,
               new={'name': plan.name, 'price': float(plan.price), 'currency': plan.currency})
        return Response(_plan_json(plan, {}), status=201)

    plans = list(SubscriptionPlan.objects.all().order_by('id'))
    counts = dict(Subscription.objects.values_list('plan_id').annotate(n=Count('id')))
    return Response({'results': [_plan_json(p, counts) for p in plans], 'count': len(plans)})


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def subscription_plan_update(request, plan_id):
    if not can_perform_action(request.user, 'subscriptions', 'manage'):
        return Response({'detail': 'You cannot manage subscription plans.'}, status=403)
    try:
        plan = SubscriptionPlan.objects.get(pk=plan_id)
    except (SubscriptionPlan.DoesNotExist, ValueError):
        return Response({'detail': 'Plan not found.'}, status=404)

    old = {'name': plan.name, 'price': float(plan.price), 'currency': plan.currency,
           'is_active': plan.is_active, 'duration_days': plan.duration_days}

    if 'is_active' in request.data and len(request.data) == 1:
        # Activate/deactivate only — deactivating never touches historical
        # subscriptions (they keep their own `plan_id` FK and `status`
        # regardless of the plan's current is_active flag).
        plan.is_active = bool(request.data['is_active'])
        plan.updated_at = timezone.now()
        plan.save(update_fields=['is_active', 'updated_at'])
        _audit(request, f'{"Activated" if plan.is_active else "Deactivated"} plan "{plan.name}"',
               'edit', plan.id, old=old, new={'is_active': plan.is_active})
        return Response(_plan_json(plan, _counts_for(plan)))

    errors, cleaned = _validate_plan_payload(request.data, existing=plan)
    if errors:
        return Response({'detail': 'Invalid plan data.', 'errors': errors}, status=400)
    plan.name = cleaned['name']
    plan.price = cleaned['price']
    plan.currency = cleaned['currency']
    plan.duration_days = cleaned['duration_days']
    if 'features_unlocked' in request.data or 'features' in request.data:
        features = request.data.get('features_unlocked') or request.data.get('features') or []
        if not isinstance(features, list):
            return Response({'detail': 'features_unlocked must be a list.'}, status=400)
        plan.features_unlocked = features
    if 'disease_scan_limit' in request.data:
        plan.disease_scan_limit = request.data['disease_scan_limit']
    if 'is_active' in request.data:
        plan.is_active = bool(request.data['is_active'])
    plan.updated_at = timezone.now()
    try:
        plan.save()
    except IntegrityError:
        return Response({'detail': 'A plan with this name already exists.'}, status=409)
    _audit(request, f'Edited plan "{plan.name}"', 'edit', plan.id, old=old,
           new={'name': plan.name, 'price': float(plan.price), 'currency': plan.currency,
                'is_active': plan.is_active, 'duration_days': plan.duration_days})
    return Response(_plan_json(plan, _counts_for(plan)))


def _counts_for(plan):
    return {plan.id: Subscription.objects.filter(plan=plan).count()}
