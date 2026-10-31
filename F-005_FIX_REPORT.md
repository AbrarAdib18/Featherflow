# F-005 — Delivery arrival + proof review workflow: fix report

**Status: fixed in the working tree. Nothing was committed** (`git log` still ends at `6a036eb Sub-admin roles fixed`).

## 1. Problem
The delivery state machine was `accepted → picked_up → on_the_way → delivered|failed`. There was no "arrived" state, and the rider completed the order themselves by uploading a proof token. Admins could not review, reject, request resubmission or approve a proof.

## 2. New lifecycle

```
Assigned (pending/accepted) → Picked up → Out for delivery → Arrived
   → Proof submitted ("Proof under review") → Completed          (admin approves)
Proof under review → Proof rejected (reason required) → Resubmission required
   → Proof submitted → … → Completed
```
* `delivered` is reachable **only** through admin approval (`delivery/lifecycle.py::approve_proof`). A rider `PATCH status=delivered` now returns **409**.
* Approval is the single completion event: it sets `delivered`, creates the rider earning (idempotent, one per order), increments `total_deliveries`, mirrors the farmer feed/pharmacy expense (`get_or_create` on the source-order id) and notifies farmer + rider — all in one transaction under row locks.

## 3. What changed

| Area | Change |
|---|---|
| DB (`backend/delivery_proof_review_extension.sql`, idempotent, applied to dev + scratch DB) | status CHECK gains `arrived`, `proof_submitted`, `proof_rejected`; new `delivery_proofs` (every attempt kept: URL, note, status, reason, reviewer, times; unique one-open and one-approved proof per order; CHECK that a rejection has a reason) and `delivery_order_events` (append-only state history); Feed Admin gets `approve`/`reject` on `feed-delivery`. Pre-change backup: `audit_logs/db_backup/featherflow_pre_f005_20261001.dump`. |
| Backend models/services | `DeliveryProof`, `DeliveryOrderEvent`; `delivery/lifecycle.py` (transitions, submit/reject/approve, audit, notifications); `ACTIVE_ORDER_STATUSES` extended. |
| Rider API | `PATCH /api/delivery/orders/<id>/status/` (adds `arrived`; no `delivered`); `POST /api/delivery/orders/<id>/proof/` (multipart only → 415 otherwise; `file` required; magic-byte/size/type validation; OTP checked for pharmacy handovers; resubmission allowed from `proof_rejected`); `GET /api/delivery/orders/<id>/history/`. The unvalidated `proof_of_delivery_url` assignment on PATCH was removed. |
| Admin API (`api/admin_delivery_proofs.py`) | `GET /api/admin-panel/delivery-proofs/?status=submitted|rejected|approved|all`, `GET …/<id>/` (all attempts + state history), `POST …/<id>/approve/`, `POST …/<id>/reject/ {reason}` (≥3 chars, else 400). Object-level authorization per order type: delivery admins any; Feed Admin feed orders only; Pharmacy Admin pharmacy orders only. Duplicate/stale decisions → 409. |
| Audit | every submit/reject/approve → `ActivityLog` (module `delivery-proofs`, reason on rejections) + a row per state transition in `delivery_order_events`; original proofs are never overwritten. |
| Notifications | admins (proof awaiting review), rider (rejected with reason / completed), farmer (arrived / under review / delivered). |
| Farmer status | feed + pharmacy order payloads/timelines now include `arrived` and `proof_under_review` (a rejection is internal: the farmer keeps seeing "under review"); farmer feed + pharmacy screens render the new labels. |
| Flutter rider | `DeliveryDetailScreen`: **Mark Arrived**, photo picker + in-memory **preview**, multipart **Submit Delivery Proof** (button disabled until a photo exists), error + **Try again** (photo kept), "Proof under review" banner, rejection banner with the admin's reason + **Resubmit**; "Mark Delivered" removed everywhere; 6-step stepper, chips and orders quick-action updated; `DeliveryApiService/Session.submitProof`. |
| Flutter admin | new `AdminDeliveryProofsScreen` at `/admin/delivery-proofs` (sidebar "Delivery Proofs" for delivery/feed/pharmacy admins): filters, proof photo, History dialog (attempts + state history), Approve (confirm) and Reject (dialog, reason mandatory). Fallback permissions give Feed Admin approve/reject on `feedDelivery`. |
| Admin status labels | `arrived`, `Proof Under Review`, `Proof Rejected` added to the admin delivery lists. |

## 4. Tests

### Backend — `backend/scripts/test_delivery_proof_review.py` → **75 passed, 0 failed** (live DB, throw-away `proofreview+` accounts, self-cleaning)
valid/invalid transitions (skipping `arrived`, rider `delivered`/`proof_submitted` refused) · arrival (own rider only, farmer 403, other rider 404) · missing proof 400 · non-image 400 · fake image 400 · oversized 400 · JSON instead of multipart 415 · order unchanged and no proof rows after every failed upload · valid proof 201 and order **not** completed, no earning · second proof while one is open 409 · admin queue visibility per role (super/feed yes, pharmacy admin no) · rider/farmer/support/other-type admins cannot approve (403) · reject without/whitespace reason 400 · reject → `proof_rejected`, rider notified, reason visible, original proof preserved, farmer still sees "under review" · duplicate rejection 409, approving a rejected proof 409 · resubmission attempt 2 · old proof not approvable · approval → `delivered`, **exactly one earning and one farmer expense**, duplicate approval (same/other admin) 409 with no second record, delivered order refuses new proof · `total_deliveries` +1 · exact 7-step state history · 4 activity-log entries · admin detail with both attempts + events · pharmacy flow (wrong/missing OTP 400, pharmacy admin approves, feed admin 403).

Existing scripts updated for the new lifecycle through `scripts/delivery_flow_helpers.py` (rider no longer completes): `test_feed_order_delivery` 28, `test_delivery_proof_and_earnings` 27, `test_pharmacy_flow` 25 — all green.

### Flutter — `test/delivery_proof_review_test.dart` → **13 passed** (+ `delivery_proof_and_stats_test.dart` updated)
arrival button sends `arrived` and never shows "Mark Delivered" · proof picker, preview, submit disabled without photo · multipart upload lands on "proof under review" · upload failure + retry · rejection banner shows the reason, resubmission · admin queue lists proof, approve (confirm → POST → reload), reject dialog (confirm disabled without reason, sends reason), rejected view without actions, error state with Retry · Feed Admin fallback permissions · farmer feed order card shows "ARRIVED" / "PROOF UNDER REVIEW".

### Full suites
| Command | Result |
|---|---|
| `manage.py check` / `migrate --check` | no issues / exit 0 |
| `manage.py test` | cannot run — known F-014 (unchanged; asks to recreate a test DB for unmanaged tables) |
| all 47 `backend/scripts/test_*.py` | **all pass, 0 failures** |
| `flutter analyze` | 6 `info` (pre-existing `prefer_const` hints), 0 errors/warnings |
| `flutter test` | **262 passed**, 0 failed |
| `flutter build web --release` | `√ Built build\web` |

## 5. Real browser test (Chrome + Playwright, release build, backend on scratch DB `featherflow_clean`)
Order `#FD-75BBA6` (2 × layer feed, ৳2060) placed by a farmer. Evidence in `audit_logs/f005/` (screenshots, `e2e_log.txt`, JSON responses, `db_verification.json`).

| # | Step | Result | Evidence |
|---|---|---|---|
| 1 | Feed Admin assigns rider (real endpoint) | order `assigned`; rider sees request | `01_rider_assigned_request.png` |
| 2 | Rider accepts / opens delivery | detail screen, status Accepted | `02_rider_delivery_opened.png` |
| 3 | Picked up | API `picked_up`, farmer "out_for_delivery" | `03_…png` |
| 4 | Out for delivery | `on_the_way` | `04_…png` |
| 5 | Arrived | `arrived`, farmer sees **"arrived"**; "Mark Delivered" absent; direct PATCH delivered → **409** | `05_rider_arrived.png` |
| 6 | Upload proof (file chooser, preview, submit) | `proof_submitted` / "Proof under review"; farmer **"proof_under_review"**; **not** completed; no earning | `06a_…preview.png`, `06b_rider_proof_submitted.png` |
| 7 | Admin rejects | queue shows the order + photo; reject dialog needs a reason ("Photo is blurry, retake it") → `proof_rejected`; farmer still "under review" | `07a`–`07d_*.png` |
| 8 | Rider resubmits | rejection banner with reason; attempt 2 → `proof_submitted` (attempt 1 kept as rejected) | `08b`–`08d_*.png` |
| 9 | Admin approves | confirm dialog → approved | `09a`–`09c_*.png` |
| 10 | Completed | order `delivered` / "Completed"; farmer "delivered" (UI: `11_farmer_my_orders_delivered.png`) | `10a_rider_completed_tab.png` |
| 11 | Financial records | **1** `delivery_earnings` row (৳60), **1** feed `expenses` row (৳2060, `source_feed_order_id=FEED-71E675BBA6`); duplicate approve → **409** and reject-after-approve → **409** (`duplicate_approval.txt`) | `db_verification.json` |

State history (`delivery_order_events`): accepted→picked_up→on_the_way→arrived→proof_submitted→proof_rejected→proof_submitted→delivered, with actor role and notes. Proofs: attempt 1 `rejected` (reason + reviewer), attempt 2 `approved`. Activity log: Proof submitted / rejected / submitted / approved. Notifications: rider (assignment, rejected, completed), admins (×2 awaiting review).

Note: a first run (`audit_logs/f005/run1_no_category/`) showed 0 expense rows only because the scratch DB had no `Feed` expense category (seed data absent there); after adding it the full flow was re-run and produced the single expense above. The dev DB has the category, and the backend regression asserts the exactly-once mirror.

## 6. Notes / limits
* The `proof_rejected` state is hidden from the farmer by design (they see "Proof under review").
* The older `POST /api/delivery/proof-upload/` endpoint is kept (used for the optional signature), but it no longer completes anything.
* Servers were stopped after testing; scratch DB `featherflow_clean` left in place.

## 7. Confirmation
Verified with backend and Flutter regression tests, all existing suites, a release build and a real Chrome run against the real backend — not by code review alone. **Nothing was committed.**
