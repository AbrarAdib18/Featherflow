# Operations Admin Live-Data Verification

Companion to `OPERATIONS_ADMIN_DASHBOARD_AUDIT.md`. This records how each
"does the dashboard actually update when real state changes" requirement
was verified, and the actual results from the last run against the local
dev backend/DB. Nothing here was committed.

## Method

All numbers below are **before/after deltas** over a set of throwaway
`admindashtest+`-prefixed accounts created and deleted by
`backend/scripts/test_admin_dashboard_metrics.py`, not absolute counts —
this dev database already has many pre-existing rows from other seed/test
scripts run earlier in this project's history, so an absolute-count
assertion would be meaningless. Each check re-fetches
`GET /api/admin-panel/dashboard/` as a real authenticated `admin_operations`
user and compares the new stats to the immediately-prior fetch.

Run with: `backend/venv/Scripts/python.exe backend/scripts/test_admin_dashboard_metrics.py`

## Last run result

```
== RBAC: only admin accounts may read the dashboard ==
  ok   a non-admin role is refused (403)
  ok   an anonymous request is refused (401/403)

== baseline read ==
  ok   ops admin can read the dashboard (200)
  ok   'generated_at' is present and parseable

== active_users / pending_users / suspended_users are correctly defined (delta over known-status accounts) ==
  ok   active_users increased by exactly 3
  ok   pending_users increased by exactly 2
  ok   suspended_users increased by exactly 1
  ok   total_users increased by exactly 6 (3+2+1), confirming it is the honest all-rows figure active_users used to be mislabeled as

== active_doctors ==
  ok   active_doctors increased by exactly 1 (only the verified one)

== pending_delivery ==
  ok   pending_delivery increased by exactly 1 (approved_by_admin is null)

== metrics update after a real status change ==
  ok   active_users increased by 1 after approving a pending user
  ok   pending_users decreased by 1 after approving a pending user

12 passed, 0 failed
```

## Coverage against the requested lifecycle list

| Lifecycle event | Verified how | Result |
|---|---|---|
| Signup → pending count increases | 3 farmer signups with `account_status='pending'` → `pending_users` delta | +2 confirmed (2 of the 3 created accounts were pending; see table below) |
| Doctor verification status → metric | one verified + one unverified `DoctorProfile` created → `active_doctors` delta | +1 (only the verified one counted) |
| Delivery approval status → metric | one `DeliveryProfile` with `approved_by_admin=None` → `pending_delivery` delta | +1 |
| User approve (pending → active) → both metrics update | flipped one pending user's `account_status` to `'active'`, re-fetched | `active_users` +1, `pending_users` −1, in the same request cycle |
| User suspend → metric | one user created directly with `account_status='suspended'` → `suspended_users` delta | +1 |
| `generated_at` reflects the current request | parsed as ISO-8601 on every fetch | present and parseable every time |
| RBAC — only admin roles can read | farmer-role token → 403; no token → 401/403 | both confirmed |

Consultation lifecycle → metric, delivery-order lifecycle → metric, and
support-ticket lifecycle → metric were **not** re-verified in this pass —
those metrics (`urgent_consultations`, `pending_approval_requests`,
`open_escalations`, `pending_admin_registrations`) were not touched by
this fix (no bug was found in them) and already have coverage in the
pre-existing `backend/scripts/test_admin_panel.py` suite (oversight/
escalation section), which continues to pass unchanged. Re-deriving that
coverage here would have duplicated it without adding information.

## Exact account mix created for the delta test

| # | role | `account_status` | counted in |
|---|---|---|---|
| 3 | farmer | `active` | `active_users` |
| 2 | farmer | `pending` | `pending_users` |
| 1 | farmer | `suspended` | `suspended_users` |
| 1 | doctor | `active` account, `is_verified=True` | `active_doctors` |
| 1 | doctor | `active` account, `is_verified=False` | not counted in `active_doctors` (confirms the filter excludes unverified) |
| 1 | delivery | `approved_by_admin=None` | `pending_delivery` |

All 9 throwaway accounts plus their profile rows are deleted by the
script's `cleanup()` at both start and end (idempotent — safe to re-run).

## What this does and does not prove

This proves the *backend* aggregation is correct and live (each metric
moves by exactly the expected amount when the underlying row set changes,
in the same request/response cycle, with no caching staleness). It does
**not** by itself prove the Flutter dashboard re-renders those numbers
instantly without a manual refresh — that depends on `RefreshIndicator`
pull-to-refresh / the existing periodic-refresh wiring in
`_DashboardBodyState`, which was reviewed by reading the code (no
polling timer currently exists beyond initial load + pull-to-refresh +
the "Retry" button added in this pass) but is not claimed to be
sub-second real-time push. See "Known limitations" in
`OPERATIONS_ADMIN_DASHBOARD_AUDIT.md` for why this could not be
end-to-end widget-tested against live data in this harness.
