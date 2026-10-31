# Pharmacy Admin — End-to-End Report (Verification & Repair Pass)

## Addendum (same day, second correction): two real bugs found by driving actual signup + approve through the live server

The user reported, after reading the first version of this report, that
admin actions on a pharmacy account did not actually affect the real owner
account, and that "backend logic isn't working." Rather than defend the
prior verification, this addendum reproduced the exact scenario end-to-end
against the live running server — a real `POST /api/auth/register/` signup,
not a test-helper shortcut — and found two real, distinct bugs:

**Bug 1 — `PharmacyOrganization.review_state` defaulted to `'approved'` for
brand-new signups.** The model field's default is `'approved'` (deliberately
— set that way so the migration that originally added the column wouldn't
retroactively lock already-active pharmacies), but `users/serializers.py`'s
`_create_pharmacy()` never overrode that default when creating a fresh
signup's business profile. A pharmacy that had never been reviewed by anyone
carried a business-profile row saying "approved." This did not by itself
unlock any operational feature (`pharmacy_lifecycle_status()` checks the
shared `account_status` field first, which correctly stayed `pending`), but
it was a real, user-visible data-correctness bug in the one place that field
is surfaced raw: `GET /api/pharmacy/profile/` and `/permissions/`.
**Fixed**: `_create_pharmacy()` now explicitly sets
`review_state='pending_review'` on creation.

**Bug 2 — the actual bug behind "admin actions don't affect the real owner
account."** Every pharmacy status-transition endpoint
(`approve`/`reject`/`request-info`/`suspend`/`reinstate`) fetches a `User` row
once, calls `transition_pharmacy_status()` (which internally re-fetches its
*own* `select_for_update()` copy of that same row, mutates it, and saves it —
the database write is correct), then serializes the **caller's original,
now-stale** `User` object into the HTTP response via
`_pharmacy_account_json()`. Verified live: approving a genuinely pending
pharmacy signup returned `"status":"PENDING_REVIEW","account_status":"pending"`
in the API response — while the database row was, in fact, already `active`
(confirmed by a direct DB read in the same moment). The admin clicking
"Approve" would see the account snap right back to looking locked/pending in
the very response meant to confirm the action worked — exactly the symptom
reported. **Fixed**: `_pharmacy_account_json()` now calls
`user.refresh_from_db()` before serializing, closing this for all five
transition endpoints (plus the account-detail GET, harmlessly).

Both fixes were verified against the **real running server**, not just the
Django test client: a real signup → real admin login → real approve call →
confirmed the response body itself now correctly shows `ACTIVE`/`active` and
unlocked permissions, then confirmed the real owner's own session reflects
the change immediately after. Two new regression tests were added to
`test_pharmacy_admin.py` (which drives the actual `/api/auth/register/`
endpoint for the first bug, rather than the test-helper shortcut every other
check in that file uses — the reason 120 prior passing checks never caught
either bug) plus one more on the suspend response body. Suite: **120 → 132
passed, 0 failed**. Full regression battery re-run clean afterward (22/107/
25/66). Test accounts created during live verification were deleted from the
dev DB afterward. Nothing committed.

Files touched in this addendum: `backend/users/serializers.py` (1 line),
`backend/api/admin_pharmacy.py` (1 line + comment), `backend/scripts/test_pharmacy_admin.py`
(+12 checks).


Date: 2026-09-26. This is the third work pass on this feature. The first two
(`PHARMACY_ADMIN_AUDIT.md`, `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md`) built
the system described in `PHARMACY_ADMIN_END_TO_END_REQUIREMENTS.md`'s matrix.
This pass's mandate was explicit: **do not trust those reports without
verifying the actual running application.** It did not re-implement anything
already built — it verified it against the live system, found one real bug
that only a live, authenticated-as-the-real-role check could surface, fixed
it, and added regression coverage.

## 1. What this pass actually did

1. Read both prior reports in full and cross-checked their claims against the
   current `git status` (51 changed/new files, matching what both reports
   describe — nothing had drifted since they were written).
2. Ran every backend regression suite fresh, against the live dev database,
   not by trusting the reports' printed numbers:
   - `test_pharmacy_admin.py`: 120/120 passed (before this pass's changes)
   - `test_pharmacy_flow.py`: 22/22
   - `test_signup_flows.py`: 107/107
   - `test_verification_status.py`: 25/25
   - `test_admin_panel.py`: 66/66
   - `manage.py check`: clean. `manage.py migrate --check`: clean.
3. Restarted the backend (`uvicorn`, no autoreload — the same gotcha both
   prior reports flagged) and the Flutter web dev server to guarantee the
   running processes served the current on-disk code, not stale in-memory
   code from an earlier session.
4. Logged in as the **real** `pharmacy.admin@featherflow.local` account
   (not `admin_super`) and drove authenticated HTTP calls against the live
   backend: login, dashboard, pharmacy list, delivery queue, and — critically
   — the rider list the delivery-assignment picker depends on.
5. That last check surfaced a real, previously-undetected 403: the Pharmacy
   Admin role cannot use the generic riders collection the Flutter delivery
   picker was calling. Traced, fixed, verified end-to-end (including
   confirming the offline-rider warning behavior actually works against a
   real assignment, not a synthetic one), and covered with 6 new automated
   checks. Full detail in the requirements matrix's "The one real bug found
   this session" section — not duplicated here.
6. Re-ran the full backend battery after the fix — 126/126 in
   `test_pharmacy_admin.py` (was 120), everything else unchanged and still
   green (22/107/25/66).
7. `flutter analyze` on the touched files: clean. Full `flutter test`:
   192/192 passed, no regressions. `flutter build web --release`: succeeded.
8. Restarted both the backend and frontend dev servers one final time so the
   currently-running application reflects every change made in this pass.

## 2. Files changed in this pass

**Backend:**
- `backend/api/admin_pharmacy.py` — new `admin_pharmacy_available_riders`
  view (`GET /admin-panel/pharmacy-riders/`), gated on `pharmacy:assign`.
- `backend/api/urls.py` — new route + import.
- `backend/scripts/test_pharmacy_admin.py` — new "delivery assignment"
  section (6 checks): generic riders 403 for Pharmacy Admin (documenting the
  correct isolation, not a bug), the new endpoint returns 200 and includes a
  real offline rider, a pharmacy owner is denied on it, and a real assignment
  to a genuinely offline rider both succeeds and returns the warning field.

**Flutter:**
- `lib/features/admin/data/services/admin_api_service.dart` — new
  `pharmacyAvailableRiders()` method.
- `lib/features/admin/presentation/screens/admin_pharmacy_screen.dart` —
  `_assign()` now calls `pharmacyAvailableRiders()` instead of the
  RBAC-blocked generic `list('riders')`.

No models, migrations, or database schema changes were needed — this was a
routing/permission-scoping fix, not a data-model gap.

## 3. What was NOT changed, and why

Everything else described in the two prior reports (§1–§38 of
`PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md`) was verified working as described
and left untouched: the transition engine, appeals, chat, medicine CRUD,
commission/settlement math, the 7-tab admin shell, the CSV export/audit
system, and the permission-snapshot-driven locked UI. Re-implementing
already-correct code would have added risk without benefit; this pass's job
was to verify and repair, not rebuild.

**Not attempted this pass** (honest, explicit, matches the prior reports'
own named gaps, not newly discovered):
- Inventory stock-**movement history** (a per-medicine timeline distinct
  from the stock-adjust action, which does exist and was re-verified). No
  dedicated table or view exists.
- Fixing `seed_platform_demo`'s pre-existing, unrelated Farm-duplication
  crash so it can seed the Pharmacy Admin account end-to-end on a clean DB.
  `_create_pharmacy_admin.py` remains the reliable path.
- A from-scratch Playwright/browser-automation click-through of the fixed
  rider picker specifically — no browser-automation tool is available in
  this session's environment (confirmed via tool search). The fix was
  instead verified at the level the actual bug lived at: a real HTTP call
  through the real endpoint chain, as the real account, producing the real
  `warning` field — which is what the Flutter dialog renders directly from
  the response, so this is strong evidence the UI will now work, short of an
  actual click.

## 4. Runtime state at the end of this pass

- Backend: `uvicorn` on `http://127.0.0.1:8000`, restarted twice during this
  pass (once after the fix, confirmed serving current code both times).
- Frontend: `flutter run -d web-server --web-port 8090 --web-hostname
  127.0.0.1 --release`, restarted after the Flutter-side fix, confirmed
  serving (`curl http://127.0.0.1:8090/` → 200).
- Demo credentials unchanged: `pharmacy.admin@featherflow.local` /
  `ChangeMe@2026!` (see `PHARMACY_ADMIN_DEMO_CREDENTIALS.md`).

## 5. Test totals (this pass, live-verified)

| Suite | Result |
|---|---|
| `test_pharmacy_admin.py` | **126 passed**, 0 failed (was 120; +6 new delivery-assignment checks) |
| `test_pharmacy_flow.py` | 22 passed, 0 failed |
| `test_signup_flows.py` | 107 passed, 0 failed |
| `test_verification_status.py` | 25 passed, 0 failed |
| `test_admin_panel.py` | 66 passed, 0 failed |
| `flutter test` (full suite) | 192 passed, 0 failed |
| `flutter analyze` | clean |
| `flutter build web --release` | succeeded |
| `manage.py check` / `migrate --check` | clean |

## 6. Confirmation: nothing committed

`git status` at the end of this pass shows only working-tree modifications —
the same files the prior two reports listed, plus this pass's 4 edited/new
files. No `git add`, `git commit`, or other git write operation was run.

## 7. Bottom line

The Pharmacy Admin system described across all three passes is real,
backend-verified (126+22+107+25+66 = 346 live checks passing this session
alone), Flutter-verified (192/192, clean analyze, successful release build),
and now has one fewer hidden gap than it did at the start of this session —
a real 403 that would have broken delivery assignment for the actual
dedicated Pharmacy Admin account in production use, found specifically
because this pass insisted on testing as that real account instead of
trusting an admin_super-flavored walkthrough. The two gaps that remain
(inventory movement history; `seed_platform_demo`'s unrelated Farm-seed bug)
are the same two gaps the prior report already named — nothing is hidden,
and this report does not claim either one is done.
