"""Admin proof-of-delivery review queue (fault F-005).

    GET  /api/admin-panel/delivery-proofs/?status=submitted|rejected|approved|all
    GET  /api/admin-panel/delivery-proofs/<proof_id>/        (proof + attempts + state history)
    POST /api/admin-panel/delivery-proofs/<proof_id>/approve/  -> order becomes `delivered`
    POST /api/admin-panel/delivery-proofs/<proof_id>/reject/   {"reason": "..."} (required)

Authorization is server-side and object-level, per order type:
  * any order      : `delivery` module (Super / Operations / Delivery Admin)
  * feed delivery  : also `feed-delivery` module (Feed Marketplace Admin)
  * pharmacy order : also `pharmacy` module (Pharmacy Admin)
"""
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from api.admin_rbac import IsAdminUser, can_perform_action
from audit.models import AdminPanelRecord
from delivery import lifecycle
from delivery.models import DeliveryOrder, DeliveryProof
from delivery.views import _create_earning, _sync_source


def _modules_for(order):
    mods = [('delivery', None)]
    if order.order_type == 'marketplace':
        mods.append(('feed-delivery', None))
    else:
        mods.append(('pharmacy', None))
    return [m for m, _ in mods]


def _can(user, order, action):
    """`action` is view/approve/reject. Pharmacy Admin's pharmacy module has no
    `reject` verb split from `approve` semantics, so approve/reject both map to
    `approve`/`reject` as stored in roles.permissions."""
    return any(can_perform_action(user, m, action) for m in _modules_for(order))


def _forbidden(action):
    return Response({'detail': f'Your admin role cannot "{action}" delivery proofs for this order.',
                     'code': 'forbidden_module_action'}, status=403)


def _source(order):
    module = 'feed-orders' if order.order_type == 'marketplace' else 'pharmacy-orders'
    return AdminPanelRecord.objects.filter(module=module, id=order.order_reference_id).first()


def _row(proof, order, source=None, detail=False):
    payload = (source.payload if source else {}) or {}
    rider = order.delivery_person.user
    data = {
        **lifecycle.proof_json(proof),
        'order_id': str(order.id),
        'order_number': payload.get('order_number') or payload.get('id') or str(order.order_reference_id)[:8].upper(),
        'order_type': 'feed' if order.order_type == 'marketplace' else 'pharmacy',
        'customer': payload.get('farmer_name', ''),
        'destination': order.delivery_address,
        'rider': rider.full_name or rider.email,
        'rider_phone': rider.phone or '',
        'order_status': order.status,
        'order_stage_label': lifecycle.STAGE_LABELS.get(order.status, order.status),
        'attempts': order.proofs.count(),
    }
    if detail:
        data['proofs'] = [lifecycle.proof_json(p) for p in order.proofs.select_related('reviewed_by').order_by('attempt')]
        data['events'] = [lifecycle.event_json(e) for e in order.events.select_related('actor').order_by('created_at')]
    return data


@api_view(['GET'])
@permission_classes([IsAdminUser])
def proofs_list(request):
    status = request.query_params.get('status', 'submitted')
    qs = DeliveryProof.objects.select_related(
        'delivery_order__delivery_person__user', 'reviewed_by').order_by('-submitted_at')
    if status != 'all':
        if status not in ('submitted', 'approved', 'rejected'):
            return Response({'detail': 'status must be submitted, approved, rejected or all.'}, status=400)
        qs = qs.filter(status=status)
    try:
        limit = min(int(request.query_params.get('limit', 50)), 200)
        offset = max(int(request.query_params.get('offset', 0)), 0)
    except (TypeError, ValueError):
        limit, offset = 50, 0
    rows, total = [], 0
    for p in qs:
        o = p.delivery_order
        if not _can(request.user, o, 'view'):
            continue
        total += 1
        if offset < total <= offset + limit:
            rows.append(_row(p, o, _source(o)))
    return Response({'results': rows, 'total': total, 'limit': limit, 'offset': offset})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def proof_detail(request, proof_id):
    proof = DeliveryProof.objects.select_related('delivery_order__delivery_person__user', 'reviewed_by').filter(pk=proof_id).first()
    if proof is None:
        return Response({'detail': 'Proof not found.'}, status=404)
    order = proof.delivery_order
    if not _can(request.user, order, 'view'):
        return _forbidden('view')
    return Response(_row(proof, order, _source(order), detail=True))


def _decide(request, proof_id, action):
    proof = DeliveryProof.objects.select_related('delivery_order').filter(pk=proof_id).first()
    if proof is None:
        return Response({'detail': 'Proof not found.'}, status=404)
    order = proof.delivery_order
    if not _can(request.user, order, action):
        return _forbidden(action)
    try:
        if action == 'approve':
            order, proof = lifecycle.approve_proof(
                proof_id, request.user, sync=_sync_source, create_earning=_create_earning, request=request)
        else:
            order, proof = lifecycle.reject_proof(
                proof_id, request.user, request.data.get('reason', ''), sync=_sync_source, request=request)
    except lifecycle.LifecycleError as exc:
        return Response({'detail': exc.detail}, status=exc.status)
    order = DeliveryOrder.objects.select_related('delivery_person__user').get(pk=order.pk)
    return Response(_row(proof, order, _source(order), detail=True))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def proof_approve(request, proof_id):
    return _decide(request, proof_id, 'approve')


@api_view(['POST'])
@permission_classes([IsAdminUser])
def proof_reject(request, proof_id):
    return _decide(request, proof_id, 'reject')
