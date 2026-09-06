"""Shared serialisers and business logic for the pharmacy catalogue.

Kept separate from views so the farmer-facing, pharmacy-facing and admin-facing
modules can reuse one definition of "what a medicine looks like" and one copy of
the expiry-alert / delivery-bridge rules.
"""

import random
import uuid
from datetime import datetime, timedelta

from django.db import transaction
from django.utils import timezone

from audit.models import ActivityLog, AdminPanelRecord
from notifications.models import Notification
from users.models import User

from pharmacy.models import (
    EXPIRY_CRITICAL_DAYS, EXPIRY_INFO_DAYS, EXPIRY_WARNING_DAYS,
    LOW_STOCK_THRESHOLD, PharmacyExpiryAlert, PharmacyMedicine,
)

# Order status vocabulary the app speaks, mapped onto the tested JSON bridge
# (pharmacy-orders payload `status`). The bridge stays the source of truth; we
# only translate at the edges so the delivery integration is untouched.
BRIDGE_TO_APP_STATUS = {
    'pending': 'pending',
    'processing': 'preparing',
    'shipped': 'ready_for_delivery',
    'delivered': 'delivered',
    'cancelled': 'cancelled',
    'delivery_failed': 'delivery_failed',
}


def notify(user, title, body, reference_type='pharmacy_order', reference_id=None,
           notification_type='system'):
    if user is None:
        return
    Notification.objects.create(
        user=user, title=title, body=body, notification_type=notification_type,
        reference_id=reference_id, reference_type=reference_type,
    )


def log_action(user, action, entity_id=None, values=None, module='Pharmacy'):
    try:
        target_id = uuid.UUID(str(entity_id)) if entity_id else None
    except (TypeError, ValueError, AttributeError):
        target_id = None
    ActivityLog.objects.create(
        user=user, module=module, action=action,
        entity_type='pharmacy', entity_id=target_id, new_values=values,
    )


def pharmacy_public_profile(user):
    """The pharmacy identity a farmer sees. Mirrors views._profile but adds the
    fields the marketplace/directory needs."""
    data = user.profile_data if isinstance(user.profile_data, dict) else {}
    return {
        'id': str(user.id),
        'name': data.get('business_name') or user.full_name or user.email,
        'license_number': data.get('pharmacy_license_number', ''),
        'address': data.get('business_address') or user.present_address or '',
        'phone': user.phone or '',
        'email': user.email,
        'rating': float(data.get('rating', 0) or 0),
        'is_verified': bool(user.is_verified),
        'cold_chain_capable': bool(data.get('storage_cold_chain_capability', False)),
        'delivery_coverage': data.get('delivery_coverage_area', ''),
    }


# ── Medicine serialisation ──────────────────────────────────────────────────

def medicine_json(medicine, *, include_pharmacy=False, for_farmer=False):
    days = medicine.expires_in_days
    data = {
        'id': str(medicine.id),
        'medicine_id': str(medicine.id),
        'name': medicine.name,
        'generic_name': medicine.generic_name or '',
        'manufacturer': medicine.manufacturer or '',
        'category': medicine.category,
        'prescription_required': medicine.prescription_required,
        'price': float(medicine.price),
        'stock_quantity': medicine.stock_quantity,
        'unit': medicine.unit,
        'pack_size': medicine.pack_size or '',
        'description': medicine.description or '',
        'dosage_instructions': medicine.dosage_instructions or '',
        'storage_instructions': medicine.storage_instructions or '',
        'cold_chain_required': medicine.cold_chain_required,
        'expiry_date': medicine.expiry_date.isoformat() if medicine.expiry_date else None,
        'batch_number': medicine.batch_number or '',
        'images': medicine.images or [],
        'is_active': medicine.is_active,
        'is_approved': medicine.is_approved,
        'approval_status': _approval_label(medicine),
        'approval_rejected_reason': medicine.approval_rejected_reason or '',
        'expires_in_days': days,
        'expiry_alert_level': medicine.expiry_alert_level,
        'stock_status': medicine.stock_status,
        'is_low_stock': medicine.is_low_stock,
        'views_count': medicine.views_count,
        'orders_count': medicine.orders_count,
        'created_at': medicine.created_at.isoformat() if medicine.created_at else None,
        'updated_at': medicine.updated_at.isoformat() if medicine.updated_at else None,
    }
    if include_pharmacy or for_farmer:
        try:
            data['pharmacy'] = pharmacy_public_profile(medicine.pharmacy_user)
        except User.DoesNotExist:
            data['pharmacy'] = None
    if for_farmer:
        # Farmers never see internal counters / batch numbers.
        for hidden in ('views_count', 'orders_count', 'batch_number', 'is_approved',
                       'approval_status', 'approval_rejected_reason'):
            data.pop(hidden, None)
    return data


def _approval_label(medicine):
    if medicine.is_approved:
        return 'approved'
    if medicine.approval_rejected_reason:
        return 'rejected'
    return 'pending'


# ── Validation ─────────────────────────────────────────────────────────────

CATEGORY_VALUES = {c[0] for c in PharmacyMedicine.CATEGORY_CHOICES}
UNIT_VALUES = {u[0] for u in PharmacyMedicine.UNIT_CHOICES}


def clean_medicine_payload(data, *, partial=False):
    """Returns (cleaned_dict, error_string). Enforces price > 0, stock >= 0,
    expiry in the future, valid category/unit."""
    cleaned = {}
    errors = []

    def want(field):
        return (not partial) or field in data

    if want('name'):
        name = str(data.get('name', '')).strip()
        if not name:
            errors.append('Medicine name is required.')
        cleaned['name'] = name
    if want('category'):
        category = str(data.get('category', '')).strip().lower()
        if category not in CATEGORY_VALUES:
            errors.append(f'Category must be one of: {", ".join(sorted(CATEGORY_VALUES))}.')
        else:
            cleaned['category'] = category
    if want('unit'):
        unit = str(data.get('unit', '')).strip().lower()
        if unit not in UNIT_VALUES:
            errors.append(f'Unit must be one of: {", ".join(sorted(UNIT_VALUES))}.')
        else:
            cleaned['unit'] = unit
    if want('price'):
        try:
            price = round(float(data.get('price')), 2)
            if price <= 0:
                errors.append('Price must be greater than 0.')
            else:
                cleaned['price'] = price
        except (TypeError, ValueError):
            errors.append('Price must be a number.')
    if 'stock_quantity' in data or (not partial):
        try:
            stock = int(data.get('stock_quantity', 0))
            if stock < 0:
                errors.append('Stock quantity cannot be negative.')
            else:
                cleaned['stock_quantity'] = stock
        except (TypeError, ValueError):
            errors.append('Stock quantity must be a whole number.')
    if want('expiry_date'):
        expiry = _parse_date(data.get('expiry_date'))
        if expiry is None:
            errors.append('A valid expiry date (YYYY-MM-DD) is required.')
        elif expiry <= timezone.now().date():
            errors.append('Expiry date must be in the future.')
        else:
            cleaned['expiry_date'] = expiry

    for text_field in ('generic_name', 'manufacturer', 'pack_size', 'description',
                       'dosage_instructions', 'storage_instructions', 'batch_number'):
        if text_field in data:
            cleaned[text_field] = str(data.get(text_field) or '').strip()
    for bool_field in ('prescription_required', 'cold_chain_required', 'is_active'):
        if bool_field in data:
            cleaned[bool_field] = bool(data.get(bool_field))
    if 'images' in data and isinstance(data['images'], list):
        cleaned['images'] = [str(u) for u in data['images']][:5]

    return cleaned, ('; '.join(errors) if errors else None)


def _parse_date(value):
    if not value:
        return None
    for fmt in ('%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%S.%f'):
        try:
            return datetime.strptime(str(value)[:len(fmt) + 6], fmt).date()
        except (TypeError, ValueError):
            continue
    try:
        return datetime.fromisoformat(str(value)).date()
    except (TypeError, ValueError):
        return None


def apply_auto_approval(medicine):
    """Industry decision §E.7 — OTC auto-approves, prescription items wait for
    an admin. Call after setting prescription_required / before save."""
    if not medicine.prescription_required:
        medicine.is_approved = True
        medicine.approval_rejected_reason = None
    elif medicine.is_approved and not medicine._state.adding:
        # keep an already-approved prescription medicine approved
        pass
    else:
        medicine.is_approved = False


# ── Expiry alert generation (on-demand; cron deferred to Pass 2) ────────────

def regenerate_expiry_alerts(pharmacy_user=None):
    """Recompute PharmacyExpiryAlert rows. Scoped to one pharmacy when given,
    otherwise platform-wide. Returns the number of live alerts."""
    today = timezone.now().date()
    horizon = today + timedelta(days=EXPIRY_INFO_DAYS)
    medicines = PharmacyMedicine.objects.filter(is_active=True, expiry_date__lte=horizon)
    if pharmacy_user is not None:
        medicines = medicines.filter(pharmacy_user=pharmacy_user)

    live_ids = set()
    with transaction.atomic():
        for medicine in medicines:
            days = (medicine.expiry_date - today).days
            level = _alert_level(days)
            if level is None:
                continue
            alert, created = PharmacyExpiryAlert.objects.get_or_create(
                medicine=medicine,
                defaults={
                    'pharmacy_user_id': medicine.pharmacy_user_id,
                    'expires_in_days': days, 'alert_level': level,
                    'created_at': timezone.now(),
                },
            )
            if not created and (alert.expires_in_days != days or alert.alert_level != level):
                alert.expires_in_days = days
                alert.alert_level = level
                # a worsening alert re-surfaces even if previously acknowledged
                if _severity(level) > _severity(alert.alert_level):
                    alert.is_acknowledged = False
                alert.save(update_fields=['expires_in_days', 'alert_level', 'is_acknowledged'])
            live_ids.add(alert.id)

        stale = PharmacyExpiryAlert.objects.exclude(id__in=live_ids)
        if pharmacy_user is not None:
            stale = stale.filter(pharmacy_user=pharmacy_user)
        stale.delete()

    scope = PharmacyExpiryAlert.objects.all()
    if pharmacy_user is not None:
        scope = scope.filter(pharmacy_user=pharmacy_user)
    return scope.count()


def _alert_level(days):
    if days < EXPIRY_CRITICAL_DAYS:
        return 'critical'
    if days < EXPIRY_WARNING_DAYS:
        return 'warning'
    if days < EXPIRY_INFO_DAYS:
        return 'info'
    return None


def _severity(level):
    return {'info': 1, 'warning': 2, 'critical': 3}.get(level, 0)


def expiry_alert_json(alert):
    medicine = alert.medicine
    return {
        'alert_id': str(alert.id),
        'medicine_id': str(medicine.id),
        'medicine_name': medicine.name,
        'pharmacy_id': str(alert.pharmacy_user_id),
        'batch_number': medicine.batch_number or '',
        'expiry_date': medicine.expiry_date.isoformat() if medicine.expiry_date else None,
        'expires_in_days': alert.expires_in_days,
        'alert_level': alert.alert_level,
        'stock_quantity': medicine.stock_quantity,
        'is_acknowledged': alert.is_acknowledged,
        'created_at': alert.created_at.isoformat() if alert.created_at else None,
    }


# ── Inventory summary ──────────────────────────────────────────────────────

def inventory_summary(pharmacy_user):
    qs = PharmacyMedicine.objects.filter(pharmacy_user=pharmacy_user)
    active = qs.filter(is_active=True)
    total = active.count()
    low_stock = active.filter(stock_quantity__lt=LOW_STOCK_THRESHOLD,
                              stock_quantity__gt=0).count()
    out_of_stock = active.filter(stock_quantity__lte=0).count()
    stock_value = sum(float(m.price) * m.stock_quantity for m in active)
    regenerate_expiry_alerts(pharmacy_user)
    alerts = PharmacyExpiryAlert.objects.filter(pharmacy_user=pharmacy_user)
    return {
        'total_products': total,
        'active_products': total,
        'low_stock_count': low_stock,
        'out_of_stock_count': out_of_stock,
        'expiring_soon_count': alerts.count(),
        'critical_expiry_count': alerts.filter(alert_level='critical').count(),
        'pending_approval_count': active.filter(is_approved=False).count(),
        'stock_value': round(stock_value, 2),
        'low_stock_threshold': LOW_STOCK_THRESHOLD,
    }


# ── Order <-> catalogue bridge helpers ─────────────────────────────────────

def order_key(pharmacy_user_id, order_id):
    return f'{pharmacy_user_id}:{order_id}'


def generate_otp():
    return f'{random.randint(0, 999999):06d}'


def order_items_from_cart(pharmacy_user, cart, *, lock=True):
    """Validate a farmer cart against the real catalogue. Returns
    (items, medicines_by_id, error_string). Does NOT decrement stock."""
    if not cart:
        return None, None, 'At least one item is required.'
    items, medicines = [], {}
    for entry in cart:
        mid = str(entry.get('medicine_id') or entry.get('product_id') or '')
        try:
            quantity = int(entry.get('quantity', 0))
        except (TypeError, ValueError):
            return None, None, 'Item quantity must be a whole number.'
        if quantity <= 0:
            return None, None, 'Item quantity must be greater than 0.'
        query = PharmacyMedicine.objects.filter(pk=mid, pharmacy_user=pharmacy_user)
        medicine = (query.select_for_update().first() if lock else query.first())
        if medicine is None:
            return None, None, f'Medicine {mid} is not sold by this pharmacy.'
        if not medicine.is_active:
            return None, None, f'{medicine.name} is not available right now.'
        if not medicine.is_approved:
            return None, None, f'{medicine.name} is awaiting admin approval and cannot be ordered yet.'
        if medicine.stock_quantity < quantity:
            return None, None, f'Only {medicine.stock_quantity} {medicine.unit} of {medicine.name} in stock.'
        medicines[str(medicine.id)] = medicine
        items.append({
            'product_id': str(medicine.id),
            'medicine_id': str(medicine.id),
            'product_name': medicine.name,
            'quantity': quantity,
            'unit_price': float(medicine.price),
            'category': medicine.category,
            'cold_chain_required': medicine.cold_chain_required,
            'prescription_required': medicine.prescription_required,
        })
    return items, medicines, None


def delivery_fee_for(distance_km):
    """Transparent pricing (industry decision §E.8): ৳60 base + ৳15/km beyond 2km."""
    base = 60.0
    if distance_km and distance_km > 2:
        base += (float(distance_km) - 2) * 15.0
    return round(base, 2)
