# Feed & Data-Integrity Audit

Companion to `FEED_MARKETPLACE_INTEGRATION.md`. Covers Priority 1 (farmer/role profile-field
persistence) and Priority 2 (verification-status consistency) of the remediation program. All
findings below were produced by reading the live code (file:line cited), not assumed from
documentation.

## Priority 1 — Profile field persistence

### Method

For every role, traced: signup screen (Flutter) → `role_data` JSON key → `UserRegistrationSerializer`
key → profile model field → DB column → GET-profile response key → Flutter model parsing →
displayed screen. Checked for three failure modes: (a) field accepted by the frontend but never
read by the backend, (b) an endpoint computing a summary from the wrong table instead of the
field the user actually filled in, (c) a response key the Flutter model silently drops.

### Farmer — the confirmed example (bird count) and the full chain

`farmer_signup_screen.dart` sends `bird_count` (and 13 other keys) →
`UserRegistrationSerializer._create_farmer` (`backend/users/serializers.py:353-385`) accepts
both `number_of_birds` and `bird_count` (fallback pattern used for every farmer field, so no
naming mismatch exists) → `FarmerProfile.number_of_birds` (`backend/profiles/models.py:14`, real
DB column `farmer_profiles.number_of_birds`) → `GET/PUT /api/farmers/profile/`
(`backend/farmers/profile_views.py`) reads/writes it correctly (line 35 in the response, line 22
in `PROFILE_FIELDS`) → `FarmerProfileService`/`farmer_profile_screen.dart` display and edit it
with matching keys throughout. **This entire chain works.** Confirmed by
`backend/scripts/test_farmer_panel.py:111-118` (round-trips `number_of_birds: 5000`).

**Root cause of the user-visible symptom**: the farmer **Dashboard** (`GET /api/farmers/dashboard/`,
polled every 4s, almost certainly the first screen after signup) computed its "Birds" tile from
`Sum(Flock.current_quantity)` over `active` `Flock` rows (`backend/farmers/dashboard_views.py:39-40`,
old code) — a completely different table that starts out empty because flock/batch rows are
only created later via a separate, unrelated "Sheds & Batches" flow
(`backend/farmers/farm_views.py:76-100`). A brand-new farmer who entered "500" at signup saw "0
Birds" on their dashboard, even though the value was correctly saved and correctly shown on the
Profile screen. **Fix applied**: `dashboard_views.py` now falls back to
`FarmerProfile.number_of_birds` when the farmer has no active flocks yet (see diff). Phase 4
(flock/feed management) builds on top of this so the two sources reconcile as flocks are created.

Fields mentioned in the request that are genuinely **missing from the schema** (not a bug —
never collected, so nothing to persist): a separate `land_area` field, `district`/`upazila` as
structured fields distinct from the single freeform `farm_location`/`farm_address` text fields,
housing/shed detail at signup time (shed/housing exists only post-signup via `Shed` CRUD),
structured "feed preferences" beyond the single `feed_type`/`feed_sourcing_method` pair, a
"production capacity" field, and "existing livestock records" beyond the single
`number_of_birds` scalar. These are feature gaps for a future signup-wizard iteration, not
silently-dropped data.

Full farmer field table:

| Frontend field | JSON key(s) sent | Serializer key(s) accepted | Model.field | In profile GET response? | Flutter parses it? | Verdict |
|---|---|---|---|---|---|---|
| Farm name | `farm_name` | `farm_name` | `FarmerProfile.farm_name` | yes | yes | OK |
| Owner name | `farm_owner` | `owner_name`/`farm_owner` | `FarmerProfile.owner_name` | yes | yes | OK |
| Farm location | `farm_location` | `farm_location` | `FarmerProfile.farm_location` | yes | yes | OK |
| Farm address | (reuses `farm_location`) | `farm_address`/`farm_location` | `FarmerProfile.farm_address` | yes | yes | OK |
| Farm type | `farm_type` | `farm_type` | `FarmerProfile.farm_type` | yes | yes | OK |
| Bird count | `bird_count` | `number_of_birds`/`bird_count` | `FarmerProfile.number_of_birds` | yes | yes | OK on Profile screen; **Dashboard tile was wrong source — fixed** |
| Farm registration no. | `farm_registration` | `farm_registration_number`/`farm_registration` | `FarmerProfile.farm_registration_number` | yes | yes | OK |
| Years farming | `years_in_farming` | `years_in_farming` | `FarmerProfile.years_in_farming` | yes | yes | OK |
| Experience level | `experience_level` | `experience_level` | `FarmerProfile.experience_level` | yes | yes | OK |
| Primary disease | `primary_disease` | `primary_diseases_faced`/`primary_disease` | `FarmerProfile.primary_diseases_faced` | yes | yes | OK |
| Feed type | `feed_type` | `feed_type` | `FarmerProfile.feed_type` | yes | yes | OK |
| Vet contact | `vet_contact` | `existing_vet_consultant`/`vet_contact` | `FarmerProfile.existing_vet_consultant` | yes | yes | OK |
| Active workers | `active_workers` | `number_of_active_workers`/`active_workers` | `FarmerProfile.number_of_active_workers` | yes | yes | OK |
| Farm photos | `farm_photos: [url]` | `farm_photos` | `FarmerProfile.farm_photos` (JSON) | yes | yes | OK |
| Consent | `consent: true` | `consent_data_collection`/`consent` | `FarmerProfile.consent_data_collection` | yes | yes | OK |
| Breed / flock / shed / land area / district / upazila / production capacity | not collected | — | — | — | — | Not implemented (feature gap, not a bug) |

### Doctor, pharmacy, delivery, researcher — signup chain

Same fallback-free, single-key pattern in each `_create_*` (`backend/users/serializers.py:387-497`).
Cross-checked every accepted key against the corresponding Flutter signup screen
(`doctor_signup_screen.dart`, `pharmacy_signup_screen.dart`, `delivery_signup_screen.dart`,
`researcher_signup_screen.dart`) — **every key matches exactly**, no aliasing needed, no
mismatches found. `doctor/views.py::profile`, `research/views.py::profile` (dedicated
GET/PUT/PATCH endpoints) round-trip their fields correctly, including the researcher app's
verified-field-locking behavior (`VERIFIED_PROFILE_FIELDS`, `research/views.py:290-321`).

Pharmacy and delivery accounts have **no dedicated self-service profile-edit endpoint** —
unlike farmer/doctor/researcher. Their submitted data is fully visible (every concrete field on
`PharmacyOrganization`/`DeliveryProfile` is generically serialized by
`UserSerializer.get_profile_data`, `backend/users/serializers.py:612-644`, into `/me`'s
`profile_data`), but there's no in-app way for those roles to edit those fields after signup
except through admin action. **This is a feature gap, not a persistence bug** — nothing typed in
is lost, there's just no self-service edit UI yet for those two roles.

### Safeguard added

`UserRegistrationSerializer.validate()` now checks incoming `role_data` keys against a
`KNOWN_ROLE_DATA_FIELDS` registry (`backend/users/serializers.py`) built from what each
`_create_*` method actually reads. An unrecognised key always logs a clear warning
(`users.signup` logger, names the role and the offending key(s)) — so a future frontend field
added without backend wiring shows up immediately in the logs instead of silently vanishing.
This is intentionally a **log, not a hard rejection**: this backend runs with `DJANGO_DEBUG=True`
in the current `.env` (not a staging/prod-only flag), and hard-rejecting would have broken
already-working signups that happen to carry a harmless extra key (confirmed by an existing
test payload — see below). Rejecting unknown keys outright is safe only once every role's
signup payload is verified byte-for-byte and `DEBUG` is reliably prod-false; until then, a
loud log is the fix that satisfies "don't silently discard" without a regression risk.

**Found via this exact mechanism**: `backend/scripts/test_signup_flows.py`'s doctor
`ROLE_DATA` fixture sends a `district` key that `_create_doctor` has never read — a pre-existing,
harmless (test-only, not sent by the real `doctor_signup_screen.dart`) unused key, now visible
in the logs instead of invisible.

## Priority 2 — Account verification status

Root cause: there was no single source of truth. `User.account_status` is the only field that
actually gates login/JWT access (`users/views.py:196`, `User.is_active` property at
`users/models.py:107`); five-plus other flags (`User.is_verified`, `DoctorProfile.is_verified`,
`PharmacyOrganization.is_verified`, `ResearcherProfile.is_verified`,
`DeliveryProfile.approved_by_admin`) were each updated by a different, often incomplete, subset
of admin-panel actions in `backend/api/admin_views.py::admin_record`. Fixed bugs:

1. **Doctor approval never set `User.is_verified`** (`module='doctors'` branch) — the Users
   screen badge and the community "Verified Vet" badge (both read `User.is_verified`) stayed
   unchecked for an admin-approved doctor. **Fixed**: the doctors branch now sets
   `profile.user.is_verified` in the same save as `account_status`.
2. **Pharmacy approved via the generic Users screen never cascaded to
   `PharmacyOrganization.is_verified`** — the Pharmacies list and the admin-oversight backlog
   counter could disagree about the same account. **Fixed**: `module='users'` now cascades to
   `PharmacyOrganization` (and grants `DeliveryProfile.approved_by_admin` for riders approved
   the same way), matching the existing doctor/researcher cascade.
3. **Suspending/deleting a pharmacy via `DELETE` mutated `org.is_verified` in memory but skipped
   the `.save()` guard** (the guard only fired for an explicit `status` body, which a bare
   `DELETE` never sends), leaving the DB value stale at `True`. **Fixed**: the guard now also
   fires on `request.method == 'DELETE'`.
4. **`User.is_verified` is read by `community/permissions.py::verified_badge()` as the source of
   the "Verified Vet/Pharmacy" community badge for doctor/pharmacy accounts — the same flag the
   Doctors/Pharmacies/Users admin screens manage.** The community-moderation "toggle verified
   badge" action could silently override the outcome of the real approval workflow (or be
   overridden by it) with no coordination between the two screens. **Fixed** (simpler than
   introducing a parallel field, since the community badge for doctor/pharmacy/researcher is
   *supposed* to mirror professional approval): `module='community-users'`'s `verified=` action
   now returns `409` for any account that has a dedicated approval workflow (doctor/pharmacy/
   researcher profile present), pointing the moderator at the authoritative screen instead. It
   still works unchanged for accounts with no such profile (there is currently no badge for
   those roles either way, so this is a no-op restriction, not a feature removal).
5. **Rider suspension didn't clear or otherwise account for `DeliveryProfile.approved_by_admin`**,
   so a suspended rider still read as `"approved": true` in admin lists. **Fixed**: the approval
   *history* (`approved_by_admin`) is intentionally preserved (so "who approved this rider" is
   never lost), but `_rider_json['approved']` now also requires `account_status != 'suspended'`.
6. **`module='users'` accepted a different status vocabulary** (`Approved`/`Pending`/`Suspended`)
   **than `module='doctors'`/`'researchers'`** (`Verified`/`Suspended`/`Rejected`/`verify`/
   `suspend`/`reject`) with no server-side validation — an unrecognised value used to fall
   through to `.lower()`, silently producing an `account_status` the login gate doesn't
   recognise. **Fixed**: `module='users'` now returns `400` for any `status` outside its known
   vocabulary.
7. **The farmer dashboard *and* farmer profile GET rendered `is_verified` from
   `FarmerProfile.approved_by_admin_id is not None`** (`dashboard_views.py`,
   `farmers/profile_views.py`) — a field that is never set for farmers (they self-activate and
   have no approval workflow), so a farmer's dashboard/profile permanently showed "Verification
   pending" regardless of the real account state. This is almost certainly the exact symptom
   described in the request (a role that "does not require professional approval" stuck showing
   a not-verified badge forever) — confirmed live in `farmer_profile_screen.dart`'s "Verified
   farm" / "Verification pending" pill (lines ~193-213), which was reading this exact dead field.
   **Fixed**: both now derive `is_verified` from `user.account_status == 'active'`.

### Unified verification status model (fix)

`backend/verification/status.py::compute_verification_status(user)` is the new single source of
truth. It returns three independent axes instead of one overloaded boolean:

- **contact**: `email_verified` / `phone_verified` (from `User.email_verified_at`/`phone_verified_at`,
  OTP-driven, unrelated to admin approval).
- **professional_approval**: `not_required` (farmers) / `pending` / `approved` / `rejected`
  (admin-staff only, via `AdminProfile.approval_status` — every other role's reject/suspend
  collapse into `account_status='suspended'`, so they surface as `suspended`, matching what the
  underlying data actually distinguishes) / `suspended`, each with a ready-to-display message
  matching the request's examples ("Your vet application has been approved.", etc.).
- **documents**: aggregated from `SignupDocument.is_verified` (excluding plain photos) into
  `not_applicable` / `pending` / `partial` / `verified`. Note: no admin endpoint currently sets
  `SignupDocument.is_verified` (confirmed dead field pre-existing this pass), so in practice
  every submitted-documents account shows `pending` today — this is an accurate reflection of
  the current (non-)review process, not a bug in the new status computation; a document-review
  admin action is a follow-up, not part of this pass's scope.

Exposed via `GET /api/farmers/profile/` (`verification` key) and `GET /api/me/updates/`
(`verification_status` key, polled by every role's dashboard). Old fields
(`account_status`, `is_verified`) are kept unchanged on both responses for backward
compatibility — new UI should read the unified payload instead.

**Frontend**: `lib/core/widgets/verification_status_banner.dart` (`VerificationStatusBanner`)
renders the three axes as plain-language lines, wired into the farmer profile screen
(`farmer_profile_screen.dart`) below the existing status pill. Other roles' screens can adopt it
the same way — the backend now exposes the same payload shape everywhere via `/api/me/updates/`;
wiring every remaining screen was out of scope for this pass given the size of the overall
program (see the final report's "remaining limitations").

## Priority 4 — timezone-safety bug found while building feed notifications

While implementing `generate_feed_notifications` (idempotent, once-a-day feeding reminders —
see `FEED_MARKETPLACE_INTEGRATION.md`), a same-day dedupe check written as
`Notification.objects.filter(..., created_at__date=timezone.localdate())` was found to
**silently fail to match same-day rows and re-notify on every run**, because
`notifications.created_at` is a `timestamp without time zone` column: Postgres's
`AT TIME ZONE 'Asia/Dhaka'` (which Django emits for a `__date` lookup under `USE_TZ=True` +
non-UTC `TIME_ZONE`) *reinterprets* a naive value as if it were already local time and converts
it as such — the opposite of "this naive value is UTC, show me its local date" — so the computed
date silently disagrees with `timezone.localdate()` whenever the UTC/local day boundary is
crossed (i.e. every day, for several hours, in Dhaka's UTC+6). **Fixed** by using a plain UTC
time-window check (`created_at__gte=timezone.now() - timedelta(hours=20)`) instead of a
calendar-day lookup — verified by `backend/scripts/test_flock_feed_management.py` (a second
same-second run creates zero additional notifications). This class of bug can affect **any**
other `__date`/`__day` lookup against a naive timestamp column. A repo-wide grep found it
already present, **pre-existing and out of scope for this pass**, in
`backend/delivery/views.py:148,152,568` — the rider dashboard's "completed today" / "today's
earnings" / "earnings since" figures use the same `created_at__date=today` pattern against the
naive `delivery_earnings`/`delivery_orders` timestamp columns, and will be wrong for the same
several-hours-a-day UTC/Dhaka boundary window. Flagged here rather than fixed, since it's
unrelated to any of the 11 priorities and touching a working, separately-tested module
(`test_doctor_flow.py`, admin panel tests) risked an unrequested regression — worth a follow-up
pass using the same UTC-time-window fix.

## Priority 4 — pre-existing schema/validation mismatch found while seeding demo flocks

`backend/farmers/farm_views.py`'s `BIRD_TYPES` Python set (`{'broiler','layer','breeder','other'}`
pre-dating this pass) let a farmer submit `bird_type='other'`, but the real
`flocks.bird_type` CHECK constraint in `featherflow_schema.sql` only allowed
`broiler/layer/breeder/hatchery` — so a farmer picking "Other" would 500 on the INSERT, and
`hatchery` (a valid DB value) was never offered to farmers at all. Priority 4 additionally asks
for `chick` as a selectable bird type, which existed in neither set. **Fixed**: the DB constraint
(`feed_flock_extension.sql`) now allows `broiler/layer/breeder/hatchery/chick/other`, matching
`farm_views.BIRD_TYPES` (which already had `chick` added for this pass) plus the pre-existing
`hatchery` value. Found and fixed via `seed_feed_demo_data`'s chick-flock row, which hit the
constraint immediately.

## Live interactive verification pass (browser + Playwright against the real running app)

Everything above was validated against the backend directly (Django test client / live-DB
scripts). This section covers a follow-up pass that actually launched the Django dev server and
the built Flutter **web** app in a real browser (Playwright, coordinate-based clicking — Flutter
web renders to a `<canvas>` via CanvasKit, so there is no DOM text to query), logged in as each
seeded demo account, and clicked through the flows a human would. Three real bugs were found
this way that no backend-only test could have caught, because all three are in the Flutter
client or in the interaction between two already-individually-correct layers.

### Bug 1 — `flock_service.dart` / `feed_marketplace_service.dart` missing the `farmers/` URL prefix

`FarmManagementService._request()` builds `'${baseUrl}/api/$path'` with **no** implicit prefix —
every caller must supply the full path itself (confirmed against the working
`farmer_profile_service.dart`, which correctly uses `'farmers/profile'`). The two newest service
files instead called bare paths (`'flocks'`, `'feed-catalogue/orders'`), producing 404s against
`/api/flocks/` instead of the real `/api/farmers/flocks/`. Caught by clicking into Feed Management
and the marketplace as the farmer and seeing empty/error states where seeded data should have
appeared. **Fixed**: both files now prefix every path with `farmers/`. Re-verified live — flock
list/detail/age-chart and marketplace browse/cart/order all render seeded data correctly.

### Bug 2 (critical) — `feed_admin` login routed to the farmer dashboard, not the admin panel

Logging in as `feedadmin.demo@example.com` landed on `/farmer/cost-management` ("A farmer account
is required"), not the Admin Dashboard, even though the backend RBAC for `feed_admin` was already
correct and already covered by `test_feed_catalogue.py`'s isolation checks. Root cause: three
separate places in the Flutter app gate "is this user an admin" with
`role == 'admin' || role.startsWith('admin_')`, and the seeded role name is the literal string
`feed_admin` — it doesn't start with `admin_`, so all three silently treated a feed_admin session
as non-admin: `auth_service.dart::getRoleDestination()` (the post-login redirect), and two spots
in `admin_session.dart::refresh()` (the initial `isAdmin` gate and the offline/catch-block role
fallback). **This made the entire Feed Admin role unusable through the UI** despite the backend
being fully correct — the kind of bug that is invisible to any test that logs in via `APIClient`
directly instead of through the real login screen. **Fixed** by adding an explicit
`|| role == 'feed_admin'` check in all three places. Re-verified live: fresh login now lands on
the Admin Dashboard with the sidebar correctly scoped to only Dashboard / Feed / Audit Trail.

### Bug 3 (critical) — no way to reassign a feed delivery after the rider rejects/expires it

`delivery/views.py`'s `OFFER_WINDOW = timedelta(minutes=3)` auto-rejects an unanswered rider offer.
This is a real scenario (found by accident, because a slow multi-step manual test run naturally
took longer than 3 minutes between assigning and accepting) that exposed a genuine gap: the feed
order's `AdminPanelRecord` payload stays at `status='assigned'` forever, and
`order_assign()`'s guard only permitted (re)assignment when payload status was one of
`created/confirmed/preparing/ready_for_pickup` — **`assigned` was never in that list**, so once a
rider rejected or missed the offer window, feed_admin had **no way, ever, to assign a different
rider**; the order was permanently stuck. (Pharmacy has the same underlying gap in principle, but
its recovery path — a separate generic reassign endpoint gated behind a delivery-ops-admin
permission — isn't reachable by `feed_admin`'s narrower RBAC scope either way.) **Fixed**:
`order_admin_views.py::_order_admin_json()` now checks the *live* `DeliveryOrder.status` whenever
the payload says `assigned`, exposing new `delivery_status` / `can_assign_rider` fields;
`order_assign()` now permits reassignment when the current delivery order is `rejected` or
`failed`. Flutter's Orders & Delivery tab shows a red "Rider rejected this assignment — needs a
new rider." message and a "Reassign rider" action in this state. Added a full regression test
(`test_feed_order_delivery.py`, +2 checks) and **re-verified live end-to-end**: captured the
actual network response feed_admin's browser receives (`delivery_status: "rejected"`,
`can_assign_rider: true`), clicked "Reassign rider", picked a different rider, got a `201` and a
"Rider assigned" toast, with the order returning to a clean `ASSIGNED` state.

### Bug fixed (follow-up pass) — a rider with two concurrent active deliveries could only see one

While testing the accept → picked-up → on-the-way → delivered progression, a rider (assigned two
feed deliveries in quick succession by the test) had their second-oldest active order silently
disappear from the "Active" tab. Root cause, confirmed by reading the code (not guessed): the
rider dashboard endpoint (`delivery/views.py::dashboard()`, line ~156) computed `active_order` as
a single record — `DeliveryOrder.objects.filter(status__in=['accepted','picked_up','on_the_way'])
.order_by('-assigned_at').first()` — and `DeliverySession.activeOrder` (Flutter,
`delivery_session.dart`) mirrored that as a nullable singular field, not a list. If a rider was
ever assigned a second active order before finishing the first, the older one became invisible and
un-progressable through the UI, even though it still existed correctly in the database (confirmed
via direct DB query) and would resurface once the newer one was delivered. This was **pre-existing,
shared infrastructure** used identically by pharmacy deliveries (not introduced by the feed
marketplace work), and no code anywhere guarded against double-assigning a busy rider in the first
place.

**Fixed in a follow-up pass, per explicit instruction to implement a proper multi-active-delivery
model rather than leave it flagged.** Full before/after, API changes, UI changes, new tests, and
live re-verification are documented in a dedicated section below —
["Multi-active-delivery fix (follow-up pass)"](#multi-active-delivery-fix-follow-up-pass).

### Confirmed working end-to-end via the live browser (not just backend tests)

- Farmer: login, dashboard bird count (flock-derived) vs. profile bird count (signup value) are
  intentionally different numbers and both correct per their own source; profile screen shows the
  unified verification banner exactly as specified ("Email verified.", "Phone verified.",
  "Documents awaiting review."); logout/login persists data.
- Labour payment: "Pay" opens a review step (does not immediately complete).
- Feed marketplace: only approved products are browsable; cart/order totals are server-computed;
  order placed successfully in sandbox payment mode.
- Feed Admin: catalogue add-product → pending review → approve cycle works end-to-end (verified
  via a real `POST .../feed-catalogue/products/` returning `201`, then an approve action
  returning the correct "Product approved" toast and moving the pending-review count); Super
  Admin has the same unrestricted access to the Feed module as feed_admin has to its scoped
  subset.
- Delivery rider: only assigned orders are offered; accept/reject and status-progression
  (`accepted → picked_up → on_the_way → delivered`) all confirmed via direct log/DB inspection
  after live clicks, not assumed.
- Notifications: the farmer's notification center correctly shows "Order placed", "Rider
  assigned" (once per genuine assignment event, including the reassignment case — two real
  events, two notifications, not a duplicate), and "Feed delivery picked up", with no duplicates
  observed across repeated test runs that hit the same endpoints multiple times.

### Not independently re-verified via the live browser in this pass

Feed Admin's add-company and image-upload flows (add-product was verified; company creation and
image upload use the same pattern but were not separately clicked through), the Windows desktop
build (only Flutter web was exercised — no functional difference is expected since both share the
same Dart codebase, but it was not launched), and an exhaustive per-screen visual/contrast/overflow
sweep across every new and changed screen (representative screens across all four roles were
checked and found correct; a full systematic pass was not completed given the scope of this
session). These are lower-risk gaps than the three bugs above and are noted for completeness
rather than as known problems.

## Multi-active-delivery fix (follow-up pass)

Implements a proper multi-active-delivery model to replace the singular `active_order` design
flagged above, per explicit follow-up instruction. New shared module: `backend/delivery/services.py`.

### Before / after

| | Before | After |
|---|---|---|
| Rider dashboard | `active_order`: one record, `.order_by('-assigned_at').first()` over `accepted/picked_up/on_the_way` | `active_orders`: **all** in-progress orders for the rider, deterministically ordered; `active_order` kept as a deprecated alias (first of the list) for backward compatibility |
| Nearby-rider notification (`PATCH /api/delivery/location/`) | Checked distance against only the single most-recently-assigned order | Checks every active order independently — each farmer gets their own "rider is nearby" notification as their delivery comes into range |
| Assignment (feed `order_assign`, pharmacy `_assign_from_queue`/`_reassign_order`) | No cap — a rider could be assigned unlimited concurrent orders | Capped at **3 concurrent open orders per rider** (pending + accepted + picked_up + on_the_way, combined); a 4th assignment attempt returns `409` with a human-readable message naming the rider and the limit, and the order itself remains assignable to a different rider — it is never silently dropped |
| Feed Admin's rider picker (`riders/available/`) | Showed `"{name} ({active_orders} active)"` | Also returns `at_capacity` and `max_concurrent_orders`; the Flutter dropdown shows `"{name} ({n}/{max} active) — full"` in red when a rider has no room, so an admin sees the constraint before choosing, not only after a 409 |
| Flutter `DeliverySession` | `DeliveryOrder? activeOrder` — a single mutable field, overwritten on every accept/status-update | `List<DeliveryOrder> activeOrders`, merged per-order-id (`_upsertActive`) so accepting a new order or progressing one order's status never touches any other order's state; `activeOrder` kept as a deprecated getter (`activeOrders.first` or null) for anything not yet migrated |
| Delivery dashboard screen | One "Active Order" card, or empty state | "Active Order" (singular header) for one, "Active Orders (N)" for multiple, one full card per order, each with its own Call/View Details bound to that specific order |
| Delivery Orders screen → Active tab | Same singular-card layout, `session.activeOrder!` | A `ListView` of one card per active order (multi-select-safe: each card's progress button is bound to its own order), plus a dedicated loading spinner, empty state, and an error banner with its own Retry action (previously only the Dashboard tab had a retry affordance) |
| Accepting an order (New tab) | Switched to the Active tab, which — with only one slot — always showed the right order | Still switches to the Active tab, and additionally pushes straight into that specific order's `DeliveryDetailScreen`, so acceptance always lands on the order just accepted regardless of how many others are already active |

### Operational limit — intentionally supported, now bounded

Multiple concurrent active deliveries **are** intentionally supported by this platform (a rider
finishing one drop-off while already carrying the next is normal, not a bug) — this was true
before the fix too, just unbounded and partially invisible. `MAX_CONCURRENT_ORDERS_PER_RIDER = 3`
in `delivery/services.py` is a single, deployment-wide constant (not yet configurable per rider or
per admin) chosen as a reasonable operational ceiling; it is not derived from any existing product
requirement, so it should be revisited once real delivery volumes give a basis for the right
number. Ordering within a rider's active list is deterministic: closest-to-completion first
(`on_the_way` → `picked_up` → `accepted`), then oldest-assigned-first within the same status —
defined once in `_STATUS_PRIORITY` / `active_orders_for()` and reused by every consumer (the
dashboard, the nearby-notification loop) so the ordering can never drift between endpoints.

### Least-privilege

`active_orders_for(rider)` filters by `delivery_person=rider` at the query level, the same
pattern `requests_view`/`orders_view` already used — no new surface for one rider to see another's
orders was introduced. Verified explicitly in both the new automated test (`test_delivery_multi_active.py`)
and the live manual pass below.

### Tests added

**Backend** — new `backend/scripts/test_delivery_multi_active.py` (34 checks, all passing):
one active delivery; two active deliveries (proves the original bug is fixed — the older order
stays visible); feed + pharmacy active on the same rider at once; the 4th-assignment 409 (and that
the order can immediately go to a different, non-full rider instead of being dropped); a status
update to one order leaving two others untouched, including correct re-sort by priority; a fresh
dashboard fetch after all of the above still returning the full set; least-privilege isolation
(a second rider sees none of the first rider's orders, in both the dashboard and order-history
endpoints); and reassignment after rejection still working now that a capacity check sits in the
same code path. Also had to fix a **pre-existing test-hygiene bug** surfaced by the new capacity
check: `test_admin_panel.py`'s persistent `adminpaneltest+rider@featherflow.dev` fixture had
accumulated 65 leftover open `DeliveryOrder` rows across this session's repeated runs (nothing had
ever cleaned them up), which the new cap correctly started rejecting; fixed by purging that
fixture's own open orders before each run, restoring it to properly idempotent (65 passed → 0
failed, up from 60 passed / 1 failed the run before the fix, the extra passing checks being ones
that were previously silently skipped inside an `if r.status_code == 201:` guard).

**Flutter** — new `test/delivery_multi_active_test.dart` (13 checks, all passing): pure
`DeliverySession` state tests for zero/one/multiple active orders, a status update to one order
never touching another, and an order moving to a terminal status being removed from the active
list — all driven through new `@visibleForTesting` seams on `DeliverySession`
(`debugSetActiveOrders`/`debugUpsertActive`/`debugSetError`/`debugSetLoading`), since the session
is a singleton wired directly to real HTTP with no injectable client, matching this repo's existing
convention of testing screens against the real singleton rather than adding a mocking layer.
Widget tests cover the Dashboard and Orders-screen Active tab: empty state, single-card state,
multi-card state with an accurate "(N)" count, that two different-status cards each show their own
distinct next-action button (not the `StatusStepper`'s repeated step-name text), selecting the
correct order via `DeliveryDetailScreen(order: ...)` (second card's id is shown, first card's is
not), and the error/Retry affordance on both screens not throwing when tapped with no live session.

### Live manual verification (real browser, real backend, real demo accounts)

Performed against the actual running Django server and `flutter build web --release` bundle
(Playwright-driven, since Flutter web renders to canvas). Two orders — one feed, one pharmacy —
were placed and assigned to the same seeded rider (`rider.arif@example.com`; the assignment used
the exact `POST .../feed-catalogue/orders/<id>/assign/` and `PATCH
/api/admin-panel/delivery-orders/<qid>/` endpoints the real Feed Admin / delivery-ops admin UIs
call) after clearing that rider's leftover orders from earlier testing sessions to demonstrate a
clean before/after:

1. Both offers appeared in the rider's "New" tab and were accepted individually.
2. The Dashboard immediately showed **"Active Orders (2)"** with two full, independent cards — the
   feed order and the pharmacy order — each with its own status stepper and View Details button.
   This is the exact scenario that previously hid the older order.
3. The Orders screen's Active tab showed the same two cards in a scrollable list, each with its
   own "Mark as Picked Up" button and the pharmacy-specific "Medicine Delivery — Handle with care"
   banner attached only to the pharmacy card.
4. Tapping "Mark as Picked Up" on the feed order moved **only** that card to "Picked Up" (button
   label updated to "On The Way"); the pharmacy card stayed at "Accepted", unchanged, in the same
   screenshot.
5. A full page reload (simulating an app restart) re-fetched the dashboard from the backend and
   both orders reappeared with their correct, distinct statuses intact — confirming the state is
   server-persisted, not just an in-memory artifact of the session that happened to survive.

No console errors were introduced by any of the above (two pre-existing, unrelated 404s appeared
from the optional Google-Maps route-polyline lookup, which already degrades gracefully to the
static pickup/drop markers when it fails — unaffected by this change).

### Quality gates (re-run after this fix)

`python manage.py check` — clean. `python manage.py migrate --check` — clean (no new migrations;
`delivery/services.py` adds no models). Backend: `test_admin_panel.py` (65/65, after the fixture
fix above), `test_feed_order_delivery.py` (22/22, unaffected), `test_delivery_multi_active.py`
(34/34, new). Flutter: `flutter analyze` — no issues. `flutter test` — 100/100 (87 previous + 13
new). `flutter build web --release` — succeeded.
