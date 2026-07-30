from datetime import date
from decimal import Decimal
from django.db.models import Sum
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from workers.views import farm_for
from .models import ExpenseCategory,Expense,RevenueSource,Revenue,Loan,TaxRecord

def _period(qs,field,period):
    today=date.today()
    if period=='monthly': return qs.filter(**{f'{field}__year':today.year,f'{field}__month':today.month})
    if period=='yearly': return qs.filter(**{f'{field}__year':today.year})
    return qs

@api_view(['GET'])
def dashboard(request):
    farm=farm_for(request.user); period=request.query_params.get('period','monthly')
    eq=_period(farm.expenses.select_related('category'), 'expense_date',period)
    rq=_period(farm.revenues.select_related('source'),'revenue_date',period)
    expenses_total=eq.aggregate(v=Sum('amount'))['v'] or 0
    revenue_total=rq.aggregate(v=Sum('amount'))['v'] or 0
    categories=[{'name':x['category__name'],'amount':float(x['amount'])} for x in eq.values('category__name').annotate(amount=Sum('amount')).order_by('-amount')]
    active_loans=farm.loans.exclude(status='paid')
    tax=farm.tax_records.filter(tax_year=date.today().year).order_by('-tax_month').first()
    transactions=[{'id':str(x.id),'date':x.expense_date.isoformat(),'section':x.category.name,'description':x.description or x.supplier_name or x.category.name,'status':x.payment_status,'amount':float(x.amount),'kind':'expense'} for x in eq.order_by('-expense_date','-created_at')[:10]]
    transactions += [{'id':str(x.id),'date':x.revenue_date.isoformat(),'section':x.source.name,'description':x.description or x.source.name,'status':'paid','amount':float(x.amount),'kind':'revenue'} for x in rq.order_by('-revenue_date','-created_at')[:10]]
    transactions.sort(key=lambda x:x['date'],reverse=True)
    return Response({'farm_name':farm.farm_name,'summary':{'total_expense':float(expenses_total),'total_revenue':float(revenue_total),'net_profit':float(revenue_total-expenses_total),'loan_balance':float(active_loans.aggregate(v=Sum('remaining_balance'))['v'] or 0),'tax_due':float((tax.tax_due-tax.tax_paid) if tax else 0)},'categories':categories,'transactions':transactions[:10],'loans':[{'id':str(x.id),'lender_name':x.lender_name,'remaining_balance':float(x.remaining_balance),'status':x.status,'due_date':x.due_date.isoformat()} for x in active_loans]})

@api_view(['POST'])
def expenses(request):
    farm=farm_for(request.user)
    try:
        category,_=ExpenseCategory.objects.get_or_create(name=request.data['category'].strip())
        item=Expense.objects.create(farm=farm,category=category,amount=Decimal(str(request.data['amount'])),description=request.data.get('description',''),expense_date=request.data['expense_date'],payment_status=request.data.get('payment_status','pending'),payment_method=request.data.get('payment_method',''),supplier_name=request.data.get('supplier_name',''),created_by=request.user)
        return Response({'id':item.id},status=status.HTTP_201_CREATED)
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
def revenues(request):
    farm=farm_for(request.user)
    try:
        source,_=RevenueSource.objects.get_or_create(name=request.data['source'].strip())
        item=Revenue.objects.create(farm=farm,source=source,amount=Decimal(str(request.data['amount'])),revenue_date=request.data['revenue_date'],description=request.data.get('description',''),created_by=request.user)
        return Response({'id':item.id},status=status.HTTP_201_CREATED)
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST','PATCH'])
def loans(request):
    farm=farm_for(request.user)
    try:
        if request.method=='PATCH':
            loan=farm.loans.get(pk=request.data['id']); payment=Decimal(str(request.data['amount']))
            loan.remaining_balance=max(Decimal('0'),loan.remaining_balance-payment)
            if loan.remaining_balance==0:loan.status='paid'
            loan.save(); return Response({'remaining_balance':float(loan.remaining_balance),'status':loan.status})
        amount=Decimal(str(request.data['loan_amount']))
        loan=Loan.objects.create(farm=farm,lender_name=request.data['lender_name'],loan_amount=amount,remaining_balance=amount,interest_rate=request.data['interest_rate'],start_date=request.data['start_date'],due_date=request.data['due_date'])
        return Response({'id':loan.id},status=status.HTTP_201_CREATED)
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
def calculate_tax(request):
    farm=farm_for(request.user); year=int(request.data.get('tax_year',date.today().year))
    income=farm.revenues.filter(revenue_date__year=year).aggregate(v=Sum('amount'))['v'] or 0
    expense=farm.expenses.filter(expense_date__year=year).aggregate(v=Sum('amount'))['v'] or 0
    taxable=max(Decimal('0'),income-expense); due=taxable*Decimal('0.05')
    record,_=TaxRecord.objects.update_or_create(farm=farm,tax_year=year,tax_month=None,defaults={'total_income':income,'total_expense':expense,'taxable_amount':taxable,'tax_due':due})
    return Response({'id':record.id,'tax_due':float(due),'taxable_amount':float(taxable)})

@api_view(['PATCH'])
def expense_status(request):
    farm=farm_for(request.user)
    try:
        item=farm.expenses.get(pk=request.data['id'])
        item.payment_status=request.data['payment_status']; item.save(update_fields=['payment_status'])
        return Response({'id':item.id,'payment_status':item.payment_status})
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)

@api_view(['POST'])
def pay_tax(request):
    farm=farm_for(request.user)
    try:
        item=farm.tax_records.get(pk=request.data['id']); item.tax_paid=item.tax_due
        item.status='paid'; item.payment_date=date.today(); item.save()
        return Response({'id':item.id,'status':item.status})
    except Exception as exc:return Response({'detail':str(exc)},status=status.HTTP_400_BAD_REQUEST)
