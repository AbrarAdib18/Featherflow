"""Labor management read endpoints under /api/farmers/labor/.

Create / attendance-mark / payroll-run already live in ``workers.views`` and
are routed straight to those functions from urls.py. This module only adds the
history reads and the full worker edit the panel needs.
"""
from datetime import date

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from workers.models import Worker, WorkerAttendance, WorkerPayment

from .services import IsFarmer, farm_for, money, parse_date


@api_view(['GET'])
@permission_classes([IsFarmer])
def attendance_history(request):
    farm = farm_for(request.user)
    worker_id = request.query_params.get('worker_id')
    start = parse_date(request.query_params.get('from'), date.today().replace(day=1))
    qs = WorkerAttendance.objects.filter(worker__farm=farm, attendance_date__gte=start)
    if worker_id:
        qs = qs.filter(worker_id=worker_id)
    rows = [{
        'id': str(a.id), 'worker_id': str(a.worker_id), 'worker_name': a.worker.full_name,
        'attendance_date': a.attendance_date.isoformat(), 'status': a.status,
        'check_in_time': a.check_in_time.strftime('%H:%M') if a.check_in_time else None,
    } for a in qs.select_related('worker').order_by('-attendance_date')[:400]]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsFarmer])
def payment_history(request):
    farm = farm_for(request.user)
    qs = (WorkerPayment.objects.filter(worker__farm=farm)
          .select_related('worker').order_by('-payment_date'))
    rows = [{
        'id': str(p.id), 'worker_id': str(p.worker_id), 'worker_name': p.worker.full_name,
        'amount': float(p.amount), 'payment_date': p.payment_date.isoformat(),
        'payment_method': p.payment_method,
        'period_start': p.period_start.isoformat(), 'period_end': p.period_end.isoformat(),
    } for p in qs[:300]]
    return Response({'results': rows, 'total_paid': float(sum(p.amount for p in qs))})


@api_view(['PATCH', 'DELETE'])
@permission_classes([IsFarmer])
def worker_detail(request, worker_id):
    farm = farm_for(request.user)
    try:
        worker = farm.workers.get(pk=worker_id)
    except Worker.DoesNotExist:
        return Response({'detail': 'Worker not found.'}, status=404)
    if request.method == 'DELETE':
        worker.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
    data = request.data
    try:
        for field in ('full_name', 'phone', 'job_role'):
            if data.get(field) is not None:
                setattr(worker, field, str(data[field]).strip())
        if data.get('daily_wage') is not None:
            worker.daily_wage = money(data['daily_wage'], 'daily_wage')
        if data.get('status') in ('active', 'inactive'):
            worker.status = data['status']
        if data.get('join_date'):
            worker.join_date = parse_date(data['join_date'])
        worker.save()
    except (ValueError, TypeError) as exc:
        return Response({'detail': str(exc)}, status=400)
    return Response({'id': str(worker.id), 'status': worker.status})
