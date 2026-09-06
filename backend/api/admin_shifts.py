"""Admin Shift Timer + Hourly Payment.

Design (per the approved decisions):
  * weekly Mon–Sun periods (server TZ = Asia/Dhaka), manual payroll generation
  * breaks are unpaid; a single logged break per shift is subtracted
  * a shift that spans midnight stays one row — per-day / per-week hours are
    computed here by interval overlap, so both calendar days get credit
  * overtime = 1.5x for hours beyond ``AdminProfile.max_hours_per_week``
  * a rate change takes effect the following Monday (``pending_hourly_rate`` /
    ``pending_rate_effective_from``); the amount actually paid for a period is
    snapshotted onto the ``AdminPayment`` row
  * Super Admin (tier 1) is the platform owner — no shifts, no payments

All DB datetimes are naive-UTC wall-clock (schema columns are
``timestamp without time zone``); ``_aware`` labels them UTC before any maths,
matching ``delivery/views.py``.
"""
import csv
import io
from datetime import timedelta, timezone as dt_timezone
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from audit.models import ActivityLog
from notifications.models import Notification
from profiles.models import AdminPayment, AdminProfile, AdminShift
from users.models import User

from api.admin_rbac import IsAdminUser, admin_tier, is_super_admin

FLAG_AFTER = timedelta(hours=16)          # a shift open longer than this is flagged
OVERTIME_MULTIPLIER = Decimal('1.5')
TWO_DP = Decimal('0.01')


# ── time helpers ───────────────────────────────────────────────────────────

def _aware(dt):
    if dt is not None and timezone.is_naive(dt):
        return dt.replace(tzinfo=dt_timezone.utc)
    return dt


def _now():
    return timezone.now()


def _local(dt):
    return timezone.localtime(_aware(dt))


def _week_bounds(dt=None):
    """[Monday 00:00, next Monday 00:00) of the local week containing ``dt``."""
    local = _local(dt or _now())
    sod = local.replace(hour=0, minute=0, second=0, microsecond=0)
    monday = sod - timedelta(days=sod.weekday())
    return monday, monday + timedelta(days=7)


def _month_bounds(dt=None):
    local = _local(dt or _now())
    start = local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end = (start.replace(year=start.year + 1, month=1) if start.month == 12
           else start.replace(month=start.month + 1))
    return start, end


def _day_bounds(dt=None):
    local = _local(dt or _now())
    sod = local.replace(hour=0, minute=0, second=0, microsecond=0)
    return sod, sod + timedelta(days=1)


def _overlap_seconds(a0, a1, r0, r1):
    if a0 is None or a1 is None:
        return 0.0
    lo, hi = max(a0, r0), min(a1, r1)
    return max(0.0, (hi - lo).total_seconds())


def _shift_hours_in_range(shift, r0, r1):
    """Paid hours of ``shift`` that fall inside [r0, r1) — work overlap minus the
    portion of the logged break that also falls in the window."""
    start = _aware(shift.start_time)
    end = _aware(shift.end_time) or _now()
    work = _overlap_seconds(start, end, r0, r1)
    brk = 0.0
    if shift.break_start and shift.break_end:
        brk = _overlap_seconds(_aware(shift.break_start), _aware(shift.break_end), r0, r1)
    return max(0.0, (work - brk) / 3600.0)


def _dec(x):
    return Decimal(str(round(float(x), 4))).quantize(TWO_DP, rounding=ROUND_HALF_UP)


def _hours_between(admin, r0, r1):
    total = sum(
        _shift_hours_in_range(s, r0, r1)
        for s in admin.shifts.filter(start_time__lt=r1).exclude(
            end_time__isnull=False, end_time__lt=r0)
    )
    return _dec(total)


# ── profile / guard helpers ────────────────────────────────────────────────

def _admin_profile(user):
    try:
        return user.admin_profile
    except AdminProfile.DoesNotExist:
        return None


def _hourly_admin_or_response(request):
    """The caller's AdminProfile if they are an hourly admin (tier 2-4), else a
    403 Response. Super Admin is the owner and has no shift/pay."""
    if is_super_admin(request.user):
        return None, Response(
            {'detail': 'Super Admin is the platform owner and does not track shifts or payment.'},
            status=403)
    profile = _admin_profile(request.user)
    if profile is None:
        return None, Response({'detail': 'No admin profile for this account.'}, status=404)
    return profile, None


def _client_ip(request):
    fwd = request.META.get('HTTP_X_FORWARDED_FOR')
    return fwd.split(',')[0].strip() if fwd else request.META.get('REMOTE_ADDR')


def _audit(request, action, action_type, target_id=None, old=None, new=None, reason=''):
    ActivityLog.objects.create(
        user=request.user, module='shifts' if 'shift' in action_type else 'payments',
        action=action, action_type=action_type, entity_type='admin_shift',
        entity_id=target_id, old_values=old, new_values=new, reason=reason or None,
        ip_address=_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:1000] or None,
    )


# ── serialisers ────────────────────────────────────────────────────────────

def _shift_json(shift):
    start, end = _aware(shift.start_time), _aware(shift.end_time)
    return {
        'id': str(shift.id),
        'shift_date': shift.shift_date.isoformat() if shift.shift_date else None,
        'start_time': start.isoformat() if start else None,
        'end_time': end.isoformat() if end else None,
        'break_start': _aware(shift.break_start).isoformat() if shift.break_start else None,
        'break_end': _aware(shift.break_end).isoformat() if shift.break_end else None,
        'break_minutes': shift.break_duration_minutes,
        'total_hours': float(shift.total_hours),
        'is_active': shift.is_active,
        'on_break': shift.on_break,
        'auto_flagged': shift.auto_flagged,
    }


def _status_payload(profile):
    now = _now()
    active = profile.shifts.filter(is_active=True).first()
    wk0, wk1 = _week_bounds()
    mo0, mo1 = _month_bounds()
    dy0, dy1 = _day_bounds()
    elapsed_today = float(_hours_between(profile, dy0, dy1))
    rate = profile.effective_hourly_rate()
    payload = {
        'is_on_shift': active is not None,
        'on_break': bool(active and active.on_break),
        'active_shift': _shift_json(active) if active else None,
        'seconds_elapsed': int(round(
            _shift_hours_in_range(active, _aware(active.start_time), now) * 3600)) if active else 0,
        'hours_today': elapsed_today,
        'hours_this_week': float(_hours_between(profile, wk0, wk1)),
        'hours_this_month': float(_hours_between(profile, mo0, mo1)),
        'hourly_rate': float(rate),
        'pending_hourly_rate': float(profile.pending_hourly_rate) if profile.pending_hourly_rate is not None else None,
        'pending_rate_effective_from': profile.pending_rate_effective_from.isoformat() if profile.pending_rate_effective_from else None,
        'max_hours_per_week': profile.max_hours_per_week,
        'week_start': wk0.date().isoformat(),
    }
    if profile.max_hours_per_week:
        payload['over_max_hours'] = payload['hours_this_week'] > profile.max_hours_per_week
    return payload


def _payment_json(p):
    return {
        'id': str(p.id),
        'admin': (p.admin.user.full_name or p.admin.user.email),
        'admin_id': str(p.admin_id),
        'period_start': p.period_start.isoformat(),
        'period_end': p.period_end.isoformat(),
        'total_hours': float(p.total_hours),
        'regular_hours': float(p.regular_hours),
        'overtime_hours': float(p.overtime_hours),
        'hourly_rate': float(p.hourly_rate),
        'overtime_rate': float(p.overtime_rate),
        'total_payment': float(p.total_payment),
        'status': p.payment_status,
        'payment_date': _aware(p.payment_date).isoformat() if p.payment_date else None,
        'payment_method': p.payment_method,
        'payment_reference': p.payment_reference or '',
        'notes': p.notes or '',
    }


# ══ OWN SHIFT — every hourly admin ═════════════════════════════════════════

@api_view(['GET'])
@permission_classes([IsAdminUser])
def my_shift_status(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    return Response(_status_payload(profile))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def my_shift_start(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    if profile.shifts.filter(is_active=True).exists():
        return Response({'detail': 'You are already on shift.', 'code': 'already_on_shift'}, status=409)
    now = _now()
    with transaction.atomic():
        shift = AdminShift.objects.create(
            admin=profile, shift_date=_local(now).date(), start_time=now,
            is_active=True, ip_address=_client_ip(request), created_at=now,
        )
        profile.last_shift_start = now
        profile.save(update_fields=['last_shift_start', 'updated_at'])
    _audit(request, 'Started shift', 'shift_start', shift.id)
    _notify_super('shift_started', f'{profile.user.full_name or profile.user.email} started their shift.',
                  reference_id=shift.id)
    return Response(_status_payload(profile), status=201)


@api_view(['POST'])
@permission_classes([IsAdminUser])
def my_shift_end(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    shift = profile.shifts.filter(is_active=True).first()
    if shift is None:
        return Response({'detail': 'You are not on shift.', 'code': 'not_on_shift'}, status=409)
    _close_shift(shift, ended_by=None)
    _audit(request, 'Ended shift', 'shift_end', shift.id,
           new={'total_hours': float(shift.total_hours)})
    _notify_super('shift_ended',
                  f'{profile.user.full_name or profile.user.email} ended their shift '
                  f'({shift.total_hours} h).', reference_id=shift.id)
    return Response(_status_payload(profile))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def my_break_start(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    shift = profile.shifts.filter(is_active=True).first()
    if shift is None:
        return Response({'detail': 'Start a shift before taking a break.'}, status=409)
    if shift.break_start and not shift.break_end:
        return Response({'detail': 'You are already on a break.'}, status=409)
    if shift.break_start and shift.break_end:
        return Response({'detail': 'This shift already had its break. Breaks are once per shift.'}, status=409)
    shift.break_start = _now()
    shift.save(update_fields=['break_start', 'updated_at'])
    _audit(request, 'Started break', 'break_start', shift.id)
    return Response(_status_payload(profile))


@api_view(['POST'])
@permission_classes([IsAdminUser])
def my_break_end(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    shift = profile.shifts.filter(is_active=True).first()
    if shift is None or not shift.break_start or shift.break_end:
        return Response({'detail': 'You are not on a break.'}, status=409)
    now = _now()
    shift.break_end = now
    shift.break_duration_minutes = int(round(
        (_aware(now) - _aware(shift.break_start)).total_seconds() / 60))
    shift.save(update_fields=['break_end', 'break_duration_minutes', 'updated_at'])
    _audit(request, 'Ended break', 'break_end', shift.id,
           new={'break_minutes': shift.break_duration_minutes})
    return Response(_status_payload(profile))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def my_shift_hours(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    wk0, wk1 = _week_bounds()
    mo0, mo1 = _month_bounds()
    # per-day breakdown for the current week (handles the midnight split)
    days = []
    for i in range(7):
        d0 = wk0 + timedelta(days=i)
        days.append({'date': d0.date().isoformat(),
                     'hours': float(_hours_between(profile, d0, d0 + timedelta(days=1)))})
    return Response({
        'week_start': wk0.date().isoformat(),
        'hours_this_week': float(_hours_between(profile, wk0, wk1)),
        'hours_this_month': float(_hours_between(profile, mo0, mo1)),
        'per_day': days,
        'max_hours_per_week': profile.max_hours_per_week,
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def my_shift_history(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    qs = profile.shifts.all()[:200]
    return Response({'results': [_shift_json(s) for s in qs]})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def my_payments(request):
    profile, err = _hourly_admin_or_response(request)
    if err:
        return err
    return Response({'results': [_payment_json(p) for p in profile.payments.all()[:100]]})


def _close_shift(shift, ended_by=None):
    now = _now()
    fields = ['end_time', 'is_active', 'total_hours', 'updated_at']
    shift.end_time = now
    shift.is_active = False
    if ended_by is not None:
        shift.ended_by = ended_by
        fields.append('ended_by')
    # if a break was left open, close it at end-of-shift
    if shift.break_start and not shift.break_end:
        shift.break_end = now
        shift.break_duration_minutes = int(round(
            (_aware(now) - _aware(shift.break_start)).total_seconds() / 60))
        fields += ['break_end', 'break_duration_minutes']
    worked = (_aware(now) - _aware(shift.start_time)).total_seconds() / 3600.0
    shift.total_hours = _dec(max(0.0, worked - shift.break_duration_minutes / 60.0))
    # update_fields only — a bare save() would re-write the naive start_time
    # column through Django's "assume local tz" path and shift it by the offset.
    shift.save(update_fields=fields)
    return shift


def _notify_super(kind, body, reference_id=None):
    for admin in User.objects.filter(roles__name='admin_super').distinct():
        Notification.objects.create(
            user=admin, title={'shift_started': 'Admin on shift',
                               'shift_ended': 'Admin off shift'}.get(kind, 'Shift update'),
            body=body, notification_type='system',
            reference_id=reference_id, reference_type='admin_shift',
        )


# ══ SUPER ADMIN — team & payroll ═══════════════════════════════════════════

def _require_super(request):
    if not is_super_admin(request.user):
        return Response({'detail': 'Super Admin only.'}, status=403)
    return None


def _all_admin_profiles():
    return (AdminProfile.objects.select_related('user', 'admin_role')
            .prefetch_related('user__roles')
            .exclude(admin_role__name='admin_super'))


def _admin_row(profile):
    wk0, wk1 = _week_bounds()
    mo0, mo1 = _month_bounds()
    hrs_week = _hours_between(profile, wk0, wk1)
    rate = profile.effective_hourly_rate(wk0.date())
    regular, overtime = _split_regular_overtime(hrs_week, profile.max_hours_per_week)
    due = (regular * rate + overtime * rate * OVERTIME_MULTIPLIER).quantize(TWO_DP)
    active = profile.shifts.filter(is_active=True).first()
    role = profile.admin_role
    return {
        'id': str(profile.id),
        'user_id': str(profile.user_id),
        'name': profile.user.full_name or profile.user.email,
        'email': profile.user.email,
        'role': role.name if role else None,
        'role_display': role.display_name if role else 'Admin',
        'tier': role.tier_level if role else None,
        'department': profile.department,
        'hourly_rate': float(rate),
        'pending_hourly_rate': float(profile.pending_hourly_rate) if profile.pending_hourly_rate is not None else None,
        'pending_rate_effective_from': profile.pending_rate_effective_from.isoformat() if profile.pending_rate_effective_from else None,
        'rate_range': [float(role.hourly_rate_range_min or 0), float(role.hourly_rate_range_max or 0)] if role else [0, 0],
        'max_hours_per_week': profile.max_hours_per_week,
        'hours_this_week': float(hrs_week),
        'hours_this_month': float(_hours_between(profile, mo0, mo1)),
        'regular_hours_week': float(regular),
        'overtime_hours_week': float(overtime),
        'payment_due_this_week': float(due),
        'is_on_shift': active is not None,
        'on_break': bool(active and active.on_break),
        'shift_started_at': _aware(active.start_time).isoformat() if active else None,
        'is_suspended': profile.is_suspended,
        'last_shift_start': _aware(profile.last_shift_start).isoformat() if profile.last_shift_start else None,
    }


def _split_regular_overtime(hours, max_week):
    hours = Decimal(str(hours))
    if not max_week or hours <= max_week:
        return _dec(hours), Decimal('0.00')
    return _dec(max_week), _dec(hours - max_week)


@api_view(['GET'])
@permission_classes([IsAdminUser])
def all_admins(request):
    denied = _require_super(request)
    if denied:
        return denied
    rows = [_admin_row(p) for p in _all_admin_profiles()]
    return Response({
        'results': rows,
        'summary': {
            'total_admins': len(rows),
            'on_shift': sum(1 for r in rows if r['is_on_shift']),
            'payment_due_this_week': round(sum(r['payment_due_this_week'] for r in rows), 2),
            'total_hours_this_week': round(sum(r['hours_this_week'] for r in rows), 2),
        },
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def online_admins(request):
    denied = _require_super(request)
    if denied:
        return denied
    rows = [_admin_row(p) for p in _all_admin_profiles() if p.shifts.filter(is_active=True).exists()]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def offline_admins(request):
    denied = _require_super(request)
    if denied:
        return denied
    rows = [_admin_row(p) for p in _all_admin_profiles() if not p.shifts.filter(is_active=True).exists()]
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_shifts_list(request):
    denied = _require_super(request)
    if denied:
        return denied
    qs = AdminShift.objects.select_related('admin__user').all()
    if request.query_params.get('admin_id'):
        qs = qs.filter(admin_id=request.query_params['admin_id'])
    frm, to = request.query_params.get('from'), request.query_params.get('to')
    if frm:
        qs = qs.filter(shift_date__gte=frm)
    if to:
        qs = qs.filter(shift_date__lte=to)
    if request.query_params.get('active') == 'true':
        qs = qs.filter(is_active=True)
    rows = []
    for s in qs[:500]:
        row = _shift_json(s)
        row['admin'] = s.admin.user.full_name or s.admin.user.email
        row['admin_id'] = str(s.admin_id)
        rows.append(row)
    return Response({'results': rows})


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_shift_detail(request, shift_id):
    denied = _require_super(request)
    if denied:
        return denied
    try:
        s = AdminShift.objects.select_related('admin__user').get(pk=shift_id)
    except (AdminShift.DoesNotExist, ValueError):
        return Response({'detail': 'Shift not found.'}, status=404)
    row = _shift_json(s)
    row['admin'] = s.admin.user.full_name or s.admin.user.email
    return Response(row)


@api_view(['POST'])
@permission_classes([IsAdminUser])
def admin_shift_force_end(request):
    denied = _require_super(request)
    if denied:
        return denied
    shift_id = request.data.get('shift_id')
    try:
        shift = AdminShift.objects.select_related('admin__user').get(pk=shift_id, is_active=True)
    except (AdminShift.DoesNotExist, ValueError):
        return Response({'detail': 'Active shift not found.'}, status=404)
    _close_shift(shift, ended_by=request.user)
    Notification.objects.create(
        user=shift.admin.user, title='Your shift was closed by an administrator',
        body=f'A Super Admin ended your shift at {_local(shift.end_time):%b %d %H:%M} '
             f'({shift.total_hours} h recorded).',
        notification_type='system', reference_id=shift.id, reference_type='admin_shift')
    _audit(request, f'Force-ended shift for {shift.admin.user.email}', 'force_end_shift',
           shift.id, new={'total_hours': float(shift.total_hours)},
           reason=str(request.data.get('reason', '')))
    return Response(_shift_json(shift))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_hourly_rate(request, admin_id):
    denied = _require_super(request)
    if denied:
        return denied
    try:
        profile = AdminProfile.objects.select_related('user', 'admin_role').get(pk=admin_id)
    except (AdminProfile.DoesNotExist, ValueError):
        return Response({'detail': 'Admin not found.'}, status=404)
    if profile.admin_role and profile.admin_role.name == 'admin_super':
        return Response({'detail': 'Super Admin is not an hourly employee.'}, status=400)
    try:
        new_rate = Decimal(str(request.data.get('hourly_rate'))).quantize(TWO_DP)
    except (TypeError, ValueError):
        return Response({'detail': 'hourly_rate must be a number.'}, status=400)
    if new_rate < 0:
        return Response({'detail': 'hourly_rate cannot be negative.'}, status=400)
    role = profile.admin_role
    if role and role.hourly_rate_range_min is not None:
        lo, hi = role.hourly_rate_range_min, role.hourly_rate_range_max
        if not (lo <= new_rate <= hi):
            return Response({'detail': f'Rate for {role.display_name} must be between ৳{lo} and ৳{hi}.'},
                            status=400)
    _, next_monday = _week_bounds()   # next period starts next Monday
    old = float(profile.hourly_rate)
    # If they have no rate yet, apply immediately; otherwise queue for next period.
    if profile.hourly_rate == 0 and not profile.payments.exists():
        profile.hourly_rate = new_rate
        profile.pending_hourly_rate = None
        profile.pending_rate_effective_from = None
        applied = 'immediately'
    else:
        profile.pending_hourly_rate = new_rate
        profile.pending_rate_effective_from = next_monday.date()
        applied = f'from {next_monday.date().isoformat()}'
    profile.save(update_fields=['hourly_rate', 'pending_hourly_rate',
                                'pending_rate_effective_from', 'updated_at'])
    Notification.objects.create(
        user=profile.user, title='Your hourly rate was updated',
        body=f'New rate ৳{new_rate}/h, effective {applied}.',
        notification_type='system')
    _audit(request, f'Set hourly rate for {profile.user.email} -> {new_rate} ({applied})',
           'rate_changed', profile.id, old={'hourly_rate': old},
           new={'hourly_rate': float(new_rate), 'applied': applied})
    return Response(_admin_row(profile))


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_max_hours(request, admin_id):
    denied = _require_super(request)
    if denied:
        return denied
    try:
        profile = AdminProfile.objects.get(pk=admin_id)
    except (AdminProfile.DoesNotExist, ValueError):
        return Response({'detail': 'Admin not found.'}, status=404)
    value = request.data.get('max_hours_per_week')
    profile.max_hours_per_week = int(value) if value not in (None, '', 0, '0') else None
    profile.save(update_fields=['max_hours_per_week', 'updated_at'])
    _audit(request, f'Set max hours/week for {profile.user.email}', 'edit', profile.id,
           new={'max_hours_per_week': profile.max_hours_per_week})
    return Response(_admin_row(profile))


# ── payroll ────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminUser])
def admin_payments_list(request):
    denied = _require_super(request)
    if denied:
        return denied
    if request.method == 'POST':
        return _generate_payroll(request)
    qs = AdminPayment.objects.select_related('admin__user').all()
    if request.query_params.get('admin_id'):
        qs = qs.filter(admin_id=request.query_params['admin_id'])
    if request.query_params.get('status'):
        qs = qs.filter(payment_status=request.query_params['status'])
    if request.query_params.get('period_start'):
        qs = qs.filter(period_start=request.query_params['period_start'])
    return Response({'results': [_payment_json(p) for p in qs[:500]]})


def _generate_payroll(request):
    """Create/refresh the AdminPayment rows for a week (default: last complete
    week). Existing *paid* rows are never touched; pending rows are recomputed."""
    period = request.data.get('period_start')
    if period:
        wk0, _ = _week_bounds(timezone.datetime.fromisoformat(period))
    else:
        wk0, _ = _week_bounds(_now() - timedelta(days=7))   # last complete week
    wk1 = wk0 + timedelta(days=7)
    created, updated, skipped = 0, 0, 0
    for profile in _all_admin_profiles():
        hours = _hours_between(profile, wk0, wk1)
        rate = profile.effective_hourly_rate(wk0.date())
        regular, overtime = _split_regular_overtime(hours, profile.max_hours_per_week)
        ot_rate = (rate * OVERTIME_MULTIPLIER).quantize(TWO_DP)
        total = (regular * rate + overtime * ot_rate).quantize(TWO_DP)
        existing = profile.payments.filter(period_start=wk0.date()).first()
        if existing and existing.payment_status == 'paid':
            skipped += 1
            continue
        defaults = dict(
            period_end=(wk1 - timedelta(days=1)).date(),
            total_hours=hours, regular_hours=regular, overtime_hours=overtime,
            hourly_rate=rate, overtime_rate=ot_rate, total_payment=total,
            generated_by=request.user,
        )
        if existing:
            for k, v in defaults.items():
                setattr(existing, k, v)
            existing.save(update_fields=list(defaults) + ['updated_at'])
            updated += 1
        else:
            AdminPayment.objects.create(admin=profile, period_start=wk0.date(),
                                        created_at=_now(), **defaults)
            created += 1
    # promote any pending rate whose effective Monday has now passed
    for profile in AdminProfile.objects.filter(pending_rate_effective_from__lte=_local(_now()).date()):
        profile.hourly_rate = profile.pending_hourly_rate
        profile.pending_hourly_rate = None
        profile.pending_rate_effective_from = None
        profile.save(update_fields=['hourly_rate', 'pending_hourly_rate',
                                    'pending_rate_effective_from', 'updated_at'])
    _audit(request, f'Generated weekly payroll for {wk0.date()} '
                    f'({created} new, {updated} updated, {skipped} already paid)',
           'payment_made', reason=f'period {wk0.date()}')
    return Response({
        'period_start': wk0.date().isoformat(),
        'period_end': (wk1 - timedelta(days=1)).date().isoformat(),
        'created': created, 'updated': updated, 'skipped_paid': skipped,
        'results': [_payment_json(p) for p in
                    AdminPayment.objects.select_related('admin__user').filter(period_start=wk0.date())],
    }, status=201)


@api_view(['PATCH'])
@permission_classes([IsAdminUser])
def admin_payment_update(request, payment_id):
    denied = _require_super(request)
    if denied:
        return denied
    try:
        payment = AdminPayment.objects.select_related('admin__user').get(pk=payment_id)
    except (AdminPayment.DoesNotExist, ValueError):
        return Response({'detail': 'Payment not found.'}, status=404)
    action = request.data.get('action')
    if action == 'mark_paid':
        if payment.payment_status == 'paid':
            return Response({'detail': 'Already marked paid.'}, status=409)
        method = request.data.get('payment_method')
        if method not in ('cash', 'bank_transfer', 'mobile_wallet'):
            return Response({'detail': 'payment_method must be cash / bank_transfer / mobile_wallet.'}, status=400)
        payment.payment_status = 'paid'
        payment.payment_method = method
        payment.payment_reference = request.data.get('payment_reference', '')
        payment.payment_date = _now()
        payment.paid_by = request.user
        payment.notes = request.data.get('notes', payment.notes)
        payment.save(update_fields=['payment_status', 'payment_method', 'payment_reference',
                                    'payment_date', 'paid_by', 'notes', 'updated_at'])
        Notification.objects.create(
            user=payment.admin.user, title='You have been paid',
            body=f'৳{payment.total_payment} for {payment.period_start}–{payment.period_end} '
                 f'via {method.replace("_", " ")}.',
            notification_type='system', reference_id=payment.id, reference_type='admin_payment')
        _audit(request, f'Marked payment paid for {payment.admin.user.email} '
                        f'(৳{payment.total_payment})', 'payment_made', payment.id,
               new={'status': 'paid', 'method': method})
    elif action == 'mark_failed':
        payment.payment_status = 'failed'
        payment.notes = request.data.get('notes', payment.notes)
        payment.save(update_fields=['payment_status', 'notes', 'updated_at'])
        _audit(request, f'Marked payment failed for {payment.admin.user.email}', 'edit', payment.id)
    else:
        return Response({'detail': 'action must be mark_paid / mark_failed.'}, status=400)
    return Response(_payment_json(payment))


@api_view(['GET'])
@permission_classes([IsAdminUser])
def admin_payments_export(request):
    denied = _require_super(request)
    if denied:
        return denied
    qs = AdminPayment.objects.select_related('admin__user', 'admin__admin_role').all()
    if request.query_params.get('period_start'):
        qs = qs.filter(period_start=request.query_params['period_start'])
    if request.query_params.get('status'):
        qs = qs.filter(payment_status=request.query_params['status'])
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(['Admin', 'Email', 'Role', 'Period start', 'Period end', 'Regular hours',
                'Overtime hours', 'Hourly rate', 'Overtime rate', 'Total payment',
                'Status', 'Method', 'Reference', 'Paid on'])
    for p in qs:
        w.writerow([
            p.admin.user.full_name or p.admin.user.email, p.admin.user.email,
            p.admin.admin_role.name if p.admin.admin_role_id else '',
            p.period_start, p.period_end, p.regular_hours, p.overtime_hours,
            p.hourly_rate, p.overtime_rate, p.total_payment, p.payment_status,
            p.payment_method or '', p.payment_reference or '',
            _local(p.payment_date).strftime('%Y-%m-%d %H:%M') if p.payment_date else '',
        ])
    _audit(request, f'Exported {qs.count()} admin payment rows', 'export')
    resp = HttpResponse(buf.getvalue(), content_type='text/csv')
    resp['Content-Disposition'] = f'attachment; filename="admin-payroll-{_local(_now()):%Y%m%d-%H%M}.csv"'
    return resp
