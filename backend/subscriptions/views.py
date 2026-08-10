from datetime import timedelta
from django.utils import timezone
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Subscription,SubscriptionPlan

def plan_json(p):
    return {'id':p.id,'name':p.name,'price':float(p.price),'currency':p.currency,'duration_days':p.duration_days,'features':p.features_unlocked,'disease_scan_limit':p.disease_scan_limit}

@api_view(['GET','POST'])
def subscriptions(request):
    if request.method=='GET':
        current=Subscription.objects.filter(user=request.user,status='active').select_related('plan').order_by('-started_at').first()
        return Response({'plans':[plan_json(p) for p in SubscriptionPlan.objects.filter(is_active=True)],'current':None if not current else {'id':str(current.id),'plan':plan_json(current.plan),'status':current.status,'started_at':current.started_at,'expires_at':current.expires_at,'auto_renew':current.auto_renew}})
    plan=SubscriptionPlan.objects.filter(pk=request.data.get('plan_id'),is_active=True).first()
    if not plan:return Response({'detail':'Plan not found.'},status=404)
    now=timezone.now();expires=now+timedelta(days=plan.duration_days) if plan.duration_days else None
    item=Subscription.objects.create(user=request.user,plan=plan,status='pending',started_at=now,expires_at=expires,auto_renew=bool(request.data.get('auto_renew',False)))
    return Response({'id':str(item.id),'status':item.status},status=201)
