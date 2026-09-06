"""GET /api/farmers/dashboard/ — the one call the home screen makes.

Farm summary + finance headline + cross-module counts + recent activity +
alerts. Polled every 4 s by the app.
"""
from datetime import date
from decimal import Decimal

from django.db.models import Sum
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import AdminPanelRecord
from consultations.models import Consultation
from payments.models import Payment
from profiles.models import FarmerProfile

from .cost_views import _alerts
from .services import IsFarmer, f, farm_for


@api_view(['GET'])
@permission_classes([IsFarmer])
def dashboard(request):
    user = request.user
    farm = farm_for(user)
    fp = FarmerProfile.objects.get(user=user)

    life_rev = farm.revenues.aggregate(v=Sum('amount'))['v'] or Decimal('0')
    life_exp = farm.expenses.aggregate(v=Sum('amount'))['v'] or Decimal('0')
    paid_exp = farm.expenses.filter(payment_status='paid').aggregate(v=Sum('amount'))['v'] or Decimal('0')
    cashout = Payment.objects.filter(user=user, payment_type='cashout',
                                     status__in=('pending', 'completed')).aggregate(v=Sum('amount'))['v'] or Decimal('0')
    disbursed = farm.loans.filter(status__in=('active', 'paid', 'overdue')).aggregate(
        v=Sum('loan_amount'))['v'] or Decimal('0')
    loan_balance = farm.loans.exclude(status__in=('paid', 'rejected')).aggregate(
        v=Sum('remaining_balance'))['v'] or Decimal('0')

    active_flocks = farm.flocks.filter(status='active')
    birds = active_flocks.aggregate(v=Sum('current_quantity'))['v'] or 0

    pharmacy_orders = AdminPanelRecord.objects.filter(
        module='pharmacy-orders', payload__farmer_id=str(user.id))
    open_orders = sum(1 for r in pharmacy_orders
                      if (r.payload or {}).get('status') not in ('delivered', 'cancelled', 'completed'))

    consults = Consultation.objects.filter(farmer=user)
    upcoming = consults.filter(status__in=('requested', 'accepted', 'rescheduled'),
                               appointment_date__gte=date.today()).count()

    recent = []
    for e in farm.expenses.select_related('category').order_by('-created_at')[:5]:
        recent.append({'kind': 'expense', 'title': f'{e.category.name} expense',
                       'amount': f(e.amount), 'status': e.payment_status,
                       'date': e.expense_date.isoformat()})
    for r in farm.revenues.select_related('source').order_by('-created_at')[:5]:
        recent.append({'kind': 'revenue', 'title': f'{r.source.name}',
                       'amount': f(r.amount), 'status': 'received',
                       'date': r.revenue_date.isoformat()})
    recent.sort(key=lambda x: x['date'], reverse=True)

    return Response({
        'farm': {
            'name': farm.farm_name, 'type': fp.farm_type or 'mixed',
            'location': fp.farm_location, 'total_birds': birds,
            'active_batches': active_flocks.count(),
            'is_verified': fp.approved_by_admin_id is not None,
        },
        'finance': {
            'total_revenue': f(life_rev), 'total_expense': f(life_exp),
            'net_profit': f(life_rev - life_exp),
            'cash_balance': f(life_rev + disbursed - paid_exp - cashout),
            'loan_balance': f(loan_balance), 'due_tax': None,
        },
        'counts': {
            'open_pharmacy_orders': open_orders,
            'upcoming_consultations': upcoming,
            'unread_notifications': user.notifications.filter(is_read=False).count(),
            'pending_loans': farm.loans.filter(status='pending').count(),
        },
        'recent_activity': recent[:8],
        'alerts': _alerts(farm, user),
        'quick_actions': [
            {'label': 'Add Expense', 'path': '/farmer/cost-management', 'icon': 'remove_circle_outline'},
            {'label': 'Add Revenue', 'path': '/farmer/cost-management', 'icon': 'add_circle_outline'},
            {'label': 'Request Loan', 'path': '/farmer/cost-management', 'icon': 'account_balance'},
            {'label': 'View Reports', 'path': '/farmer/cost-management', 'icon': 'bar_chart'},
        ],
    })
