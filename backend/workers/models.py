import uuid
from django.db import models
from farms.models import Farm


class Worker(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    farm = models.ForeignKey(Farm, on_delete=models.CASCADE, related_name='workers')
    full_name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, blank=True)
    job_role = models.CharField(max_length=100)
    daily_wage = models.DecimalField(max_digits=10, decimal_places=2)
    join_date = models.DateField()
    status = models.CharField(max_length=10, choices=[('active', 'Active'), ('inactive', 'Inactive')], default='active')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class WorkerAttendance(models.Model):
    worker = models.ForeignKey(Worker, on_delete=models.CASCADE, related_name='attendance')
    attendance_date = models.DateField()
    status = models.CharField(max_length=10, choices=[('present', 'Present'), ('absent', 'Absent'), ('half_day', 'Half day')])
    check_in_time = models.TimeField(null=True, blank=True)
    check_out_time = models.TimeField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['worker', 'attendance_date'], name='unique_worker_attendance')]

class WorkerTask(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    worker=models.ForeignKey(Worker,on_delete=models.CASCADE,related_name='tasks')
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='worker_tasks')
    task_name=models.CharField(max_length=150)
    description=models.TextField(blank=True)
    assigned_date=models.DateField()
    due_date=models.DateField(null=True,blank=True)
    status=models.CharField(max_length=20,choices=[('pending','Pending'),('in_progress','In progress'),('completed','Completed')],default='pending')
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)

class WorkerPayment(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    worker=models.ForeignKey(Worker,on_delete=models.CASCADE,related_name='payments')
    amount=models.DecimalField(max_digits=10,decimal_places=2)
    payment_date=models.DateField()
    payment_method=models.CharField(max_length=50)
    period_start=models.DateField()
    period_end=models.DateField()
    notes=models.TextField(blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
