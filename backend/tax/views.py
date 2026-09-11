"""Tax estimation + record-keeping API for the farmer panel.

    POST /api/farmers/tax/calculate/          estimate tax from revenue + assets
    GET  /api/farmers/tax/profile/            the farmer's saved tax profile
    PUT  /api/farmers/tax/profile/            update it
    POST /api/farmers/tax/payment/            record a tax payment
    POST /api/farmers/tax/payment/upload-receipt/   attach a receipt image
    GET  /api/farmers/tax/payments/           list recorded payments
    GET  /api/farmers/tax/summary/            paid / estimated / pending for the year

This is an estimation + recording tool only — nothing here is enforced and there
is no NBR integration.
"""
from datetime import date

from django.db.models import Sum
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from expenses.models import ExpenseCategory
from farms.models import Farm

from consultations.permissions import IsFarmer

from . import calculator
from .models import TaxPayment, TaxProfile
from .serializers import (CalcRequestSerializer, TaxPaymentSerializer,
                          TaxProfileSerializer)

try:  # optional helpers — keep tax working even if the farmers app moves
    from farmers.services import store_image
except Exception:  # pragma: no cover
    store_image = None


# ── helpers ─────────────────────────────────────────────────────────────────

def _profile_for(user):
    profile, _ = TaxProfile.objects.get_or_create(user=user)
    return profile


def _farm_for(user):
    return Farm.objects.filter(farmer__user=user, is_active=True).first()


def _year_revenue_breakdown(user, year):
    """{'Bird Sales': 12345.0, ...} from cost-management revenue rows for `year`."""
    farm = _farm_for(user)
    if not farm:
        return {}, 0.0
    rows = (farm.revenues.filter(revenue_date__year=year)
            .values('source__name').annotate(total=Sum('amount')))
    breakdown = {r['source__name']: float(r['total'] or 0) for r in rows}
    expenses = farm.expenses.filter(expense_date__year=year).aggregate(v=Sum('amount'))['v'] or 0
    return breakdown, float(expenses)


def _assets_from_profile(profile):
    return {
        'land_area': float(profile.land_area or 0),
        'land_unit': profile.land_unit,
        'land_use': profile.land_use,
        'location': profile.location,
        'vehicles': profile.vehicles or [],
    }


def _estimate(user, *, revenue_breakdown=None, expenses=None, overrides=None):
    profile = _profile_for(user)
    overrides = overrides or {}
    year = date.today().year

    if revenue_breakdown is None:
        revenue_breakdown, auto_expenses = _year_revenue_breakdown(user, year)
        if expenses is None:
            expenses = auto_expenses
    if expenses is None:
        expenses = 0.0

    assets = _assets_from_profile(profile)
    assets.update(overrides.get('assets') or {})

    return calculator.calculate_total_tax(
        revenue_breakdown=revenue_breakdown,
        assets=assets,
        income_type=overrides.get('income_type') or profile.income_type,
        exemptions=overrides.get('exemptions', float(profile.exemptions or 0)),
        rebates=overrides.get('rebates', float(profile.rebates or 0)),
        is_senior=overrides.get('is_senior', bool(profile.is_senior)),
        expenses=expenses,
    )


# ── endpoints ───────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsFarmer])
def calculate(request):
    body = CalcRequestSerializer(data=request.data)
    body.is_valid(raise_exception=True)
    data = body.validated_data

    overrides = {k: data[k] for k in ('income_type', 'exemptions', 'rebates', 'is_senior', 'assets')
                 if k in data}
    result = _estimate(
        request.user,
        revenue_breakdown=data.get('revenue_breakdown'),
        expenses=data.get('expenses'),
        overrides=overrides,
    )
    return Response(result)


@api_view(['GET', 'PUT', 'PATCH'])
@permission_classes([IsFarmer])
def profile(request):
    obj = _profile_for(request.user)
    if request.method == 'GET':
        return Response(TaxProfileSerializer(obj).data)

    ser = TaxProfileSerializer(obj, data=request.data, partial=True)
    ser.is_valid(raise_exception=True)
    ser.save()
    return Response(ser.data)


@api_view(['GET', 'POST'])
@permission_classes([IsFarmer])
def payments(request):
    if request.method == 'GET':
        qs = TaxPayment.objects.filter(user=request.user)
        tax_type = request.query_params.get('tax_type')
        if tax_type:
            qs = qs.filter(tax_type=tax_type)
        year = request.query_params.get('year')
        if year and year.isdigit():
            qs = qs.filter(payment_date__year=int(year))
        rows = TaxPaymentSerializer(qs, many=True).data
        total = qs.aggregate(v=Sum('amount'))['v'] or 0
        return Response({'results': rows, 'count': len(rows), 'total_paid': float(total)})

    ser = TaxPaymentSerializer(data=request.data)
    ser.is_valid(raise_exception=True)
    payment = ser.save(user=request.user)

    # optional: mirror the payment into cost-management as a "Tax" expense
    if str(request.data.get('log_as_expense', '')).lower() in ('1', 'true', 'yes'):
        _mirror_expense(request.user, payment)

    return Response(TaxPaymentSerializer(payment).data, status=201)


@api_view(['POST'])
@permission_classes([IsFarmer])
def payment_upload_receipt(request):
    if store_image is None:
        return Response({'detail': 'Receipt upload is unavailable.'}, status=503)
    url, error = store_image(request, 'tax-receipts')
    if error:
        return Response({'detail': error}, status=400)
    return Response({'image_url': url}, status=201)


@api_view(['GET'])
@permission_classes([IsFarmer])
def summary(request):
    year = date.today().year
    estimate = _estimate(request.user)

    qs = TaxPayment.objects.filter(user=request.user, payment_date__year=year)
    paid_total = float(qs.aggregate(v=Sum('amount'))['v'] or 0)
    by_type = {row['tax_type']: float(row['total'] or 0)
               for row in qs.values('tax_type').annotate(total=Sum('amount'))}

    estimated_by_type = {
        'income': estimate['income_tax'],
        'land': estimate['land_tax'],
        'vehicle': estimate['vehicle_tax'],
    }
    lines = []
    for key, label in (('income', 'Income / business tax'), ('land', 'Land development tax'),
                       ('vehicle', 'Vehicle tax')):
        est = estimated_by_type[key]
        pd = by_type.get(key, 0.0)
        lines.append({
            'tax_type': key, 'label': label,
            'estimated': round(est, 2), 'paid': round(pd, 2),
            'pending': round(max(0.0, est - pd), 2),
        })
    other_paid = by_type.get('other', 0.0)
    if other_paid:
        lines.append({'tax_type': 'other', 'label': 'Other', 'estimated': 0.0,
                      'paid': round(other_paid, 2), 'pending': 0.0})

    estimated_total = estimate['total']
    return Response({
        'year': year,
        'tax_year': estimate['tax_year'],
        'estimated_total': estimated_total,
        'total_paid': round(paid_total, 2),
        'pending': round(max(0.0, estimated_total - paid_total), 2),
        'lines': lines,
        'estimate': estimate,
        'disclaimer': ('This is an estimate to help you plan, not a tax assessment. '
                       'Confirm the exact amount with a tax adviser or your local '
                       'NBR / land office before paying.'),
    })


# ── internals ───────────────────────────────────────────────────────────────

def _mirror_expense(user, payment):
    try:
        from expenses.models import Expense
        farm = _farm_for(user)
        if not farm:
            return
        category, _ = ExpenseCategory.objects.get_or_create(name='Tax')
        expense = Expense.objects.create(
            farm=farm, category=category, amount=payment.amount,
            description=f'{payment.get_tax_type_display()}'
                        + (f' (ref {payment.reference_number})' if payment.reference_number else ''),
            expense_date=payment.payment_date, payment_status='paid',
            payment_method='other', created_by=user)
        payment.expense_id = expense.id
        payment.save(update_fields=['expense_id'])
    except Exception:  # mirroring must never break the tax record
        pass
