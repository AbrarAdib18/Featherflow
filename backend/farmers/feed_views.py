"""Feed consumption logging under /api/farmers/feed/consumption/.

Stock in/out + schedules already live in ``feed.views`` and route straight
there. Logging consumption also draws the stock down and (best-effort) derives
a cost-per-bird figure for the flock.
"""
from datetime import date
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from farms.models import Flock
from feed.models import FeedConsumption, FeedingGuideline, FeedStock, FeedStockMovement, FeedType

from .services import IsFarmer, farm_for, money, notify, parse_date


def _guideline_json(g):
    return {
        'id': str(g.id), 'bird_type': g.bird_type,
        'min_age_days': g.min_age_days, 'max_age_days': g.max_age_days,
        'stage_label': g.stage_label, 'feed_type_label': g.feed_type_label,
        'recommended_grams_per_bird_per_day':
            float(g.recommended_grams_per_bird_per_day) if g.recommended_grams_per_bird_per_day is not None else None,
        'frequency_per_day': g.frequency_per_day, 'guidance_text': g.guidance_text,
    }


@api_view(['GET'])
@permission_classes([IsFarmer])
def flock_feed_chart(request, flock_id):
    """Age-based feeding chart data for one flock (Priority 4) — flock age,
    the matching feeding stage/guideline, the full guideline timeline for
    this bird type (so the UI can draw a chart across the whole cycle),
    actual consumption logged so far, and the current bird count (which
    reflects any mortality/sale events already applied to current_quantity).

    Labelled explicitly as general guidance, not veterinary/medical advice —
    see FeedingGuideline's docstring and the request's Priority 4 scope.
    """
    farm = farm_for(request.user)
    try:
        flock = farm.flocks.get(pk=flock_id)
    except Flock.DoesNotExist:
        return Response({'detail': 'Flock not found.'}, status=404)

    bird_type = flock.bird_type or 'other'
    all_guidelines = list(FeedingGuideline.objects.filter(bird_type=bird_type, is_active=True))
    current = FeedingGuideline.for_age(bird_type, flock.age_days)
    total_consumed = (FeedConsumption.objects.filter(flock=flock)
                      .aggregate(v=Sum('quantity_consumed'))['v'] or 0)
    recent_events = list(flock.events.all()[:20])

    from .farm_views import _event_json, _flock_json
    return Response({
        'flock': _flock_json(flock),
        'current_guideline': _guideline_json(current) if current else None,
        'guidelines': [_guideline_json(g) for g in all_guidelines],
        'total_consumed': float(total_consumed),
        'recent_events': [_event_json(e) for e in recent_events],
        'disclaimer': ('General feeding guidance only — not veterinary or nutritional advice. '
                       'Consult a qualified poultry professional for flock-specific decisions.'),
    })


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def consumption(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        qs = (FeedConsumption.objects.filter(flock__farm=farm)
              .select_related('flock', 'feed_type').order_by('-consumed_date'))
        if request.query_params.get('flock'):
            qs = qs.filter(flock_id=request.query_params['flock'])
        rows = [{
            'id': str(c.id), 'flock_id': str(c.flock_id), 'flock_name': c.flock.batch_name,
            'feed_type': c.feed_type.name, 'feed_type_id': str(c.feed_type_id),
            'quantity_consumed': float(c.quantity_consumed), 'unit': c.feed_type.unit or 'kg',
            'consumed_date': c.consumed_date.isoformat(), 'notes': c.notes or '',
        } for c in qs[:400]]
        total = qs.aggregate(v=Sum('quantity_consumed'))['v'] or 0
        return Response({'results': rows, 'total_consumed': float(total)})

    data = request.data
    try:
        flock = Flock.objects.get(pk=data['flock_id'], farm=farm)
        feed_type = FeedType.objects.get(pk=data['feed_type_id'])
        qty = money(data['quantity_consumed'], 'quantity_consumed')
    except (KeyError, Flock.DoesNotExist, FeedType.DoesNotExist, ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'flock_id, feed_type_id and quantity_consumed are required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    with transaction.atomic():
        item = FeedConsumption.objects.create(
            flock=flock, feed_type=feed_type, quantity_consumed=qty,
            consumed_date=parse_date(data.get('consumed_date'), date.today()),
            recorded_by=request.user, notes=data.get('notes', ''))
        stock = FeedStock.objects.select_for_update().filter(farm=farm, feed_type=feed_type).first()
        if stock:
            actual_drawn = min(qty, stock.quantity_available)
            stock.quantity_available = max(Decimal('0'), stock.quantity_available - qty)
            stock.save(update_fields=['quantity_available', 'updated_at'])
            if actual_drawn:
                # note carries a parseable "consumption:<id>" tag so a later
                # delete can restore exactly what was actually drawn down
                # (actual_drawn, clamped at 0) rather than the raw requested
                # quantity_consumed, which may have been more than the stock
                # on hand at the time.
                FeedStockMovement.objects.create(
                    farm=farm, feed_type=feed_type, movement_type='consumption',
                    quantity_delta=-actual_drawn, quantity_after=stock.quantity_available,
                    note=f'consumption:{item.id} — logged against flock {flock.batch_name}',
                    created_by=request.user, created_at=timezone.now(),
                )
    if stock:
        if stock.quantity_available < 50:
            notify(request.user, 'Feed stock low',
                   f'{feed_type.name}: {float(stock.quantity_available):g} {feed_type.unit} left.',
                   'alert', stock.id, 'feed_stock')
    cost_per_bird = 0
    if stock and stock.cost_per_unit and flock.current_quantity:
        cost_per_bird = round(float(qty * stock.cost_per_unit) / flock.current_quantity, 3)
    return Response({'id': str(item.id), 'cost_per_bird': cost_per_bird},
                    status=status.HTTP_201_CREATED)


@api_view(['DELETE'])
@permission_classes([IsFarmer])
def stock_detail(request, stock_id):
    farm = farm_for(request.user)
    with transaction.atomic():
        stock = FeedStock.objects.select_for_update().filter(pk=stock_id, farm=farm).first()
        if not stock:
            return Response({'detail': 'Feed stock not found.'}, status=404)
        if stock.quantity_available:
            FeedStockMovement.objects.create(
                farm=farm, feed_type=stock.feed_type, movement_type='removal',
                quantity_delta=-stock.quantity_available, quantity_after=Decimal('0'),
                created_by=request.user, created_at=timezone.now(),
            )
        stock.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['DELETE'])
@permission_classes([IsFarmer])
def consumption_detail(request, consumption_id):
    farm = farm_for(request.user)
    try:
        item = FeedConsumption.objects.get(pk=consumption_id, flock__farm=farm)
    except FeedConsumption.DoesNotExist:
        return Response({'detail': 'Consumption record not found.'}, status=404)
    # Cancelling a consumption log restores the stock it drew down — otherwise
    # deleting a mistaken entry would leave "current stock" permanently wrong.
    # Restore the amount actually drawn (the linked movement's delta), not the
    # raw quantity_consumed — a consumption request can exceed what was on
    # hand and gets clamped at 0 (see `consumption()` above), so restoring the
    # requested amount instead of the clamped one would over-restore stock.
    with transaction.atomic():
        movement = FeedStockMovement.objects.filter(
            farm=farm, feed_type=item.feed_type, movement_type='consumption',
            note__startswith=f'consumption:{item.id}',
        ).first()
        restore_amount = -movement.quantity_delta if movement else item.quantity_consumed
        stock = FeedStock.objects.select_for_update().filter(
            farm=farm, feed_type=item.feed_type).first()
        if stock and restore_amount:
            stock.quantity_available += restore_amount
            stock.save(update_fields=['quantity_available', 'updated_at'])
            FeedStockMovement.objects.create(
                farm=farm, feed_type=item.feed_type, movement_type='adjustment',
                quantity_delta=restore_amount, quantity_after=stock.quantity_available,
                note=f'Consumption log entry {item.id} deleted — stock restored',
                created_by=request.user, created_at=timezone.now(),
            )
        item.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)
