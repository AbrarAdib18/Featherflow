# Pharmacy & Marketplace Fix Report — 2026-09-21

Full findings: [`PHARMACY_MARKETPLACE_FUNCTIONAL_AUDIT.md`](PHARMACY_MARKETPLACE_FUNCTIONAL_AUDIT.md).
Verification matrix: [`PHARMACY_MARKETPLACE_TEST_MATRIX.md`](PHARMACY_MARKETPLACE_TEST_MATRIX.md).
This builds on the prior `PHARMACY_PANEL_AUDIT.md` / `PHARMACY_PANEL_REPORT.md`
session (Cost Management mirroring), which remains current and was
re-verified, not redone.

## Original problems (as reported) and disposition

1. **"Design is inconsistent across pharmacy, marketplace, farmer, and
   related screens."** — Spot-checked, not overhauled. All pharmacy staff
   screens already share one theme file (`pharmacy_theme.dart`); no forked
   design language found. See "Design consistency" below for exactly what
   was and wasn't checked.
2. **"Back buttons are missing or inconsistent."** — **Root-caused and
   fixed.** 5 pharmacy staff screens had `automaticallyImplyLeading: false`
   with no `leading` replacement, breaking their standalone routes (their
   tab-embedded use inside the dashboard was already correct and unchanged).
3. **"Pharmacy staff cannot add medicine images in the marketplace."** —
   **Root-caused and fixed.** The Add Medicine dialog blocked image picking
   entirely until after the first save; fixed to stage and upload images as
   part of one continuous create flow, and added a remove-image action that
   didn't exist before.
4. **"Some options... may exist visually but are not fully functional."** —
   The two items above were the only concretely non-functional ones found in
   this pass. Everything else exercised (order status machine, delivery
   assignment, cost-management mirroring, medicine visibility/authorization)
   was verified working via live-DB API tests, not just code reading.
5. **"Full end-to-end test run... every option, validation, transition,
   permission, failure path."** — Not literally exhaustive (see Known
   Limitations); the two reported defects got dedicated new test scripts, and
   the existing regression scripts from the prior session were re-run
   clean. See the Test Matrix for exactly what was and wasn't covered.

## Root causes

- **Back buttons:** `PharmacyCatalogueScreen`, `PharmacyInventoryScreen`,
  `PharmacyOrdersScreen`, `PharmacySuppliersScreen`, `PharmacyAnalyticsScreen`
  each set `automaticallyImplyLeading: false` on their `AppBar` and never
  provided a `leading` widget. This is correct when they're shown as tabs
  inside `PharmacyDashboardScreen`'s bottom nav (no back button needed — the
  nav bar *is* the navigation), but `app_router.dart` also registers each as
  its own standalone `GoRoute` (`/pharmacy/catalogue`, etc.) with no nav bar
  and, previously, no way back.
- **Medicine images:** `add_medicine_dialog.dart`'s `_pickImage()` refused to
  do anything unless `_isEdit` was true, because the upload endpoint needs a
  medicine id that doesn't exist until the first save. The dialog then closed
  immediately after a successful save, so completing "add a photo" required
  closing the dialog, finding the medicine in the list, and reopening it in
  edit mode — a broken-feeling workflow, not a backend bug. The backend
  (model field, migration/SQL, serializer, multipart handling, media
  serving, validation, permissions) was already fully correct.

## Design consistency changes

None needed a code change — the pharmacy panel already centralizes tokens in
`pharmacy_theme.dart` (`PhColors`, `phCard()`, `phChip()`, `phInput()`,
`showPharmacyNotice()`) and uses them consistently across the 6 staff
screens: AppBar color/foreground, card radius/border/shadow, status chip
colors, currency formatting. **Not independently re-audited in this pass**
(flagged, not fixed, not claimed broken): farmer-side pharmacy screen's
typography vs. the rest of the farmer app; the admin pharmacy oversight
screen's styling vs. the rest of the admin panel. If the design-inconsistency
report was about something specific there, it needs a follow-up pass with
screenshots to pin down.

## Back-button changes

New shared helper in `lib/features/pharmacy/presentation/pharmacy_theme.dart`:

```dart
Widget? phBackLeading(BuildContext context, {required bool embedded}) {
  if (embedded) return null;
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.pharmacyDashboard);
      }
    },
  );
}
```

Applied via a new `embedded` constructor flag (default `false`) on:
- `pharmacy_catalogue_screen.dart`
- `pharmacy_inventory_screen.dart`
- `pharmacy_orders_screen.dart`
- `pharmacy_suppliers_screen.dart`
- `pharmacy_analytics_screen.dart`

`pharmacy_dashboard_screen.dart`'s `IndexedStack` now passes `embedded: true`
to all five (unchanged tab behaviour — no back button, nav bar handles it).
The nested `GoRoute` builders in `app_router.dart` were left as-is (they
default to `embedded: false`), so reaching any of these 5 routes directly now
gets a real back button that falls back to `/pharmacy` when there's nothing
to pop to — it never crashes and never pops the whole app. Every other
pharmacy-adjacent screen (`farmer_pharmacy_screen.dart`,
`admin_pharmacy_screen.dart`, all of `lib/features/delivery/`) was grep-audited
for the same `automaticallyImplyLeading: false` pattern and none had it;
`farmer_pharmacy_screen.dart` already implements the exact
canPop/pop/fallback pattern this fix replicates.

## Image-upload implementation

**Backend:** unchanged — already correct (verified, not assumed):
`PharmacyMedicine.images` (`JSONField`, up to 5 URLs),
`POST /api/pharmacy/medicines/{id}/upload-image/` (multipart, field name
`image`, JPEG/PNG/WebP only, 5 MB cap, absolute URL response), and
`PATCH /api/pharmacy/medicines/{id}/` already accepts a text-only `images`
array edit (`clean_medicine_payload`), which is what "remove an image" now
uses.

**Flutter (`add_medicine_dialog.dart`):**
- Image picking now works during *create*, not just edit. Picked files are
  staged (`_pendingImages: List<(Uint8List, String)>`), previewed via
  `Image.memory` with an "uploads once you save" note, and uploaded
  one-by-one right after the create call returns the new medicine's id — one
  continuous submit action.
- New remove (×) button on every thumbnail: for a staged image, drops it
  locally; for an already-saved image, `PATCH`es the medicine's `images`
  array with that URL removed and updates local state on success.
- An upload failure after a successful create no longer loses the
  submission — it's a non-blocking warning telling the pharmacist to edit
  the medicine and retry.
- Up to 5 images enforced client-side too (counts staged + saved), matching
  the backend limit, with a clear message instead of a rejected request.

**Flutter image display:** unchanged — `farmer_pharmacy_screen.dart`'s
medicine card and detail sheet already render `medicine.images` with
`errorBuilder` fallbacks (blank box, never a broken-image icon or crash) and
already worked correctly; they simply had no real images to show before,
since staff couldn't attach them during creation.

## Database migrations

None. No model/table changes were needed — `images` already existed and was
already fully wired.

## Delivery, calling, and Cost Management changes

None in this session — verified via re-running the prior session's live-DB
regression scripts (`test_pharmacy_flow.py`, `test_labour_payment.py`), both
still green. Not re-derived from scratch.

## Authorization/security changes

None needed — verified via the new `test_pharmacy_medicine_images.py`: a
different pharmacy cannot upload/edit another pharmacy's medicine images
(404, scoped by owner via `_get_medicine`), and a farmer cannot upload a
medicine image at all (401/403, `IsPharmacyUser`).

## Full test matrix

See [`PHARMACY_MARKETPLACE_TEST_MATRIX.md`](PHARMACY_MARKETPLACE_TEST_MATRIX.md).

## Backend test results

```
backend/scripts/test_pharmacy_medicine_images.py   19 passed, 0 failed   (new this session)
backend/scripts/test_pharmacy_flow.py              21 passed, 0 failed   (prior session, re-run clean)
backend/scripts/test_labour_payment.py             27 passed, 0 failed   (regression check, re-run clean)
manage.py check                                     System check identified no issues (0 silenced)
manage.py migrate --check                           exit code 0
```

Both new/re-run scripts were executed twice back-to-back with identical
pass counts, confirming idempotent cleanup (no leftover `pharmimg+`/`pharmtest+`
rows between runs).

`backend/pharmacy/tests.py` (`PharmacyEcosystemTests`, Django `APITestCase`)
was **not** run — `manage.py test` cannot build a Postgres test database in
this environment (`relation "users" does not exist`; several core tables are
provisioned via raw `*_extension.sql` files, not Django migrations, and the
test-db bootstrap only runs migrations). This is a pre-existing environment
limitation, documented in the prior `PHARMACY_PANEL_REPORT.md` and
unaffected by this session's changes; its logic was read by hand and no
change in this session touches the code paths it exercises.

## Flutter test result

```
flutter test   →  146 passed, 0 failed   (full suite, not just pharmacy tests)
```

No pharmacy/marketplace-specific widget tests were added in this session
(see Known Limitations) — the 146 are the project's existing suite, run to
confirm this session's changes caused no regression anywhere else.

## Analyze result

```
flutter analyze   →  6 pre-existing info-level lints in farmer_feed_marketplace_screen.dart
                      (unrelated file, not touched this session; 0 issues in
                      changed files)
```

## Release-build result

```
flutter build web --release   →  √ Built build\web
```
(Wasm-dry-run compatibility notes for `flutter_secure_storage_web` and
`socket_io_common` are pre-existing third-party-package warnings, unrelated
to this session's changes, and did not block the build.)

## Seed/idempotency result

No new seed command in this session. The prior session's
`seed_pharmacy_demo_data` (suppliers) remains idempotent, unchanged.

## Manual verification result

The backend (`http://127.0.0.1:8000`) and the Flutter web app
(`flutter run -d chrome`, served at `http://127.0.0.1:5061`) were both
launched and confirmed live (`200` on the app root, `401` — correctly,
auth-gated — on `/api/pharmacy/medicines/`) with this session's changes
applied, and the app's console log shows no runtime errors. **A live
click-through of the UI was not performed** — no browser-automation tool
(`chromium-cli`/Playwright) is configured in this Windows environment. Every
functional claim above is instead backed by a live-DB API test that
exercises the real backend the UI calls, which is the strongest verification
available without that tooling — but it is not the same as watching the
dialog and back buttons work in the browser. If you want that confirmed
visually, the app is running now at the URL above; log in as
`pharmacy.greenvet@example.com` / `FeatherflowDemo@2026` and try Add
Medicine → pick a photo before saving → save → see it appear in the list
and in `farmer.rashed@example.com`'s Pharmacy marketplace.

## Known limitations

- **No browser automation available** in this session/environment, so no
  screenshots or literal click-through were captured — see above.
- **No new Flutter widget tests** for the back-button fix or the image
  dialog changes. The fixes were verified via (a) `flutter analyze` (0
  issues), (b) the full existing `flutter test` suite (146/146, no
  regressions), and (c) live-DB backend tests of the exact API sequence the
  UI now performs. Writing true widget tests for `AddMedicineDialog` would
  need mocking `PharmacySession`/`FilePicker`, which the existing pharmacy
  test suite doesn't have scaffolding for yet — flagged as follow-up work
  rather than skipped silently.
- **`manage.py test` cannot run** in this environment (pre-existing,
  documented in the prior report) — `backend/pharmacy/tests.py` and
  `backend/pharmacy/test_catalogue.py` were not executed this session.
- **Design consistency** was spot-checked (tokens are centralized, no forked
  language found) but not exhaustively audited pixel-by-pixel across every
  screen — see the audit doc for exactly what was and wasn't looked at.
- **Delivery calling/map actions** (`tel:` links, "Open in Maps") were
  confirmed present in code (file:line cited in the test matrix) but not
  clicked live this session — they were fully verified in the prior
  `PHARMACY_PANEL_AUDIT.md` pass and unchanged since.
- **Admin pharmacy oversight screen** (approve/reject/suspend) was not
  re-tested this session — unchanged from the prior pass.

## Exact files modified

```
lib/features/pharmacy/presentation/pharmacy_theme.dart          (new phBackLeading helper)
lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart   (embedded: true on tabs)
lib/features/pharmacy/presentation/screens/pharmacy_catalogue_screen.dart   (embedded flag + back button)
lib/features/pharmacy/presentation/screens/pharmacy_inventory_screen.dart   (embedded flag + back button)
lib/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart      (embedded flag + back button)
lib/features/pharmacy/presentation/screens/pharmacy_suppliers_screen.dart   (embedded flag + back button)
lib/features/pharmacy/presentation/screens/pharmacy_analytics_screen.dart   (embedded flag + back button)
lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart         (create-flow image upload + remove)
backend/scripts/test_pharmacy_medicine_images.py                (new test script)
PHARMACY_MARKETPLACE_FUNCTIONAL_AUDIT.md                         (new)
PHARMACY_MARKETPLACE_TEST_MATRIX.md                              (new)
PHARMACY_MARKETPLACE_FIX_REPORT.md                               (this file, new)
```

No backend production code changed in this session (only the new test
script) — the medicine-image and order/status/cost-management backend logic
was already correct; only the Flutter workflow and the two back-button
screens needed fixing.

## Confirmation

Nothing in this session was committed. All changes are in the working tree.
