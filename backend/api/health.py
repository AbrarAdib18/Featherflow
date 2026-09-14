"""Liveness/readiness endpoints for load balancers, container orchestrators,
and uptime monitors. Unauthenticated by design (that's the point of a health
check) but deliberately reveal nothing about the app beyond up/down.
"""
import time

from django.core.cache import cache
from django.db import connections
from django.db.utils import OperationalError
from rest_framework.decorators import api_view, permission_classes, authentication_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(['GET'])
@authentication_classes([])
@permission_classes([AllowAny])
def liveness(request):
    """Is the process up and serving requests at all? No dependency checks —
    a DB/cache outage should not make the orchestrator kill/restart healthy
    app instances that can't fix the outage anyway (that's what readiness is
    for: taking the instance out of the load-balancer pool instead)."""
    return Response({'status': 'ok'})


@api_view(['GET'])
@authentication_classes([])
@permission_classes([AllowAny])
def readiness(request):
    """Can this instance actually serve real requests right now?"""
    checks = {}
    healthy = True

    started = time.monotonic()
    try:
        with connections['default'].cursor() as cursor:
            cursor.execute('SELECT 1')
        checks['database'] = {'ok': True, 'latency_ms': round((time.monotonic() - started) * 1000, 1)}
    except OperationalError:
        healthy = False
        checks['database'] = {'ok': False, 'error': 'unavailable'}

    started = time.monotonic()
    try:
        marker = '__health_check__'
        cache.set(marker, '1', timeout=5)
        ok = cache.get(marker) == '1'
        checks['cache'] = {'ok': ok, 'latency_ms': round((time.monotonic() - started) * 1000, 1)}
        healthy = healthy and ok
    except Exception:
        healthy = False
        checks['cache'] = {'ok': False, 'error': 'unavailable'}

    return Response({'status': 'ok' if healthy else 'degraded', 'checks': checks},
                     status=200 if healthy else 503)
