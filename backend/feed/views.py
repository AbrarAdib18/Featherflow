from datetime import timedelta
from decimal import Decimal
from django.db.models import Sum
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from workers.views import farm_for
from .models import FeedType, FeedStock, FeedSchedule
from farms.models import Flock
from notifications.models import Notification
def self_notify(user,title,body,reference_id=None,reference_type='feed'):
    Notification.objects.create(user=user,title=title,body=body,notification_type='system',reference_id=reference_id,reference_type=reference_type)


@api_view(['GET', 'POST'])
def feed(request):
    farm = farm_for(request.user)
    if request.method == 'POST':
        required = ('name', 'unit', 'quantity', 'cost_per_unit')
        missing = [key for key in required if not str(request.data.get(key, '')).strip()]
        if missing:
            return Response({'detail': f"Required: {', '.join(missing)}"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            feed_type, _ = FeedType.objects.get_or_create(
                name=request.data['name'].strip(), brand=request.data.get('brand', '').strip(),
                unit=request.data['unit'],
            )
            stock, _ = FeedStock.objects.get_or_create(farm=farm, feed_type=feed_type)
            stock.quantity_available += Decimal(str(request.data['quantity']))
            stock.cost_per_unit = Decimal(str(request.data['cost_per_unit']))
            stock.supplier_name = request.data.get('supplier_name', '').strip()
            stock.last_restocked_at = timezone.now()
            stock.save()
            self_notify(request.user,'Feed purchase recorded',f'{request.data["quantity"]} {feed_type.unit} of {feed_type.name} was added.',stock.id,'feed_stock')
        except Exception as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'id': stock.id}, status=status.HTTP_201_CREATED)
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
    history=[{'id':str(s.id),'feed_type':s.feed_type.name,'unit':s.feed_type.unit,'quantity':float(s.quantity_available),'cost':float(s.quantity_available*(s.cost_per_unit or 0)),'supplier_name':s.supplier_name,'purchased_at':(s.last_restocked_at or s.created_at).isoformat()} for s in stocks]
    suppliers=[{'name':x.supplier_name,'feed_types':list(farm.feed_stock.filter(supplier_name=x.supplier_name).values_list('feed_type__name',flat=True))} for x in stocks if x.supplier_name]
    return Response({'farm_name': farm.farm_name, 'stock': rows, 'schedules':schedules,'history':history,'suppliers':suppliers,'summary': {
        'total_stock': sum(r['quantity_available'] for r in rows),
        'stock_value': sum(r['total_value'] for r in rows),
        'feed_types': len(rows),
        'low_stock_items': sum(r['status'] in ('low','out') for r in rows),
    }})

@api_view(['PATCH','DELETE'])
def stock_detail(request):
    farm=farm_for(request.user)
    try:
        item=farm.feed_stock.get(pk=request.data['id'])
        if request.method=='DELETE':
            name=item.feed_type.name;item.delete();self_notify(request.user,'Feed stock removed',f'{name} was removed from current stock.');return Response(status=status.HTTP_204_NO_CONTENT)
        return Response({'detail':'Stock status is calculated from quantity and is not stored in the PostgreSQL schema.'},status=status.HTTP_400_BAD_REQUEST)
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
def orders(request):
    return Response({'detail':'Feed orders are not part of the current PostgreSQL schema.'},status=status.HTTP_501_NOT_IMPLEMENTED)

@api_view(['POST','PATCH','DELETE'])
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
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)
