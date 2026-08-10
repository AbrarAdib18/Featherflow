import uuid
from django.conf import settings
from django.db import models
from farms.models import Farm

class ExpenseCategory(models.Model):
    name=models.CharField(max_length=100,unique=True)
    linked_module=models.CharField(max_length=50,blank=True)
    icon=models.CharField(max_length=50,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        managed=False
        db_table='expense_categories'

class Expense(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='expenses')
    category=models.ForeignKey(ExpenseCategory,on_delete=models.PROTECT)
    flock_id=models.UUIDField(db_column='flock_id',null=True,blank=True)
    amount=models.DecimalField(max_digits=12,decimal_places=2)
    description=models.TextField(blank=True)
    expense_date=models.DateField()
    payment_status=models.CharField(max_length=10,choices=[('paid','Paid'),('pending','Pending'),('overdue','Overdue')],default='pending')
    payment_method=models.CharField(max_length=50,blank=True)
    supplier_name=models.CharField(max_length=150,blank=True)
    receipt_url=models.TextField(blank=True)
    created_by=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,db_column='created_by')
    approved_by=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,db_column='approved_by',related_name='approved_expenses',null=True,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        managed=False
        db_table='expenses'

class RevenueSource(models.Model):
    name=models.CharField(max_length=100,unique=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        managed=False
        db_table='revenue_sources'

class Revenue(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='revenues')
    source=models.ForeignKey(RevenueSource,on_delete=models.PROTECT)
    flock_id=models.UUIDField(db_column='flock_id',null=True,blank=True)
    amount=models.DecimalField(max_digits=12,decimal_places=2)
    revenue_date=models.DateField()
    description=models.TextField(blank=True)
    created_by=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,db_column='created_by')
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        managed=False
        db_table='revenues'

class Loan(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='loans')
    lender_name=models.CharField(max_length=150)
    loan_amount=models.DecimalField(max_digits=12,decimal_places=2)
    interest_rate=models.DecimalField(max_digits=5,decimal_places=2)
    start_date=models.DateField()
    due_date=models.DateField()
    remaining_balance=models.DecimalField(max_digits=12,decimal_places=2)
    status=models.CharField(max_length=10,choices=[('active','Active'),('paid','Paid'),('overdue','Overdue')],default='active')
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta:
        managed=False
        db_table='loans'

class TaxRecord(models.Model):
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    farm=models.ForeignKey(Farm,on_delete=models.CASCADE,related_name='tax_records')
    tax_year=models.PositiveIntegerField()
    tax_month=models.PositiveSmallIntegerField(null=True,blank=True)
    total_income=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    total_expense=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    taxable_amount=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    tax_due=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    tax_paid=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    payment_date=models.DateField(null=True,blank=True)
    payment_id=models.UUIDField(db_column='payment_id',null=True,blank=True)
    status=models.CharField(max_length=10,choices=[('pending','Pending'),('paid','Paid')],default='pending')
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta:
        managed=False
        db_table='tax_records'
