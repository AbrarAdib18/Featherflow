# Feed Marketplace Verification — Reconciliation

This document corrects and grounds the prior implementation report against
direct evidence: file diffs, fresh test runs, direct database queries, real
HTTP calls against the running backend with freshly-created disposable data,
and live headless-browser screenshots. **It supersedes
`FEED_MARKETPLACE_REQUIREMENTS_MATRIX.md` wherever the two disagree** — that
earlier matrix incorrectly marked several Feed Marketplace Admin workflow
steps as "Done (pre-existing)" based on a subagent's summary rather than
direct verification. Section 4 below documents exactly which claims were
wrong and corrects them.

No code was changed during this reconciliation. Only: read-only inspection,
fresh test runs, disposable database rows created and deleted through real
API calls, and two short-lived local dev-server sessions for verification
(both stopped at the end).

---

## 1. Working-tree accounting — all 79 changed/untracked files

Verified by reading `git diff` for every file this report claims was touched
this session, and confirming byte-for-byte which hunks are mine vs.
pre-existing (present in git status before this conversation began, per the
very first system-reminder git status in this conversation).

### Backend models/migrations (this session)

| File | Why |
|---|---|
| `backend/feed_owner_extension.sql` | New. DDL: `feed_owner` role, widened `roles.panel_type` CHECK constraint, `feed_owner_profiles` table, `expenses.source_feed_order_id` column + unique index. |
| `backend/profiles/models.py` | +33 lines: added `FeedOwnerProfile` class only. **Diff also contains a pre-existing, unrelated hunk** (`PharmacyOrganization.review_state` field + `REVIEW_STATE_CHOICES`) that predates this session — it was already uncommitted before this conversation started (git status showed `M backend/profiles/models.py` at conversation start). Verified via `git diff`: both hunks are present against HEAD; only the `FeedOwnerProfile` class is mine. |
| `backend/profiles/migrations/0007_feed_owner_profile.py` | New. State-only `CreateModel` for `FeedOwnerProfile`, mirrors the existing `pharmacy/migrations/0003_pharmacy_admin_portal.py` pattern exactly. |
| `backend/expenses/models.py` | +4 lines: added `source_feed_order_id` field only. Verified via `git diff` — isolated hunk, nothing else touched. |
| `backend/expenses/migrations/0003_source_order_mirrors.py` | New. Also reconciles two **pre-existing, previously-unmigrated** fields (`source_intent_id`, `source_pharmacy_order_id`) that were already on the model but never had a migration — a pre-existing state drift, not introduced by this session (confirmed: neither field's migration existed anywhere in `expenses/migrations/` before this file). |

### Backend permissions (this session)

| File | Why |
|---|---|
| `backend/feed_catalogue/owner_permissions.py` | New. `IsFeedOwnerAccount` — plain role check, mirrors `pharmacy/permissions.py::IsPharmacyAccount` verbatim. |

### Backend APIs/views/urls (this session)

| File | Why |
|---|---|
| `backend/feed_catalogue/owner_views.py` | New. Owner's own profile GET/PATCH. |
| `backend/feed_catalogue/owner_chat_views.py` | New. Owner side of the owner↔admin chat. |
| `backend/feed_catalogue/owner_urls.py` | New. Mounts the two files above at `/api/feed-owner/`. |
| `backend/api/admin_feed_chat.py` | New. Admin side of the owner↔admin chat (team inbox), mirrors `api/admin_pharmacy_chat.py`. |
| `backend/api/urls.py` | +71/-... lines in the raw diff, but **only ~10 of those lines are mine** (verified via full `git diff` read): the `admin_feed_chat` import block, `feed_catalogue.owner_urls` import, `path('feed-owner/', include(...))`, and the 5 `admin-panel/feed-chats/...` routes. The remaining ~60 lines in the same diff (all the `admin_pharmacy_*` routes) are pre-existing, uncommitted from before this session — `backend/api/urls.py` was already listed as `M` in the very first git status of this conversation. |
| `backend/delivery/views.py` | +3 lines: the `mirror_feed_expense` call in `_sync_feed_order`'s `delivered` branch. Isolated hunk, verified via `git diff`. |
| `backend/feed_catalogue/services.py` | +66 lines: `mirror_feed_expense` function only, appended to the existing file. |
| `backend/community/permissions.py` | +1 line: `feed_owner` entry in `_BADGE_ROLES`. |

### Backend tests (this session)

| File | Why |
|---|---|
| `backend/scripts/test_feed_owner_flow.py` | New. 32-assertion regression suite for the new role/chat/finance-mirror. |
| `backend/scripts/test_feed_order_delivery.py` | +5 lines: added `Expense.objects.filter(created_by__in=users).delete()` to `cleanup()`. **Why this changed**: wiring `mirror_feed_expense` into the delivery-completion path (above) meant this pre-existing test's `delivered` step now creates a real `Expense` row for its test farmer; its `cleanup()` didn't know about that new row and hit a `ProtectedError` trying to delete the user first. This is a **real regression this session caused and then fixed** — documented honestly in section 2. |

### Backend seed/demo files (this session)

| File | Why |
|---|---|
| `backend/feed_catalogue/management/commands/seed_feed_marketplace_demo.py` | +50 lines: added `_seed_fixed_accounts()` (creates `feed.admin@featherflow.local` / `feed.owner@featherflow.local` idempotently) and its call site. Isolated addition — the rest of the file (companies/products/farmers/riders/orders seeding) is unchanged and pre-existing. |

### Flutter screens/widgets (this session)

| File | Why |
|---|---|
| `lib/features/feed_owner/presentation/screens/feed_owner_home_screen.dart` | New. |
| `lib/features/feed_owner/presentation/screens/feed_owner_chat_screen.dart` | New. |
| `lib/features/admin/presentation/screens/admin_feed_chats_screen.dart` | New. |
| `lib/features/admin/presentation/widgets/admin_sidebar.dart` | +8 lines: one new `_NavItem` ("Feed Owner Chat"). This file was **not** modified before this session (absent from the original git status) — the entire diff is mine. |

### Flutter services/models (this session)

| File | Why |
|---|---|
| `lib/features/feed_owner/data/services/feed_owner_service.dart` | New. |
| `lib/features/admin/data/services/admin_api_service.dart` | Diff is +232 lines total, but **only 15 of those lines are mine** (the `feedChats`/`feedChatDetail`/`replyFeedChat`/`setFeedChatStatus` block, verified via `git diff` grep). The remaining ~217 lines (pharmacy account-lifecycle/medicine-CRUD/employee/chat/appeals/metrics methods) are pre-existing, uncommitted from before this session (`admin_api_service.dart` was already `M` at conversation start). |
| `lib/core/router/app_router.dart` | +17 lines: `AppRoutes.feedOwnerHome`/`adminFeedChats` constants, two `GoRoute`s, two imports. Entirely mine — this file was **not** in the original git status. |
| `lib/core/network/auth_service.dart` | +1 line: `'feed_owner': AppRoutes.feedOwnerHome` in the role→destination map. Entirely mine — not in the original git status. |

### Flutter tests (this session)

| File | Why |
|---|---|
| `test/feed_owner_smoke_test.dart` | New. 2-assertion widget smoke test. |

### Documentation (this session)

| File | Why |
|---|---|
| `FEED_MARKETPLACE_ADMIN_AUDIT.md` | Written this session. |
| `FEED_MARKETPLACE_ADMIN_IMPLEMENTATION_REPORT.md` | Written this session — **contains claims corrected by this document** (see section 4). |
| `FEED_MARKETPLACE_REQUIREMENTS_MATRIX.md` | Written this session — **contains claims corrected by this document** (see section 4). |
| `FEED_MARKETPLACE_VERIFICATION_RECONCILIATION.md` | This file. |

### Unrelated changes (pre-existing, NOT from this session — listed for completeness since they're part of the same 79-file working tree)

All of the following were already modified/untracked **before this
conversation started** (present in the very first git-status system-reminder)
and were never touched by this session — verified by (a) absence from every
tool call I made this session, and (b) for the handful sharing a file with my
own edits, isolating the diff hunks as shown above:

`backend/api/admin_approvals.py`, `backend/api/admin_extra.py`,
`backend/api/admin_pharmacy.py`, `backend/api/admin_rbac.py`,
`backend/api/admin_views.py`, `backend/doctor/models.py`,
`backend/featherflow_backend/settings.py`, `backend/pharmacy/catalogue_views.py`,
`backend/pharmacy/models.py`, `backend/pharmacy/services.py`,
`backend/pharmacy/urls.py`, `backend/pharmacy/views.py`,
`backend/scripts/test_admin_panel.py`, `backend/scripts/test_pharmacy_flow.py`,
`backend/scripts/test_signup_flows.py`, `backend/scripts/test_verification_status.py`,
`backend/users/management/commands/seed_platform_demo.py`,
`backend/users/serializers.py`, `backend/users/views.py`,
`lib/core/widgets/profile_photo_field.dart`,
`lib/features/admin/presentation/screens/admin_pharmacy_screen.dart`,
`lib/features/pharmacy/data/services/pharmacy_session.dart`,
`lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart`,
`test/admin_screens_smoke_test.dart`, all `PHARMACY_ADMIN_*.md` and
`FEATHERFLOW_COMPLETE_REQUIREMENTS_MATRIX.md` docs, `backend/api/admin_pharmacy_chat.py`,
`backend/api/admin_pharmacy_metrics.py`, `backend/doctor/migrations/0002_pharmacy_chat_fields.py`,
`backend/pharmacy/appeal_views.py`, `backend/pharmacy/auth.py`,
`backend/pharmacy/chat_views.py`, `backend/pharmacy/migrations/0003_pharmacy_admin_portal.py`,
`backend/pharmacy/permissions.py`, `backend/pharmacy/permissions_views.py`,
`backend/pharmacy_admin_portal_extension.sql`, `backend/profiles/migrations/0006_pharmacy_review_state.py`,
`backend/scripts/_create_missing_admin_accounts.py`, `backend/scripts/_create_pharmacy_admin.py`,
`backend/scripts/_create_pharmacy_admin_2.py`, `backend/scripts/test_pharmacy_admin.py`,
`lib/features/pharmacy/data/services/pharmacy_appeal_service.dart`,
`lib/features/pharmacy/data/services/pharmacy_chat_service.dart`,
`lib/features/pharmacy/data/services/pharmacy_permissions_service.dart`,
`lib/features/pharmacy/presentation/screens/pharmacy_appeal_screen.dart`,
`lib/features/pharmacy/presentation/screens/pharmacy_support_chat_screen.dart`,
`lib/features/pharmacy/presentation/widgets/pharmacy_locked_banner.dart`.

**No accidental or unexplained changes were found.** Every hunk in every file
this session touched is accounted for above, and it is isolated (a handful of
added lines or a small new file) rather than a broad refactor.

---

## 2. Exact test results

### New backend tests

```
backend/venv/Scripts/python.exe scripts/test_feed_owner_flow.py
```
**32 passed, 0 failed.** (Re-run fresh during this reconciliation, not reused
from earlier in the conversation.)

### Full backend suite (39 scripts, run fresh, individually, this reconciliation)

38 of 39 scripts exited 0 with a clean `N passed, 0 failed` summary line; **sum
of passing assertions across those 38 scripts: 1,367.** One script failed —
see below. No script reported any failed assertion; the one failure is a
crash before its summary line is reached, not a counted test failure.

Per-script counts (all "0 failed"):
`test_admin_panel.py`=66, `test_admin_row_builder_performance.py`=35,
`test_articles_feed.py`=28, `test_community.py`=56,
`test_community_feed_performance.py`=20, `test_consultation_booking_rules.py`=29,
`test_consultation_chat_access.py`=13, `test_consultation_transitions_and_receipts.py`=53,
`test_cost_dashboard_charts.py`=20, `test_dashboard_integrity_and_seed_idempotency.py`=13,
`test_data_integrity.py`=11, `test_delivery_multi_active.py`=34,
`test_delivery_proof_and_earnings.py`=24, `test_disease_detection.py`=25,
`test_doctor_flow.py`=58, `test_farmer_panel.py`=39, `test_feed_catalogue.py`=22,
`test_feed_marketplace_ux.py`=20, `test_feed_order_delivery.py`=26,
`test_feed_owner_flow.py`=32, `test_feed_stock_integrity.py`=29,
`test_flock_feed_management.py`=17, `test_labour_payment.py`=27,
`test_pharmacy_admin.py`=132, `test_pharmacy_flow.py`=22,
`test_pharmacy_marketplace_card_fields.py`=13, `test_pharmacy_medicine_edit.py`=7,
`test_pharmacy_medicine_images.py`=20, `test_pharmacy_profile.py`=32,
`test_private_documents.py`=31, `test_profile_photo.py`=58,
`test_signup_documents.py`=46, `test_signup_flows.py`=107,
`test_subscription_payment.py`=65, `test_tax_calculator.py`=64,
`test_verification_flows.py`=36, `test_verification_status.py`=25,
`test_vets_nearby.py`=12.

### The confirmed unrelated failure

**`scripts/test_admin_pagination_performance.py`** — crashes 65 assertions in
(all 65 preceding assertions passed), on the "consultations" module's
pagination check:

```
Traceback (most recent call last):
  File "D:\Featherflow Final\backend\scripts\test_admin_pagination_performance.py", line 140, in <module>
    main()
  File "D:\Featherflow Final\backend\scripts\test_admin_pagination_performance.py", line 100, in main
    check_module(c, module)
  File "D:\Featherflow Final\backend\scripts\test_admin_pagination_performance.py", line 71, in check_module
    r = c.get(f'/api/admin-panel/{module}/?page=1&page_size={page_size}')
  ...
  File "D:\Featherflow Final\backend\api\admin_views.py", line 1177, in admin_collection
    rows, total = _collection_rows(request, module)
  File "D:\Featherflow Final\backend\api\admin_views.py", line 1032, in _collection_rows
    'time': f'{c.appointment_date} {c.appointment_time:%H:%M}',
TypeError: unsupported format string passed to NoneType.__format__
```

**Proof this is 100% pre-existing and unrelated to this session:**
```
$ git diff backend/api/admin_views.py | grep appointment_time
(no output — the line is not part of any uncommitted change)

$ git show HEAD:backend/api/admin_views.py | sed -n '1020,1035p'
...
'time': f'{c.appointment_date} {c.appointment_time:%H:%M}',
...

$ git log -1 --format="%H %ai" -- backend/api/admin_views.py
0b6903734770f8924294d355c835ffb6bd81f596 2026-09-17 20:50:35 +0600
```
The buggy line exists verbatim in the last real commit (dated 2026-09-17,
nine days before this conversation), and `git diff` shows zero changes to it.
A `Consultation` row in the live DB has `appointment_time = NULL`, which this
pre-existing code doesn't guard against. **This is not touched by, or a
consequence of, this session's work.**

### Flutter tests

```
flutter test
```
**194 passed, 0 failed.** (Re-run fresh during this reconciliation.)

### `flutter analyze`

Full-project run (not scoped to changed files): **6 issues found** — all
`info`-level lint suggestions (`prefer_const_constructors`,
`prefer_const_literals_to_create_immutables`) in
`lib/features/farmer/presentation/screens/farmer_feed_marketplace_screen.dart`,
a file never touched by this session. Zero issues in any file this session
added or modified (confirmed by an earlier scoped run against exactly those
files, and by this full-project run producing no findings outside that one
unrelated file).

### `flutter build web --release`

Re-run fresh during this reconciliation. **Succeeded, exit code 0.**
`build/web/main.dart.js` (6.6 MB) timestamped `2026-09-26 20:41` — current,
built after every code change in this session. Pre-existing Wasm-compat
warnings (`flutter_secure_storage_web`, `socket_io_common`) are advisory only
and don't block the build; unrelated to this session's files.

### `manage.py check`

```
System check identified no issues (0 silenced).
```

### `manage.py migrate --check`

Exit code **0** (clean) — but only after this session's SQL extension
(`feed_owner_extension.sql`) was applied to the live DB and
`manage.py migrate` was run to record the two new migrations. **Before that
step, `migrate --check` exits 1** (2 unapplied migrations: `profiles.0007`,
`expenses.0003`) — this is expected and is the normal state for a change that
hasn't been deployed yet, not a defect.

Separately, `manage.py makemigrations --check --dry-run` shows unrelated,
pre-existing model/migration drift across `audit`, `community`, `expenses`
(Meta-options only), `farms`, `feed`, `notifications`, `payments`,
`profiles` (Meta-options only), `subscriptions`, `users`, `workers` — none of
it touches anything this session added; it predates this conversation.

---

## 3. Verify the current running database

Live Postgres, `featherflow` @ `localhost:5432` (from
`backend/featherflow_backend/settings.py`'s `DATABASES['default']`, backed by
`.env`'s `POSTGRES_*` vars) — the same single dev database used throughout
this entire conversation; not a separate test database.

**Migration names applied** (`manage.py showmigrations profiles expenses`):
```
profiles: 0001_initial, 0002_doctorprofile_district, 0003_add_missing_profile_models,
          0004_rider_location, 0005_admin_shift_payment, 0006_pharmacy_review_state,
          0007_feed_owner_profile          [X]
expenses: 0001_initial, 0002_farmer_panel, 0003_source_order_mirrors   [X]
```

**Direct ORM queries against the live DB** (run this reconciliation session):

```
feed_owner role exists: True, panel_type= feed_owner
feed.owner@featherflow.local count: 1
feed.admin@featherflow.local count: 1
owner roles: ['feed_owner']
FeedOwnerProfile count for owner: 1
profile: Featherflow Feed Inventory | Savar, Dhaka | ['starter','grower','finisher','layer'] | active
admin roles: ['feed_admin']
case-insensitive dupe check owner: 1, admin: 1
```

**No duplicate demo accounts** — confirmed by the counts above (exactly 1
each), and by running `seed_feed_marketplace_demo` a second time within this
session: `created=0, skipped=42` (every row already existed, nothing
duplicated).

**Feed order expense mirroring — exactly once, proven live**: the earlier
in-conversation test (`test_feed_owner_flow.py`) had already cleaned up its
own demonstration row, so a **fresh, disposable** direct call was made
against the live DB this reconciliation session:

```
CALL 1 -> expense id: e6155bec-c5b6-49cb-b5aa-d4e6435caeed, amount: 999.50, category: Feed
CALL 2 -> expense id: e6155bec-c5b6-49cb-b5aa-d4e6435caeed, same row as call 1: True
Total Expense rows for this order id after 2 calls: 1
```
And the DB-level guard was confirmed independently of the Python logic:
```
$ psql ... -c "\d expenses" | grep uq_expenses_source_feed_order
"uq_expenses_source_feed_order" UNIQUE, btree (source_feed_order_id) WHERE source_feed_order_id IS NOT NULL
```
A second, independent live demonstration ran later in this same
reconciliation via the full order lifecycle (see section 4, item 32) —
also exactly one row. Both disposable rows were deleted after being recorded.

---

## 4. Feed Marketplace Admin requirements — live verification matrix

**Method**: fresh disposable data created through real HTTP calls against the
running backend (`http://127.0.0.1:8000`, real Postgres, real JWT
authentication) — a new company, product, farmer, and rider, none of them
seed data — walked through the entire order lifecycle end to end, plus two
live browser screenshots for the UI-rendering claims. All disposable data was
deleted afterward (confirmed: 0 remaining rows). **This section corrects
several "Done (pre-existing)" claims in the earlier
`FEED_MARKETPLACE_REQUIREMENTS_MATRIX.md`, which were based on a
subagent's code summary rather than direct testing — that was a mistake.**

| # | Step | URL/route | Request | Response | Artifact | Result |
|---|---|---|---|---|---|---|
| 1 | Feed Marketplace Admin login | `POST /api/auth/login/` | `{email, password}` (real password `ChangeMe@2026!`) | `200`, real user object, `roles:["feed_admin"]` | — | ✅ VERIFIED |
| 2 | Dashboard | `GET /api/admin-panel/feed-catalogue/analytics/` + live browser | — | `200`, `{"total_orders":11,...}` (live counts) | `recon_01_feed_dashboard.png` — shows 5 Companies/26 Products/12 Orders, matching the DB state at that moment | ✅ VERIFIED |
| 3 | Add feed product | `POST /api/admin-panel/feed-catalogue/products/` | fresh company + product payload | `201`, `approval_status:"pending_review"` | `step4_product.json` | ✅ VERIFIED |
| 4 | Edit feed product | `PATCH .../products/{id}/` | `{price:1100, description:"Edited..."}` | `200`, fields updated | — | ✅ VERIFIED |
| 5 | Upload image | `POST .../products/{id}/image/` | multipart PNG | `201`, real `image_url` set | — | ✅ VERIFIED (upload only — replace/remove-primary-image were **not exercised** this pass; the gallery-delete endpoint exists in code (`product_gallery_image_delete`) but wasn't called) |
| 6 | Add stock | `PATCH .../products/{id}/` | `{stock_quantity:50}` | `200` | — | ✅ VERIFIED — but **no dedicated "adjust stock" endpoint or stock-history audit trail exists**; it's a plain field overwrite via the general product-edit endpoint, unlike pharmacy's delta-based `adjustPharmacyMedicineStock` |
| 7 | Adjust stock | (same endpoint as #6) | — | — | — | ✅ VERIFIED, same caveat as #6 |
| 8 | Farmer sees active product | `GET /api/farmers/feed-catalogue/products/?search=Reconcile` | — | `200`, product listed, `in_stock:true` | — | ✅ VERIFIED |
| 9 | Farmer adds valid quantity | `POST /api/farmers/feed-catalogue/orders/` | qty=3 (min=2, stock=50) | `201` | `step12_order.json` | ✅ VERIFIED |
| 10 | Minimum quantity validation | same endpoint | qty=1 (min=2) | `409`, `"has a minimum order quantity of 2."` | — | ✅ VERIFIED |
| 11 | Stock validation | same endpoint | qty=1000 (stock=50) | `409`, `"Only 50 bag_25kg ... in stock."` | — | ✅ VERIFIED |
| 12 | Farmer submits order | (same call as #9) | — | `201`, real `total_amount`, `latitude/longitude`, `delivery_address` | — | ✅ VERIFIED |
| 13 | Admin receives order | `GET .../orders/{id}/` | — | `200` | — | ✅ VERIFIED (also: real `Notification` created for both `feed.admin@...` and the demo admin) |
| 14 | Admin sees farmer address | (same) + browser | — | `delivery_address` field present | screenshot shows `Reconcile Farmer · +8801999111222 · Reconcile Test Farm, Dhaka` rendered on the order card | ✅ VERIFIED |
| 15 | Admin sees lat/lng | (same) + browser | — | `latitude:23.81, longitude:90.41` | screenshot shows `Map: 23.81, 90.41` as plain text | ✅ VERIFIED (data present) |
| 16 | Admin sees **map preview** | — | — | — | `recon_02_orders_delivery_tab.png` | ❌ **NOT IMPLEMENTED** — "Map: 23.81, 90.41" is plain grey text, not a rendered map. No `flutter_map`/`google_maps_flutter` widget anywhere in `admin_feed_screen.dart` (confirmed by reading the file's `_ordersTab()`). **Corrects the earlier matrix's "Done (pre-existing)" claim.** |
| 17 | Admin confirms/prepares order | — | — | — | — | ❌ **NOT IMPLEMENTED** — `backend/feed_catalogue/admin_urls.py` has no confirm/prepare/ready endpoint. An order goes directly from `created` to `assigned` via `order_assign`; the farmer-facing "timeline" UI shows `confirmed`/`preparing`/`ready_for_pickup` steps that nothing ever marks done. **Corrects the earlier matrix.** |
| 18 | Admin assigns a rider | `POST .../orders/{id}/assign/` | `{rider_id}` | `201`, `status:"assigned"`, real `DeliveryOrder` created | — | ✅ VERIFIED |
| 19 | **Offline-rider warning** before assignment | (same call, rider pre-set `is_online=False`) | — | `201` — assignment succeeded silently, **no warning field anywhere in the response** | `available_riders` does expose `is_online:false` for the picker, but `order_assign` itself performs no check and returns no warning | ❌ **NOT IMPLEMENTED** for feed orders (pharmacy's equivalent flow does have this, per `test_pharmacy_admin.py`: "assigning to an offline rider still succeeds (warn, do not block)" — feed orders were never given the same treatment). **Corrects the earlier matrix.** |
| 20 | Rider sees assignment in queue | `GET /api/delivery/requests/` | — | `200`, real order with `delivery_lat/lng`, items, farmer contact | — | ✅ VERIFIED |
| 21 | Rider sees route/map | `GET /api/delivery/orders/{id}/route/` | — | `404 "No route found."` | — | ⚠️ **UNVERIFIED** — this dev environment has no `GOOGLE_MAPS_API_KEY` configured, so the Google Directions proxy this endpoint calls has nothing to query. Not proven broken, not proven working. |
| 22 | Rider accepts/picks up | `PATCH /api/delivery/requests/{id}/respond/` then `PATCH /api/delivery/orders/{id}/status/` | `{action:"accept"}`, `{status:"picked_up"}` | `200`, `200` | — | ✅ VERIFIED |
| 23 | Rider marks out for delivery | `PATCH .../status/` | `{status:"on_the_way"}` | `200` | — | ✅ VERIFIED |
| 24 | Rider marks **arrived** | `PATCH .../status/` | `{status:"arrived"}` | `409 "Cannot move delivery from on_the_way to arrived."` | — | ❌ **NOT IMPLEMENTED** — there is no `arrived` state in `delivery/views.py`'s `_TRANSITIONS` (`accepted→picked_up→on_the_way→delivered/failed`). **Corrects the earlier matrix**, which listed this as done. |
| 25 | Rider must upload proof photo | `POST /api/delivery/proof-upload/` then `PATCH .../status/ {status:"delivered"}` **without** a proof URL | multipart PNG; then bare delivered | Upload `201`; delivered-without-proof `400 "A proof-of-delivery photo is required..."` | — | ✅ VERIFIED (mandatory, enforced server-side) |
| 26 | Admin sees proof in a **review queue** | — | — | — | — | ❌ **NOT IMPLEMENTED** — no such queue/endpoint exists anywhere in `feed_catalogue/order_admin_views.py`. |
| 27 | Admin **rejects proof with reason** | — | — | — | — | ❌ **NOT IMPLEMENTED** |
| 28 | Rider **resubmits proof** | — | — | — | — | ❌ **NOT IMPLEMENTED** (moot — nothing rejects it in the first place) |
| 29 | Admin **approves proof** | — | — | — | — | ❌ **NOT IMPLEMENTED** |
| 30 | Order completed **only after approval** | `PATCH .../status/ {status:"delivered", proof_of_delivery_url:"..."}` | real proof token | `200`, `status:"delivered"`, `delivered_at` set **immediately** | — | ❌ **NOT IMPLEMENTED** — the order becomes `delivered` the instant the rider submits a valid proof token; there is no intermediate "submitted/pending review" state and no admin gate. **This directly contradicts the earlier implementation report's claim that this workflow was "Done (pre-existing)."** |
| 31 | Farmer sees completed status | `GET /api/farmers/feed-catalogue/orders/{id}/` | — | `200`, `status:"delivered"` | — | ✅ VERIFIED |
| 32 | Feed expense — exactly once | direct DB query | — | 1 `Expense` row, `source_feed_order_id` set, amount matches order total | — | ✅ VERIFIED (this specific order, in addition to the isolated double-call test in section 3) |
| 33 | Notifications appear | direct DB query | — | Real `Notification` rows: farmer got "Order placed" → "Rider assigned" → "Feed delivery picked up" → "Feed delivery delivered"; `feed.admin@featherflow.local` got "New feed order" | — | ✅ VERIFIED |
| 34 | Refresh/relogin preserves state | full backend process restart, then re-query | — | Feed owner↔admin chat history and all order data intact after a full server restart (real Postgres persistence, not in-memory) | — | ✅ VERIFIED |

### Summary of section 4

- **Verified working**: 1–15, 18, 20, 22, 23, 25, 31–34 (23 of 34 items).
- **Not implemented** (confirmed by code inspection + live 409/absence of any
  endpoint, not by assumption): 16, 17, 19, 24, 26, 27, 28, 29, 30 (9 items).
  **This is the single most important correction in this reconciliation**:
  the "mandatory proof photo → admin review → approve/reject → completion"
  pipeline the original spec asked for **does not exist for feed orders**.
  What exists is: proof photo is mandatory, but submitting it completes the
  order immediately with no human review step.
- **Unverified** (environment limitation, not a code defect): 21 (no Google
  Maps API key configured in this dev environment).
- Items 5 (partial — replace/remove not exercised).

---

## 5. Feed Inventory Owner — verification

| Item | Method | Result |
|---|---|---|
| 1. Login | Real password `POST /api/auth/login/` — verified **twice** in this reconciliation: once via live browser (screenshot, this conversation's earlier turn) and again via a fresh `curl` call after a full backend restart | ✅ `200` both times |
| 2. Only home/profile/inventory/chat/Community/logout visible | Live browser screenshot | ✅ Confirmed — see `02_feed_owner_home.png` from earlier in this conversation |
| 3. No admin sidebar | Code: `FeedOwnerHomeScreen` never references `AdminShell`/`AdminSidebar`; live screenshot confirms a plain `Scaffold`, not the admin shell | ✅ Confirmed |
| 4. No pharmacy/farmer/doctor/delivery/finance/unrelated-admin access | Live `curl` (this reconciliation, fresh tokens, post-restart): `/api/admin-panel/feed-catalogue/products/` → `403`; `/api/admin-panel/pharmacy-chats/` → `403`; `/api/doctor/dashboard/` → `403 "A doctor account is required."`; `/api/delivery/dashboard/` → `403`; `/api/pharmacy/dashboard/` → `403`; `/api/costs/expenses/` → `403 "A farmer account is required."` | ✅ Confirmed — 6 real denials, not inferred |
| 5. Profile renders | Live browser + `GET /api/feed-owner/profile/` | ✅ Real data shown (business name, location, categories, status) |
| 6. Chat opens | `POST /api/feed-owner/chat/` + browser | ✅ `201`/live |
| 7. Message sends | `POST /api/feed-owner/chat/{id}/` + browser | ✅ |
| 8. Admin receives it | `GET /api/admin-panel/feed-chats/` (admin token) | ✅ Real conversation + message visible |
| 9. Admin replies | `POST /api/admin-panel/feed-chats/{id}/messages/` + browser | ✅ |
| 10. Owner receives reply | Owner GET + browser, and after a full relogin | ✅ |
| 11. Read/unread works | `unread_count` verified 0→1→0 across the flow | ✅ |
| 12. Resolve works | `PATCH .../status/ {resolved}` + browser (button flips to "Reopen") | ✅ |
| 13. Reopen works | `PATCH .../status/ {reopened}` | ✅ |
| 14. Refresh/relogin preserves history | Verified across a **full backend process restart** this reconciliation session — `GET /api/admin-panel/feed-chats/` still shows `status:"resolved"` and the last message from the prior conversation-turn's browser session | ✅ Strongest possible evidence — real Postgres persistence, not client cache |
| 15. Unauthorized role access denied | See item 4, plus: another `feed_owner` account gets `404` (not data leakage) trying to post into this owner's conversation; `admin_pharmacy` gets `403` on the feed chat inbox (`test_feed_owner_flow.py`) | ✅ Confirmed |

All 15 items verified. No corrections needed to this section.

---

## 6. Community access — verification (freshly re-tested this reconciliation, both roles)

| Item | Feed Marketplace Admin | Feed Inventory Owner |
|---|---|---|
| Community opens | Pre-existing, no gate (any authenticated user) | ✅ Live browser, `recon`/earlier screenshot |
| Feed-related post created | `POST /api/community/` → `201`, `role:"Feed Admin"`, `badge:{"type":"team","label":"Team Featherflow"}` | `POST /api/community/` → `201`, `role:"Feed Owner"`, `badge:{"type":"feed_owner","label":"Verified Feed Supplier"}` (proves this session's `_BADGE_ROLES` addition works) |
| Post appears in feed | `GET /api/community/posts/{id}/` as a third-party farmer → `200`, visible | Same, verified |
| Own post edited | — (not separately tested for admin; identical code path to owner's, which was tested) | `PUT /api/community/posts/{id}/` → `200`, content updated |
| Own post archived | — (same code path) | `DELETE /api/community/posts/{id}/` → `204` |
| Comments/replies work | — | Farmer commented on owner's post → `201` |
| Reactions work | — | Farmer reacted `like` on owner's post → `200` |
| Notifications work | — | `Notification(title="New community reply")` confirmed created for the owner in the live DB |
| Neither role can moderate unrelated content | A disposable `admin_pharmacy` account tried `DELETE` on the owner's **active** post it doesn't own → `403 "You can only edit your own posts."`/`"You can only delete your own posts."` (not a moderator grant) | Same denial applies structurally (community moderation is gated by `can_perform_action(user,'community',action)`, and neither `feed_owner` nor `feed_admin` holds it) |
| Pharmacy Admin / delivery / unauthenticated denied per policy | Pharmacy Admin: denied moderation as above. Unauthenticated: `GET /api/community/` → `401 "Authentication credentials were not provided."` | Same |
| Refresh/relogin preserves posts | Postgres-backed, same persistence guarantee demonstrated in section 5 item 14 | Same |

All Community claims are now backed by fresh, this-session API evidence
(not just a single "opened the feed" screenshot as in the prior report).

---

## 7. Code-quality concerns

**Reusing pharmacy chat status fields — domain leakage?** The columns are
literally named `pharmacy_chat_status`/`assigned_admin` on the shared
`conversations` table (from `pharmacy_admin_portal_extension.sql`), reused
as-is for the feed owner↔admin chat. This is a real naming leak (a
maintainer reading `feed_owner_extension.sql`'s comment or the column name
cold, without context, could reasonably assume it's pharmacy-only) but not a
functional/security leak: the two chat surfaces are fully isolated by query
(`_pharmacy_conversations_qs()` filters `roles__name='pharmacy'`;
`_feed_owner_conversations_qs()` filters `roles__name='feed_owner'` —
verified by reading both files side by side), so a pharmacy conversation can
never appear in the feed inbox or vice versa. **Recommendation**: if this
pattern is extended to a third chat type, rename the columns to something
generic (`admin_chat_status`) via a follow-up migration; not urgent for two
consumers.

**Is Feed Inventory Owner incorrectly treated as admin?** No — verified at
the code level, not just empirically. `api/admin_rbac.py::admin_roles()`
returns `[r for r in user.roles.all() if r.panel_type == 'admin']`; the live
DB confirms `feed_owner`'s `panel_type = 'feed_owner'`, a distinct value. A
`feed_owner` user can never populate that list, so `is_admin()` and
`IsAdminUser` are always `False` for it — proven both by this code trace and
by 6 real `403`s in section 5.

**Is the DB role CHECK migration safe and reversible?** Safe: it only widens
an enum (adds `'feed_owner'` to the allowed `panel_type` values), so it
cannot invalidate any existing row. Reversible in principle (drop and
re-add the constraint without `'feed_owner'`) but only after removing/
reassigning any row that has `panel_type='feed_owner'` first — standard for
tightening any CHECK constraint, and not something `feed_owner_extension.sql`
provides a down-script for. This matches the existing convention in this
codebase: none of the other extension SQL files here (`feed_marketplace_extension.sql`,
`pharmacy_admin_portal_extension.sql`, etc.) ship a rollback script either —
this is a project-wide pattern, not a deviation introduced this session.

**Is the expense mirror idempotent and correctly tied to order completion?**
Idempotent: yes, proven twice this session (section 3's isolated double-call,
and section 4 item 32's real order) plus a DB-level unique index (not just
application logic) as the actual guard. Correctly tied to completion: this
is where section 4 matters — it fires on the `delivered` transition, which
(per the same section's findings) happens **immediately** on proof upload
with no admin approval gate. The mirror itself is correct; the event it's
tied to fires earlier in the lifecycle than the original spec intended.

**Are permissions enforced server-side?** Yes, for everything this session
built — every restriction claimed in section 5 was demonstrated with a real
HTTP call returning `403`/`404`, not a UI-only check. The pre-existing Feed
Marketplace Admin surface (section 4) also enforces its permissions
server-side (`can_perform_action` checks throughout) — the gaps found there
are missing *features* (no map, no confirm step, no proof-review gate), not
missing *authorization checks* on the features that do exist.

**Do the 79 files include accidental broad refactors?** No — see section 1.
Every file this session touched has an isolated, small diff; the large diffs
in the working tree (`admin_pharmacy.py` +1054, `admin_pharmacy_screen.dart`
+1517, etc.) all predate this session and were never touched by it.

**Is the frontend being tested the same build served to the user?** For this
reconciliation: yes — `flutter build web --release` was re-run fresh
immediately before the live-browser verification pass, `build/web/main.dart.js`
was timestamped seconds before the browser session started, and it was served
directly from `build/web` via `python -m http.server 8080` with no
intermediate deploy step. There is no separate "production" instance in this
environment — the only thing ever served to anyone in this conversation was
this same freshly-built `build/web` folder.

---

## 8. Nothing was committed

```
$ git status --short | wc -l
79
$ git log --oneline -1
49c3d74 Merge branch 'main' of https://github.com/AbrarAdib18/Featherflow
```
Same file count and same HEAD as before this reconciliation began. No `git
add`, `git commit`, or `git push` was run at any point.

## Recommended fixes (priority order, not yet implemented — awaiting direction)

1. Add an explicit admin confirm/prepare/ready-for-pickup action for feed
   orders (items 17), mirroring the pharmacy flow's `order_confirm`/
   `_do_ready`.
2. Add an offline-rider warning to `feed_catalogue/order_admin_views.py::order_assign`
   (item 19) — pharmacy already has this pattern to copy from.
3. Add an `arrived` transition to the feed delivery state machine if the
   product wants it (item 24) — currently pharmacy doesn't have it either, so
   this may be an intentional platform-wide simplification rather than a
   feed-specific gap; worth confirming with the user before building it.
4. Decide whether feed orders need a genuine admin proof-review gate (items
   26–30) or whether "mandatory photo + immediate completion" is the accepted
   design — this is the biggest behavioral gap versus the original spec and
   should be a product decision, not an assumption.
5. Render `latitude`/`longitude` as an actual embedded map (item 16) instead
   of plain text, using whichever map package the project settles on (no
   `flutter_map`/`google_maps_flutter` widget currently exists in the admin
   feed screens at all).
6. Configure `GOOGLE_MAPS_API_KEY` in this dev environment if rider
   route/map verification (item 21) needs to be exercised end-to-end.
