"""Feed consumption logging under /api/farmers/feed/consumption/.

Stock in/out + schedules already live in ``feed.views`` and route straight
there. Logging consumption also draws the stock down and (best-effort) derives
a cost-per-bird figure for the flock.
"""
from datetime import date
from decimal import Decimal

from django.db.models import Sum
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from farms.models import Flock
from feed.models import FeedConsumption, FeedStock, FeedType

from .services import IsFarmer, farm_for, money, notify, parse_date


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
    item = FeedConsumption.objects.create(
        flock=flock, feed_type=feed_type, quantity_consumed=qty,
        consumed_date=parse_date(data.get('consumed_date'), date.today()),
        recorded_by=request.user, notes=data.get('notes', ''))
    stock = FeedStock.objects.filter(farm=farm, feed_type=feed_type).first()
    if stock:
        stock.quantity_available = max(Decimal('0'), stock.quantity_available - qty)
        stock.save(update_fields=['quantity_available', 'updated_at'])
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
    stock = FeedStock.objects.filter(pk=stock_id, farm=farm).first()
    if not stock:
        return Response({'detail': 'Feed stock not found.'}, status=404)
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
    item.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)
