"""Admin Panel — farmer loan applications.

A farmer submits a loan request from Cost Management (status='pending'); an
Operations / Finance admin reviews it here and approves (→ 'active', with an
installment schedule generated from the term) or rejects it.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from expenses.models import Loan, LoanInstallment
from notifications.models import Notification

from api.admin_rbac import IsAdminUser, can_perform_action


def _loan_json(loan):
    return {
        'id': str(loan.id), 'farm': loan.farm.farm_name,
        'farmer': loan.requested_by.full_name if loan.requested_by_id else '',
        'farmer_id': str(loan.requested_by_id) if loan.requested_by_id else None,
        'lender_name': loan.lender_name, 'loan_amount': float(loan.loan_amount),
        'remaining_balance': float(loan.remaining_balance),
        'interest_rate': float(loan.interest_rate or 0), 'term_months': loan.term_months,
        'purpose': loan.purpose or '', 'status': loan.status,
        'rejection_reason': loan.rejection_reason or '',
        'requested_at': loan.created_at.isoformat() if loan.created_at else None,
        'decided_at': loan.decided_at.isoformat() if loan.decided_at else None,
    }


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_farmer_loans(request):
    if not can_perform_action(request.user, 'finance', 'view'):
        return Response({'detail': 'Your admin role cannot view farmer finance.'}, status=403)
    qs = Loan.objects.select_related('farm', 'requested_by').order_by('-created_at')
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)
    return Response({'results': [_loan_json(loan) for loan in qs[:200]]})


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_farmer_loan_decide(request, loan_id):
    if not can_perform_action(request.user, 'finance', 'approve'):
        return Response({'detail': 'Your admin role cannot approve loans.'}, status=403)
    try:
        loan = Loan.objects.select_related('farm', 'requested_by').get(pk=loan_id)
    except Loan.DoesNotExist:
        return Response({'detail': 'Loan not found.'}, status=404)
    if loan.status != 'pending':
        return Response({'detail': 'This loan has already been decided.'}, status=400)

    decision = request.data.get('decision')
    if decision == 'approve':
        rate = Decimal(str(request.data.get('interest_rate', loan.interest_rate or 12)))
        term = int(request.data.get('term_months') or loan.term_months or 12)
        start = date.today()
        loan.status = 'active'
        loan.interest_rate = rate
        loan.term_months = term
        loan.start_date = start
        loan.due_date = start + timedelta(days=30 * term)
        loan.lender_name = request.data.get('lender_name') or loan.lender_name
        total_repayable = loan.loan_amount * (1 + rate / 100)
        loan.remaining_balance = total_repayable.quantize(Decimal('0.01'))
        loan.decided_by = request.user
        loan.decided_at = timezone.now()
        loan.save()
        LoanInstallment.objects.filter(loan=loan).delete()
        per = (total_repayable / term).quantize(Decimal('0.01'))
        for i in range(1, term + 1):
            LoanInstallment.objects.create(
                loan=loan, due_date=start + timedelta(days=30 * i), amount=per)
        Notification.objects.create(
            user=loan.requested_by, title='Loan approved',
            body=f'৳{float(loan.loan_amount):,.0f} approved at {rate}% over {term} months.',
            notification_type='approval', reference_id=loan.id, reference_type='loan')
        action_type, msg = 'approve', 'Approved farmer loan'
    elif decision == 'reject':
        loan.status = 'rejected'
        loan.rejection_reason = request.data.get('reason', '')
        loan.decided_by = request.user
        loan.decided_at = timezone.now()
        loan.save()
        Notification.objects.create(
            user=loan.requested_by, title='Loan request declined',
            body=loan.rejection_reason or 'Your loan request was not approved.',
            notification_type='system', reference_id=loan.id, reference_type='loan')
        action_type, msg = 'reject', 'Rejected farmer loan'
    else:
        return Response({'detail': 'decision must be "approve" or "reject".'}, status=400)

    ActivityLog.objects.create(
        user=request.user, module='finance', action=msg, action_type=action_type,
        entity_type='loan', entity_id=loan.id, new_values=_loan_json(loan))
    return Response(_loan_json(loan))
