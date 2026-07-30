from django.utils.timesince import timesince
from rest_framework.decorators import api_view
from rest_framework.response import Response
@api_view(['GET','PATCH'])
def inbox(request):
    qs=request.user.notifications.order_by('-created_at')
    if request.method=='PATCH':
        qs.filter(is_read=False).update(is_read=True);return Response({'unread_count':0})
    rows=[]
    for x in qs[:100]:
        rows.append({'id':str(x.id),'title':x.title,'body':x.body,'type':x.notification_type,'reference_id':str(x.reference_id) if x.reference_id else None,'reference_type':x.reference_type,'is_read':x.is_read,'time':f"{timesince(x.created_at).split(',')[0]} ago"})
    return Response({'notifications':rows,'unread_count':qs.filter(is_read=False).count()})
