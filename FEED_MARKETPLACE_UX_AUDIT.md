# Feed Marketplace UX Correction — Audit & Implementation Report

Companion to `FEED_AND_DATA_INTEGRITY_AUDIT.md` (Priorities 1-9) and
`FEED_MARKETPLACE_INTEGRATION.md` (original architecture). This document covers
the follow-up UX-correction pass: consolidating farmer feed ordering into Feed
Management, fixing Feed Admin product creation, adding a Clients section,
adding real image upload, and expanding demo data — all against the existing
schema, with no duplicate models. No reference design image was attached to
the request; the visual direction (green nav/white text, light content/dark
text, card-based marketplace) was implemented from the written spec and the
app's existing brand theme.

## 1. Audit — before this pass

### Farmer routes (before)
- `/farmer/feed-management` → `FeedManagementScreen` — a **separate** farm
  stock/supplier-order feature (talks to the `farms`/`feed` Django app via
  `FarmManagementService`), unrelated to the admin-approved catalogue.
  - `feed-management/flocks` → `FlockAgeChartScreen` → `flocks/:flockId` → `FlockDetailScreen`.
- `/farmer/order-feed` → `FarmerFeedMarketplaceScreen` — the **real**
  admin-approved-catalogue marketplace (talks to `feed_catalogue` via
  `FeedMarketplaceService`). This was a **sibling** top-level dashboard tile,
  not nested under Feed Management — the exact problem statement: "Order Feed
  appears as a separate farmer feature."
- Two separate "order feed" concepts existed side by side: `feed_management_screen.dart`'s
  own `_SupplierSection`/`_orderFeed()` dialog (an internal stock-purchase log,
  posts to `feed/orders` on the `farms` app) and the real catalogue marketplace.
  This was flagged as worth resolving but the internal stock/supplier-log
  feature was **left in place** (existing functionality preserved) — only the
  duplicate *navigation entry point* to the catalogue was removed.

### Feed Admin routes (before)
- `/admin/feed` → `AdminFeedScreen`, 3 tabs: **Companies & Products** (a flat
  list mixing both concepts with a 6-field "Add product" dialog that had no
  image field, no description/ingredients/nutrition/min-order-quantity
  fields), **Orders & Delivery**, **Analytics**. No dedicated Clients screen;
  no dashboard with quick actions.

### API endpoints (before)
- `feed_catalogue/admin_urls.py`: `companies/`, `companies/<id>/`, `products/`,
  `products/<id>/`, `orders/`, `orders/<id>/`, `orders/<id>/assign/`,
  `riders/available/`, `analytics/`. No image-upload endpoints anywhere.
  `companies/`/`products/`/`orders/` GET were **unbounded** (no pagination).
- `farmers/feed-catalogue/products|orders` (farmer browse/order) — also
  unbounded; filters were `bird_type/feed_type/company_id/search/max_price/in_stock_only`
  (no `min_price`).

### Models/tables (before)
- `FeedCompany` (`feed_companies`): name/contact/address/license/status
  (`active`/`suspended` only)/admin_notes — **no image fields, no
  district/upazila/description.**
- `FeedProduct` (`feed_products`): full catalogue fields including
  `image_url` (plain `TextField`, never populated by any upload path) —
  **no gallery field.**
- Both `managed=False`, DDL owned by `feed_marketplace_extension.sql`
  (idempotent raw SQL, applied and confirmed present in the connected DB).

### Why Feed Admin item creation was reported as failing
A static read of the whole request→view→model chain (`admin_feed_screen.dart`'s
`_addProduct()` → `AdminApiService.createFeedProduct` → `POST
/api/admin-panel/feed-catalogue/products/` → `admin_views.py::products()`)
found **no field-name/content-type/permission mismatch** — a well-formed
request from that dialog did succeed (confirmed by direct testing:
`feed_admin` role has `feed-catalogue: [view, create, edit, approve, reject,
suspend, delete, export]` correctly seeded, and `feed_companies`/`feed_products`
tables exist in the connected DB). The **real, reproducible problem** was
narrower and different from a broken create endpoint:

1. **No way to attach a product photo at all.** The "Add product" dialog had
   no image field, and there was no backend upload endpoint for one — a Feed
   Admin trying to add a *complete, real* product (with a picture, as any
   real catalogue entry needs) simply could not, which is what "cannot add
   feed products/items successfully" most plausibly meant in practice.
2. **The dialog was missing most of the model's real fields** — description,
   ingredients, nutritional info, and minimum order quantity were silently
   never collected, so even a "successful" save produced an incomplete
   catalogue record compared to what the schema/spec actually calls for.
3. A **generic 500 with no diagnostic detail** would have resulted if the DB
   tables or RBAC grant were ever missing in some other environment (the
   view has no try/except around the `FeedCompany.objects.get`/`FeedProduct.objects.create`
   calls) — not observed in this DB, but worth hardening; not changed this
   pass since it wasn't the actual fault and touching working error-handling
   without a reproduced failure would be scope creep.

Root cause, stated plainly: **the Feed Admin "Add Product" experience was
incomplete, not broken** — it created bare-minimum records with no image and
several required fields missing, which the fix below replaces with a real,
complete "Add Feed Product" screen.

## 2. Farmer navigation — after this pass

```
Farmer Dashboard
└── Feed Management  (/farmer/feed-management)
    ├── Hero header: "N active flocks · M birds" + notification bell
    ├── Feed Marketplace  → /farmer/feed-management/marketplace (nested route, new)
    ├── My Feed Orders    → same screen, opened on its Orders tab
    ├── My Flocks         → feed-management/flocks (unchanged)
    ├── Feeding Schedule  → existing in-page section (unchanged)
    └── Feed Consumption  → existing stock/history sections (unchanged)
```

- The standalone **"Order Feed" dashboard tile was removed** from
  `farmer_dashboard_screen.dart` — there is now exactly one entry point.
- `/farmer/order-feed` **still resolves** (no broken deep link) — it's now a
  `redirect` to `/farmer/feed-management/marketplace`, per the explicit
  backward-compatibility requirement.
- `FarmerFeedMarketplaceScreen` gained an `initialTab` parameter so "My Feed
  Orders" can deep-link straight to the Orders tab instead of always opening
  on Browse.

## 3. Farmer Feed Management landing screen — after

`feed_management_screen.dart` keeps its existing stock/schedule/history
sections (existing functionality preserved) and gains, at the top:
- A hero header (`_FlockHeaderCard`) showing live active-flock/bird counts
  (fetched via the existing `FlockService.list()`).
- A notification bell with unread-count badge, reusing the same
  `notifications`/`notifications` PATCH endpoints the farmer dashboard's own
  bell already uses (self-contained copy, not a shared widget extraction —
  kept small and local rather than refactoring the dashboard's private
  dialog).
- Two quick-access cards, `_MarketplaceQuickAccess`: **Feed Marketplace**
  and **My Feed Orders** — the only two ways to reach the e-commerce section.
- An error state with a visible **Retry** button (previously just raw error
  text with no recovery action).

## 4. Farmer feed e-commerce — after

Rewrote `farmer_feed_marketplace_screen.dart` and added
`farmer_feed_product_detail_screen.dart`:
- **Header**: title, search, filter icon (opens a bottom sheet), cart icon
  with a live item-count badge, back button to Feed Management.
- **Filters** (`_FilterSheet`): bird-type chips (unchanged, always visible),
  plus a bottom sheet for feed stage, company/brand (derived from the
  farmer's own approved-product results — no new backend endpoint needed),
  price range (min/max), and an in-stock-only switch. Farmers still only
  ever select `product_id`s from server results — no free-text entry exists
  anywhere in this flow (unchanged, already enforced server-side by
  `services.order_items_from_cart`).
- **Product cards**: real image via the new `CatalogueImage` widget (proper
  aspect ratio, loading spinner, icon fallback on missing/broken image), an
  "Approved" badge, company/brand, bird/feed-stage, price, stock, add-to-cart.
- **Product detail** (new screen): image/gallery strip, company, bird type,
  feed stage, unit, price, stock, min order qty, description, ingredients,
  nutritional info (rendered from the existing `nutritional_info` JSON
  field), quantity stepper, add-to-cart.
- **Cart**: image thumbnails, qty steppers, remove, subtotal, an *estimated*
  delivery fee (clearly labelled "final fee calculated at checkout" — the
  real fee is always server-computed at order time, this is just a UX
  preview), estimated total, "Continue shopping" / "Proceed to checkout".
- **Checkout** (new, split out of the old single cart screen): address,
  phone, district, upazila, delivery notes, payment method (sandbox-labelled
  for non-COD, since no real provider is configured — unchanged limitation),
  final total, "Place order". **All totals are still recalculated
  server-side** at `POST .../orders/` — the client-shown numbers are always
  a preview, never trusted (unchanged, pre-existing guarantee).
- **Order history/tracking**: each order card is now expandable, rendering
  the backend's existing `timeline` field (created → confirmed → preparing →
  ready_for_pickup → assigned → picked_up → out_for_delivery → delivered) as
  a checklist, with a distinct cancelled/failed banner instead of a
  misleading partial timeline for those terminal states. Delivery address is
  now shown on every card. Cancel action unchanged; a cancel failure now
  shows an inline retry instead of only a snackbar.

## 5. Feed Admin "Add Feed Product" — after

New `admin_feed_product_form_screen.dart` (used for both add and edit)
replaces the old 6-field dialog. Required fields present: product name,
company/client, bird type, feed stage, description, ingredients, two common
nutrition fields (protein %, energy kcal/kg — mapped into the existing
`nutritional_info` JSON field), package size/unit, price, stock quantity,
minimum order quantity, and — new — a primary photo with upload progress,
plus approve/reject/suspend actions once the product exists.

**Naming note**: the spec's "Feed type" + "Feed stage" as two separate
fields don't exist as two separate columns in the schema — the existing
`feed_type` field's actual values (`starter/grower/finisher/layer/breeder/
supplement/other`) already *are* life-stage buckets. Rather than add a
second, redundant field with unclear semantics, the UI labels this single
field **"Feed stage"** (matching what the data represents) — documented here
per the "standardize labels" instruction elsewhere in the request.

**Validation** (client + server, matching): product name required, company
required, price/stock non-negative, min order qty ≥ 1, clear inline field
errors (`TextFormField.validator`) plus a toast for anything the server
still rejects (e.g. a race on company deletion).

**Image-upload sequencing**: a brand-new product has no id until the first
save succeeds (the image endpoint is `products/<id>/image/`), so the flow is
save-fields-first → screen flips into edit mode in place → a "Photos"
section appears immediately, so a Feed Admin can add a picture right after
without losing any context or re-navigating. This is stated explicitly in
the success toast: *"Product saved — add photos below, then it will wait
for approval."*

**Approval policy — unchanged, verified**: a new product is always created
as `pending_review`; `services.order_items_from_cart`/the farmer browse
endpoint only ever return `approval_status='approved'` rows — a farmer can
never see a product that hasn't been explicitly approved, checked in
`test_feed_marketplace_ux.py` and the pre-existing `test_feed_catalogue.py`.

## 6. Feed Admin dashboard — after

`AdminFeedScreen` now has 4 tabs: **Dashboard**, **Products** (was
"Companies & Products" — companies moved to their own Clients screen),
**Orders & Delivery** (unchanged), **Analytics** (unchanged).

Dashboard tab: 9 stat cards (Clients, Active clients, Approved products,
Pending approvals, Low stock, New orders, Awaiting assignment, Active
deliveries, Failed/cancelled) fed by an expanded `analytics()` endpoint (see
§9), plus 5 quick actions (Add product, Add client, Review pending, View new
orders, View clients).

**Scope decision, stated plainly**: the full nav tree in the request
(`Catalogue > Products/Add Product/Companies/Categories/Product Approvals`,
`Orders > New/Preparing/Ready/Assignment/Completed` as separate pages,
plus top-level `Inventory`/`Delivery`/`Reports`) was **not built as fully
separate pages**. "Categories" doesn't correspond to a distinct concept
beyond the existing bird-type/feed-stage fields already used as filters;
"Inventory"/"Reports" would need new aggregation views with no clear existing
data model to back them beyond what Analytics already shows; splitting
Orders into 5 separate status-filtered pages is a thin wrapper around the
existing single Orders & Delivery view. Given the scope of this pass, the
highest-value, concretely-useful pieces were built (Clients as a real new
section, a proper Add Product screen, a real dashboard with real numbers and
quick actions) rather than a wider set of thin/placeholder pages. This is a
deliberate reduction, not an oversight — flagged here rather than silently
dropped.

## 7. Clients section — after

New `AdminFeedClientsScreen` + `AdminFeedClientDetailScreen`, new sidebar
item ("Clients", gated by the same `feed-catalogue` permission as "Feed" —
implemented as a new `AdminModule.feedClients` enum value sharing the
backend's `'feed-catalogue'` permission key, the same one-key/two-sidebar-
entries pattern `adminManagement`/`teamPayroll` already used for `'team'`).

**Data-model clarification** (as requested): a "client" is always a
`FeedCompany` row — a feed company/brand working with FeatherFlow. Farmers
are order customers and never appear in this screen or model. No new model
was created; `FeedCompany` was extended with `district`, `upazila`,
`description`, `logo_url`, `cover_url`, and its `status` vocabulary widened
from `{active, suspended}` to `{pending, active, suspended, rejected}`.

List screen: search, status filter chips, card grid (logo thumbnail, name,
contact person/phone, status badge, product count). Detail screen: logo +
cover image pickers (upload progress, replace), full contact/address/
district/description fields (view + edit), status-change buttons (any of
the 4 statuses), and an inline product list with an "Add product" shortcut
that opens the product form pre-locked to that client.

**RBAC**: Feed Admin can manage clients (`feed-catalogue: create/edit/
suspend`, already granted); farmers have no route or permission to this
screen at all; another admin role only sees "Clients" in the sidebar if it
separately holds `feed-catalogue` permissions (none do by default — same
isolation `test_feed_catalogue.py` already verifies for the parent module).
Every status/field change goes through the same `updateFeedCompany` PATCH
already covered by this backend's existing audit-logging middleware — no
separate audit wiring was needed.

## 8. Image upload — after

New `backend/feed_catalogue/uploads.py`:
- `store_public_image(request, file, prefix)` — reuses
  `verification.uploads.validate_upload(images_only=True)` (the strongest
  existing validator: extension + size + **magic-byte sniff** — deliberately
  chosen over the weaker inline checks `community.views.upload`/
  `pharmacy.catalogue_views._store_image` use elsewhere in this codebase),
  then saves via Django's standard public `default_storage`/`MEDIA_ROOT`
  (the same mechanism those two existing public-image endpoints use — no new
  storage system invented). Returns an absolute URL.
- `delete_public_image(url)` — best-effort cleanup of a *replaced* image,
  called only **after** the new image is already saved and persisted, so a
  failed upload never touches the old image, and a successful replace
  doesn't leave the old file around indefinitely (some orphaning is still
  possible if a file is referenced from more than one place at save time,
  which never happens in this feature — each image URL is written to exactly
  one field).
- `generate_placeholder_image(label, ...)` — Pillow-rendered labelled PNG,
  used **only** by the demo seed command (never by a real upload path) so
  demo data has real, loadable images instead of a fake URL that 404s.

New endpoints: `POST companies/<id>/logo/`, `POST companies/<id>/cover/`,
`POST products/<id>/image/` (primary, or `gallery=1` to append instead),
`DELETE products/<id>/gallery/?url=...`. All gated by the same
`feed-catalogue: edit` permission as every other catalogue mutation.

New Flutter widgets: `CatalogueImage` (display: aspect ratio, loading
spinner, icon fallback) and `CatalogueImagePicker` (upload: local preview,
progress overlay, replace, inline error) — the latter mirrors
`ProfilePhotoField`'s exact client-side validation (same extension/size/
magic-byte checks) but as a rectangle with a configurable aspect ratio
instead of a circular avatar, since product/company images aren't avatars.

**Public vs private**: these images are intentionally public (farmers must
see them in the marketplace) — correctly kept separate from
`PRIVATE_MEDIA_ROOT`/`verification.documents`, which continues to hold
signup documents, prescriptions, and delivery proof-of-delivery photos
unchanged.

## 9. Backend API/data-integrity — after

- Pagination added to every previously-unbounded feed_catalogue list
  endpoint: admin `companies/`, `products/`, `orders/`, and farmer
  `feed-catalogue/products/`/`orders/` — all now accept `limit`/`offset`
  (default 50, capped at 200) and return `total`/`offset`/`limit` alongside
  `results`, matching the existing convention `delivery/views.py::orders_view`
  already used.
- `analytics()` expanded with `active_companies`, `new_orders`,
  `orders_awaiting_assignment`, `active_deliveries` (cross-referenced
  against `delivery.services.ACTIVE_ORDER_STATUSES` — the same constant the
  multi-active-delivery fix introduced, so this dashboard card can never
  drift from what "active" means there), `failed_cancelled_orders`.
- Farmer product-browse filter gained `min_price` (was `max_price`-only).
- Product/company JSON responses now include `company_logo_url`,
  `gallery_urls`, `district`, `upazila`, `description`, `logo_url`,
  `cover_url` as appropriate.
- **Everything already correct and left unchanged, verified by the new
  test suite**: prices/stock are still fully server-controlled
  (`order_items_from_cart` never trusts client-supplied values); order
  items still store a full product-name/company-name/unit-price/line-total
  **snapshot** at order time, so a later product price edit never rewrites
  historical orders (new explicit test added — see §11); stock
  decrements/order creation remain inside the existing `transaction.atomic()`
  block; order status transitions are unchanged; the delivery-assignment
  path is untouched and remains fully compatible with the multi-active-
  delivery fix (no changes to `delivery/services.py` or the assignment
  endpoints); riders still only ever see their own assigned orders
  (unchanged, pre-existing `delivery_person=rider` scoping).

## 10. Demo data — after

New `backend/feed_catalogue/management/commands/seed_feed_marketplace_demo.py`
(the old `seed_feed_demo_data` is now a thin backward-compatible alias that
calls into it — see that file's docstring). `--reset` only ever deletes rows
this command owns (companies named `"Demo …"`, their products, and
`AdminPanelRecord`s with a `feed:FEEDMKT-`/legacy `feed:FEEDDEMO-` id) —
verified not to touch farmer/pharmacy/doctor/admin data.

Seeded (verified against the live DB after a `--reset` run):
- **4 companies** — 3 `active`, 1 `pending` (`Demo BioFeed Solutions`) —
  each with a generated logo (300×300) and cover (900×300) image.
- **25 products**: **20 approved** (broiler starter/grower/finisher ×2 each,
  layer starter/grower/layer-feed ×2 each + economy variants, chick
  starter/grower, breeder rearing/layer, 5 supplement/vitamin/mineral/
  electrolyte products), **3 pending_review**, **1 rejected** (with a
  rejection reason), **1 suspended** — every product has a generated primary
  image, ingredients text, and a 2-key nutrition dict.
- **6 orders** spanning `created`, `confirmed`, `preparing`,
  `out_for_delivery` (rider-assigned), `delivered` (rider-assigned +
  completed `DeliveryOrder`), `cancelled`.
- **3 farmers** with flocks of different ages/bird-types, feed-consumption
  history, and a reminder notification (reused from the existing farmer
  seed data where present).
- **2 riders**, both admin-approved.

Command output reports `created=N updated=N skipped=N` counts as required.
Verified idempotent: a second run with no `--reset` produces
`created=0 updated=0 skipped=40`. Every generated image was verified to
actually load (`curl` returned `200` with real PNG bytes) — no fake/404 URLs.

## 11. Manual testing — results

Performed against the real running backend (fresh `--noreload` process,
confirmed single-listener) and a `flutter build web --release` bundle, via
Playwright driving the actual app (Flutter web renders to canvas — no DOM
shortcuts).

**Feed Admin**: logged in → landed on the Admin Dashboard with sidebar
correctly showing only Dashboard/Feed/Clients/Audit Trail. Feed → Dashboard
tab showed live stat cards (4 clients, 25 products, 3 pending review, 10
orders at the time) and working quick actions. Clicked "Add product" →
filled the full form → **Save → `201`, confirmed persisted in the database**
→ Photos section appeared in place → screen correctly switched to "Edit Feed
Product". Clients → list showed all 4 seeded clients with real logo images
and correct status badges (BioFeed Solutions correctly `PENDING`) → opened a
client → logo/cover images with "Replace image" controls, full contact/
district/description fields, status-change buttons, and its product list all
rendered correctly.

**Farmer**: logged in → Feed Management showed the new hero header
("3 active flocks · 5110 birds") and the two Feed Marketplace/My Feed Orders
quick-access cards at the top → Feed Marketplace → product grid with real
labelled images, "Approved" badges, bird-type filter chips → opened a
product detail → image, chips, price/stock, description/ingredients/
nutrition all rendered → Add to cart → Cart tab showed the thumbnail, qty
controls, subtotal/delivery/total breakdown → Proceed to checkout → address/
phone/district/upazila/payment method/final total → **Place order → `201`**
→ landed on My Orders showing the new order plus every previously-seeded
order with readable, correctly-coloured status pills and no green-on-green
text anywhere observed.

**Delivery rider**: not re-tested this pass — no delivery-rider code was
touched (the multi-active-delivery fix from the prior pass is untouched and
unaffected, confirmed by `test_delivery_multi_active.py` still passing
34/34 unchanged).

**Responsive/design checks**: web build tested at the standard 1400px
viewport used throughout this session's testing; narrow-viewport and native
Windows-desktop rendering were **not separately verified** this pass (no
Windows build was launched) — flagged as a limitation, not claimed as done.
No overflow, clipped text, or green-on-green text was observed in any
screenshot taken during the flows above; every new screen has an explicit
loading/empty/error state with a retry action (dashboard error banners,
clients/products lists, marketplace browse/cart/orders all checked).

## 12. Automated tests — results

New `backend/scripts/test_feed_marketplace_ux.py` (20 checks): client
creation with district/upazila/description, company status widened to
`pending`, company logo upload + persistence + magic-byte rejection of a
non-image file, product creation, product primary + gallery image upload +
persistence + rejection of an unsupported file type, farmer sees
`image_url`/`company_logo_url` on an approved product, **product price
snapshot preservation** (an order's captured `unit_price` is unchanged after
the product's price is edited afterwards), pagination on all four
product/company/order list endpoints, and seed-command idempotency
(before/after product count unchanged on a second run, ≥6 demo orders
present).

Full suite after this pass:

| Suite | Result |
|---|---|
| `manage.py check` | clean |
| `manage.py migrate --check` | clean (one new state-only migration, no new DDL — see `feed_marketplace_ux_extension.sql`) |
| `seed_feed_marketplace_demo --reset` | `created=35 updated=0 skipped=5` |
| `seed_feed_marketplace_demo` (no reset) | `created=0 updated=0 skipped=40` (idempotent) |
| `test_data_integrity.py` | 11/11 |
| `test_verification_status.py` | 24/24 |
| `test_labour_payment.py` | 18/18 |
| `test_flock_feed_management.py` | 17/17 |
| `test_feed_catalogue.py` | 22/22 |
| `test_feed_order_delivery.py` | 22/22 |
| `test_delivery_multi_active.py` | 34/34 |
| `test_feed_marketplace_ux.py` (new) | 20/20 |
| `test_admin_panel.py` | 65/65 |
| `flutter analyze` | clean (6 pre-existing `prefer_const_*` lint infos only, no errors/warnings) |
| `flutter test` | 100/100 |
| `flutter build web --release` | succeeded |

**233 backend checks, 0 failures. 100 Flutter tests, 0 failures.**

## 13. Remaining limitations

- The full Feed Admin nav tree's `Categories`/`Inventory`/`Reports`/
  standalone `Delivery` top-level pages and Orders-split-into-5-pages were
  not built as separate screens (see §6's scope decision) — the underlying
  data (approval queue, low-stock, delivery status, analytics) is all
  reachable through the Dashboard/Products/Orders & Delivery/Analytics tabs
  that do exist.
- Delivery-rider screens and Windows-native/narrow-viewport rendering were
  not re-verified this pass (no code changed there).
- No real payment provider is configured (unchanged, pre-existing,
  clearly sandbox-labelled) — this was true before this pass and remains
  true.
- `generate_placeholder_image` depends on Pillow having a system font
  (`arial.ttf`) available; falls back to Pillow's built-in bitmap font if
  not found — confirmed working in this environment either way.

## Confirmation

Nothing was committed. `git log` HEAD is unchanged throughout this pass; all
changes remain uncommitted in the working tree.
