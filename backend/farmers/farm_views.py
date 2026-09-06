"""Minimal shed + flock (batch) management so cost tracking can attribute
expenses/revenue to a real flock cycle.
"""
from datetime import date

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from farms.models import Farm, Flock, Shed

from .services import IsFarmer, farm_for, parse_date

BIRD_TYPES = {'broiler', 'layer', 'breeder', 'other'}
FLOCK_STATUS = {'active', 'sold', 'closed'}


def _shed_json(s):
    return {'id': str(s.id), 'shed_name': s.shed_name, 'capacity': s.capacity,
            'current_bird_count': s.current_bird_count or 0, 'shed_type': s.shed_type or ''}


def _flock_json(fl):
    return {'id': str(fl.id), 'batch_name': fl.batch_name, 'bird_type': fl.bird_type or '',
            'breed': fl.breed or '', 'quantity': fl.quantity, 'current_quantity': fl.current_quantity,
            'shed_id': str(fl.shed_id) if fl.shed_id else None,
            'status': fl.status or 'active',
            'start_date': fl.start_date.isoformat() if fl.start_date else None,
            'end_date': fl.end_date.isoformat() if fl.end_date else None}


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
