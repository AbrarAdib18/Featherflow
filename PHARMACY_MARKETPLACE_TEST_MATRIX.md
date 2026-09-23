# Pharmacy & Marketplace Verification Matrix — 2026-09-21

Honesty note on the "Manual result" column: this session does not have a
browser-automation tool available (no `chromium-cli`/Playwright configured in
this Windows environment — see `PHARMACY_PANEL_REPORT.md`'s prior session for
the same limitation). "Verified (API)" means the underlying backend call was
exercised end-to-end by a live-DB test script and its response checked
programmatically — a strong signal the feature works, but not literally a
mouse click in the running Chrome window. "Not clicked" means the code was
read and reasoned about but not exercised at all this session. Nothing below
is marked "Verified (UI)" unless it actually was.

| Screen | Option/action | Expected behaviour | Automated test | Manual result | Status |
|---|---|---|---|---|---|
| Pharmacy Catalogue | Add medicine button | Opens Add Medicine dialog | — | Not clicked | Pre-existing, unchanged |
| Pharmacy Catalogue | Add Medicine → pick image (create mode) | Stages photo locally, previews it | — | Not clicked | **Fixed this session** |
| Pharmacy Catalogue | Add Medicine → save (with staged image) | Creates medicine, then uploads staged image(s) | `test_pharmacy_medicine_images.py` (create→upload sequence) | Verified (API) | **Fixed this session** |
| Pharmacy Catalogue | Add Medicine → remove pending image | Drops the local staged image, no API call | — | Not clicked | **Fixed this session** |
| Edit Medicine dialog | Pick image (edit mode) | Uploads immediately, appears in strip | `test_pharmacy_medicine_images.py` (2nd upload) | Verified (API) | Pre-existing, unchanged |
| Edit Medicine dialog | Remove saved image | PATCHes `images` array minus that URL | `test_pharmacy_medicine_images.py` (remove step) | Verified (API) | **Fixed this session** (button didn't exist before) |
| Edit Medicine dialog | Reject invalid image type | 400, error shown | `test_pharmacy_medicine_images.py` | Verified (API) | Pre-existing, unchanged |
| Edit Medicine dialog | Reject oversized image | 400, error shown | `test_pharmacy_medicine_images.py` | Verified (API) | Pre-existing, unchanged |
| Edit Medicine dialog | Text-only field edit | Existing images untouched | `test_pharmacy_medicine_images.py` | Verified (API) | Pre-existing, unchanged |
| Catalogue | Search field | Filters list by name/generic/manufacturer | `pharmacy/test_catalogue.py` (not re-run this session, see report) | Not clicked | Pre-existing |
| Catalogue | Category / Rx-only chips | Filters list client-side | — | Not clicked | Pre-existing |
| Catalogue | Deactivate/reactivate medicine | `DELETE`/`PATCH` toggling `is_active` | `catalogue_views.medicine_detail` (existing behaviour, not re-tested this session) | Not clicked | Pre-existing, not re-verified |
| Catalogue (standalone route `/pharmacy/catalogue`) | Back button | Returns to `/pharmacy` dashboard, no crash if unreachable | `flutter analyze` (compiles); route logic reused from `farmer_pharmacy_screen.dart`'s proven pattern | Not clicked | **Fixed this session** |
| Inventory / Orders / Suppliers / Analytics (standalone routes) | Back button | Same as above | Same as above | Not clicked | **Fixed this session** |
| Inventory / Orders / Suppliers / Analytics (tabs inside dashboard) | No back button (nav bar is the navigation) | Correct, unchanged | — | Not clicked | Verified by design (intentional) |
| Orders | Confirm / ship / mark delivered | Status machine transitions, rejects invalid ones | `test_pharmacy_flow.py` (processing→shipped→delivered, repeat-delivered 409) | Verified (API) | Pre-existing, re-verified |
| Orders | Call farmer / call rider | `tel:` launch | — | Not clicked (code present, `lib/.../pharmacy_orders_screen.dart:146,261`) | Pre-existing |
| Orders | Assign delivery person | Admin queue → rider assignment → real `DeliveryOrder` | `test_pharmacy_flow.py` (rider path scenario) | Verified (API) | Pre-existing, re-verified |
| Farmer Pharmacy — Browse tab | Search / list active medicines | Only `is_active && is_approved` shown | `farmer_views.medicine_search` (existing filter, re-read not re-tested) | Not clicked | Pre-existing |
| Farmer Pharmacy — Browse tab | Medicine card image | Shows uploaded image or blank fallback | `test_pharmacy_medicine_images.py` (image present in search result) | Verified (API) | Pre-existing display code, now has real images to show |
| Farmer Pharmacy — Browse tab | Medicine detail bottom sheet | Shows description/price/images | — | Not clicked | Pre-existing |
| Farmer Pharmacy — Cart tab | Add to cart / change qty / remove | Client-side cart state | — | Not clicked | Pre-existing |
| Farmer Pharmacy — Cart tab | Exceed stock | Rejected before/at submit | `test_pharmacy_flow.py` (order creation stock check, existing `order_items_from_cart`) | Verified (API, via stock-decrement assertions) | Pre-existing |
| Farmer Pharmacy | Submit order | Atomic creation, stock decrement, notifies pharmacy | `test_pharmacy_flow.py` | Verified (API) | Pre-existing, re-verified |
| Farmer Pharmacy — My Orders tab | Status timeline, cancel action | Cancel only while `pending` | `test_pharmacy_flow.py` (farmer cancel scenario) | Verified (API) | Pre-existing, re-verified |
| Farmer Pharmacy | Call rider / call pharmacy | `tel:` launch, fallback to number shown | — | Not clicked (code present, `farmer_pharmacy_screen.dart:711,720`) | Pre-existing |
| Farmer Pharmacy | Back button (AppBar) | canPop→pop, else go('/farmer') | — | Not clicked | Pre-existing, already correct |
| Cost Management | Pharmacy expense appears after delivery | Exactly once, category "Medicines" | `test_pharmacy_flow.py` + `test_labour_payment.py` (shared-model regression) | Verified (API) | Pre-existing (prior session's fix), re-verified this session |
| Admin Pharmacy oversight | Approve/reject medicine, suspend pharmacy | RBAC-gated, audit-logged | — | Not clicked, not re-tested this session | Pre-existing, not re-verified |

## What this matrix does **not** claim

- Every dropdown/tab/icon in every screen was **not** individually clicked in
  a running browser this session (no browser-automation tool available).
  Where a row says "Not clicked," the code was read and is structurally
  sound (correct handler wiring, no dead buttons found), but a live click was
  not performed.
- Admin pharmacy oversight and the full Catalogue/Inventory filter UI were
  not re-exercised this session — they were confirmed working in the prior
  `PHARMACY_PANEL_AUDIT.md` pass and not touched by this session's changes.
- See `PHARMACY_MARKETPLACE_FIX_REPORT.md` for the full list of what was and
  wasn't covered, and why.
