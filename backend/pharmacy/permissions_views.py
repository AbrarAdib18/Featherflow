"""The centralized permission/status guard the spec asks for (§7): one
endpoint the Flutter pharmacy panel polls instead of every screen inspecting
`account_status` itself, and the same computation the backend uses to lock
operational endpoints server-side (pharmacy.services.pharmacy_lifecycle_status).
"""
from decimal import Decimal

from django.db.models import Sum
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from pharmacy.auth import PharmacyAlwaysOnAuthentication
from pharmacy.models import PharmacyCommission, PharmacySale
from pharmacy.permissions import IsPharmacyAccount
from pharmacy.services import pharmacy_permission_snapshot


@api_view(['GET'])
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def permissions_view(request):
    return Response(pharmacy_permission_snapshot(request.user))


@api_view(['GET'])
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def earnings_view(request):
    """Real (never mock/zero-by-default) lifetime earnings — reachable at
    every lifecycle stage per spec §1 ('Earnings/revenue count, showing zero
    or verified historical value' stays visible while locked)."""
    sales = PharmacySale.objects.filter(pharmacy_user=request.user, status='completed')
    totals = PharmacyCommission.objects.filter(sale__in=sales).aggregate(
        commission=Sum('commission_amount'), pharmacy_amount=Sum('pharmacy_amount'))
    gross = sales.aggregate(v=Sum('gross_amount'))['v'] or Decimal('0')
    money = lambda v: str((v or Decimal('0')).quantize(Decimal('0.01')))  # noqa: E731
    return Response({
        'total_orders': sales.count(),
        'gross_sales': money(gross),
        'featherflow_commission': money(totals['commission']),
        'pharmacy_earnings': money(totals['pharmacy_amount']),
    })


@api_view(['GET'])
@authentication_classes([PharmacyAlwaysOnAuthentication])
@permission_classes([IsPharmacyAccount])
def verification_status_view(request):
    snapshot = pharmacy_permission_snapshot(request.user)
    return Response({
        'status': snapshot['status'],
        'is_verified': snapshot['is_verified'],
        'rejection_reason': snapshot['rejection_reason'],
        'more_information_reason': snapshot['more_information_reason'],
        'locked_reason': snapshot['locked_reason'],
    })
