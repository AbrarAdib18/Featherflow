"""Cost Management — the farmer's farm-finance workspace.

Everything lives under /api/farmers/costs/. Revenue - Expense = Net Profit;
Cash Balance = revenue received - expenses paid - cashouts + loans disbursed.
Tax ("Calculate My Tax" / Due Tax) is deferred to a later pass and is not
served here.
"""
import csv
import io
from datetime import date
from decimal import Decimal

from django.db.models import Count, Sum
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from expenses.models import (Expense, ExpenseCategory, Loan, LoanInstallment,
                             Revenue, RevenueSource)
from farms.models import Flock
from feed.models import FeedStock
from payments.models import Payment

from .services import (IsFarmer, f, farm_for, in_range, log_finance, money,
                       notify, parse_date, period_range, store_image)

STANDARD_CATEGORIES = ['Feed', 'Medicines', 'Labor', 'Utilities', 'Chicks',
                       'Vaccines', 'Litter', 'Transport', 'Repairs']
STANDARD_SOURCES = ['Bird Sales', 'Egg Sales', 'By-products', 'Refunds', 'Other']
CATEGORY_LINKS = {'Feed': '/farmer/feed-management', 'Labor': '/farmer/labor',
                  'Medicines': '/farmer/pharmacy'}
PAYMENT_METHODS = {'cash', 'bkash', 'nagad', 'bank_transfer', 'card', 'other'}


# ── shared serialisers ────────────────────────────────────────────────────

def _expense_json(e):
    return {
        'id': str(e.id), 'category': e.category.name, 'category_id': e.category_id,
        'amount': f(e.amount), 'description': e.description or '',
        'expense_date': e.expense_date.isoformat(),
        'payment_status': e.payment_status, 'payment_method': e.payment_method or '',
        'supplier_name': e.supplier_name or '', 'receipt_url': e.receipt_url or '',
        'flock_id': str(e.flock_id) if e.flock_id else None,
        'paid_at': e.paid_at.isoformat() if e.paid_at else None,
        'created_at': e.created_at.isoformat() if e.created_at else None,
    }


def _revenue_json(r):
    return {
        'id': str(r.id), 'source': r.source.name, 'source_id': r.source_id,
        'amount': f(r.amount), 'description': r.description or '',
        'revenue_date': r.revenue_date.isoformat(),
        'payment_method': r.payment_method or '', 'buyer_name': r.buyer_name or '',
        'receipt_url': r.receipt_url or '',
        'flock_id': str(r.flock_id) if r.flock_id else None,
        'created_at': r.created_at.isoformat() if r.created_at else None,
    }


def _loan_json(loan):
    installments = list(loan.installments.all())
    next_due = next((i for i in installments if i.status != 'paid'), None)
    overdue = sum((i.amount for i in installments
                   if i.status != 'paid' and i.due_date and i.due_date < date.today()), Decimal('0'))
    return {
        'id': str(loan.id), 'lender_name': loan.lender_name,
        'loan_amount': f(loan.loan_amount), 'remaining_balance': f(loan.remaining_balance),
        'interest_rate': f(loan.interest_rate), 'status': loan.status,
        'purpose': loan.purpose or '', 'term_months': loan.term_months,
        'start_date': loan.start_date.isoformat() if loan.start_date else None,
        'due_date': loan.due_date.isoformat() if loan.due_date else None,
        'rejection_reason': loan.rejection_reason or '',
        'next_payment_date': next_due.due_date.isoformat() if next_due and next_due.due_date else None,
        'next_payment_amount': f(next_due.amount) if next_due else 0,
        'overdue_amount': f(overdue),
        'installments': [{
            'id': str(i.id), 'due_date': i.due_date.isoformat(), 'amount': f(i.amount),
            'status': i.status, 'paid_date': i.paid_date.isoformat() if i.paid_date else None,
        } for i in installments],
        'created_at': loan.created_at.isoformat() if loan.created_at else None,
    }


def _category(name):
    obj, _ = ExpenseCategory.objects.get_or_create(name=name.strip())
    return obj


def _source(name):
    obj, _ = RevenueSource.objects.get_or_create(name=name.strip())
    return obj


# ── dashboard ─────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsFarmer])
def dashboard(request):
    farm = farm_for(request.user)
    start, end = period_range(request.query_params)

    exp = in_range(farm.expenses.select_related('category'), 'expense_date', start, end)
    rev = in_range(farm.revenues.select_related('source'), 'revenue_date', start, end)

    total_expense = exp.aggregate(v=Sum('amount'))['v'] or Decimal('0')
    total_revenue = rev.aggregate(v=Sum('amount'))['v'] or Decimal('0')
    paid_expense = exp.filter(payment_status='paid').aggregate(v=Sum('amount'))['v'] or Decimal('0')
    received_revenue = total_revenue  # revenue rows are money already received

    # lifetime cash position (ignores the period filter on purpose)
    life_rev = farm.revenues.aggregate(v=Sum('amount'))['v'] or Decimal('0')
    life_paid_exp = farm.expenses.filter(payment_status='paid').aggregate(v=Sum('amount'))['v'] or Decimal('0')
    life_cashout = Payment.objects.filter(
        user=request.user, payment_type='cashout', status__in=('pending', 'completed')
    ).aggregate(v=Sum('amount'))['v'] or Decimal('0')
    life_disbursed = farm.loans.filter(status__in=('active', 'paid', 'overdue')).aggregate(
        v=Sum('loan_amount'))['v'] or Decimal('0')
    cash_balance = life_rev + life_disbursed - life_paid_exp - life_cashout

    birds = farm.flocks.filter(status='active').aggregate(v=Sum('current_quantity'))['v'] or 0

    # per-category rollup
    sections = []
    by_cat = {row['category__name']: row for row in exp.values('category__name').annotate(
        total=Sum('amount'), n=Count('id'))}
    for name in STANDARD_CATEGORIES:
        cat_qs = exp.filter(category__name=name)
        spent = cat_qs.aggregate(v=Sum('amount'))['v'] or Decimal('0')
        pending = cat_qs.filter(payment_status__in=('pending', 'overdue')).aggregate(v=Sum('amount'))['v'] or Decimal('0')
        paid = cat_qs.filter(payment_status='paid').aggregate(v=Sum('amount'))['v'] or Decimal('0')
        sections.append({
            'category': name, 'total_spent': f(spent), 'pending_bills': f(pending),
            'paid_bills': f(paid), 'entries': by_cat.get(name, {}).get('n', 0),
            'cost_per_bird': round(f(spent) / birds, 2) if birds else 0,
            'manage_path': CATEGORY_LINKS.get(name),
        })

    revenue_sections = []
    for name in STANDARD_SOURCES:
        src_qs = rev.filter(source__name=name)
        amount = src_qs.aggregate(v=Sum('amount'))['v'] or Decimal('0')
        revenue_sections.append({'source': name, 'total': f(amount), 'entries': src_qs.count()})

    active_loans = farm.loans.exclude(status__in=('paid', 'rejected')).prefetch_related('installments')

    tx = [{'id': str(e.id), 'date': e.expense_date.isoformat(), 'section': e.category.name,
           'description': e.description or e.supplier_name or e.category.name,
           'status': e.payment_status, 'amount': f(e.amount), 'kind': 'expense'}
          for e in exp.order_by('-expense_date', '-created_at')[:12]]
    tx += [{'id': str(r.id), 'date': r.revenue_date.isoformat(), 'section': r.source.name,
            'description': r.description or r.buyer_name or r.source.name,
            'status': 'received', 'amount': f(r.amount), 'kind': 'revenue'}
           for r in rev.order_by('-revenue_date', '-created_at')[:12]]
    tx.sort(key=lambda x: x['date'], reverse=True)

    return Response({
        'farm_name': farm.farm_name,
        'period': (request.query_params.get('period') or 'lifetime').lower(),
        'summary': {
            'total_revenue': f(total_revenue), 'total_expense': f(total_expense),
            'total_earning': f(received_revenue), 'net_profit': f(total_revenue - total_expense),
            'cash_balance': f(cash_balance),
            'gross_profit': f(total_revenue - total_expense),
            'operating_profit': f(total_revenue - paid_expense),
            'money_in': f(total_revenue), 'money_out': f(paid_expense),
            'loan_balance': f(active_loans.aggregate(v=Sum('remaining_balance'))['v'] or 0),
            'due_tax': None,  # deferred
        },
        'expense_sections': sections,
        'revenue_sections': revenue_sections,
        'loans': [_loan_json(loan) for loan in active_loans],
        'transactions': tx[:12],
        'alerts': _alerts(farm, request.user),
    })


def _alerts(farm, user):
    out = []
    today = date.today()
    due = farm.expenses.filter(payment_status__in=('pending', 'overdue')).select_related('category')
    for e in due.order_by('expense_date')[:5]:
        out.append({'type': 'bill_due', 'severity': 'warning',
                    'title': f'{e.category.name} bill unpaid',
                    'body': f'৳{f(e.amount):,.0f} to {e.supplier_name or "supplier"}',
                    'reference_id': str(e.id)})
    for loan in farm.loans.filter(status__in=('active', 'overdue')).prefetch_related('installments'):
        nxt = next((i for i in loan.installments.all() if i.status != 'paid'), None)
        if nxt and nxt.due_date and (nxt.due_date - today).days <= 7:
            out.append({'type': 'loan_due', 'severity': 'warning',
                        'title': f'Loan payment to {loan.lender_name}',
                        'body': f'৳{f(nxt.amount):,.0f} due {nxt.due_date.isoformat()}',
                        'reference_id': str(loan.id)})
    for s in FeedStock.objects.filter(farm=farm).select_related('feed_type'):
        if s.quantity_available <= 0:
            out.append({'type': 'alert', 'severity': 'error', 'title': f'{s.feed_type.name} out of stock',
                        'body': 'Feed stock is empty.', 'reference_id': str(s.id)})
        elif s.quantity_available < 50:
            out.append({'type': 'alert', 'severity': 'warning', 'title': f'{s.feed_type.name} low',
                        'body': f'{f(s.quantity_available):g} {s.feed_type.unit} left.',
                        'reference_id': str(s.id)})
    return out[:8]


# ── expenses ──────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def expenses(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        qs = farm.expenses.select_related('category').order_by('-expense_date', '-created_at')
        p = request.query_params
        if p.get('category'):
            qs = qs.filter(category__name__iexact=p['category'])
        if p.get('status'):
            qs = qs.filter(payment_status=p['status'])
        if p.get('flock'):
            qs = qs.filter(flock_id=p['flock'])
        qs = in_range(qs, 'expense_date', parse_date(p.get('from')), parse_date(p.get('to')))
        rows = [_expense_json(e) for e in qs[:500]]
        return Response({'results': rows, 'total': f(sum(Decimal(str(r['amount'])) for r in rows)),
                         'count': len(rows)})

    data = request.data
    try:
        category = _category(data['category'])
        amount = money(data['amount'])
        expense_date = parse_date(data.get('expense_date'), date.today())
        method = (data.get('payment_method') or '').lower()
        if method and method not in PAYMENT_METHODS:
            return Response({'detail': f'payment_method must be one of {sorted(PAYMENT_METHODS)}.'}, status=400)
        pstatus = data.get('payment_status', 'pending')
        item = Expense.objects.create(
            farm=farm, category=category, amount=amount,
            description=data.get('description', ''), expense_date=expense_date,
            payment_status=pstatus if pstatus in ('paid', 'pending', 'overdue') else 'pending',
            payment_method=method, supplier_name=data.get('supplier_name', ''),
            receipt_url=data.get('receipt_url', ''),
            flock_id=data.get('flock_id') or None,
            paid_at=timezone.now() if pstatus == 'paid' else None,
            created_by=request.user)
    except (KeyError, ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'category and amount are required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    log_finance(request.user, f'Added {category.name} expense', 'create', 'expense', item.id,
                {'amount': f(amount), 'category': category.name})
    return Response(_expense_json(item), status=status.HTTP_201_CREATED)


@api_view(['GET', 'PUT', 'PATCH', 'DELETE'])
@permission_classes([IsFarmer])
def expense_detail(request, expense_id):
    farm = farm_for(request.user)
    try:
        item = farm.expenses.select_related('category').get(pk=expense_id)
    except Expense.DoesNotExist:
        return Response({'detail': 'Expense not found.'}, status=404)
    if request.method == 'GET':
        return Response(_expense_json(item))
    if request.method == 'DELETE':
        log_finance(request.user, f'Deleted {item.category.name} expense', 'delete', 'expense',
                    item.id, old_values=_expense_json(item))
        item.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
    data = request.data
    try:
        if data.get('category'):
            item.category = _category(data['category'])
        if data.get('amount') is not None:
            item.amount = money(data['amount'])
        if data.get('expense_date'):
            item.expense_date = parse_date(data['expense_date'])
        if 'description' in data:
            item.description = data['description']
        if 'supplier_name' in data:
            item.supplier_name = data['supplier_name']
        if 'receipt_url' in data:
            item.receipt_url = data['receipt_url']
        if 'flock_id' in data:
            item.flock_id = data['flock_id'] or None
        if data.get('payment_method'):
            item.payment_method = str(data['payment_method']).lower()
        if data.get('payment_status') in ('paid', 'pending', 'overdue'):
            item.payment_status = data['payment_status']
            item.paid_at = timezone.now() if data['payment_status'] == 'paid' else None
        item.save()
    except (ValueError, TypeError) as exc:
        return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    log_finance(request.user, f'Edited {item.category.name} expense', 'edit', 'expense', item.id,
                _expense_json(item))
    return Response(_expense_json(item))


# ── revenue ───────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def revenue(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        qs = farm.revenues.select_related('source').order_by('-revenue_date', '-created_at')
        p = request.query_params
        if p.get('source'):
            qs = qs.filter(source__name__iexact=p['source'])
        if p.get('flock'):
            qs = qs.filter(flock_id=p['flock'])
        qs = in_range(qs, 'revenue_date', parse_date(p.get('from')), parse_date(p.get('to')))
        rows = [_revenue_json(r) for r in qs[:500]]
        by_source = [{'source': row['source__name'], 'total': f(row['t'])}
                     for row in qs.values('source__name').annotate(t=Sum('amount')).order_by('-t')]
        return Response({'results': rows, 'total': f(sum(Decimal(str(r['amount'])) for r in rows)),
                         'by_source': by_source, 'count': len(rows)})
    data = request.data
    try:
        src = _source(data['source'])
        amount = money(data['amount'])
        method = (data.get('payment_method') or '').lower()
        if method and method not in PAYMENT_METHODS:
            return Response({'detail': f'payment_method must be one of {sorted(PAYMENT_METHODS)}.'}, status=400)
        item = Revenue.objects.create(
            farm=farm, source=src, amount=amount,
            revenue_date=parse_date(data.get('revenue_date'), date.today()),
            description=data.get('description', ''), payment_method=method,
            buyer_name=data.get('buyer_name', ''), receipt_url=data.get('receipt_url', ''),
            flock_id=data.get('flock_id') or None, created_by=request.user)
    except (KeyError, ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'source and amount are required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    log_finance(request.user, f'Added {src.name} revenue', 'create', 'revenue', item.id,
                {'amount': f(amount), 'source': src.name})
    return Response(_revenue_json(item), status=status.HTTP_201_CREATED)


@api_view(['GET', 'PUT', 'PATCH', 'DELETE'])
@permission_classes([IsFarmer])
def revenue_detail(request, revenue_id):
    farm = farm_for(request.user)
    try:
        item = farm.revenues.select_related('source').get(pk=revenue_id)
    except Revenue.DoesNotExist:
        return Response({'detail': 'Revenue entry not found.'}, status=404)
    if request.method == 'GET':
        return Response(_revenue_json(item))
    if request.method == 'DELETE':
        log_finance(request.user, f'Deleted {item.source.name} revenue', 'delete', 'revenue',
                    item.id, old_values=_revenue_json(item))
        item.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
    data = request.data
    try:
        if data.get('source'):
            item.source = _source(data['source'])
        if data.get('amount') is not None:
            item.amount = money(data['amount'])
        if data.get('revenue_date'):
            item.revenue_date = parse_date(data['revenue_date'])
        for field in ('description', 'buyer_name', 'receipt_url'):
            if field in data:
                setattr(item, field, data[field])
        if data.get('payment_method'):
            item.payment_method = str(data['payment_method']).lower()
        if 'flock_id' in data:
            item.flock_id = data['flock_id'] or None
        item.save()
    except (ValueError, TypeError) as exc:
        return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    log_finance(request.user, f'Edited {item.source.name} revenue', 'edit', 'revenue', item.id,
                _revenue_json(item))
    return Response(_revenue_json(item))


# ── receipts ──────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsFarmer])
def upload_receipt(request):
    url, error = store_image(request, 'receipts')
    if error:
        return Response({'detail': error}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'image_url': url}, status=status.HTTP_201_CREATED)


# ── loans ─────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def loans(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        qs = farm.loans.prefetch_related('installments').order_by('-created_at')
        return Response({'results': [_loan_json(loan) for loan in qs]})
    data = request.data
    try:
        amount = money(data.get('loan_amount') or data.get('amount'), 'loan_amount')
        loan = Loan.objects.create(
            farm=farm, lender_name=data.get('lender_name') or 'Featherflow Lending Partner',
            loan_amount=amount, remaining_balance=amount, status='pending',
            purpose=data.get('purpose', ''), term_months=data.get('term_months') or None,
            interest_rate=data.get('interest_rate') or None,
            requested_by=request.user)
    except (ValueError, TypeError) as exc:
        return Response({'detail': str(exc) or 'loan_amount is required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    notify(request.user, 'Loan request submitted',
           f'Your request for ৳{f(amount):,.0f} is pending admin review.',
           'system', loan.id, 'loan')
    log_finance(request.user, 'Requested loan', 'create', 'loan', loan.id,
                {'amount': f(amount), 'purpose': loan.purpose})
    return Response(_loan_json(loan), status=status.HTTP_201_CREATED)


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def loan_detail(request, loan_id):
    farm = farm_for(request.user)
    try:
        loan = farm.loans.prefetch_related('installments').get(pk=loan_id)
    except Loan.DoesNotExist:
        return Response({'detail': 'Loan not found.'}, status=404)
    if request.method == 'GET':
        return Response(_loan_json(loan))
    # POST = repayment
    if loan.status not in ('active', 'overdue'):
        return Response({'detail': 'Only an active loan can be repaid.'}, status=400)
    try:
        amount = money(request.data['amount'])
    except (KeyError, ValueError):
        return Response({'detail': 'A repayment amount is required.'}, status=400)
    amount = min(amount, loan.remaining_balance)
    loan.remaining_balance = max(Decimal('0'), loan.remaining_balance - amount)
    if loan.remaining_balance == 0:
        loan.status = 'paid'
    loan.save()
    nxt = loan.installments.filter(status__in=('pending', 'overdue')).first()
    if nxt:
        nxt.status = 'paid'
        nxt.paid_date = date.today()
        nxt.save(update_fields=['status', 'paid_date'])
    Payment.objects.create(
        user=request.user, amount=amount, payment_type='loan_repayment',
        payment_method=request.data.get('payment_method') or 'cash', status='completed',
        reference_id=loan.id, reference_type='loan', confirmed_at=timezone.now())
    log_finance(request.user, f'Loan repayment to {loan.lender_name}', 'payment_made', 'loan',
                loan.id, {'amount': f(amount), 'remaining': f(loan.remaining_balance)})
    notify(request.user, 'Loan repayment recorded',
           f'৳{f(amount):,.0f} paid — balance ৳{f(loan.remaining_balance):,.0f}.',
           'system', loan.id, 'loan')
    return Response(_loan_json(loan))


# ── expense payment + cashout ────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsFarmer])
def pay_expense(request, expense_id):
    farm = farm_for(request.user)
    try:
        item = farm.expenses.select_related('category').get(pk=expense_id)
    except Expense.DoesNotExist:
        return Response({'detail': 'Expense not found.'}, status=404)
    if item.payment_status == 'paid':
        return Response({'detail': 'This bill is already paid.'}, status=400)
    method = (request.data.get('payment_method') or 'cash').lower()
    payment = Payment.objects.create(
        user=request.user, amount=item.amount, payment_type='expense_payment',
        payment_method=method if method in PAYMENT_METHODS else 'cash',
        status='completed', reference_id=item.id, reference_type='expense',
        confirmed_at=timezone.now())
    item.payment_status = 'paid'
    item.payment_method = method
    item.paid_at = timezone.now()
    item.payment_id = payment.id
    item.save(update_fields=['payment_status', 'payment_method', 'paid_at', 'payment_id'])
    log_finance(request.user, f'Paid {item.category.name} bill', 'payment_made', 'expense',
                item.id, {'amount': f(item.amount), 'method': method})
    notify(request.user, 'Expense paid',
           f'{item.category.name}: ৳{f(item.amount):,.0f} marked paid.', 'system', item.id, 'expense')
    return Response(_expense_json(item))


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def cashout(request):
    farm = farm_for(request.user)
    if request.method == 'GET':
        rows = Payment.objects.filter(user=request.user).order_by('-created_at')[:200]
        return Response({'results': [{
            'id': str(p.id), 'amount': f(p.amount), 'type': p.payment_type,
            'method': p.payment_method or '', 'status': p.status,
            'reference_type': p.reference_type or '',
            'created_at': p.created_at.isoformat() if p.created_at else None,
        } for p in rows]})
    data = request.data
    try:
        amount = money(data['amount'])
    except (KeyError, ValueError):
        return Response({'detail': 'A cashout amount is required.'}, status=400)
    method = (data.get('payment_method') or '').lower()
    if method not in {'bkash', 'nagad', 'bank_transfer'}:
        return Response({'detail': 'Cashout method must be bkash, nagad or bank_transfer.'}, status=400)
    payment = Payment.objects.create(
        user=request.user, amount=amount, payment_type='cashout', payment_method=method,
        status='pending', reference_type='cashout',
        notes=data.get('account_details', ''))
    log_finance(request.user, 'Requested cashout', 'create', 'payment', payment.id,
                {'amount': f(amount), 'method': method})
    notify(request.user, 'Cashout requested',
           f'৳{f(amount):,.0f} to {method} — pending settlement by the finance team.',
           'system', payment.id, 'cashout')
    return Response({'id': str(payment.id), 'status': payment.status, 'amount': f(amount)},
                    status=status.HTTP_201_CREATED)


# ── inventory ─────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsFarmer])
def inventory(request):
    farm = farm_for(request.user)
    feed = [{
        'id': str(s.id), 'name': s.feed_type.name, 'brand': s.feed_type.brand or '',
        'unit': s.feed_type.unit or 'kg', 'quantity': f(s.quantity_available),
        'cost_per_unit': f(s.cost_per_unit), 'value': f(s.quantity_available * (s.cost_per_unit or 0)),
        'status': s.stock_status, 'supplier_name': s.supplier_name or '',
        'last_restocked_at': s.last_restocked_at.isoformat() if s.last_restocked_at else None,
    } for s in FeedStock.objects.filter(farm=farm).select_related('feed_type')]

    # Medicines / vaccines / chicks / litter have no quantity ledger in Pass 1 —
    # surface the spend rollup from the matching expense category instead.
    derived = {}
    for name in ('Medicines', 'Vaccines', 'Chicks', 'Litter'):
        cq = farm.expenses.filter(category__name=name)
        agg = cq.aggregate(total=Sum('amount'), n=Count('id'))
        last = cq.order_by('-expense_date').first()
        derived[name.lower()] = {
            'total_spent': f(agg['total']), 'purchases': agg['n'] or 0,
            'last_purchase': last.expense_date.isoformat() if last else None,
            'tracked': False,
        }
    return Response({
        'feed': feed,
        'feed_summary': {
            'items': len(feed), 'total_value': f(sum(Decimal(str(x['value'])) for x in feed)),
            'low_stock': sum(1 for x in feed if x['status'] in ('low', 'out')),
        },
        'other': derived,
    })


# ── batch / flock cost tracking ──────────────────────────────────────────

def _batch_rows(farm):
    flocks = list(Flock.objects.filter(farm=farm).select_related('shed').order_by('-start_date'))
    exp_by_flock = {row['flock_id']: row['t'] for row in
                    farm.expenses.exclude(flock_id=None).values('flock_id').annotate(t=Sum('amount'))}
    rev_by_flock = {row['flock_id']: row['t'] for row in
                    farm.revenues.exclude(flock_id=None).values('flock_id').annotate(t=Sum('amount'))}
    unlinked_exp = farm.expenses.filter(flock_id=None).aggregate(v=Sum('amount'))['v'] or Decimal('0')
    unlinked_rev = farm.revenues.filter(flock_id=None).aggregate(v=Sum('amount'))['v'] or Decimal('0')
    rows = []
    for fl in flocks:
        spent = exp_by_flock.get(fl.id, Decimal('0'))
        earned = rev_by_flock.get(fl.id, Decimal('0'))
        rows.append({
            'id': str(fl.id), 'batch_name': fl.batch_name, 'breed': fl.breed or '',
            'bird_type': fl.bird_type or '', 'shed': fl.shed.shed_name if fl.shed_id else None,
            'quantity': fl.quantity, 'current_quantity': fl.current_quantity,
            'status': fl.status or 'active',
            'start_date': fl.start_date.isoformat() if fl.start_date else None,
            'end_date': fl.end_date.isoformat() if fl.end_date else None,
            'total_expense': f(spent), 'total_revenue': f(earned),
            'net_profit': f(earned - spent),
            'cost_per_bird': round(f(spent) / fl.current_quantity, 2) if fl.current_quantity else 0,
            'mortality': max(0, (fl.quantity or 0) - (fl.current_quantity or 0)),
        })
    return rows, {'total_expense': f(unlinked_exp), 'total_revenue': f(unlinked_rev)}


@api_view(['GET'])
@permission_classes([IsFarmer])
def batches(request):
    farm = farm_for(request.user)
    rows, unlinked = _batch_rows(farm)
    return Response({'results': rows, 'unlinked': unlinked})


# ── reports (PDF via reportlab / CSV) ────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsFarmer])
def reports(request):
    farm = farm_for(request.user)
    report_type = (request.query_params.get('type') or 'profit_loss').lower()
    fmt = (request.query_params.get('export') or 'csv').lower()
    start, end = period_range(request.query_params)
    exp = in_range(farm.expenses.select_related('category'), 'expense_date', start, end)
    rev = in_range(farm.revenues.select_related('source'), 'revenue_date', start, end)

    if report_type == 'expense':
        headers = ['Date', 'Category', 'Supplier', 'Status', 'Amount']
        data = [[e.expense_date.isoformat(), e.category.name, e.supplier_name or '',
                 e.payment_status, f(e.amount)] for e in exp.order_by('expense_date')]
    elif report_type == 'revenue':
        headers = ['Date', 'Source', 'Buyer', 'Amount']
        data = [[r.revenue_date.isoformat(), r.source.name, r.buyer_name or '', f(r.amount)]
                for r in rev.order_by('revenue_date')]
    elif report_type == 'batch':
        headers = ['Batch', 'Breed', 'Birds', 'Expense', 'Revenue', 'Net profit']
        batch_rows, _unlinked = _batch_rows(farm)
        data = [[row['batch_name'], row['breed'], row['current_quantity'],
                 row['total_expense'], row['total_revenue'], row['net_profit']]
                for row in batch_rows]
    else:  # profit_loss / cash_flow
        te = exp.aggregate(v=Sum('amount'))['v'] or 0
        tr = rev.aggregate(v=Sum('amount'))['v'] or 0
        paid = exp.filter(payment_status='paid').aggregate(v=Sum('amount'))['v'] or 0
        headers = ['Metric', 'Amount']
        data = [['Total revenue', f(tr)], ['Total expense', f(te)],
                ['Net profit', f(tr - te)], ['Money in', f(tr)], ['Money out', f(paid)],
                ['Cash position (period)', f(tr - paid)]]

    title = f'{farm.farm_name} — {report_type.replace("_", " ").title()} Report'
    period_label = f'{start or "start"} to {end or date.today().isoformat()}'
    filename = f'{report_type}_report_{date.today().isoformat()}'

    if fmt == 'pdf':
        return _pdf_report(title, period_label, headers, data, filename)
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow([title])
    writer.writerow([period_label])
    writer.writerow([])
    writer.writerow(headers)
    writer.writerows(data)
    resp = HttpResponse(buf.getvalue(), content_type='text/csv')
    resp['Content-Disposition'] = f'attachment; filename="{filename}.csv"'
    return resp


def _pdf_report(title, period_label, headers, data, filename):
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import (Paragraph, SimpleDocTemplate, Spacer, Table,
                                    TableStyle)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, title=title)
    styles = getSampleStyleSheet()
    story = [Paragraph(title, styles['Title']),
             Paragraph(period_label, styles['Normal']), Spacer(1, 16)]
    table = Table([headers] + [[str(c) for c in row] for row in data], repeatRows=1)
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#00695C')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#B2DFDB')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F0F7F4')]),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
    ]))
    story.append(table)
    doc.build(story)
    resp = HttpResponse(buf.getvalue(), content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="{filename}.pdf"'
    return resp
