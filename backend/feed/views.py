from datetime import timedelta
from decimal import Decimal, InvalidOperation
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework import status
from consultations.permissions import IsFarmer
from workers.views import farm_for
from .models import FeedType, FeedStock, FeedStockMovement, FeedSchedule
from farms.models import Flock
from notifications.models import Notification
def self_notify(user,title,body,reference_id=None,reference_type='feed'):
    Notification.objects.create(user=user,title=title,body=body,notification_type='system',reference_id=reference_id,reference_type=reference_type)


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def feed(request):
    farm = farm_for(request.user)
    if request.method == 'POST':
        required = ('name', 'unit', 'quantity', 'cost_per_unit')
        missing = [key for key in required if not str(request.data.get(key, '')).strip()]
        if missing:
            return Response({'detail': f"Required: {', '.join(missing)}"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            quantity = Decimal(str(request.data['quantity']))
            cost_per_unit = Decimal(str(request.data['cost_per_unit']))
        except (InvalidOperation, ValueError, TypeError):
            return Response({'detail': 'Quantity and cost must be numbers.'}, status=status.HTTP_400_BAD_REQUEST)
        if quantity <= 0:
            return Response({'detail': 'Quantity must be greater than zero.'}, status=status.HTTP_400_BAD_REQUEST)
        if cost_per_unit < 0:
            return Response({'detail': 'Cost per unit cannot be negative.'}, status=status.HTTP_400_BAD_REQUEST)
        name = request.data['name'].strip()
        brand = request.data.get('brand', '').strip()
        unit = request.data['unit'].strip()
        try:
            with transaction.atomic():
                # Case/whitespace-insensitive match — the actual root cause of
                # "current stock doesn't update": get_or_create's old exact-
                # string match created a brand-new FeedType (and therefore a
                # brand-new FeedStock row starting at 0) whenever the same feed
                # was retyped with different casing/whitespace, so the row the
                # farmer was looking at never moved. Unit is still an exact
                # match — kg and bag are genuinely different units, no
                # conversion is implemented, so they intentionally remain
                # separate stock lines. See
                # FARMER_FEED_MANAGEMENT_AND_DASHBOARD_FIXES.md.
                feed_type = FeedType.objects.filter(
                    name__iexact=name, brand__iexact=brand, unit=unit,
                ).first()
                if feed_type is None:
                    feed_type = FeedType.objects.create(name=name, brand=brand, unit=unit)
                # select_for_update() + get_or_create locks the existing row
                # for the rest of this transaction (or safely creates one if
                # this is genuinely the first stock of this feed type for this
                # farm) — two concurrent purchases of the same feed can no
                # longer race and lose an update.
                stock, _created = FeedStock.objects.select_for_update().get_or_create(
                    farm=farm, feed_type=feed_type)
                stock.quantity_available += quantity
                stock.cost_per_unit = cost_per_unit
                stock.last_restocked_at = timezone.now()
                stock.save()
                FeedStockMovement.objects.create(
                    farm=farm, feed_type=feed_type, movement_type='purchase',
                    quantity_delta=quantity, quantity_after=stock.quantity_available,
                    unit_cost=cost_per_unit, note=request.data.get('note', '').strip() or None,
                    created_by=request.user, created_at=timezone.now(),
                )
        except Exception as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        self_notify(request.user, 'Feed purchase recorded',
                    f'{quantity} {feed_type.unit} of {feed_type.name} was added.', stock.id, 'feed_stock')
        return Response({
            'id': stock.id, 'feed_type_id': str(feed_type.id),
            'quantity_available': float(stock.quantity_available),
        }, status=status.HTTP_201_CREATED)
    stocks = list(farm.feed_stock.select_related('feed_type').order_by('feed_type__name'))
    rows = [{
        'id': str(s.id), 'feed_type_id':str(s.feed_type_id), 'name': s.feed_type.name, 'brand': s.feed_type.brand,
        'unit': s.feed_type.unit, 'quantity_available': float(s.quantity_available),
        'cost_per_unit': float(s.cost_per_unit or 0), 'supplier_name': s.supplier_name,
        'last_restocked_at': s.last_restocked_at.isoformat() if s.last_restocked_at else None,
        'total_value': float(s.quantity_available * (s.cost_per_unit or 0)),'status':s.stock_status,
    } for s in stocks]
    schedule_qs=FeedSchedule.objects.filter(flock__farm=farm).select_related('feed_type').order_by('scheduled_time')
    schedules=[{'id':str(x.id),'feed_type':x.feed_type.name,'scheduled_time':x.scheduled_time.strftime('%H:%M'),'quantity_per_feeding':float(x.quantity_per_feeding),'frequency':x.frequency} for x in schedule_qs]
    # Real event history (see feed_stock_integrity_extension.sql) — previously
    # this just relabeled the current stock rows as if they were purchase
    # entries, so it never reflected repeat purchases of the same feed or any
    # consumption events. Capped at the most recent 100 events.
    movements = FeedStockMovement.objects.filter(farm=farm).select_related('feed_type').order_by('-created_at')[:100]
    history = [{
        'id': str(m.id), 'feed_type': m.feed_type.name, 'unit': m.feed_type.unit,
        'movement_type': m.movement_type, 'quantity': float(m.quantity_delta),
        'quantity_after': float(m.quantity_after),
        'cost': float(m.unit_cost * abs(m.quantity_delta)) if m.unit_cost is not None else None,
        'purchased_at': m.created_at.isoformat() if m.created_at else None,
    } for m in movements]
    suppliers=[{'name':x.supplier_name,'feed_types':list(farm.feed_stock.filter(supplier_name=x.supplier_name).values_list('feed_type__name',flat=True))} for x in stocks if x.supplier_name]
    return Response({'farm_name': farm.farm_name, 'stock': rows, 'schedules':schedules,'history':history,'suppliers':suppliers,'summary': {
        'total_stock': sum(r['quantity_available'] for r in rows),
        'stock_value': sum(r['total_value'] for r in rows),
        'feed_types': len(rows),
        'low_stock_items': sum(r['status'] in ('low','out') for r in rows),
    }})

@api_view(['PATCH','DELETE'])
@permission_classes([IsFarmer])
def stock_detail(request):
    farm=farm_for(request.user)
    try:
        item=farm.feed_stock.get(pk=request.data['id'])
        if request.method=='DELETE':
            name=item.feed_type.name
            with transaction.atomic():
                if item.quantity_available:
                    FeedStockMovement.objects.create(
                        farm=farm, feed_type=item.feed_type, movement_type='removal',
                        quantity_delta=-item.quantity_available, quantity_after=Decimal('0'),
                        created_by=request.user, created_at=timezone.now(),
                    )
                item.delete()
            self_notify(request.user,'Feed stock removed',f'{name} was removed from current stock.');return Response(status=status.HTTP_204_NO_CONTENT)
        return Response({'detail':'Stock status is calculated from quantity and is not stored in the PostgreSQL schema.'},status=status.HTTP_400_BAD_REQUEST)
    except (KeyError, ValueError, TypeError) as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
@permission_classes([IsFarmer])
def orders(request):
    return Response({'detail':'Feed orders are not part of the current PostgreSQL schema.'},status=status.HTTP_501_NOT_IMPLEMENTED)

@api_view(['POST','PATCH','DELETE'])
@permission_classes([IsFarmer])
def schedules(request):
    farm=farm_for(request.user)
    try:
        if request.method=='DELETE':
            FeedSchedule.objects.get(pk=request.data['id'],flock__farm=farm).delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        feed_type=FeedType.objects.get(pk=request.data['feed_type_id'])
        flock=Flock.objects.get(pk=request.data['flock_id'],farm=farm)
        values={'flock':flock,'feed_type':feed_type,'scheduled_time':request.data['scheduled_time'],
                'quantity_per_feeding':request.data['quantity_per_feeding'],
                'frequency':request.data.get('frequency','daily')}
        if request.method=='PATCH':
            item=FeedSchedule.objects.get(pk=request.data['id'],flock__farm=farm)
            for key,value in values.items():setattr(item,key,value)
            item.save()
        else:item=FeedSchedule.objects.create(**values)
        return Response({'id':item.id},status=status.HTTP_201_CREATED if request.method=='POST' else status.HTTP_200_OK)
    except (KeyError, ValueError, TypeError) as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)
