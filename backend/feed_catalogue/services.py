"""Shared helpers for the farmer-facing feed marketplace (Priorities 5, 7).

``order_items_from_cart`` is the security boundary: every order endpoint
must go through it so an unknown/rejected/suspended/inactive product id,
an altered price, or an out-of-stock/negative/excessive quantity is rejected
here rather than trusted from the client — mirrors
``pharmacy.services.order_items_from_cart`` for the same reason.
"""
from django.core.exceptions import ValidationError

from .models import FeedProduct


def product_json(p):
    return {
        'id': str(p.id), 'company_id': str(p.company_id), 'company_name': p.company.name,
        'company_logo_url': p.company.logo_url or '',
        'product_name': p.product_name, 'brand': p.brand, 'feed_type': p.feed_type,
        'bird_type': p.bird_type, 'description': p.description or '',
        'ingredients': p.ingredients or '', 'nutritional_info': p.nutritional_info or {},
        'unit': p.unit, 'price': float(p.price),
        'stock_quantity': p.stock_quantity, 'min_order_quantity': p.min_order_quantity,
        'image_url': p.image_url or '', 'gallery_urls': p.gallery_urls or [],
        'in_stock': p.stock_quantity >= p.min_order_quantity,
    }


def order_key(order_id):
    return f'feed:{order_id}'


def order_items_from_cart(cart, *, lock=True):
    """Validate a farmer cart against the real, admin-approved catalogue.

    Returns (items, products_by_id, error_string). Never trusts a client-
    supplied name/price/total — every value in the returned ``items`` is
    read straight off the current (locked, if requested) DB row. Does NOT
    decrement stock; the caller does that inside its own transaction after
    this succeeds, so a validation failure never touches stock.
    """
    if not cart:
        return None, None, 'At least one item is required.'
    items, products = [], {}
    for entry in cart:
        pid = str(entry.get('product_id') or '')
        try:
            quantity = int(entry.get('quantity', 0))
        except (TypeError, ValueError):
            return None, None, 'Item quantity must be a whole number.'
        if quantity <= 0:
            return None, None, 'Item quantity must be greater than 0.'
        if not pid:
            return None, None, 'Each item must reference a catalogue product_id — free-text products are not allowed.'
        query = FeedProduct.objects.select_related('company').filter(pk=pid)
        try:
            product = query.select_for_update().first() if lock else query.first()
        except (ValueError, ValidationError):
            product = None
        if product is None:
            return None, None, f'Product {pid} does not exist in the feed catalogue.'
        if product.approval_status != 'approved':
            return None, None, f'{product.product_name} is not available for order ({product.approval_status}).'
        if product.company.status != 'active':
            return None, None, f'{product.product_name}\'s supplier is not currently active.'
        if quantity < product.min_order_quantity:
            return None, None, f'{product.product_name} has a minimum order quantity of {product.min_order_quantity}.'
        if product.stock_quantity < quantity:
            return None, None, f'Only {product.stock_quantity} {product.unit} of {product.product_name} in stock.'
        products[str(product.id)] = product
        items.append({
            'product_id': str(product.id),
            'product_name': product.product_name,
            'company_name': product.company.name,
            'quantity': quantity,
            'unit_price': float(product.price),   # server value — never the client's
            'unit': product.unit,
            'line_total': round(float(product.price) * quantity, 2),
        })
    return items, products, None


def delivery_fee_for(distance_km):
    """Same transparent pricing formula as the pharmacy marketplace
    (৳60 base + ৳15/km beyond 2km) — kept as a small local copy rather than
    an import so this module has no dependency on the pharmacy app."""
    base = 60.0
    if distance_km and distance_km > 2:
        base += (float(distance_km) - 2) * 15.0
    return round(base, 2)
