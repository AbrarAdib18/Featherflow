from rest_framework import serializers

from .calculator import LAND_UNIT_TO_DECIMAL, VEHICLE_ALIASES, VEHICLE_TAX
from .models import TaxPayment, TaxProfile

_LAND_USE_CHOICES = ['agricultural', 'residential', 'commercial']
_LOCATION_CHOICES = ['rural', 'urban']

_VEHICLE_CHOICES = set(VEHICLE_TAX) | set(VEHICLE_ALIASES)


def _clean_vehicles(value):
    if value in (None, ''):
        return []
    if not isinstance(value, list):
        raise serializers.ValidationError('vehicles must be a list of {type, count}.')
    cleaned = []
    for item in value:
        if not isinstance(item, dict):
            raise serializers.ValidationError('each vehicle must be an object {type, count}.')
        vtype = str(item.get('type', '')).strip().lower().replace(' ', '_').replace('-', '_')
        if not vtype:
            continue
        try:
            count = int(item.get('count', 1) or 1)
        except (TypeError, ValueError):
            raise serializers.ValidationError('vehicle count must be a whole number.')
        cleaned.append({'type': vtype, 'count': max(0, count)})
    return cleaned


class TaxProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = TaxProfile
        fields = ['id', 'land_area', 'land_unit', 'land_use', 'location', 'vehicles',
                  'income_type', 'exemptions', 'rebates', 'is_senior',
                  'district', 'upazila', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']

    def validate_vehicles(self, value):
        return _clean_vehicles(value)

    def validate_land_area(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError('Land area cannot be negative.')
        return value

    def validate_exemptions(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError('Exemptions cannot be negative.')
        return value

    def validate_rebates(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError('Rebates cannot be negative.')
        return value


class TaxPaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = TaxPayment
        fields = ['id', 'tax_type', 'amount', 'payment_date', 'reference_number',
                  'notes', 'receipt_url', 'expense_id', 'created_at']
        read_only_fields = ['id', 'created_at', 'expense_id']

    def validate_amount(self, value):
        if value is None or value <= 0:
            raise serializers.ValidationError('Amount must be greater than zero.')
        return value


class CalcAssetsSerializer(serializers.Serializer):
    land_area = serializers.FloatField(required=False, default=0, min_value=0)
    land_unit = serializers.ChoiceField(choices=list(LAND_UNIT_TO_DECIMAL), required=False, default='katha')
    land_use = serializers.ChoiceField(choices=_LAND_USE_CHOICES, required=False, default='agricultural')
    location = serializers.ChoiceField(choices=_LOCATION_CHOICES, required=False, default='rural')
    vehicles = serializers.ListField(child=serializers.DictField(), required=False, default=list)

    def validate_vehicles(self, value):
        return _clean_vehicles(value)


class CalcRequestSerializer(serializers.Serializer):
    """POST /calculate/ — revenue + assets. Anything omitted falls back to the
    farmer's saved TaxProfile / cost-management revenue."""
    revenue_breakdown = serializers.DictField(child=serializers.FloatField(), required=False)
    expenses = serializers.FloatField(required=False, min_value=0)
    income_type = serializers.ChoiceField(choices=['agricultural', 'business', 'mixed'], required=False)
    exemptions = serializers.FloatField(required=False, min_value=0)
    rebates = serializers.FloatField(required=False, min_value=0)
    is_senior = serializers.BooleanField(required=False)
    assets = CalcAssetsSerializer(required=False)
