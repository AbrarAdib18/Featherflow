"""Feed Admin — company + catalogue management (Priorities 5-6).

RBAC follows the exact same pattern as ``api/admin_views.py``'s pharmacy
branch: ``IsAdminUser`` (any active admin-panel role) + an explicit
``can_perform_action(user, 'feed-catalogue', action)`` check per call. A
``feed_admin`` role (seeded by ``../feed_marketplace_extension.sql``) is
scoped to exactly ``feed-catalogue``/``feed-orders``/``feed-delivery`` and
nothing else — it cannot reach unrelated admin modules, and non-feed-admin
roles cannot reach these views unless separately granted.

Self-approval (a feed_admin both creates and approves) mirrors the existing
``admin_pharmacy`` role, which has the same ``create``+``approve`` pair for
its own module — there is no separate "super admin must approve" chain
elsewhere in this codebase for a module-scoped admin, so none is invented
here; ``admin_super``'s wildcard permissions can always review/override.
"""
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from api.admin_rbac import IsAdminUser, can_perform_action

from .models import FeedCompany, FeedProduct
from .uploads import UploadError, delete_public_image, store_public_image

MODULE = 'feed-catalogue'


def _forbidden(action):
    return Response({
        'detail': f'Your admin role cannot "{action}" in the "{MODULE}" module.',
        'code': 'forbidden_module_action',
    }, status=403)


def _paginate(request):
    try:
        limit = min(int(request.query_params.get('limit', 50)), 200)
    except (TypeError, ValueError):
        limit = 50
    try:
        offset = max(int(request.query_params.get('offset', 0)), 0)
    except (TypeError, ValueError):
        offset = 0
    return limit, offset


def _company_json(c):
    return {
        'id': str(c.id), 'name': c.name, 'contact_person': c.contact_person,
        'contact_phone': c.contact_phone, 'contact_email': c.contact_email,
        'address': c.address, 'district': c.district, 'upazila': c.upazila,
        'description': c.description or '', 'logo_url': c.logo_url or '',
        'cover_url': c.cover_url or '', 'license_number': c.license_number or '',
        'status': c.status, 'admin_notes': c.admin_notes or '',
        'product_count': c.products.count(),
        'created_at': c.created_at.isoformat() if c.created_at else None,
        'updated_at': c.updated_at.isoformat() if c.updated_at else None,
    }


def _product_json(p):
    return {
        'id': str(p.id), 'company_id': str(p.company_id), 'company_name': p.company.name,
        'company_logo_url': p.company.logo_url or '',
        'product_name': p.product_name, 'brand': p.brand, 'feed_type': p.feed_type,
        'bird_type': p.bird_type, 'description': p.description or '',
        'ingredients': p.ingredients or '', 'nutritional_info': p.nutritional_info or {},
        'unit': p.unit, 'price': float(p.price), 'stock_quantity': p.stock_quantity,
        'min_order_quantity': p.min_order_quantity, 'image_url': p.image_url or '',
        'gallery_urls': p.gallery_urls or [],
        'approval_status': p.approval_status, 'rejection_reason': p.rejection_reason or '',
        'orders_count': p.orders_count,
        'created_at': p.created_at.isoformat() if p.created_at else None,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def companies(request):
    action = 'view' if request.method == 'GET' else 'create'
    if not can_perform_action(request.user, MODULE, action):
        return _forbidden(action)
    if request.method == 'GET':
        qs = FeedCompany.objects.all()
        if request.query_params.get('status'):
            qs = qs.filter(status=request.query_params['status'])
        if request.query_params.get('search'):
            qs = qs.filter(name__icontains=request.query_params['search'])
        total = qs.count()
        limit, offset = _paginate(request)
        page = qs[offset:offset + limit]
        return Response({'results': [_company_json(c) for c in page],
                          'total': total, 'offset': offset, 'limit': limit})
    data = request.data
    if not str(data.get('name', '')).strip():
        return Response({'detail': 'name is required.'}, status=400)
    now = timezone.now()
    status_value = data.get('status')
    if status_value not in dict(FeedCompany.STATUS_CHOICES):
        status_value = 'active'
    company = FeedCompany.objects.create(
        name=data['name'].strip(), contact_person=data.get('contact_person', ''),
        contact_phone=data.get('contact_phone', ''), contact_email=data.get('contact_email', ''),
        address=data.get('address', ''), district=data.get('district', ''),
        upazila=data.get('upazila', ''), description=data.get('description') or None,
        logo_url=data.get('logo_url') or None, cover_url=data.get('cover_url') or None,
        license_number=data.get('license_number') or None, status=status_value,
        admin_notes=data.get('admin_notes') or None, created_by=request.user,
        created_at=now, updated_at=now,
    )
    return Response(_company_json(company), status=201)


@api_view(['GET', 'PATCH', 'DELETE'])
@permission_classes([IsAdminUser])
def company_detail(request, company_id):
    action = 'view' if request.method == 'GET' else ('suspend' if request.method == 'DELETE' else 'edit')
    if not can_perform_action(request.user, MODULE, action):
        return _forbidden(action)
    try:
        company = FeedCompany.objects.get(pk=company_id)
    except (FeedCompany.DoesNotExist, ValueError):
        return Response({'detail': 'Feed company not found.'}, status=404)
    if request.method == 'GET':
        return Response(_company_json(company))
    if request.method == 'DELETE':
        company.status = 'suspended'
        company.save(update_fields=['status', 'updated_at'])
        return Response(_company_json(company))
    data = request.data
    for field in ('name', 'contact_person', 'contact_phone', 'contact_email', 'address',
                  'district', 'upazila', 'description', 'license_number', 'admin_notes'):
        if field in data:
            setattr(company, field, data[field])
    if data.get('status') in dict(FeedCompany.STATUS_CHOICES):
        company.status = data['status']
    company.save()
    return Response(_company_json(company))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def company_logo_upload(request, company_id):
    return _company_image_upload(request, company_id, 'logo_url')


@api_view(['POST'])
@permission_classes([IsAdminUser])
def company_cover_upload(request, company_id):
    return _company_image_upload(request, company_id, 'cover_url')


def _company_image_upload(request, company_id, field):
    if not can_perform_action(request.user, MODULE, 'edit'):
        return _forbidden('edit')
    try:
        company = FeedCompany.objects.get(pk=company_id)
    except (FeedCompany.DoesNotExist, ValueError):
        return Response({'detail': 'Feed company not found.'}, status=404)
    file = request.FILES.get('file') or request.FILES.get('image')
    if not file:
        return Response({'detail': 'An image file is required (form field "file").'}, status=400)
    try:
        url = store_public_image(request, file, f'feed_companies/{company.id}/{field}')
    except UploadError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    old_url = getattr(company, field)
    setattr(company, field, url)
    company.save(update_fields=[field, 'updated_at'])
    # Only delete the old file once the new one is safely persisted above —
    # never the other way around.
    delete_public_image(old_url)
    return Response(_company_json(company), status=201)


@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def products(request):
    action = 'view' if request.method == 'GET' else 'create'
    if not can_perform_action(request.user, MODULE, action):
        return _forbidden(action)
    if request.method == 'GET':
        qs = FeedProduct.objects.select_related('company').all()
        for field in ('approval_status', 'bird_type', 'feed_type', 'company_id'):
            if request.query_params.get(field):
                qs = qs.filter(**{field: request.query_params[field]})
        if request.query_params.get('search'):
            from django.db.models import Q
            term = request.query_params['search']
            qs = qs.filter(Q(product_name__icontains=term) | Q(brand__icontains=term))
        total = qs.count()
        limit, offset = _paginate(request)
        page = qs[offset:offset + limit]
        return Response({'results': [_product_json(p) for p in page],
                          'total': total, 'offset': offset, 'limit': limit})
    data = request.data
    try:
        company = FeedCompany.objects.get(pk=data['company_id'])
    except (FeedCompany.DoesNotExist, KeyError, ValueError):
        return Response({'detail': 'A valid company_id is required.'}, status=400)
    if not str(data.get('product_name', '')).strip():
        return Response({'detail': 'product_name is required.'}, status=400)
    try:
        price = float(data.get('price', 0))
        stock = int(data.get('stock_quantity', 0))
        min_qty = int(data.get('min_order_quantity', 1))
    except (TypeError, ValueError):
        return Response({'detail': 'price/stock_quantity/min_order_quantity must be numeric.'}, status=400)
    if price < 0 or stock < 0 or min_qty < 1:
        return Response({'detail': 'price and stock_quantity must be >= 0, min_order_quantity >= 1.'}, status=400)
    now = timezone.now()
    product = FeedProduct.objects.create(
        company=company, product_name=data['product_name'].strip(), brand=data.get('brand', ''),
        feed_type=data.get('feed_type', 'other'), bird_type=data.get('bird_type', 'other'),
        description=data.get('description') or None, ingredients=data.get('ingredients') or None,
        nutritional_info=data.get('nutritional_info') or {}, unit=data.get('unit', 'kg'),
        price=price, stock_quantity=stock, min_order_quantity=min_qty,
        image_url=data.get('image_url') or None,
        approval_status='pending_review', created_by=request.user,
        created_at=now, updated_at=now,
    )
    return Response(_product_json(product), status=201)


@api_view(['GET', 'PATCH', 'DELETE'])
@permission_classes([IsAdminUser])
def product_detail(request, product_id):
    try:
        product = FeedProduct.objects.select_related('company').get(pk=product_id)
    except (FeedProduct.DoesNotExist, ValueError):
        return Response({'detail': 'Feed product not found.'}, status=404)

    if request.method == 'GET':
        if not can_perform_action(request.user, MODULE, 'view'):
            return _forbidden('view')
        return Response(_product_json(product))

    if request.method == 'DELETE':
        if not can_perform_action(request.user, MODULE, 'delete'):
            return _forbidden('delete')
        product.approval_status = 'suspended'
        product.save(update_fields=['approval_status', 'updated_at'])
        return Response(_product_json(product))

    data = request.data
    action = data.get('action')
    if action in ('approve', 'reject', 'suspend'):
        needed = action if action != 'suspend' else 'suspend'
        if not can_perform_action(request.user, MODULE, needed):
            return _forbidden(needed)
        if action == 'approve':
            product.approval_status = 'approved'
            product.approved_by = request.user
            product.rejection_reason = None
        elif action == 'reject':
            reason = str(data.get('reason', '')).strip()
            if not reason:
                return Response({'detail': 'A reason is required to reject a product.'}, status=400)
            product.approval_status = 'rejected'
            product.rejection_reason = reason
        else:  # suspend
            product.approval_status = 'suspended'
        product.save(update_fields=['approval_status', 'approved_by', 'rejection_reason', 'updated_at'])
        return Response(_product_json(product))

    if not can_perform_action(request.user, MODULE, 'edit'):
        return _forbidden('edit')
    editable = ('product_name', 'brand', 'feed_type', 'bird_type', 'description', 'ingredients',
               'nutritional_info', 'unit', 'image_url')
    for field in editable:
        if field in data:
            setattr(product, field, data[field])
    for field, cast in (('price', float), ('stock_quantity', int), ('min_order_quantity', int)):
        if field in data:
            try:
                value = cast(data[field])
            except (TypeError, ValueError):
                return Response({'detail': f'{field} must be numeric.'}, status=400)
            if value < 0 or (field == 'min_order_quantity' and value < 1):
                return Response({'detail': f'{field} is out of range.'}, status=400)
            setattr(product, field, value)
    product.save()
    return Response(_product_json(product))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def product_image_upload(request, product_id):
    """Uploads the product's primary image by default; pass gallery=1 (form
    field) to append to the gallery instead of replacing the primary image."""
    if not can_perform_action(request.user, MODULE, 'edit'):
        return _forbidden('edit')
    try:
        product = FeedProduct.objects.select_related('company').get(pk=product_id)
    except (FeedProduct.DoesNotExist, ValueError):
        return Response({'detail': 'Feed product not found.'}, status=404)
    file = request.FILES.get('file') or request.FILES.get('image')
    if not file:
        return Response({'detail': 'An image file is required (form field "file").'}, status=400)
    try:
        url = store_public_image(request, file, f'feed_products/{product.id}')
    except UploadError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    if str(request.data.get('gallery', '')).lower() in ('1', 'true'):
        gallery = list(product.gallery_urls or [])
        gallery.append(url)
        product.gallery_urls = gallery
        product.save(update_fields=['gallery_urls', 'updated_at'])
    else:
        old_url = product.image_url
        product.image_url = url
        product.save(update_fields=['image_url', 'updated_at'])
        delete_public_image(old_url)
    return Response(_product_json(product), status=201)


@api_view(['DELETE'])
@permission_classes([IsAdminUser])
def product_gallery_image_delete(request, product_id):
    if not can_perform_action(request.user, MODULE, 'edit'):
        return _forbidden('edit')
    try:
        product = FeedProduct.objects.select_related('company').get(pk=product_id)
    except (FeedProduct.DoesNotExist, ValueError):
        return Response({'detail': 'Feed product not found.'}, status=404)
    url = request.query_params.get('url')
    gallery = list(product.gallery_urls or [])
    if url in gallery:
        gallery.remove(url)
        product.gallery_urls = gallery
        product.save(update_fields=['gallery_urls', 'updated_at'])
        delete_public_image(url)
    return Response(_product_json(product))
