"""Minimal shed + flock (batch) management so cost tracking can attribute
expenses/revenue to a real flock cycle.
"""
from datetime import date

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from django.db import transaction

from farms.constants import BIRD_TYPES
from farms.models import Farm, Flock, FlockEvent, Shed

from .services import IsFarmer, farm_for, parse_date

FLOCK_STATUS = {'active', 'sold', 'closed'}
FLOCK_EVENT_TYPES = {'mortality', 'sale', 'transfer', 'vaccination', 'feed_consumption', 'weight_measurement'}
# Event types that reduce the live bird count when logged.
_QUANTITY_DECREASING_EVENTS = {'mortality', 'sale', 'transfer'}


def _shed_json(s):
    return {'id': str(s.id), 'shed_name': s.shed_name, 'capacity': s.capacity,
            'current_bird_count': s.current_bird_count or 0, 'shed_type': s.shed_type or ''}


def _flock_json(fl):
    return {'id': str(fl.id), 'batch_name': fl.batch_name, 'bird_type': fl.bird_type or '',
            'breed': fl.breed or '', 'quantity': fl.quantity, 'current_quantity': fl.current_quantity,
            'shed_id': str(fl.shed_id) if fl.shed_id else None,
            'status': fl.status or 'active',
            'start_date': fl.start_date.isoformat() if fl.start_date else None,
            'end_date': fl.end_date.isoformat() if fl.end_date else None,
            'age_days': fl.age_days}


def _event_json(e):
    return {'id': str(e.id), 'flock_id': str(e.flock_id), 'event_type': e.event_type,
            'quantity': e.quantity, 'weight_kg': float(e.weight_kg) if e.weight_kg is not None else None,
            'event_date': e.event_date.isoformat(), 'notes': e.notes or '',
            'created_at': e.created_at.isoformat() if e.created_at else None}


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def sheds(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        return Response({'results': [_shed_json(s) for s in farm.sheds.order_by('shed_name')]})
    data = request.data
    try:
        shed = Shed.objects.create(
            farm=farm, shed_name=str(data['shed_name']).strip(),
            capacity=int(data.get('capacity') or 0),
            current_bird_count=int(data.get('current_bird_count') or 0),
            shed_type=data.get('shed_type', ''))
    except (KeyError, ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'shed_name is required.'}, status=400)
    Farm.objects.filter(pk=farm.id).update(total_sheds=farm.sheds.count())
    return Response(_shed_json(shed), status=status.HTTP_201_CREATED)


@api_view(['PUT', 'PATCH', 'DELETE'])
@permission_classes([IsFarmer])
def shed_detail(request, shed_id):
    farm = farm_for(request.user)
    try:
        shed = farm.sheds.get(pk=shed_id)
    except Shed.DoesNotExist:
        return Response({'detail': 'Shed not found.'}, status=404)
    if request.method == 'DELETE':
        shed.delete()
        Farm.objects.filter(pk=farm.id).update(total_sheds=farm.sheds.count())
        return Response(status=status.HTTP_204_NO_CONTENT)
    data = request.data
    for field in ('shed_name', 'shed_type'):
        if data.get(field) is not None:
            setattr(shed, field, data[field])
    for field in ('capacity', 'current_bird_count'):
        if data.get(field) is not None:
            setattr(shed, field, int(data[field]))
    shed.save()
    return Response(_shed_json(shed))


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def flocks(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        qs = farm.flocks.order_by('-start_date')
        if request.query_params.get('status'):
            qs = qs.filter(status=request.query_params['status'])
        return Response({'results': [_flock_json(fl) for fl in qs]})
    data = request.data
    try:
        quantity = int(data['quantity'])
        bird_type = str(data.get('bird_type', 'broiler')).lower()
        if bird_type not in BIRD_TYPES:
            return Response({'detail': f'bird_type must be one of {sorted(BIRD_TYPES)}.'}, status=400)
        shed = None
        if data.get('shed_id'):
            shed = farm.sheds.filter(pk=data['shed_id']).first()
        flock = Flock.objects.create(
            farm=farm, shed=shed, batch_name=str(data['batch_name']).strip(),
            bird_type=bird_type, breed=data.get('breed', ''),
            quantity=quantity, current_quantity=int(data.get('current_quantity') or quantity),
            start_date=parse_date(data.get('start_date'), date.today()),
            end_date=parse_date(data.get('end_date')), status='active')
    except (KeyError, ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'batch_name and quantity are required.'}, status=400)
    return Response(_flock_json(flock), status=status.HTTP_201_CREATED)


@api_view(['PUT', 'PATCH', 'DELETE'])
@permission_classes([IsFarmer])
def flock_detail(request, flock_id):
    farm = farm_for(request.user)
    try:
        flock = farm.flocks.get(pk=flock_id)
    except Flock.DoesNotExist:
        return Response({'detail': 'Flock not found.'}, status=404)
    if request.method == 'DELETE':
        flock.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
    data = request.data
    if data.get('batch_name'):
        flock.batch_name = data['batch_name']
    if data.get('breed') is not None:
        flock.breed = data['breed']
    for field in ('quantity', 'current_quantity'):
        if data.get(field) is not None:
            setattr(flock, field, int(data[field]))
    if data.get('status') in FLOCK_STATUS:
        flock.status = data['status']
        if data['status'] != 'active' and not flock.end_date:
            flock.end_date = date.today()
    if data.get('shed_id') is not None:
        flock.shed = farm.sheds.filter(pk=data['shed_id']).first() if data['shed_id'] else None
    if data.get('end_date'):
        flock.end_date = parse_date(data['end_date'])
    flock.save()
    return Response(_flock_json(flock))


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def flock_events(request, flock_id):
    """Immutable history log for a flock (Priority 4) — mortality, sale,
    transfer, vaccination, feed_consumption, weight_measurement. There is no
    PUT/PATCH/DELETE: a correction is a new event, the log itself never
    changes. Mortality/sale/transfer decrement Flock.current_quantity
    transactionally so the live bird count and the age chart always agree
    with the event history."""
    farm = farm_for(request.user)
    try:
        flock = farm.flocks.get(pk=flock_id)
    except Flock.DoesNotExist:
        return Response({'detail': 'Flock not found.'}, status=404)

    if request.method == 'GET':
        qs = flock.events.all()
        if request.query_params.get('event_type'):
            qs = qs.filter(event_type=request.query_params['event_type'])
        return Response({'results': [_event_json(e) for e in qs[:400]]})

    data = request.data
    event_type = str(data.get('event_type', '')).lower()
    if event_type not in FLOCK_EVENT_TYPES:
        return Response({'detail': f'event_type must be one of {sorted(FLOCK_EVENT_TYPES)}.'}, status=400)
    try:
        quantity = int(data['quantity']) if data.get('quantity') not in (None, '') else None
        weight_kg = data.get('weight_kg')
        weight_kg = float(weight_kg) if weight_kg not in (None, '') else None
    except (ValueError, TypeError):
        return Response({'detail': 'quantity/weight_kg must be numeric.'}, status=400)
    if event_type in _QUANTITY_DECREASING_EVENTS and not quantity:
        return Response({'detail': f'quantity is required for a {event_type} event.'}, status=400)
    if quantity is not None and quantity < 0:
        return Response({'detail': 'quantity cannot be negative.'}, status=400)

    with transaction.atomic():
        locked_flock = Flock.objects.select_for_update().get(pk=flock.id)
        if event_type in _QUANTITY_DECREASING_EVENTS:
            if quantity > locked_flock.current_quantity:
                return Response({
                    'detail': f'quantity ({quantity}) exceeds the current bird count '
                              f'({locked_flock.current_quantity}).',
                }, status=400)
            locked_flock.current_quantity -= quantity
            if locked_flock.current_quantity == 0 and locked_flock.status == 'active':
                locked_flock.status = 'closed'
                locked_flock.end_date = locked_flock.end_date or parse_date(data.get('event_date'), date.today())
            locked_flock.save(update_fields=['current_quantity', 'status', 'end_date', 'updated_at'])
        event = FlockEvent.objects.create(
            flock=locked_flock, event_type=event_type, quantity=quantity, weight_kg=weight_kg,
            event_date=parse_date(data.get('event_date'), date.today()),
            notes=data.get('notes', ''), recorded_by=request.user,
        )
    return Response(_event_json(event), status=status.HTTP_201_CREATED)
