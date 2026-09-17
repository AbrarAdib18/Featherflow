# Feed management, marketplace, and Feed Admin panel

Companion to `FEED_AND_DATA_INTEGRITY_AUDIT.md` (Priorities 1-2). This doc covers Priorities
3-9: labour payments via a real payment intent, flock/feed management with an age chart,
the admin-approved feed catalogue, the `feed_admin` role, the farmer feed marketplace, and
delivery integration.

## Priority 3 — Labour payment via a real payment intent

**What was wrong**: `POST /api/workers/payments/` (the "Pay"/"Pay All" button) did
`WorkerPayment.objects.create(...)` in the same request — tapping "Pay" *was* marking the
worker paid, with no review step, no method selection, and no idempotency.

**The flow now**:
```
Labour Management → tap Pay/Pay All
  → POST /api/workers/payments/     creates a billing.PaymentIntent per worker (target_type='labour_payment')
  → /farmer/labor/pay-review        review screen (worker, period, amount)
  → /farmer/labor/pay-method        choose card / bKash / Nagad
  → /farmer/labor/pay-checkout      DEV: simulated approve/decline/cancel
  → /farmer/labor/pay-result        success / failed / cancelled, per worker
```
`WorkerPayment` is only ever created by `billing.services._activate_labour_payment`, on a
verified `succeeded` intent — nothing else can create one, so a failed/cancelled/pending
payment leaves the worker unpaid. Reused, not duplicated: `billing.PaymentIntent` gained a
`target_type` field (`subscription` default / `labour_payment` / `feed_order`) and `_activate()`
branches on it; the existing `/api/payments/<id>/method|confirm|cancel/` endpoints are
completely unchanged and now serve labour payments too. Idempotency: a duplicate "Pay" tap
while an intent is still `created`/`pending` reuses it; once an intent reaches a terminal state
a new tap opens a fresh one (like retrying a failed subscription checkout).

Backend: `billing/models.py`, `billing/services.py` (`create_labour_payment_intent`,
`_activate_labour_payment`), `workers/views.py::payments`. Frontend:
`lib/features/farmer/data/labour_payment_service.dart`,
`lib/features/farmer/presentation/screens/labour_payment_flow_screens.dart` (mirrors
`subscription_flow_screens.dart`'s structure, extended to a *list* of intents so "Pay All"
settles several workers through one method choice). Test:
`backend/scripts/test_labour_payment.py`.

## Priority 4 — Flock/feed management: age chart + feeding guidance + notifications

New models (unmanaged, `feed_flock_extension.sql`): `farms.FlockEvent` (immutable log —
mortality/sale/transfer/vaccination/feed_consumption/weight_measurement; mortality/sale/
transfer decrement `Flock.current_quantity` transactionally and auto-close a flock at 0 birds)
and `feed.FeedingGuideline` (bird_type + age-range + feed type + recommended amount/frequency +
general guidance text — seeded via `manage.py seed_feeding_guidelines`, always labelled as
general reference guidance, never a flock-specific veterinary/nutritional recommendation).
`Flock.age_days` is a computed property from `start_date` — never stored, so it can't drift.

Endpoints: `GET/POST /api/farmers/flocks/<id>/events/`, `GET /api/farmers/flocks/<id>/feed-chart/`
(flock age, matching guideline, the full guideline timeline for the bird type, consumption
total, recent events, and an explicit disclaimer string). Notifications:
`manage.py generate_feed_notifications` (stage-change lookahead, daily feeding reminder,
low-stock alert) — **there is no task queue anywhere in this backend** (confirmed by a
repo-wide search), so this is meant to run on a schedule via OS cron / Windows Task Scheduler,
same as every other `manage.py <command>` in this project; it is idempotent via a UTC time-window
dedupe (see "timezone bug" below), not a wall-clock "once a day" guarantee.

**Bugs found and fixed while building this**:
- A same-day notification dedupe written as `created_at__date=timezone.localdate()` against
  `notifications.created_at` (a naive `timestamp without time zone` column) re-notified on every
  run — Postgres's `AT TIME ZONE` reinterprets a naive value as already-local instead of
  UTC-to-convert, so the computed date silently disagreed with `timezone.localdate()` for
  several hours a day in Dhaka's UTC+6. Fixed with a plain UTC time-window check. The same
  pattern exists, pre-existing and out of scope for this pass, in `delivery/views.py` (rider
  "today's earnings"/"completed today") — see `FEED_AND_DATA_INTEGRITY_AUDIT.md`.
- `flocks.bird_type`'s DB CHECK constraint only allowed `broiler/layer/breeder/hatchery`, while
  the API's Python-side validation allowed `broiler/layer/breeder/other` — a farmer picking
  "Other" would 500 on INSERT, and `hatchery` was never offered. Widened to
  `broiler/layer/breeder/hatchery/chick/other` (chick added per this priority's spec) in both
  places.

Frontend: `lib/features/farmer/data/flock_service.dart`,
`flock_age_chart_screen.dart` (flock list + add), `flock_detail_screen.dart` (age header,
matching-guideline card, a simple proportional stage-timeline bar — no charting package is a
pubspec dependency yet, so this follows the project's existing "simple bars" convention rather
than adding one — event logging, recent-events list), linked from a new button on the existing
`feed_management_screen.dart`. Test: `backend/scripts/test_flock_feed_management.py`.

## Priority 5 — Only admin-approved feed types may be ordered

New `feed_catalogue` Django app (unmanaged, `feed_marketplace_extension.sql`), modelled directly
on `pharmacy.models.PharmacyMedicine`'s real-relational-catalogue-with-approval-workflow shape:

- `FeedCompany` — name, contact info, `status` (active/suspended).
- `FeedProduct` — company FK, name/brand/feed_type/bird_type, price, stock_quantity,
  min_order_quantity, `approval_status` (draft/pending_review/approved/rejected/suspended),
  `rejection_reason`, `created_by`/`approved_by`.

**Enforcement is entirely server-side**, in `feed_catalogue/services.py::order_items_from_cart`
(the single choke point every order endpoint must go through): unknown/rejected/suspended/
inactive-company product ids are rejected, price/name/availability are always read from the
current (locked, for the order path) DB row and never trusted from the client, quantities below
`min_order_quantity` or above `stock_quantity` are rejected, and there is no code path that
accepts a farmer-typed product name — every order line requires a real catalogue `product_id`.
Test: `backend/scripts/test_feed_catalogue.py` (all the negative-order-path cases from the
request: unknown/rejected/suspended/inactive product, altered price/total, negative/excessive
quantity, arbitrary free-text).

## Priority 6 — Feed Admin role

`feed_admin` is a normal **admin-panel sub-role** — `roles.panel_type` has a DB CHECK constraint
allowing only `farmer/doctor/delivery/pharmacy/pharmacist/researcher/admin`, so (like
`admin_pharmacy`/`admin_doctor`) it is seeded with `panel_type='admin'`, `tier_level=3`, and a
permissions map scoped to exactly `feed-catalogue`/`feed-orders`/`feed-delivery` (seeded by
`feed_marketplace_extension.sql`). This reuses 100% of the existing RBAC machinery
(`api/admin_rbac.py::can_perform_action`, `IsAdminUser`) — no new permission system. Backend
views (`feed_catalogue/admin_views.py`, `order_admin_views.py`) each call
`can_perform_action(user, module, action)` explicitly per action, exactly like the pharmacy admin
branch in `api/admin_views.py`. A feed_admin can both create and approve catalogue entries —
mirroring `admin_pharmacy`'s existing create+approve pair for its own module; there is no
separate "a different admin must approve" chain anywhere else in this codebase for a
module-scoped admin role, so none was invented here (an `admin_super`'s wildcard permissions
can always review/override).

Frontend: the Feed Admin sees a normal Admin Panel with a new **Feed** sidebar item (gated by
`AdminModule.feedCatalogue`/`feedOrders`, exactly like every other module tile) →
`AdminFeedScreen` (`lib/features/admin/presentation/screens/admin_feed_screen.dart`): Companies
& Products (add company, add product, approve/reject-with-reason/suspend), Orders & Delivery
(queue + rider assignment), Analytics (order counts by status, revenue, catalogue counts).
`AdminRole.feedAdmin` / `AdminModule.feedCatalogue|feedOrders|feedDelivery` added to
`lib/features/admin/data/models/admin_role.dart`; `AdminApiService` gained the matching
`feed*` methods (same pattern as its existing `pharmacy*` methods). Demo login:
`feedadmin.demo@example.com` / `FeatherflowDemo@2026` (via `seed_feed_demo_data`).

## Priority 7 — Feed marketplace under farmer "Order Now"

New dashboard tile **"Order Feed"** (`/farmer/order-feed`) →
`FarmerFeedMarketplaceScreen` (`lib/features/farmer/presentation/screens/farmer_feed_marketplace_screen.dart`):
Browse (search + bird-type filter, product grid, only ever the admin-approved catalogue — no
free-text entry anywhere in this screen) / Cart (quantity controls, delivery address + contact
phone + payment method, server-computed total) / My Orders (status, cancel while still
`created`/`confirmed`).

Orders reuse the **exact same `audit.AdminPanelRecord` JSON-bridge queue pattern** as
`module='pharmacy-orders'` (`module='feed-orders'`) — no new order table. Cart/stock validation
and the price/total computation happen inside one `@transaction.atomic` block in
`feed_catalogue/farmer_views.py::orders`, using `select_for_update()` on each `FeedProduct` row
so two concurrent orders for the last few units of stock can't both succeed (stock cannot go
negative). Every order item is a **snapshot** (`product_name`, `company_name`, `unit_price`,
`line_total` at order time) so historical orders stay accurate even if the catalogue entry is
later edited or removed.

Payment: `cod` (default) leaves `payment_status='pending'` (collected on delivery, matching the
pharmacy marketplace's precedent); `bkash`/`nagad`/`card` are marked `paid` immediately in an
explicitly-labelled **sandbox/development** mode, since — as with every other payment path in
this backend — no real bKash/Nagad/card provider is configured (`billing.services.billing_mode()`
would need a real provider secret set; none is). This intentionally mirrors
`pharmacy.farmer_views`'s order-payment shape (order created immediately with a payment method/
status pair) rather than routing through `billing.PaymentIntent`'s multi-step checkout flow —
reusing the sibling marketplace's proven pattern was judged the better fit than inventing a
second payment pathway for a single-action "place order" flow, per the "reuse existing
architecture, don't build a parallel workflow" instruction.

Test: `backend/scripts/test_feed_catalogue.py` (ordering + enforcement),
`backend/scripts/test_feed_order_delivery.py` (full order lifecycle).

## Priority 8 — Feed Admin delivery assignment

Feed Admin's order queue (`GET /api/admin-panel/feed-catalogue/orders/`) shows every field the
request asks for (farmer name/phone, delivery address, lat/lng for a map, ordered items,
payment status, delivery notes) straight from the order's JSON payload. `available_riders`
returns only `DeliveryProfile`s with `approved_by_admin` set — the exact guard
`_assign_from_queue` already uses for pharmacy deliveries — and `order_assign` creates a real
`delivery.DeliveryOrder(order_type='marketplace', is_pharmacy_delivery=False)` referencing the
feed order's `AdminPanelRecord.id`, reusing the delivery app's existing state machine
(`accepted → picked_up → on_the_way → delivered/failed`) and OTP/proof-of-delivery fields
as-is — no parallel delivery system.

**Two gaps found and fixed in the existing (pharmacy-only) delivery rendering while wiring this
up**, since the rider-facing `_order_json`/status-sync helpers in `delivery/views.py` had never
needed to look at anything but `pharmacy-orders`:
- `_order_json` resolved the originating order payload only via `_pharmacy_source` (hardcoded to
  `module='pharmacy-orders'`), so a feed delivery's rider view showed an empty order number/
  customer/items. Added `_order_source`, a small dispatcher that also checks `module='feed-orders'`
  for `order_type='marketplace'` orders, leaving the pharmacy path untouched.
- `update_status`'s pharmacy-only sync (`_sync_pharmacy_order`) never touched a feed order's
  payload, so a farmer's own order view would stay stuck at "assigned" forever. Added
  `_sync_feed_order` (same shape: updates `status`/`delivered_at`, restocks on failure — via
  `FeedProduct`, not the pharmacy-only `_restock_failed_order` helper — and notifies farmer +
  feed_admin) and wired it in alongside the existing pharmacy branch.

Rider-facing least-privilege: unchanged from the existing pharmacy precedent — `_order_json`
exposes address/lat-lng/customer name+phone/items/notes and nothing else (no NID, no full
profile). Notifications fire at every transition listed in the request (order placed, new
order for feed_admin, rider assigned, out for delivery, delivered, delivery failed), reusing the
existing synchronous `Notification.objects.create(...)` pattern used everywhere else in this
backend (there is no task queue, see Priority 4). Test: `backend/scripts/test_feed_order_delivery.py`
(order → queue → assign-guard → accept → picked_up → on_the_way → delivered, least-privilege
checks, cross-rider isolation).

## Priority 9 — Demo data

`python manage.py seed_feed_demo_data [--reset]` — idempotent (`update_or_create`/
`get_or_create` throughout). Reuses the existing demo farmers (`farmer.rashed@example.com` etc,
from `seed_farmer_demo_data`) and the existing approved demo rider (`rider.arif@example.com`,
from `seed_platform_demo`) when present, so the whole demo dataset stays internally coherent,
while still working stood alone (falls back to creating its own farmers/riders). Seeds: 1 feed
admin (`feedadmin.demo@example.com`), 3 companies, 10 approved + 3 pending products, 3 farmer
flocks at different ages/bird-types (broiler/layer/chick) with feed-consumption history and a
sample notification, 2 delivery riders, and 4 feed orders spanning
created/preparing/out_for_delivery/delivered (the last two pre-assigned to a rider with a real
`DeliveryOrder` row).

## Known limitations (be honest, not just complete)

- **No real payment provider anywhere** — bKash/Nagad/card are sandbox/dev-mode simulations
  across the whole payment surface (subscriptions, labour payments, feed orders), clearly
  labelled as such in every screen. This mirrors the pre-existing subscription flow's own
  limitation, not something newly introduced here.
- **No task queue** (Celery/APScheduler/cron) exists in this backend. `generate_feed_notifications`
  must be scheduled externally (OS cron / Task Scheduler) — it is not "wired up" to run itself.
- **Document verification** (`SignupDocument.is_verified`) has no admin review endpoint anywhere
  in this codebase (pre-existing, confirmed dead field) — the unified verification status
  correctly reports "pending" for every account with submitted documents, which is accurate
  given no review workflow exists yet, not a bug in the new status computation.
- **Feed Admin UI is a single consolidated screen** (Companies/Products, Orders & Delivery,
  Analytics tabs) rather than the fully separate dashboard/company/catalogue/inventory/
  order-queue/delivery-assignment/analytics screens enumerated in the request — all of that
  functionality exists and is backend-enforced and tested, just consolidated for time budget
  reasons rather than split across seven navigable screens.
- **Verification status banner** (`VerificationStatusBanner`) is wired into the farmer profile
  screen as the reference integration; the backend exposes the same unified payload to every
  role via `/api/me/updates/`, but wiring the banner into every other role's screen was out of
  scope for this pass.
