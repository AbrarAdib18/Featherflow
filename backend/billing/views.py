"""Subscription checkout + payment endpoints.

    GET  /api/subscriptions/plans/          list subscribable plans (+ current + mode)
    GET  /api/subscriptions/current/        the caller's active subscription
    POST /api/subscriptions/checkout/       {plan_id, idempotency_key?} -> PaymentIntent
    GET  /api/payments/<id>/                intent detail
    POST /api/payments/<id>/method/         {payment_method}  -> pending
    POST /api/payments/<id>/confirm/        {outcome} (DEV) — success|failure|cancel
    POST /api/payments/<id>/cancel/
    POST /api/payments/webhook/<provider>/  provider callback (live mode)

All require authentication except the webhook (which is signature-verified).
Amounts are always computed server-side from the plan row.
"""
import json
import logging

from django.shortcuts import get_object_or_404
from rest_framework.decorators import (api_view, permission_classes,
                                       throttle_classes)
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from api.throttling import PaymentWriteRateThrottle

from . import services
from .models import PaymentIntent
from .webhooks import verify_and_parse

logger = logging.getLogger('billing')


def _intent_for(request, pk):
    return get_object_or_404(PaymentIntent, pk=pk, user=request.user)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def plans(request):
    return Response({
        'mode': services.billing_mode(),
        'currency': 'BDT',
        'free_plan': services.free_plan(),
        'plans': services.subscribable_plans(),
        'current': services.current_subscription(request.user),
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def current(request):
    return Response({'current': services.current_subscription(request.user),
                     'mode': services.billing_mode()})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([PaymentWriteRateThrottle])
def checkout(request):
    try:
        intent, created = services.create_checkout(
            request.user,
            request.data.get('plan_id'),
            request.data.get('idempotency_key', ''))
    except services.CheckoutError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    logger.info('checkout %s intent=%s plan=%s user=%s',
                'created' if created else 'reused', intent.id, intent.plan_code,
                request.user.email)
    return Response(services.intent_json(intent), status=201 if created else 200)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def payment_detail(request, pk):
    return Response(services.intent_json(_intent_for(request, pk)))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([PaymentWriteRateThrottle])
def select_method(request, pk):
    intent = _intent_for(request, pk)
    try:
        intent = services.select_method(intent, str(request.data.get('payment_method', '')).lower())
    except services.CheckoutError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    body = services.intent_json(intent)
    # What the client should do next.
    if services.billing_mode() == 'dev':
        body['next'] = 'dev_checkout'
        body['dev_checkout'] = {
            'note': 'Development payment mode — no real money moves. '
                    'POST /confirm/ with outcome=success|failure|cancel.',
        }
    else:
        body['next'] = 'provider_redirect'
        body['redirect_url'] = None  # a real provider integration fills this in
    return Response(body)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([PaymentWriteRateThrottle])
def confirm(request, pk):
    """DEV MODE: mark the simulated payment succeeded / failed / cancelled and,
    on success, activate the subscription. Rejected in live mode."""
    intent = _intent_for(request, pk)
    outcome = str(request.data.get('outcome', 'success')).lower()
    if outcome not in ('success', 'failure', 'cancel'):
        return Response({'detail': 'outcome must be success, failure or cancel.'}, status=400)
    try:
        intent = services.confirm_dev(intent, outcome)
    except services.CheckoutError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    return Response({
        **services.intent_json(intent),
        'subscription': services.current_subscription(request.user),
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([PaymentWriteRateThrottle])
def cancel(request, pk):
    intent = _intent_for(request, pk)
    try:
        intent = services.cancel_intent(intent)
    except services.CheckoutError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    return Response(services.intent_json(intent))


@api_view(['POST'])
@permission_classes([AllowAny])
def webhook(request, provider):
    """Provider payment callback (live mode). Verifies the signature, then
    confirms the matching intent. In dev mode there are no real webhooks."""
    if services.billing_mode() != 'live':
        return Response({'detail': 'Webhooks are only processed in live mode.'}, status=404)
    try:
        raw = request.body
        event = verify_and_parse(provider, raw, request.headers)
    except Exception as exc:
        logger.warning('webhook rejected (%s): %s', provider, exc)
        return Response({'detail': 'Invalid webhook signature.'}, status=400)

    intent = PaymentIntent.objects.filter(id=event.get('intent_id')).first() \
        or PaymentIntent.objects.filter(provider_ref=event.get('provider_ref', '\0')).first()
    if intent is None:
        logger.warning('webhook %s: no matching intent for %s', provider, event)
        return Response({'detail': 'No matching payment.'}, status=404)
    try:
        services.confirm_provider(intent, event['outcome'], event.get('provider_ref', ''),
                                  via=f'{provider}-webhook')
    except services.CheckoutError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    return Response({'ok': True})
