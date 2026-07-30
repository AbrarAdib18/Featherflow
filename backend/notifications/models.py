import uuid
from django.conf import settings
from django.db import models
class Notification(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    user=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='notifications')
    title=models.CharField(max_length=200);body=models.TextField()
    notification_type=models.CharField(max_length=20,choices=[('alert','Alert'),('reminder','Reminder'),('message','Message'),('system','System'),('approval','Approval'),('bill_due','Bill due'),('tax_due','Tax due'),('loan_due','Loan due')],default='system')
    reference_id=models.UUIDField(null=True,blank=True);reference_type=models.CharField(max_length=50,blank=True)
    is_read=models.BooleanField(default=False);created_at=models.DateTimeField(auto_now_add=True)
