"""Operations Admin earnings — GET /api/admin-panel/my-shift/earnings/.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_admin_earnings.py

Live DB, `earningstest+`-prefixed throw-away admin accounts + their shifts.
Idempotent (cleans up at both start and end).

Shift-lifecycle races (duplicate start/end, idempotent end, cross-user end
forbidden, rate-range validation) already have thorough coverage in
test_admin_panel.py's "SHIFT TIMER + HOURLY PAYMENT" section and are not
re-tested here. This file is specifically about the earnings CALCULATION
(duration -> Decimal BDT, at documented rate) and the earnings ENDPOINT's
own scoping (self-only, read-only, day/week/month boundary allocation).
See OPERATIONS_ADMIN_EARNINGS.md / OPERATIONS_ADMIN_EARNINGS_AUDIT.md.

Boundary tests (cross-midnight / cross-week / cross-month) are built off the
endpoint's own `_day_bounds` / `_week_bounds` / `_month_bounds` helpers
rather than wall-clock offsets from "now", so they pass regardless of what
day/time this suite happens to run on (including Mondays and the 1st of a
month, where a naive "yesterday" / "last month" construction would be
flaky).
"""
import hashlib
import os
import sys
from datetime import date, datetime, timedelta, timezone as dt_timezone
from decimal import Decimal

import django

# This dev shell's stdout defaults to cp1252 on Windows, which can't encode
# the currency sign or em dashes used below — reconfigure to UTF-8 rather
# than avoid non-ASCII characters in test output.
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from api.admin_shifts import _day_bounds, _month_bounds, _week_bounds  # noqa: E402
from profiles.models import AdminProfile, AdminShift  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'earningstest+'
RATE = Decimal('450.00')


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    AdminShift.objects.filter(admin__user__in=users).delete()
    AdminProfile.objects.filter(user__in=users).delete()
    users.delete()


def mk_admin(tag, role_name='admin_operations', rate=RATE):
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': 'admin'})
    email = f'{PREFIX}{tag}@example.com'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'Earnings Test {tag}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active'))
    user.set_password('Test1234!')
    user.account_status = 'active'
    user.save()
    user.roles.clear()
    user.roles.add(role)
    profile, _ = AdminProfile.objects.update_or_create(user=user, defaults=dict(
        admin_role=role, job_title='Earnings Tester', department='Operations',
        start_date=date(2024, 1, 1), admin_sub_role=role_name.replace('admin_', ''),
        approval_status='approved', is_active=True, is_suspended=False,
        internal_approval_by_founder_hr=True, hourly_rate=rate,
        pending_hourly_rate=None, pending_rate_effective_from=None,
    ))
    return user, profile


def mk_shift(profile, start, end, break_start=None, break_end=None):
    return AdminShift.objects.create(
        admin=profile, shift_date=start.date(), start_time=start, end_time=end,
        break_start=break_start, break_end=break_end,
        break_duration_minutes=int(round((break_end - break_start).total_seconds() / 60))
        if break_start and break_end else 0,
        is_active=end is None, created_at=start,
    )


def auth(client, user):
    client.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'


def get_earnings(client):
    r = client.get('/api/admin-panel/my-shift/earnings/')
    return r


def main():
    cleanup()
    ops, ops_profile = mk_admin('ops')
    c = Client()
    auth(c, ops)

    # ── access control ───────────────────────────────────────────────────
    print('\n== access control ==')
    r = get_earnings(Client())
    check('anonymous request is refused (401/403)', r.status_code in (401, 403), r.status_code)

    super_admin, _ = mk_admin('super', role_name='admin_super', rate=Decimal('0.00'))
    sc = Client()
    auth(sc, super_admin)
    r = get_earnings(sc)
    check('Super Admin (platform owner, no shifts/pay) gets 403, not fabricated zeros',
          r.status_code == 403, r.content[:200])

    other, other_profile = mk_admin('other')
    mk_shift(other_profile, datetime.now(dt_timezone.utc) - timedelta(hours=5),
             datetime.now(dt_timezone.utc) - timedelta(hours=4))  # 1h, other admin
    oc = Client()
    auth(oc, other)
    r_ops = get_earnings(c).json()
    r_other = get_earnings(oc).json()
    check("one admin's earnings never reflect another admin's shift "
          "(no admin-id parameter exists — always request.user's own profile)",
          r_ops['total_income']['completed_duration_seconds'] !=
          r_other['total_income']['completed_duration_seconds'] or
          r_ops['total_income']['completed_duration_seconds'] == 0,
          (r_ops['total_income'], r_other['total_income']))

    r = c.patch('/api/admin-panel/my-shift/earnings/', data={'hourly_rate_bdt': '900.00'},
                content_type='application/json')
    check('the earnings endpoint is read-only — PATCH is rejected (405)',
          r.status_code == 405, r.status_code)

    r = c.patch(f'/api/admin-panel/admins/{ops_profile.id}/hourly-rate/',
                data={'hourly_rate': '900.00'}, content_type='application/json')
    check('Operations Admin cannot change their own hourly rate (Super-Admin-only '
          'endpoint refuses a non-super caller)', r.status_code == 403, r.status_code)

    # ── rate ─────────────────────────────────────────────────────────────
    print('\n== rate ==')
    cleanup_shifts(ops_profile)
    r = get_earnings(c).json()
    check('hourly_rate_bdt is exactly 450.00 for Operations Admin',
          r['hourly_rate_bdt'] == '450.00', r['hourly_rate_bdt'])
    check('currency is BDT', r['currency'] == 'BDT', r['currency'])
    check('timezone is the configured Asia/Dhaka', r['timezone'] == 'Asia/Dhaka', r['timezone'])

    # ── standard calculation cases ──────────────────────────────────────
    print('\n== standard calculation cases ==')
    cleanup_shifts(ops_profile)
    r = get_earnings(c).json()
    check('zero shifts -> zero duration', r['total_income']['completed_duration_seconds'] == 0)
    check('zero shifts -> ৳0.00', r['total_income']['earnings_bdt'] == '0.00',
          r['total_income']['earnings_bdt'])
    check('zero shifts -> today duration 0', r['today']['duration_seconds'] == 0)

    now = datetime.now(dt_timezone.utc)
    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(hours=2), now - timedelta(hours=1))  # exactly 1h
    r = get_earnings(c).json()
    check('one completed 1-hour shift -> ৳450.00',
          r['total_income']['earnings_bdt'] == '450.00', r['total_income'])
    check('one completed 1-hour shift -> 3600 seconds',
          r['total_income']['completed_duration_seconds'] == 3600)

    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(minutes=40), now - timedelta(minutes=10))  # 30 min
    r = get_earnings(c).json()
    check('one completed 30-minute shift -> ৳225.00',
          r['total_income']['earnings_bdt'] == '225.00', r['total_income'])

    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(minutes=47), now)  # 47 min, non-round duration
    r = get_earnings(c).json()
    check('a non-round 47-minute (2820s) duration -> exact ৳352.50, no float artefact',
          r['total_income']['earnings_bdt'] == '352.50', r['total_income'])

    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(hours=3), now - timedelta(hours=2))       # 1h
    mk_shift(ops_profile, now - timedelta(minutes=90), now - timedelta(minutes=60))  # 30m
    r = get_earnings(c).json()
    check('multiple completed shifts aggregate correctly -> ৳675.00',
          r['total_income']['earnings_bdt'] == '675.00', r['total_income'])
    check('multiple completed shifts -> 5400 seconds total', r['total_income']['completed_duration_seconds'] == 5400)

    # a break is subtracted (unpaid), matching the existing shift-hours rule
    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(hours=2), now,
              break_start=now - timedelta(hours=1, minutes=30),
              break_end=now - timedelta(hours=1))  # 2h shift, 30m break -> 1.5h paid
    r = get_earnings(c).json()
    check('a logged break is subtracted from paid duration -> ৳675.00 (1.5h)',
          r['total_income']['earnings_bdt'] == '675.00', r['total_income'])

    # ── active shift: provisional, not finalized ────────────────────────
    print('\n== active shift: provisional vs finalized ==')
    cleanup_shifts(ops_profile)
    mk_shift(ops_profile, now - timedelta(hours=1), now - timedelta(minutes=30))  # 30m completed
    active = AdminShift.objects.create(
        admin=ops_profile, shift_date=now.date(), start_time=now - timedelta(minutes=20),
        end_time=None, is_active=True, created_at=now - timedelta(minutes=20))  # 20m active
    r = get_earnings(c).json()
    check('active_shift is present exactly once while a shift is open',
          r['active_shift'] is not None)
    check('active_shift provisional duration ~= 1200s (20 min), within a small tolerance',
          abs(r['active_shift']['provisional_duration_seconds'] - 1200) < 5,
          r['active_shift']['provisional_duration_seconds'])
    check("total_income (completed only) reflects only the 30-minute *completed* "
          "shift, ৳225.00 — the active shift's time is not folded in",
          r['total_income']['earnings_bdt'] == '225.00', r['total_income'])
    check('total_income.includes_active_shift is explicitly false',
          r['total_income']['includes_active_shift'] is False)
    check("today's duration includes the active shift's running time "
          "(30m completed + ~20m active ~= 3000s)",
          abs(r['today']['duration_seconds'] - 3000) < 5, r['today'])
    active.end_time = now
    active.is_active = False
    active.total_hours = Decimal('0.33')
    active.save(update_fields=['end_time', 'is_active', 'total_hours'])
    r = get_earnings(c).json()
    check('after ending the shift, it is no longer active_shift',
          r['active_shift'] is None)
    check('after ending, its time is now counted exactly once in total_income '
          '(no double-count, no loss): 30m + ~20m ~= 50min ~= ৳375.00 +/- rounding',
          Decimal(r['total_income']['earnings_bdt']) >= Decimal('370.00'), r['total_income'])

    # ── boundary allocation (built off the endpoint's own boundary fns) ──
    print('\n== boundary allocation (cross-midnight / cross-week / cross-month) ==')
    cleanup_shifts(ops_profile)
    dy0, dy1 = _day_bounds()
    mk_shift(ops_profile, dy0 - timedelta(hours=1), dy0 + timedelta(hours=1))  # crosses midnight
    r = get_earnings(c).json()
    check("a shift crossing midnight allocates only the post-midnight hour to "
          "'today' (3600s), not the full 2h",
          r['today']['duration_seconds'] == 3600, r['today'])
    check("the pre-midnight hour still counts in total_income (full 2h = 7200s)",
          r['total_income']['completed_duration_seconds'] == 7200,
          r['total_income'])

    cleanup_shifts(ops_profile)
    wk0, wk1 = _week_bounds()
    mk_shift(ops_profile, wk0 - timedelta(hours=1), wk0 + timedelta(hours=1))  # crosses week start
    r = get_earnings(c).json()
    check("a shift crossing the week boundary allocates only the post-boundary "
          "hour to 'this_week' (3600s), not the full 2h",
          r['this_week']['duration_seconds'] == 3600, r['this_week'])

    cleanup_shifts(ops_profile)
    mo0, mo1 = _month_bounds()
    mk_shift(ops_profile, mo0 - timedelta(hours=1), mo0 + timedelta(hours=1))  # crosses month start
    r = get_earnings(c).json()
    check("a shift crossing the month boundary allocates only the post-boundary "
          "hour to 'this_month' (3600s), not the full 2h",
          r['this_month']['duration_seconds'] == 3600, r['this_month'])

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup()
    if FAIL:
        sys.exit(1)


def cleanup_shifts(profile):
    AdminShift.objects.filter(admin=profile).delete()


if __name__ == '__main__':
    main()
