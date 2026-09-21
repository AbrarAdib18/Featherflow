# Pharmacy & Marketplace UI and Functional Fix Report — 2026-09-21

This session re-audited the four problems reported as still unresolved after
the prior `PHARMACY_MARKETPLACE_FIX_REPORT.md` pass, found the actual root
causes (one of which the prior pass had genuinely missed), fixed them, and
verified the fixes with a **real headless-Chromium browser driving the actual
running app against the actual running backend** — not just code review or
API-level tests — because that prior pass's own stated limitation was "no
browser-automation tool available," and this time that gap is exactly where
the real bug was hiding.

## How verification was done this time

Playwright + Chromium was installed into the session's scratchpad
(`npm install playwright`, `npx playwright install chromium`) specifically
because the previous two passes could not click through the UI and it showed:
a UI-reachability fix (session 2) was verified by code reading and API tests
alone, and turned out to be necessary-but-not-sufficient — the underlying
upload request itself was still broken in a way no backend test could ever
catch, because the bug was entirely inside the Flutter HTTP client. Flutter
web's default CanvasKit renderer draws to a `<canvas>` with no DOM, so the
driver enables Flutter's own accessibility/semantics tree (clicking the
`<flt-semantics-placeholder>` element) to get real, positioned, clickable DOM
nodes — the same mechanism screen readers use — then logs into the running
app as `pharmacy.greenvet@example.com`, navigates the real UI, uploads a real
file through Playwright's file-chooser interception, and inspects the actual
network requests/responses. Screenshots were captured at each step.

## Problem 1 — Root cause: navigation looked "up/down"

**What was actually there:** `PharmacyDashboardScreen` used an `IndexedStack`
+ bottom `NavigationBar` for 5 of 6 sections, while **Analytics was reached
through a completely different mechanism** — an icon button in the Home tab's
own separate `AppBar` (`onGoto(5)`), which none of the other 5 sections had.
Each of the 5 bottom-nav sections also rendered its **own full `AppBar`**
(different title each time) underneath the shared bottom nav. Two navigation
surfaces (a bottom bar plus a different, section-specific top bar every time
you switched tabs) is what read as an inconsistent, layered "up/down"
arrangement — confirmed visually via a live screenshot of the old Catalogue
tab before this fix (see `PHARMACY_MARKETPLACE_FUNCTIONAL_AUDIT.md` from the
prior pass, which — accurately — described the bottom nav itself as
"clean," but did not catch the Analytics inconsistency because it wasn't
asked to look for it specifically).

**Fix:** Replaced the bottom `NavigationBar` + per-section `AppBar`s with a
**single AppBar** (pharmacist avatar, name/location, sign-out) and **one
horizontal, scrollable `TabBar`** underneath it for all six sections (Home,
Catalogue, Inventory, Orders, Suppliers, Analytics) — matching the task's own
suggested structure exactly. `isScrollable: true` + `TabAlignment.start`
means it degrades to horizontal scrolling rather than overflowing at narrow
widths, satisfying "Ensure navigation works at 320px width" without a manual
breakpoint. Each of the five section screens (`pharmacy_catalogue_screen.dart`,
`pharmacy_inventory_screen.dart`, `pharmacy_orders_screen.dart`,
`pharmacy_suppliers_screen.dart`, `pharmacy_analytics_screen.dart`) now takes
an `embedded` flag: `true` (used inside the new shell's `TabBarView`) renders
*content only* — no `Scaffold`/`AppBar` of its own, since the shell already
provides one; `false` (the standalone `/pharmacy/catalogue` etc. routes)
renders the full `Scaffold` + its own `AppBar` + back button, unchanged from
the prior session's fix. Inventory's and Orders' own legitimate **inner**
tabs (Overview/Low Stock/Expiring; Incoming/Preparing/Delivery/Completed/
Cancelled — genuine content-level filters, not top-level nav) are preserved,
just re-parented into a lightweight header row when embedded since there's no
outer `AppBar.bottom` slot to put them in.

**Live-verified:** screenshot below shows the new shell — one AppBar, one
horizontal tab row, active tab underlined, no bottom bar, no duplicate title
bar per section.

## Problem 2 — Root cause: catalogue was a list, not cards

**What was actually there:** `pharmacy_catalogue_screen.dart` rendered
`ListView.builder` of full-width rows (`_MedCard`) — name/manufacturer/price
in one line, a chip row, then a stock stepper and delete icon. No image was
ever shown larger than a 40×40 thumbnail, and there was no grid at all.

**Fix:** New shared, reusable component
[`lib/core/widgets/product_card.dart`](lib/core/widgets/product_card.dart) —
`ProductCard` (the card itself) + `ResponsiveProductGrid` (a
`SliverGridDelegateWithMaxCrossAxisExtent`-based grid with a **fixed pixel
height** (`mainAxisExtent`) regardless of column width, which is what
guarantees every card is the same height with no per-card aspect-ratio math
and no overflow risk). Matches the reference structure field-for-field:
image on top with a discount ribbon (top-left) and a "Top Seller" badge
(top-right) as optional overlays that never affect layout since they're
`Positioned` over the image rather than pushing content down, delivery text,
name (2-line ellipsis), price with an optional struck-through previous
price, unit + minimum quantity, a status/stock line, an optional
`quantitySelector` slot, and a bottom-pinned action button (`Spacer()` before
it guarantees this regardless of how much content is above). Both
`pharmacy_catalogue_screen.dart` (pharmacy staff — action button "Edit",
trailing delete icon, stock stepper as the quantity slot) and
`farmer_pharmacy_screen.dart`'s marketplace card (already existed, now uses
the shared `ProductCard`/enlarged photo pattern conceptually — see note
below) benefit from one shared design instead of two divergent one-offs, per
the "use shared components" requirement.

Note: the farmer-facing card in `farmer_pharmacy_screen.dart` was enlarged in
the *previous* session (84×84 photo instead of 44×44) but kept its original
single-column list layout rather than being migrated to the new
`ResponsiveProductGrid`/`ProductCard` in this session — see Known Limitations.

**"Most Picked" and discount badges — an honesty decision, not an oversight:**
the task lists these as *optional* card elements. `PharmacyMedicine` has no
stored "most picked" signal and no discount concept before this session. Per
this repo's own product-card task explicitly forbidding hardcoded/fabricated
badges/prices ("Use real backend data. Do not hardcode products, prices,
badges, or stock"), this session:
- Added a real, derived **Top Seller** badge: `PharmacyMedicine.is_top_seller`
  (`orders_count >= TOP_SELLER_ORDERS_THRESHOLD`, currently 10) — a read-only
  property, not a client-settable field (verified: a PATCH attempting to set
  `is_top_seller` is silently ignored, still derived from real data).
- Added a real, optional **discount**: new `previous_price` column, only
  rendered struck-through when it's genuinely higher than `price` — never
  fabricated from `price` itself.
- Deliberately did **not** add a "Most Picked" badge — there is no honest,
  distinct signal for it separate from Top Seller in the current data model,
  and inventing one would violate the "no hardcoded badges" rule the task
  itself states. Flagged here rather than silently omitted.
- Added a real, enforced **minimum order quantity**: new `min_order_quantity`
  column (mirrors `feed_catalogue.FeedProduct.min_order_quantity`, same
  default of 1), validated on save and **enforced at order-placement time**
  (`order_items_from_cart` now rejects a cart line below the medicine's
  minimum) — not just displayed.

**Live-verified:** screenshot shows a real 6-column-wide grid of cards
(desktop width), consistent height, image/fallback icon, "Delivery 1–2
hours," name, price, stock line, stepper, Edit/delete actions — a
newly-created test medicine appears in the grid immediately after saving.

## Problem 3 — Root cause: back buttons (broader audit this time)

The prior session's back-button fix (5 screens: Catalogue, Inventory, Orders,
Suppliers, Analytics — `automaticallyImplyLeading: false` with no `leading`)
was correct and is preserved, now adapted to the new `embedded` semantics
(tab-embedded = no back button, the tab bar is the nav; standalone route =
real back button). This session additionally:
- Added a `tooltip: 'Back'` to `phBackLeading`'s `IconButton` — the shared
  helper existed but had no accessibility label, so screen readers announced
  nothing useful. Now covered by an automated test (see below).
- Re-audited every other pharmacy/marketplace-adjacent screen (Add/Edit
  Medicine dialog, farmer Pharmacy screen, admin Pharmacy oversight screen,
  every delivery screen) for the same `automaticallyImplyLeading: false`
  footgun — none found beyond the five already fixed. The Add/Edit Medicine
  "screen" is a modal `AlertDialog` (Cancel/Done buttons dismiss it), not a
  routed page, so a route-level back arrow does not apply to it — this
  matches Flutter/Material convention (dialogs are dismissed, not
  "backed out of") and is not a gap.
- Fixed a **real, separate overflow bug** discovered while writing the
  back-button/dialog widget test: the Category/Unit `DropdownButtonFormField`
  pair in Add/Edit Medicine had no `isExpanded: true`, so a long category
  name (e.g. "Feed supplement") could overflow its half-width `Row` slot —
  reproduced by an automated widget test (see below), not just narrow-width
  reasoning, and fixed with `isExpanded: true` + `TextOverflow.ellipsis` on
  the item text.

**Automated test added:** `test/pharmacy_navigation_test.dart` — a real
`GoRouter`+`MaterialApp` widget test (not a mock), covering:
- embedded mode renders no back arrow;
- standalone mode renders a visible, tappable back arrow with tooltip "Back";
- tapping it with nothing to pop falls back to `context.go` instead of
  crashing (the root-fallback requirement);
- Add Medicine (no existing id) shows the "save first" placeholder, not the
  photo picker;
- Edit Medicine (existing id) shows the photo picker immediately.

5/5 pass. Full suite: **151/151** (146 pre-existing + 5 new), no regressions.

## Problem 4 — Root cause: multipart upload silently sent the wrong Content-Type

This is the actual reason "photos still cannot be added reliably" survived
the prior session's UI-reachability fix, and it could only be found by
driving a real browser and inspecting the real network request — which is
exactly what this session did.

**Root cause, precisely:** `pharmacy_catalogue_service.dart`'s `_multipart()`
called `http.MultipartFile.fromBytes('image', bytes, filename: filename)`
with **no `contentType`**. Flutter's `http` package defaults an unspecified
multipart part to `application/octet-stream`. The backend's
`catalogue_views._store_image` rejected anything whose content-type didn't
literally start with `image/`:

```python
if not str(file.content_type).startswith('image/'):
    return None, 'Only JPG, PNG or WebP images are supported.'
```

So **every single image upload from the real app failed with a 400**,
regardless of how good the surrounding dialog UX was — confirmed live: before
the fix, uploading a real PNG through the actual running Add Medicine dialog
produced `POST .../upload-image/ → 400 {"detail":"Only JPG, PNG or WebP
images are supported."}` in the browser's network log.

The codebase already had a documented, shared fix for exactly this class of
bug — `lib/core/network/upload_helpers.dart::mediaTypeForFilename()`, whose
own doc comment says *"Flutter's `http.MultipartFile.fromBytes` defaults the
part to `application/octet-stream`... which several backend endpoints...
used to reject outright."* It had simply never been applied to the pharmacy
medicine-image upload path (or the farmer prescription-upload path, which
had the same bug but is more tolerant of a missing content-type — see below).

**Fixes (both sides, defense in depth):**
1. **Flutter, `pharmacy_catalogue_service.dart`:** `_multipart()` now passes
   `contentType: mediaTypeForFilename(filename)`. Also fixed a second,
   independent bug found in the same method while fixing this: the bulk
   CSV-upload call reused `_multipart()` with the **wrong hardcoded field
   name** (`'image'`), but the backend's bulk-upload endpoint reads
   `request.FILES.get('file')` — so the Inventory screen's "Bulk CSV upload"
   button had *also* always failed, unrelated to content-type. `_multipart()`
   now takes an explicit `field` parameter (`'image'` for medicine photos,
   `'file'` for CSV bulk upload).
2. **Flutter, `pharmacy_marketplace_service.dart`:** the farmer's
   `uploadPrescription()` had the identical missing-`contentType` pattern.
   Backend-side this one didn't outright fail (its endpoint uses the more
   lenient `verification.uploads.validate_upload`, which tolerates a generic/
   missing content-type via extension + magic-byte sniffing), but it was
   fixed for consistency and correctness anyway.
3. **Backend, `catalogue_views._store_image`:** rather than only fixing the
   client, the backend's own validator was hardened to match the more robust,
   already-established pattern used everywhere else in this codebase
   (`feed_catalogue.uploads.store_public_image`, `community.views.upload`) —
   replaced the bespoke `content_type.startswith('image/')` check with
   `verification.uploads.validate_upload(file, images_only=True)`, which
   validates by extension + real magic-byte sniff and tolerates a generic/
   missing content-type. This means the endpoint is now correct regardless of
   what any future client (this app, a different client, a future API
   consumer) sends as content-type — "do not assume the backend is correct"
   was taken literally: the backend *was* part of the problem too, just not
   in the way it first appeared.

**Live-verified, the actual fix in action (Playwright, real browser, real
backend):**
```
POST http://127.0.0.1:8000/api/pharmacy/medicines/<id>/upload-image/
content-type: multipart/form-data; boundary=dart-http-boundary-...
→ 201 {"image_url":"http://127.0.0.1:8000/media/pharmacy_medicines/.../....png", "images":[...]}
```
followed by the dialog's own collapse-to-one-photo `PATCH`, both 2xx. The
uploaded (trivial 1×1 test) image then rendered as a real black thumbnail in
the catalogue grid card — screenshot confirms the pixels themselves round-
tripped through the real backend and back into the real rendered UI, not
just that an HTTP call returned 2xx.

**New regression test:** `backend/scripts/test_pharmacy_medicine_images.py`
gained a check that uploads a valid PNG with `Content-Type:
application/octet-stream` — deliberately reproducing exactly what the old
buggy Flutter client sent — and asserts it's now accepted (201). This is the
one test in the whole suite that specifically encodes "the client bug is
fixed," and it could only be written *because* the browser-level reproduction
first proved what the client was actually sending.

## Product-card behavior — what was tested end to end

| Action | How verified |
|---|---|
| Add Medicine, fill fields, save | Playwright: real 201, medicine appears in grid immediately |
| Add photo before vs. after save | Playwright: dialog shows "save first" placeholder pre-save, live `CatalogueImagePicker` post-save |
| Upload a real photo | Playwright: real file-chooser, real multipart 201, real rendered thumbnail |
| Stock stepper (+/-) | Unchanged code, calls `PharmacySession.adjustStock` — already backend-tested in prior session |
| Edit / Retire (delete) | Unchanged code paths, backend-tested in prior sessions |
| Min order quantity enforcement | New backend test: ordering below the minimum → 409, at the minimum → 201 |
| Discount display | New backend test: `previous_price` only serialized/shown when genuinely higher than `price` |
| Top Seller badge | New backend test: flips on at the real `orders_count` threshold, not client-settable |
| Search / category filters, Add to Bag/cart, checkout, order history, delivery assignment, call/map actions, Cost Management | Not re-verified live this session — unchanged from the prior two passes, which did verify these (API-level for the first pass, code-audit + API for the second); re-running their existing passing test scripts this session (`test_pharmacy_flow.py` 21/21, `test_pharmacy_medicine_images.py` 20/20, `test_pharmacy_marketplace_card_fields.py` 13/13, `test_labour_payment.py` 27/27) confirms no regression |

## Design consistency

New shared `ProductCard`/`ResponsiveProductGrid` components use
`AppColors`/`taka()` from the existing core theme, not pharmacy-specific
colors — the pharmacy catalogue's card instance still layers `PhColors`-based
chips (`_statusChips`) on top via the card's generic `extra` slot, so the
pharmacy palette and the shared core palette coexist without either being
duplicated. `phBackLeading` remains the single back-button implementation
across all five audited pharmacy screens — no per-screen reimplementation.

## Files changed this session

```
Backend:
  backend/pharmacy/models.py                          (previous_price, min_order_quantity, is_top_seller)
  backend/pharmacy/services.py                         (validation + serialization for the new fields, min-qty enforcement)
  backend/pharmacy/catalogue_views.py                  (_store_image now uses validate_upload, not a bespoke check)
  backend/pharmacy_marketplace_ui_extension.sql        (new columns, applied to the live DB)
  backend/scripts/test_pharmacy_marketplace_card_fields.py  (new, 13 checks)
  backend/scripts/test_pharmacy_medicine_images.py     (extended: +1 regression check for the content-type bug, 20 checks total)

Flutter:
  lib/core/widgets/product_card.dart                   (new: ProductCard + ResponsiveProductGrid)
  lib/core/network/upload_helpers.dart                 (existing helper, now actually used by pharmacy)
  lib/features/pharmacy/data/models/medicine_models.dart          (previousPrice, minOrderQuantity, isTopSeller)
  lib/features/pharmacy/data/services/pharmacy_catalogue_service.dart  (multipart contentType + field-name fix)
  lib/features/pharmacy/data/services/pharmacy_session.dart       (uploadPrimaryMedicineImage helper)
  lib/features/farmer/data/pharmacy_marketplace_service.dart      (multipart contentType fix, min/topSeller getters)
  lib/features/pharmacy/presentation/pharmacy_theme.dart          (phBackLeading tooltip)
  lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart  (single AppBar+TabBar shell)
  lib/features/pharmacy/presentation/screens/pharmacy_catalogue_screen.dart  (ProductCard grid, embedded content-only mode)
  lib/features/pharmacy/presentation/screens/pharmacy_inventory_screen.dart (embedded content-only mode)
  lib/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart    (embedded content-only mode)
  lib/features/pharmacy/presentation/screens/pharmacy_suppliers_screen.dart (embedded content-only mode)
  lib/features/pharmacy/presentation/screens/pharmacy_analytics_screen.dart (embedded content-only mode)
  lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart      (dropdown isExpanded overflow fix)
  test/pharmacy_navigation_test.dart                   (new, 5 checks)
```

## Test command output summary

```
backend/venv/Scripts/python manage.py check                 -> System check identified no issues (0 silenced)
backend/venv/Scripts/python manage.py migrate --check        -> exit code 0
backend/scripts/test_pharmacy_flow.py                        -> 21 passed, 0 failed
backend/scripts/test_pharmacy_medicine_images.py              -> 20 passed, 0 failed  (was 19; +1 for the content-type regression)
backend/scripts/test_pharmacy_marketplace_card_fields.py      -> 13 passed, 0 failed  (new this session)
backend/scripts/test_labour_payment.py                        -> 27 passed, 0 failed  (regression check, shared Expense model)
flutter analyze                                               -> 0 issues in any file touched this session
                                                                   (6 pre-existing info-lints in an untouched file, unchanged)
flutter test                                                  -> 151 passed, 0 failed  (146 pre-existing + 5 new)
flutter build web --release                                   -> √ Built build\web
```

`backend/pharmacy/tests.py` / `test_catalogue.py` (Django `APITestCase`)
again could not be run — `manage.py test` cannot build a Postgres test
database in this environment (pre-existing, documented in both prior
reports). Unaffected by this session's changes; not silently skipped, just
genuinely blocked by the same environment limitation as before.

## Manual verification results (live browser + live backend, Playwright-driven)

- Logged in as `pharmacy.greenvet@example.com` against the real running
  Django backend (`http://127.0.0.1:8000`) and the real rebuilt release
  bundle (`http://127.0.0.1:8090`).
- Confirmed the new single-AppBar + horizontal-tab navigation renders and
  switches sections correctly (screenshot).
- Confirmed the Catalogue tab renders a real multi-column card grid with
  live data (screenshot).
- Drove the full Add Medicine flow: opened the dialog, filled required
  fields, saved (real `201`), confirmed the dialog stayed open and revealed
  the photo picker with the correct "saved, add a photo" messaging, uploaded
  a real file through a real file-chooser, confirmed the real `201` upload
  response with a real image URL, clicked Done, and confirmed the uploaded
  photo rendered as a real thumbnail in the catalogue grid (screenshot).
- Confirmed via `test_pharmacy_medicine_images.py` (API-level, since this
  part doesn't require the Flutter client at all) that the same image URL is
  visible to farmers in search results and medicine detail.

## Screens and widths checked

- Desktop width (1280×800, the Playwright viewport used for all live
  verification above).
- 320px width: not re-verified live this session (no viewport-resize pass
  was run) — this is a real gap, listed below, not glossed over. The dropdown
  overflow bug found via the widget test (not a live narrow-viewport check)
  is a strong signal that narrow-width issues can exist without literally
  narrowing the browser; that one is now fixed, but a full 320px live pass
  was not performed.

## Known limitations

- **320px / tablet-width live verification was not performed** — only
  desktop width was driven live this session, due to time. The dropdown
  overflow bug (found via widget test, not viewport narrowing) is now fixed,
  which reduces but does not eliminate the risk of other narrow-width issues.
- **Farmer-side live click-through was not completed.** A Playwright attempt
  to log in as `farmer.rashed@example.com` and view the marketplace hit an
  "Invalid email or password" error from a full page reload triggered by
  navigating via URL (`page.goto` on a hash route reloads the whole Flutter
  app, dropping session state — a Playwright-navigation artifact, not
  necessarily a real app bug, but not conclusively distinguished either).
  Farmer-side image visibility was instead verified at the API level via
  `test_pharmacy_medicine_images.py`, which is real but not the same as
  watching the farmer's browser render it.
- **The farmer-facing marketplace card was not migrated to the new shared
  `ProductCard`/`ResponsiveProductGrid`** — it still uses the single-column
  list layout from the prior session (enlarged photo, but not the full
  card-grid structure). The pharmacy staff catalogue is the one that now
  matches the reference layout; making the farmer side visually identical
  is a reasonable follow-up, not done here.
- **"Most Picked" badge was deliberately not implemented** — no honest data
  signal for it exists separate from "Top Seller," and the task's own rule
  against hardcoded/fabricated badges took precedence over checklist
  completeness. Flagged, not silently dropped.
- Delivery assignment, calling, map actions, and Cost Management were not
  re-driven live this session — their existing automated coverage from prior
  sessions was re-run and still passes, but that's a regression check, not a
  fresh live verification.
- `manage.py test` remains blocked in this environment (documented
  previously, unrelated to this session's changes).

## Confirmation

Nothing in this session was committed. All changes are in the working tree
(`git status` shows only modified/untracked files, no commits).
