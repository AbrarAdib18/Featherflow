from datetime import date
from decimal import Decimal
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from farms.models import Farm
from profiles.models import FarmerProfile
from django.db import models
from .models import Worker,WorkerAttendance,WorkerPayment
from notifications.models import Notification
def self_notify(user,title,body,reference_id=None):
    Notification.objects.create(user=user,title=title,body=body,notification_type='system',reference_id=reference_id,reference_type='worker')


def farm_for(user):
    profile, _ = FarmerProfile.objects.get_or_create(
        user=user,
        defaults={
            'farm_name': f"{user.full_name or 'My'} Farm",
            'owner_name': user.full_name or user.email,
            'farm_location': user.present_address,
            'farm_address': user.present_address,
            'farm_type': 'mixed',
            'consent_data_collection': user.consent_terms,
        },
    )
    return Farm.objects.get_or_create(
        farmer=profile,
        defaults={
            'farm_name': profile.farm_name,
            'farm_type': profile.farm_type or 'mixed',
            'location': profile.farm_location,
            'address': profile.farm_address,
        },
    )[0]


@api_view(['GET', 'POST'])
def workers(request):
    farm = farm_for(request.user)
    if request.method == 'POST':
        required = ('full_name', 'job_role', 'daily_wage', 'join_date')
        missing = [key for key in required if not str(request.data.get(key, '')).strip()]
        if missing:
            return Response({'detail': f"Required: {', '.join(missing)}"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            worker = Worker.objects.create(
                farm=farm, full_name=request.data['full_name'].strip(),
                phone=request.data.get('phone', '').strip(), job_role=request.data['job_role'].strip(),
                daily_wage=Decimal(str(request.data['daily_wage'])),
                join_date=request.data['join_date'], status=request.data.get('status', 'active'),
            )
            self_notify(request.user,'Worker added',f'{worker.full_name} was added as {worker.job_role}.',worker.id)
        except Exception as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'id': worker.id}, status=status.HTTP_201_CREATED)
    today = date.today()
    rows = []
    month_start=today.replace(day=1)
    for worker in farm.workers.order_by('-created_at'):
        attendance = worker.attendance.filter(attendance_date=today).first()
        present_days=worker.attendance.filter(attendance_date__gte=month_start,status='present').count()
        half_days=worker.attendance.filter(attendance_date__gte=month_start,status='half_day').count()
        days_worked=present_days+(half_days*.5)
        earned=worker.daily_wage*Decimal(str(days_worked))
        paid=worker.payments.filter(period_start__gte=month_start).aggregate(v=models.Sum('amount'))['v'] or 0
        rows.append({
            'id': str(worker.id), 'full_name': worker.full_name, 'phone': worker.phone,
            'job_role': worker.job_role, 'daily_wage': float(worker.daily_wage),
            'join_date': worker.join_date.isoformat(), 'status': worker.status,
            'attendance_status': attendance.status if attendance else 'not_marked',
            'check_in_time': attendance.check_in_time.strftime('%I:%M %p') if attendance and attendance.check_in_time else None,
            'days_worked':days_worked,'salary_due':float(max(Decimal('0'),earned-paid)),
            'paid_this_month':float(paid),
            'tasks_completed':worker.tasks.filter(status='completed').count(),
        })
    active = [w for w in rows if w['status'] == 'active']
    present = sum(w['attendance_status'] in ('present', 'half_day') for w in active)
    return Response({'farm_name': farm.farm_name, 'workers': rows, 'summary': {
        'total_workers': len(active), 'present_today': present,
        'absent_today': sum(w['attendance_status'] == 'absent' for w in active),
        'monthly_payroll': sum(w['salary_due'] for w in active),
    }})

@api_view(['PATCH'])
def attendance(request):
    farm=farm_for(request.user)
    try:
        worker=farm.workers.get(pk=request.data['worker_id'])
        item,_=WorkerAttendance.objects.update_or_create(worker=worker,attendance_date=request.data.get('attendance_date',date.today()),defaults={'status':request.data['status'],'check_in_time':request.data.get('check_in_time') or None,'check_out_time':request.data.get('check_out_time') or None,'notes':request.data.get('notes','')})
        self_notify(request.user,'Attendance updated',f'{worker.full_name} marked {item.status.replace("_"," ")}.',worker.id);return Response({'id':item.id,'status':item.status})
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
def payments(request):
    farm=farm_for(request.user)
    ids=request.data.get('worker_ids') or [request.data.get('worker_id')]
    created=[]
    try:
        for worker in farm.workers.filter(id__in=ids,status='active'):
            start=date.today().replace(day=1);present=worker.attendance.filter(attendance_date__gte=start,status='present').count();half=worker.attendance.filter(attendance_date__gte=start,status='half_day').count()
            earned=worker.daily_wage*Decimal(str(present+half*.5));paid=worker.payments.filter(period_start__gte=start).aggregate(v=models.Sum('amount'))['v'] or 0
            amount=max(Decimal('0'),earned-paid)
            if amount==0:continue
            item=WorkerPayment.objects.create(worker=worker,amount=amount,payment_date=date.today(),payment_method=request.data.get('payment_method','cash'),period_start=start,period_end=date.today(),notes=request.data.get('notes',''))
            created.append({'id':str(item.id),'worker_id':str(worker.id),'amount':float(amount)})
            self_notify(request.user,'Worker payment recorded',f'{worker.full_name} was paid {amount}.',worker.id)
        return Response({'payments':created},status=status.HTTP_201_CREATED)
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['PATCH','DELETE'])
def worker_detail(request):
    farm=farm_for(request.user)
    try:
        worker=farm.workers.get(pk=request.data['id'])
        if request.method=='DELETE':
            name=worker.full_name;worker.delete();self_notify(request.user,'Worker removed',f'{name} was removed from labor management.');return Response(status=status.HTTP_204_NO_CONTENT)
        worker.status=request.data['status'];worker.save(update_fields=['status','updated_at'])
        self_notify(request.user,'Worker status changed',f'{worker.full_name} is now {worker.status}.',worker.id)
        return Response({'id':worker.id,'status':worker.status})
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)
