"""Security monitor — real signals instead of the JSON seed rows.

Combines:
  * content-abuse flags written by ``research.views._flag_content``
    (``backend_admin_records`` module ``security-flags``)
  * brute-force: >= 8 failed logins from one IP in the last hour
    (``activity_logs`` ``action_type='login'`` rows)
  * impossible travel: one account authenticating from 3+ distinct IPs in 2 hours
  * action spikes: an admin with >= 40 mutations in 10 minutes

Derived flags carry ids like ``derived:bruteforce:<ip>``; "clear" stores a
suppression marker in ``backend_admin_records`` so they don't re-surface.
"""
from collections import Counter, defaultdict

from django.utils import timezone

from audit.models import ActivityLog, AdminPanelRecord

_SUPPRESS_MODULE = 'security-flags-cleared'


def _suppressed_ids():
    return set(
        AdminPanelRecord.objects.filter(module=_SUPPRESS_MODULE)
        .values_list('record_id', flat=True)
    )


def security_rows(request):
    now = timezone.now()
    suppressed = _suppressed_ids()
    rows = []

    # 1. real content-abuse flags (AdminPanelRecord)
    for rec in AdminPanelRecord.objects.filter(module='security-flags').order_by('-created_at'):
        payload = rec.payload
        if rec.record_id in suppressed or payload.get('cleared'):
            continue
        rows.append({
            'id': rec.record_id,
            'user': payload.get('user', 'Unknown'),
            'type': payload.get('type', 'Content Abuse'),
            'severity': payload.get('severity', 'Medium'),
            'description': payload.get('description', ''),
            'date': payload.get('date', rec.created_at.strftime('%b %d, %Y')),
            'cleared': False,
        })

    # 2/3. login-derived signals (DB does the time-window filtering)
    window = now - timezone.timedelta(hours=2)
    hour_ago = now - timezone.timedelta(hours=1)
    logins_2h = list(
        ActivityLog.objects.filter(action_type='login', created_at__gte=window)
        .values('ip_address', 'new_values')
    )
    logins_1h_ips = list(
        ActivityLog.objects.filter(action_type='login', created_at__gte=hour_ago)
        .values('ip_address', 'new_values')
    )

    ips_by_email = defaultdict(set)
    for row in logins_2h:
        nv = row.get('new_values') or {}
        if nv.get('success') and row['ip_address']:
            ips_by_email[nv.get('email', '')].add(row['ip_address'])

    failed_recent = Counter()
    for row in logins_1h_ips:
        nv = row.get('new_values') or {}
        if nv.get('success') is False:
            failed_recent[row['ip_address']] += 1
    for ip, count in failed_recent.items():
        if not ip or count < 8:
            continue
        fid = f'derived:bruteforce:{ip}'
        if fid in suppressed:
            continue
        rows.append({
            'id': fid, 'user': f'IP {ip}', 'type': 'Brute Force', 'severity': 'Critical',
            'description': f'{count} failed login attempts from {ip} in the last hour',
            'date': now.strftime('%b %d, %Y'), 'cleared': False,
        })

    for email, ips in ips_by_email.items():
        if len(ips) < 3:
            continue
        fid = f'derived:travel:{email}'
        if fid in suppressed:
            continue
        rows.append({
            'id': fid, 'user': email, 'type': 'Suspicious Activity', 'severity': 'High',
            'description': f'Account authenticated from {len(ips)} distinct IPs in 2 hours',
            'date': now.strftime('%b %d, %Y'), 'cleared': False,
        })

    # 4. admin action spikes (last 10 minutes)
    spike_window = now - timezone.timedelta(minutes=10)
    spikes = Counter(
        ActivityLog.objects.filter(created_at__gte=spike_window)
        .exclude(action_type__in=['login', 'view'])
        .values_list('user__email', flat=True)
    )
    for email, count in spikes.items():
        if not email or count < 40:
            continue
        fid = f'derived:spike:{email}'
        if fid in suppressed:
            continue
        rows.append({
            'id': fid, 'user': email, 'type': 'Content Abuse', 'severity': 'Medium',
            'description': f'{count} admin actions in 10 minutes',
            'date': now.strftime('%b %d, %Y'), 'cleared': False,
        })

    return rows


def clear_flag(request, record_id):
    if record_id.startswith('derived:'):
        AdminPanelRecord.objects.get_or_create(
            module=_SUPPRESS_MODULE, record_id=record_id,
            defaults={'payload': {'cleared_by': str(request.user.id),
                                  'cleared_at': timezone.now().isoformat()}},
        )
        return {'id': record_id, 'cleared': True}
    rec = AdminPanelRecord.objects.filter(module='security-flags', record_id=record_id).first()
    if rec:
        rec.payload = {**rec.payload, 'cleared': True}
        rec.save(update_fields=['payload', 'updated_at'])
    else:
        AdminPanelRecord.objects.get_or_create(
            module=_SUPPRESS_MODULE, record_id=record_id,
            defaults={'payload': {'cleared_at': timezone.now().isoformat()}})
    return {'id': record_id, 'cleared': True}
