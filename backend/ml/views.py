"""Disease-detection API.

    POST /api/ml/predict-disease/   run the model on an uploaded photo
    GET  /api/ml/scans/             the farmer's recent scans ("Recent Cases")
    GET  /api/ml/scans/<uuid>/      one scan with full advice
    GET  /api/ml/diseases/<uuid>/   reference card for a disease (chatbot / info panel)
    GET  /api/ml/health/            model status (no image run)
"""
import os
import uuid as _uuid
from decimal import Decimal

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle

from consultations.permissions import IsFarmer
from farms.models import Farm, Flock

from . import content, inference
from .models import DiseaseRef, DiseaseScan

MAX_IMAGE_BYTES = 5 * 1024 * 1024
ALLOWED_IMAGE_EXT = {'jpg', 'jpeg', 'png', 'webp'}
DISCLAIMER = ('This is an AI estimate from a photo, not a diagnosis. Always confirm '
              'with a qualified veterinarian before treating your birds.')

# Below this top-1 probability we do not name a disease — we return "Uncertain"
# and push the farmer toward a vet. Tune with the env var; see ML/README-ML.md.
CONFIDENCE_THRESHOLD = float(os.environ.get('DISEASE_CONFIDENCE_THRESHOLD', '0.45'))


class DiseasePredictThrottle(UserRateThrottle):
    scope = 'disease_predict'


# ── helpers ──────────────────────────────────────────────────────────────────

def _disease_ref(label, meta):
    """get-or-create the `diseases` reference row for a predicted label.

    A "Healthy" row is kept too (severity NULL) so a saved scan can be told
    apart from an "uncertain" one, which has no linked disease at all.
    """
    try:
        ref, _ = DiseaseRef.objects.get_or_create(
            name=label,
            defaults=dict(
                description=meta['description'],
                symptoms=meta['symptoms'],
                what_to_do='\n'.join(meta['what_to_do']),
                what_not_to_do='\n'.join(meta['what_not_to_do']),
                prevention_tips='\n'.join(meta['prevention']),
                severity_level=content.DB_SEVERITY[meta['severity']],
                requires_immediate_vet=meta['requires_immediate_vet'],
            ),
        )
        return ref
    except Exception:  # noqa: BLE001 — a missing reference must not fail a scan
        return None


def _advice_payload(meta, *, uncertain, confidence):
    severity = None if uncertain else meta['severity']
    return {
        'disease': content.UNCERTAIN['label'] if uncertain else meta['label'],
        'is_healthy': (not uncertain) and meta['severity'] is None,
        'uncertain': uncertain,
        'confidence': round(confidence, 4),
        'severity': (content.UNCERTAIN['severity'] if uncertain else severity),
        'requires_immediate_vet': (content.UNCERTAIN if uncertain else meta)['requires_immediate_vet'],
        'notifiable': (content.UNCERTAIN if uncertain else meta).get('notifiable', False),
        'description': (content.UNCERTAIN if uncertain else meta)['description'],
        'symptoms': (content.UNCERTAIN if uncertain else meta)['symptoms'],
        'recommendations': (content.UNCERTAIN if uncertain else meta)['what_to_do'],
        'avoid': (content.UNCERTAIN if uncertain else meta)['what_not_to_do'],
        'prevention': (content.UNCERTAIN if uncertain else meta)['prevention'],
        'urgency': 'urgent' if (content.UNCERTAIN if uncertain else meta)['requires_immediate_vet']
        or (not uncertain and meta['severity'] in ('high', 'critical')) else 'routine',
        'disclaimer': DISCLAIMER,
    }


def _scan_row(scan):
    meta = None
    label = None
    if scan.detected_disease_id:
        label = scan.detected_disease.name
        meta = content.meta_by_label(label)
    row = {
        'scan_id': str(scan.id),
        'disease': label or (content.UNCERTAIN['label'] if scan.scan_status == 'completed'
                             else 'Processing'),
        'confidence': float(scan.confidence_score) / 100 if scan.confidence_score is not None else None,
        'severity': scan.severity_level,
        'image_url': (scan.image_urls or [None])[0],
        'status': scan.scan_status,
        'created_at': scan.created_at.isoformat() if scan.created_at else None,
        'disease_ref_id': str(scan.detected_disease_id) if scan.detected_disease_id else None,
    }
    if meta:
        row.update(_advice_payload(meta, uncertain=False,
                                   confidence=row['confidence'] or 0))
    elif scan.scan_status == 'completed':
        row.update(_advice_payload(content.UNCERTAIN, uncertain=True,
                                   confidence=row['confidence'] or 0))
    return row


# ── endpoints ────────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsFarmer])
@throttle_classes([DiseasePredictThrottle])
def predict_disease(request):
    upload = request.FILES.get('image') or request.FILES.get('file')
    if upload is None:
        return Response({'detail': 'Attach a photo in the "image" field.'}, status=400)
    if upload.size > MAX_IMAGE_BYTES:
        return Response({'detail': 'Image must be 5 MB or smaller.'}, status=400)
    ext = upload.name.rsplit('.', 1)[-1].lower() if '.' in (upload.name or '') else ''
    ctype = str(upload.content_type or '')
    # Accept if the content-type says image/* OR the extension is a known image
    # type (desktop pickers often send application/octet-stream). The bytes are
    # verified for real by Pillow in inference.predict().
    if not ctype.startswith('image/') and ext not in ALLOWED_IMAGE_EXT:
        return Response({'detail': 'Only JPG, PNG or WebP images are supported.'}, status=400)

    image_bytes = upload.read()

    # optional flock link (must belong to this farmer)
    farm = Farm.objects.filter(farmer__user=request.user, is_active=True).first()
    flock = None
    flock_id = request.data.get('flock_id')
    if flock_id:
        flock = Flock.objects.filter(id=flock_id, farm=farm).first()

    scan = DiseaseScan.objects.create(
        user=request.user,
        farm_id=farm.id if farm else None,
        flock_id=flock.id if flock else None,
        image_urls=[], scan_status='processing', is_free_scan=True,
    )

    # persist the image (best effort — a storage hiccup shouldn't lose the result)
    try:
        stamp = timezone.now().strftime('%Y%m%d%H%M%S')
        path = default_storage.save(
            f'disease-scans/{request.user.id}/{stamp}_{_uuid.uuid4().hex[:8]}.{ext}',
            ContentFile(image_bytes))
        image_url = request.build_absolute_uri(default_storage.url(path))
        scan.image_urls = [image_url]
    except Exception:  # noqa: BLE001
        image_url = None

    # inference
    try:
        ranked, image_ok = inference.predict(image_bytes, top_k=5)
    except inference.ModelUnavailable as exc:
        scan.scan_status = 'failed'
        scan.save(update_fields=['scan_status', 'image_urls'])
        return Response({'detail': str(exc), 'code': 'model_unavailable'}, status=503)

    if not image_ok:
        scan.scan_status = 'failed'
        scan.image_quality_status = 'rejected'
        scan.save(update_fields=['scan_status', 'image_quality_status', 'image_urls'])
        return Response({'detail': 'That file could not be read as an image.'}, status=400)

    top = ranked[0]
    top_conf = top['confidence']
    uncertain = top_conf < CONFIDENCE_THRESHOLD
    meta = content.meta_for(top['raw_label'])
    # link a diseases row for any confident result (incl. "Healthy"); an
    # uncertain scan is left with no disease so history can tell them apart.
    ref = None if uncertain else _disease_ref(meta['label'], meta)

    scan.detected_disease = ref
    scan.confidence_score = Decimal(str(round(top_conf * 100, 2)))
    scan.severity_level = None if uncertain else content.DB_SEVERITY[meta['severity']]
    scan.scan_status = 'completed'
    scan.image_quality_status = 'good'
    scan.save()

    _log(request.user, scan, top['raw_label'], top_conf)

    payload = {
        'scan_id': str(scan.id),
        'created_at': scan.created_at.isoformat() if scan.created_at else timezone.now().isoformat(),
        'image_url': image_url,
        'disease_ref_id': str(ref.id) if ref else None,
        'all_predictions': [
            {'disease': content.meta_for(r['raw_label'])['label'],
             'confidence': round(r['confidence'], 4)}
            for r in ranked
        ],
        **_advice_payload(meta, uncertain=uncertain, confidence=top_conf),
    }
    return Response(payload, status=201)


@api_view(['GET'])
@permission_classes([IsFarmer])
def scans(request):
    limit = min(int(request.query_params.get('limit', 10) or 10), 50)
    qs = (DiseaseScan.objects.filter(user=request.user, scan_status='completed')
          .select_related('detected_disease')[:limit])
    return Response({'results': [_scan_row(s) for s in qs]})


@api_view(['GET'])
@permission_classes([IsFarmer])
def scan_detail(request, scan_id):
    try:
        scan = DiseaseScan.objects.select_related('detected_disease').get(
            id=scan_id, user=request.user)
    except (DiseaseScan.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Scan not found.'}, status=404)
    return Response(_scan_row(scan))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def disease_detail(request, disease_id):
    """Reference card — powers the disease info / "ask the assistant" panel."""
    try:
        ref = DiseaseRef.objects.get(id=disease_id)
    except (DiseaseRef.DoesNotExist, ValueError, TypeError):
        return Response({'detail': 'Disease not found.'}, status=404)
    meta = content.meta_by_label(ref.name)
    body = {
        'id': str(ref.id), 'disease': ref.name,
        'description': meta['description'] if meta else ref.description,
        'symptoms': meta['symptoms'] if meta else (ref.symptoms or []),
        'recommendations': meta['what_to_do'] if meta else _lines(ref.what_to_do),
        'avoid': meta['what_not_to_do'] if meta else _lines(ref.what_not_to_do),
        'prevention': meta['prevention'] if meta else _lines(ref.prevention_tips or ''),
        'severity': (meta['severity'] if meta else ref.severity_level),
        'requires_immediate_vet': ref.requires_immediate_vet,
        'notifiable': meta.get('notifiable', False) if meta else False,
        'disclaimer': DISCLAIMER,
    }
    return Response(body)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def health(request):
    return Response({**inference.model_info(),
                     'confidence_threshold': CONFIDENCE_THRESHOLD})


# ── internals ────────────────────────────────────────────────────────────────

def _lines(text):
    return [ln.strip() for ln in (text or '').splitlines() if ln.strip()]


def _log(user, scan, raw_label, confidence):
    try:
        from audit.models import ActivityLog
        ActivityLog.objects.create(
            user=user, module='disease_detection', action='Disease scan',
            action_type='create', entity_type='disease_scan', entity_id=scan.id,
            new_values={'raw_label': raw_label, 'confidence': round(confidence, 4)},
        )
    except Exception:  # noqa: BLE001 — audit must never break the scan
        pass
