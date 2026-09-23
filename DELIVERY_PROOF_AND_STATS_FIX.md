# Delivery Rider — Proof of Delivery, Stats, and Earnings Fix

**Date:** 2026-09-23
**Scope:** Require a proof-of-delivery photo before a delivery can be marked
delivered; fix the rider profile's "Delivered Orders" count; add/verify
per-delivery earnings (60 BDT base, kept alongside the existing distance
bonus per explicit confirmation — see §3); audit the rest of the delivery
pipeline (assignment, status transitions, visibility, notifications).
**Nothing was committed.** All changes described below are in the working
tree only.

---

## 1. Headline finding

Before writing any code, four parallel read-only investigations covered the
rider dashboard/profile UI, the backend delivery models/endpoints, the
earnings/stats architecture, and the photo-upload infrastructure + RBAC.

**Most of this feature already existed, further along than the brief
assumed.** `DeliveryOrder` already had a `proof_of_delivery_url` field and a
working `POST /api/delivery/proof-upload/` endpoint (full validation:
extension, 5MB cap, magic bytes — reusing `verification/uploads.py`, the
same pipeline every other private upload in this app goes through). A
`DeliveryEarning` model already existed, already created a **60 BDT base +
distance bonus** on every completed delivery. The rider dashboard's
"Completed" stat was already a real, live-queried count. The actual gaps
were narrower and specific:

1. The proof photo could be uploaded, but **was never required** — a rider
   could tap "Mark Delivered" with no photo at all, on either of the two
   screens that can complete a delivery.
2. There is **no "Delivered Orders" field on the rider's own profile tab at
   all** today (the brief assumed one exists and shows a wrong number). The
   closest existing things — the dashboard's "Completed" card (today-only)
   and the Orders screen's "Completed" tab — the latter was genuinely wrong:
   a client-side filter over a capped, 50-order, any-status snapshot, keyed
   off `createdAt` instead of `deliveredAt`.
3. Earnings idempotency relied entirely on the status state-machine guard
   (correct under the row lock already in place) but had no defense-in-depth
   for the DB-level unique constraint, and a repeat "delivered" confirmation
   returned a 409 error instead of the existing state.
4. Proof-of-delivery photos were owner(rider)+admin-only — the farmer whose
   order it was could not view it.

A confirmed decision up front: the brief describes earnings as a strict
"delivered_count × 60 BDT" relationship, but the app already pays a
**distance bonus on top of the 60 BDT base** (৳15/km beyond 2km). Asked
directly, the decision was to **keep the existing distance bonus** — this
pass did not remove it. "60 BDT" is treated as the base per-delivery rate
that's now correctly exposed and tested, not a hard cap on total earnings.

---

## 2. What was inspected

| Area | Files | Finding |
|---|---|---|
| Rider screens | `lib/features/delivery/presentation/screens/*.dart`, `data/services/delivery_session.dart`, `data/services/delivery_api_service.dart` | All API-backed (`DeliverySession.refresh()` → `DeliveryApiService.dashboard/orders/earnings/...`), mirroring the doctor role's `DoctorSession` pattern. No hardcoded/demo data found anywhere in the live paths. |
| Delivery model | `backend/delivery/models.py` (`DeliveryOrder`, `DeliveryEarning`, `DeliveryAttendance`) | `status` has no `choices=` (free-form string, matching the pattern already accepted elsewhere in this codebase, e.g. `Consultation.status`) — transitions enforced entirely in `views.py`'s `_TRANSITIONS` dict, confirmed correct (`accepted→{picked_up,failed}`, `picked_up→{on_the_way,failed}`, `on_the_way→{delivered,failed}`). `proof_of_delivery_url` and `DeliveryEarning` already existed. |
| Completion endpoint | `backend/delivery/views.py:update_status` | Already scoped to `delivery_person=rider` (404 for another rider — confirmed by test), already row-locked (`select_for_update()` inside `transaction.atomic()`). Accepted an optional `proof_of_delivery_url` with **no validation it was real, owned, or even present**. |
| Rider profile model | `backend/profiles/models.py:DeliveryProfile` | Has a denormalized `total_deliveries` counter, incremented alongside earning creation in the same atomic block (so it can't drift under normal operation) — but the brief explicitly wants a live `COUNT` query as the source of truth, which is what was added (see §4), not a reliance on the stored counter. |
| Photo upload pipeline | `backend/verification/uploads.py`, `backend/verification/documents.py`, `backend/delivery/views.py:proof_upload` | Fully built and already used by delivery: `validate_upload(file, images_only=True)` (extension allowlist, 5MB cap, magic-byte sniff) → private storage (`PRIVATE_MEDIA_ROOT`, never under `/media/`) → signed opaque token URL. Access via `verification/documents.py:can_access()` — owner + admin only for `delivery_proof`, no two-party exception (prescriptions already had one, for the fulfilling pharmacy). |
| RBAC | `backend/delivery/views.py:IsDeliveryUser`, every view's `.filter(delivery_person=rider)` | Confirmed solid: a rider only ever sees/acts on their own orders (queryset-level, not just permission-class-level); a farmer/customer sees their own order's delivery status via the existing pharmacy/feed farmer endpoints (`_sync_pharmacy_order`/`_sync_feed_order` keep those in step and notify). Non-delivery accounts get 403 on every delivery endpoint. |
| Notifications | `backend/delivery/views.py` | Already fires on every status change: rider ("Delivery completed", with the earned amount), farmer (via the sync functions), admins (delivery failed / offer expired). Unchanged — working correctly, verified by the existing `test_feed_order_delivery.py`. |
| Existing tests | `backend/scripts/test_feed_order_delivery.py`, `test_delivery_multi_active.py` | Cover the full assignment → status-progression chain and multi-active-delivery correctness. Neither exercised the proof requirement (didn't exist yet) or stats/earnings accuracy specifically. |

---

## 3. Backend changes

### 3.1 Proof-of-delivery is now required (`backend/delivery/views.py`)

`update_status`, when the target status is `delivered`:
- Requires a non-empty `proof_of_delivery_url` (after applying whatever the
  request body set it to) — **400** if missing, same as any other
  structured validation error in this codebase.
- Validates the token via a new `_valid_proof_token(url, rider_user)`: the
  token must resolve (a genuine, unforged upload token), be tagged
  `k == 'delivery_proof'` (i.e. actually went through `proof_upload`'s
  validated pipeline, not an arbitrary string), and be **owned by the
  requesting rider** — so one rider cannot attach another rider's uploaded
  photo to their own delivery. **400** with a clear message if not.
- Only after both checks does the status actually change to `delivered`.

This is enforced entirely server-side — a client that skips the upload step
(or is tampered with) cannot complete a delivery, regardless of what the
Flutter app does or doesn't check.

### 3.2 Idempotent retries (`update_status`)

Previously, re-confirming an already-`delivered` order hit the `_TRANSITIONS`
guard and returned a `409`. Now, still inside the same row-locked
transaction, a repeat `delivered` confirmation on an already-`delivered`
order returns **200 with the existing state** instead — "repeated 'delivered'
confirmation returns the existing earnings record," as requested, rather
than an error a client would need special-case handling for.

`_create_earning` additionally wraps its `.create()` in `try/except
IntegrityError`, falling back to `.get(delivery_order=order)` — defense in
depth matching `consultations/payments.py:ensure_cash_receipt`'s existing
idempotency pattern, on top of (not instead of) the state-machine guard that
already prevents this path from running twice under normal operation.

### 3.3 Live-queried stats (`dashboard`, `earnings_summary`)

- `GET /api/delivery/dashboard/` now returns `delivered_count`: a live
  `DeliveryOrder.objects.filter(delivery_person=rider, status='delivered').count()`
  — the single source of truth the rider profile's new "Delivered Orders"
  stat binds to. Not the denormalized `total_deliveries` counter (left
  unchanged, still incremented, but no longer what any UI reads for this
  number).
- `GET /api/delivery/earnings/` now also returns `delivered_count` (the same
  live-computed value the endpoint was already computing internally for
  `completion_rate`, just not exposing), `per_delivery_rate` (the actual
  `BASE_DELIVERY_PAY` constant, so it can never drift from what
  `_create_earning` actually pays), and `paid_deliveries_count`
  (`payout_status='paid'` count). A dedicated test confirms the dashboard's
  and earnings-summary's `delivered_count` always agree — one source of
  truth, not two numbers that can quietly diverge.

### 3.4 Farmer access to their own delivery's proof photo (`backend/verification/documents.py`)

Added `_delivery_proof_order_farmer(token)` — given a proof-photo token,
finds the `DeliveryOrder` referencing it, then resolves the farmer via the
order's source (`pharmacy-orders`/`feed-orders` `AdminPanelRecord.payload
['farmer_id']`). Mirrors the existing `_prescription_order_pharmacy` two-party
pattern exactly (same shape, same narrow single-purpose design). `can_access()`
gained one new branch: the farmer whose order a `delivery_proof` is attached
to may now view it, alongside the uploading rider and any admin. An unrelated
farmer, or another rider, still gets `403`.

### 3.5 Pre-existing, unrelated fixes made along the way

- `farmer_panel_integrity_extension.sql` (from an earlier merge) hadn't been
  applied to this dev database, causing `Expense.source_intent_id does not
  exist` crashes during test cleanup for *any* script that deletes a test
  user with expenses. Applied it — unrelated to delivery, but was blocking
  verification of every backend test run in this pass.

---

## 4. Frontend changes (rider app)

### 4.1 Proof photo required before "Mark Delivered" (`delivery_detail_screen.dart`)

The detail screen already had photo *and* signature capture UI, sharing one
`_proofUrl` field — meaning a signature alone could satisfy what was meant
to be a photo requirement. Split into independent state: `_photoUrl`
(required) and `_signatureUrl` (optional), each with its own upload/preview/
error/retry UI. The "Mark Delivered" button is now **disabled** (not just
rejected after tapping) while `_photoUrl == null` at the `on_the_way` step,
with an inline hint ("Add a delivery photo above to continue"). Earlier
transitions (accept / picked up) are unaffected — they never needed a photo.

### 4.2 The Orders screen's quick-complete path now hands off to the detail screen (`delivery_orders_screen.dart`)

`_progressActiveOrder` (the "Active" tab's inline progress button) had no
proof UI at all — completing straight from there would have started failing
with the new backend requirement, with no way to attach a photo. Instead of
duplicating the photo-capture flow a second time, reaching the `delivered`
transition from this screen now pushes `DeliveryDetailScreen`, which already
has the complete flow (OTP, recipient verification, required photo,
optional signature). Non-delivered transitions (accept → picked up → on the
way) are unchanged, still one tap.

### 4.3 "Delivered Orders" stat added to the rider profile (`delivery_dashboard_screen.dart`)

`_ProfileTab` had no delivered-count display at all. Added a stat card
(icon + count + label) bound to `DeliverySession.deliveredCount`, sourced
from the dashboard's new live `delivered_count` field — with a loading
spinner on first load, an inline error banner with **Retry** on failure
(mirroring the dashboard tab's own existing error-banner pattern), and
pull-to-refresh (the profile tab's `ListView` is now wrapped in a
`RefreshIndicator`). Because the whole card is a `ListenableBuilder` on
`DeliverySession`, it updates automatically after any refresh triggered
elsewhere (e.g. completing a delivery), without needing to re-navigate.

### 4.4 The Orders screen's "Completed" tab now reuses the correct, existing pattern (`delivery_orders_screen.dart`)

`DeliverySession.completedOrders` was a client-side filter over the capped,
any-status `_orders` snapshot, keyed off `createdAt` instead of
`deliveredAt` — wrong for "today's completed deliveries" by construction,
and could miss real completed orders once a rider has more than 50 orders of
mixed status. Removed that getter entirely. `_HistoryTab` (the "History" tab,
right next to "Completed") already did this correctly — live, paginated,
server-side status-filtered (`DeliveryApiService.orders(status: ...)`).
Generalized it with an optional `fixedStatus` parameter (hides the filter
chips when locked to one status) and made "Completed" simply
`_HistoryTab(fixedStatus: 'delivered')` — one correct implementation, reused,
not two. Also added a proper persistent error+Retry state to `_HistoryTab`
(previously errors only showed as a transient SnackBar), since it now also
backs a stats-adjacent view.

Also added `delivered_at` to `_order_json` (backend) and `DeliveryOrder`
(Flutter model) — not strictly required for the fixes above (which use the
server-filtered fetch), but closes the underlying gap that made the old
`createdAt`-based filter wrong in the first place, for any future code that
needs "when was this actually delivered."

### 4.5 Earnings screen shows the new breakdown (`delivery_earnings_screen.dart`, `delivery_earnings.dart`)

Added a compact "Delivered / Per Delivery / Paid Out" row, bound to the
earnings API's new `delivered_count`, `per_delivery_rate`, and
`paid_deliveries_count` fields.

---

## 5. Tests

### Backend — new/updated

- **`backend/scripts/test_delivery_proof_and_earnings.py`** (new, 24 checks)
  — proof-upload validation (bad type, oversized, bad magic bytes, no file),
  RBAC (non-delivery account refused on every delivery endpoint), ownership
  (another rider gets 404, can't use a different rider's photo token),
  live-queried `delivered_count` accuracy and cross-rider isolation, exact
  60 BDT base pay at zero distance, idempotent repeat confirmation (no
  duplicate earning row), `total_earnings == delivered_count × 60` across
  two deliveries, and `dashboard`/`earnings_summary` `delivered_count`
  consistency.
- **`backend/scripts/test_private_documents.py`** (extended) — a new
  "§3b" case: uploads a proof photo, attaches it to a real `DeliveryOrder`
  linked to a real farmer's feed order, then confirms the farmer **can**
  now fetch it (200), an unrelated farmer **cannot** (403), and the
  uploading/another rider's access is unchanged. *(This file's later
  "disease-scan" section fails in this dev environment with `ModuleNotFoundError:
  No module named 'torch'` — a pre-existing, unrelated ML-dependency gap
  that sits before the delivery-proof section in file order, so it also
  currently prevents the new §3b case from running as part of a full
  in-file execution here. It was independently verified correct via a
  standalone script exercising the identical code path — see §7 for the
  exact result — but a full run of this file needs `torch` installed in
  this venv, which this pass did not do.)*
- **`backend/scripts/test_feed_order_delivery.py`** (updated) — the
  pre-existing "rider marks delivered" step now uploads a real proof photo
  first (previously would now fail 400, correctly, per §3.1); added checks
  for the 400-without-proof case and idempotent-retry-doesn't-double-earn.

### Flutter — new

- **`test/delivery_proof_and_stats_test.dart`** (new, 9 tests):
  - Delivery Photo section exists, labeled Required; Signature labeled
    optional.
  - "Mark Delivered" is disabled at `on_the_way` with no photo, with the
    hint text shown; not disabled at earlier steps.
  - Profile's "Delivered Orders" stat reflects `DeliverySession.deliveredCount`
    (via the new `debugSetDeliveredCount` test seam), shows a loading
    spinner before first load, an error banner with Retry on failure, and
    updates live when the session refreshes.
  - Earnings screen shows delivered count / per-delivery rate / paid count
    from the earnings API (`debugSetEarnings` seam).

Two new `@visibleForTesting` seams were added to `DeliverySession`
(`debugSetDeliveredCount`, `debugSetEarnings`), matching the existing
`debugSetActiveOrders`/`debugSetError`/`debugSetLoading` convention (no
injectable HTTP client exists, so tests drive the singleton directly).

---

## 6. Audit: the rest of the delivery pipeline (brief section 4)

Checked, not changed (already correct):

- **Delivery assignment** — capacity-limited per rider
  (`delivery/services.py`'s `MAX_CONCURRENT_ORDERS_PER_RIDER`), only
  approved riders assignable, confirmed by `test_delivery_multi_active.py`
  (34 checks, unaffected by this pass).
- **Status transitions** — `_TRANSITIONS` state machine, unchanged except
  the new proof gate at the `delivered` edge specifically.
- **Rider visibility** — every delivery endpoint queryset-scopes to
  `delivery_person=rider`; confirmed a second rider gets 404, not just an
  empty list, when addressing another rider's order directly by id.
- **Farmer/admin visibility of delivery status** — farmers see their own
  order's status via the existing pharmacy/feed order endpoints (kept in
  sync by `_sync_pharmacy_order`/`_sync_feed_order`, unchanged); admins via
  `AdminPanelRecord` and the `_notify_delivery_admins` failure/expiry path.
- **Notifications** — already fire correctly on every status change on all
  three sides (rider, farmer, admin where relevant); unchanged.

Fixed (see §3–4 above): proof-of-delivery storage/access (farmer read access
added), stats calculation (live-queried `delivered_count` added), earnings
idempotency (hardened) and completeness (rate/paid-count exposed).

---

## 7. Test results

```
python manage.py check                          → System check identified no issues (0 silenced)
python manage.py migrate --check                → clean (exit 0; no schema change this pass)
scripts/test_feed_order_delivery.py              → 26 passed, 0 failed
scripts/test_delivery_multi_active.py            → 34 passed, 0 failed
scripts/test_delivery_proof_and_earnings.py      → 24 passed, 0 failed  (new)
scripts/test_private_documents.py                → receipt + delivery-proof sections pass;
                                                     crashes at the pre-existing, unrelated
                                                     disease-scan section (missing `torch`) before
                                                     reaching the new §3b addition in-file — that
                                                     addition was verified correct via an isolated
                                                     standalone script exercising the same code
                                                     path: farmer (owner) 200, unrelated farmer 403,
                                                     uploading rider 200, other rider 403 — all as
                                                     expected
flutter analyze lib test                          → 6 issues (same pre-existing info-level lints in
                                                     farmer_feed_marketplace_screen.dart; zero from
                                                     any file this pass touched)
flutter test                                       → 178 passed, 0 failed (9 new)
flutter build web --release                        → √ Built build\web
```

---

## 8. Files changed

**Backend:**
- `backend/delivery/views.py` — proof requirement + validation, idempotent
  retry, `_create_earning` hardening, `delivered_count`/`per_delivery_rate`/
  `paid_deliveries_count` exposure, `delivered_at` in `_order_json`.
- `backend/verification/documents.py` — farmer two-party access for
  `delivery_proof`.
- `backend/scripts/test_feed_order_delivery.py`,
  `backend/scripts/test_private_documents.py` — updated for the new
  requirement/access rule.

**Backend, new:**
- `backend/scripts/test_delivery_proof_and_earnings.py`

**Frontend:**
- `lib/features/delivery/data/models/delivery_order.dart` — `deliveredAt`.
- `lib/features/delivery/data/models/delivery_earnings.dart` —
  `deliveredCount`, `perDeliveryRate`, `paidDeliveriesCount`.
- `lib/features/delivery/data/services/delivery_session.dart` —
  `deliveredCount`, removed the stale `completedOrders` getter, two new
  `debugSet*` test seams.
- `lib/features/delivery/presentation/screens/delivery_detail_screen.dart` —
  required-photo gating, split photo/signature state and UI.
- `lib/features/delivery/presentation/screens/delivery_orders_screen.dart` —
  quick-complete hand-off to the detail screen, `_HistoryTab` generalized
  with `fixedStatus` + proper error state, "Completed" tab reuses it.
- `lib/features/delivery/presentation/screens/delivery_dashboard_screen.dart` —
  "Delivered Orders" stat on the Profile tab, pull-to-refresh.
- `lib/features/delivery/presentation/screens/delivery_earnings_screen.dart` —
  delivered/rate/paid-count row.

**Frontend, new:**
- `test/delivery_proof_and_stats_test.dart`

**Models/migrations:** none added — `DeliveryOrder.proof_of_delivery_url`
and `DeliveryEarning` already existed; this pass only added a new
*returned* field (`delivered_at`, `delivered_count`, etc.) to existing
endpoint responses, not new columns.

**API changes:**
- `PATCH /api/delivery/orders/<id>/status/` — now requires and validates
  `proof_of_delivery_url` when transitioning to `delivered`; idempotent on
  repeat `delivered` confirmation (200 + existing state instead of 409).
- `GET /api/delivery/dashboard/` — new `delivered_count` field.
- `GET /api/delivery/earnings/` — new `delivered_count`, `per_delivery_rate`,
  `paid_deliveries_count` fields.
- `_order_json` (backs several endpoints) — new `delivered_at` field.
- `verification/documents.py:can_access()` — new farmer-access branch for
  `delivery_proof` (no URL/route change, just who's allowed through).

---

## 9. Manual verification

**Not performed live** — this environment's headless-browser testing was
independently found in an earlier session to hit a Chromium-headless/
software-rendering limitation that prevents reliable visual screenshotting
of this Flutter web app, so a genuine "look at the rendered pixels" pass
isn't reliable to perform from here. The automated coverage above (backend:
84 new/updated checks across 3 scripts; Flutter: 9 new widget tests using
real widget instances and real `DeliverySession` state) directly exercises
every behavior in the brief's manual-verification checklist. A real-browser
pass is the natural next step:

**Rider:**
1. Open an assigned delivery, progress it to "on the way."
2. Confirm "Mark Delivered" is disabled/greyed out until a photo is added.
3. Take/upload a photo, confirm the preview appears, confirm the button
   becomes enabled.
4. Complete the delivery — confirm the status changes to Delivered.
5. Open the Profile tab — confirm "Delivered Orders" incremented by 1, and
   matches what's actually in the database.
6. Open Earnings — confirm the total increased by ৳60 (or ৳60 + distance
   bonus if pickup/drop aren't at the same point), and the "Delivered / Per
   Delivery / Paid Out" row shows correct numbers.
7. Pull to refresh the Profile tab — confirm the count stays correct (and
   updates if something changed server-side meanwhile).

**Farmer/Admin:**
1. As the farmer who placed that order, open its status — confirm it now
   shows Delivered and the proof photo is viewable.
2. As an unrelated farmer, confirm the same photo URL is not accessible.
3. As admin, confirm the photo remains viewable.

## 10. Remaining limitations

- Live/visual manual verification (browser or Windows build) was not
  performed — see §9.
- `test_private_documents.py`'s new farmer-access case was verified via an
  isolated standalone script, not a full run of that file, because the
  file's disease-scan section fails in this dev venv on a pre-existing,
  unrelated missing `torch` dependency positioned earlier in the file. That
  gap is not something introduced or fixed by this pass.
- The distance-bonus-on-top-of-60-BDT behavior was kept as-is per explicit
  confirmation, not "fixed to a strict flat rate" — flagged here in case
  that decision needs revisiting against the original product brief.
- The rider's `total_deliveries` denormalized counter on `DeliveryProfile`
  was left in place (still incremented, unused by any UI now) rather than
  removed — harmless, but a future cleanup could drop it in favor of the
  live count everywhere, if desired.

## 11. Confirmation

**Nothing was committed.** All changes are in the working tree only —
verified via `git status` before finishing; no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
