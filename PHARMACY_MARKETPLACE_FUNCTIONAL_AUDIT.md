# Pharmacy & Marketplace Functional Audit — 2026-09-21

Scope note up front: this is a full pharmacy+marketplace ecosystem spanning
~15 Flutter screens and ~10 backend view modules. This pass root-caused and
fixed the two concretely-reported defects (back buttons, medicine images) end
to end with real backend tests, and spot-checked the rest of the surface
(design tokens, order/delivery/cost-management flows, which were already
covered by the prior `PHARMACY_PANEL_AUDIT.md` pass) rather than re-deriving
everything from scratch. Anything not explicitly re-verified here is called
out as such in the fix report, not silently assumed fine.

---

## Issue 1 — Pharmacy staff could not add a medicine image while creating it

**Symptom reported:** "Pharmacy staff cannot add medicine images in the
marketplace."

**Root cause found:** `lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart`,
`_pickImage()` (old code, line 56-61):

```dart
Future<void> _pickImage() async {
  if (!_isEdit) {
    showPharmacyNotice(context, 'Save the medicine first, then add photos.',
        PhColors.amber, Icons.info_outline);
    return;
  }
  ...
```

The image picker was hard-blocked during the *create* flow because the
upload endpoint (`POST /api/pharmacy/medicines/{id}/upload-image/`) needs a
medicine id that doesn't exist until after the first save. The dialog's
`_submit()` then closed the dialog immediately on success
(`Navigator.pop(context, true)`), so the only way to actually attach a photo
was: save with no image → close the dialog → find the medicine in the list →
reopen it in edit mode → pick the image again. This is not a backend bug —
`POST/PATCH /api/pharmacy/medicines/` and the upload endpoint both already
worked correctly (verified below) — it was a Flutter workflow gap that made
image upload feel broken/impossible during the one moment (creation) a
pharmacist would naturally want to add a photo.

Checked and ruled out from the list of likely causes in the task: no missing
image field (`PharmacyMedicine.images` `JSONField`), no missing migration
(unmanaged table, column already exists in `postgres_backend_extension.sql`),
serializer/clean_medicine_payload already accepts `images`
(`pharmacy/services.py:199-200`), multipart *is* supported
(`_store_image`/`request.FILES`), the multipart field name is correct
(`image`), `MEDIA_URL`/`MEDIA_ROOT` are configured and served
(`settings.py:285-286`, `urls.py:22`), image URLs are absolute
(`request.build_absolute_uri`), type/size validation exists (JPEG/PNG/WebP,
5 MB cap), and permissions are enforced (`IsPharmacyUser` + owner-scoped
`_get_medicine`).

**Files involved:**
- `lib/features/pharmacy/presentation/widgets/add_medicine_dialog.dart` (fixed)
- `lib/features/pharmacy/data/services/pharmacy_session.dart` (`addMedicine`,
  `editMedicine`, `uploadMedicineImage` — already correct, reused as-is)
- `backend/pharmacy/catalogue_views.py` (`medicines`, `medicine_detail`,
  `medicine_upload_image`, `_store_image` — already correct, reused as-is)
- `backend/pharmacy/services.py` (`clean_medicine_payload` — already correct)

**Fix:** `add_medicine_dialog.dart` now lets the pharmacist pick photos
*before* saving. Picked files are staged locally (`_pendingImages`, shown via
`Image.memory` with a "New photos upload once you save" note) and uploaded
automatically, one by one, right after `addMedicine()` returns the new
medicine's id — all inside the same submit action, before the dialog closes.
Edit mode is unchanged (still uploads immediately, since the id already
exists). Also added, since neither existed before: a remove (×) button on
every thumbnail — for a pending (not-yet-uploaded) image this just drops it
locally; for an already-saved image it `PATCH`es the medicine's `images`
array with that URL removed (the backend already supported this via
`clean_medicine_payload`, it just had no UI). An upload failure after a
successful create is now a non-blocking warning ("saved, but one photo
failed — edit it to retry") instead of losing the whole submission.

**Test covering the fix:** `backend/scripts/test_pharmacy_medicine_images.py`
(19/19 passing) exercises the exact API sequence the fixed dialog now
performs: create → upload → verify the image appears on the medicine record,
in farmer search results, and in the farmer's medicine-detail view → upload a
second image (additive, not a replace) → reject a non-image content type →
reject an oversized file → confirm a text-only edit doesn't drop existing
images → remove one image via the `images` PATCH → confirm cross-pharmacy and
farmer accounts cannot upload/edit another pharmacy's medicine images.

---

## Issue 2 — Missing/inconsistent back buttons on 5 pharmacy staff screens

**Symptom reported:** "Back buttons are missing or inconsistent."

**Root cause found:** `PharmacyCatalogueScreen`, `PharmacyInventoryScreen`,
`PharmacyOrdersScreen`, `PharmacySuppliersScreen`, and `PharmacyAnalyticsScreen`
each set `automaticallyImplyLeading: false` on their `AppBar` with **no**
`leading` widget at all. In their normal, intended use — as tabs inside
`PharmacyDashboardScreen`'s bottom `NavigationBar`/`IndexedStack` shell — this
is *correct*: they aren't pushed routes, the bottom nav bar is the
navigation, and a back arrow there would be misleading (this matches the
task's own carve-out for "the root screen of a navigation shell").

The actual bug: `app_router.dart` *also* registers each of these as its own
standalone nested `GoRoute` (`/pharmacy/catalogue`, `/pharmacy/orders`, etc.,
lines 649-686). Nothing in the app currently pushes to those routes — but
they're real, reachable URLs (a typed/bookmarked/refreshed web URL, or a
future deep link/notification tap would resolve to them), and when reached
that way there is no bottom nav bar and no back arrow — a genuine dead end.

**Files involved:**
- `lib/features/pharmacy/presentation/screens/pharmacy_catalogue_screen.dart`
- `lib/features/pharmacy/presentation/screens/pharmacy_inventory_screen.dart`
- `lib/features/pharmacy/presentation/screens/pharmacy_orders_screen.dart`
- `lib/features/pharmacy/presentation/screens/pharmacy_suppliers_screen.dart`
- `lib/features/pharmacy/presentation/screens/pharmacy_analytics_screen.dart`
- `lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart`
- `lib/features/pharmacy/presentation/pharmacy_theme.dart` (new shared helper)

**Fix:** each of the 5 screens now takes an `embedded` constructor flag
(default `false`). `PharmacyDashboardScreen`'s `IndexedStack` passes
`embedded: true` (tab mode — no back button, unchanged behaviour). The
standalone `GoRoute` builders in `app_router.dart` don't pass it, so they get
`embedded: false` and a real back button via the new shared
`phBackLeading(context, embedded: ...)` helper in `pharmacy_theme.dart`,
which follows the project's standard pattern: `context.canPop()` → `pop()`,
else falls back to `context.go('/pharmacy')` (never crashes, never pops the
whole app). Every other pharmacy-adjacent screen was grep-audited for the
same `automaticallyImplyLeading: false` footgun
(`farmer_pharmacy_screen.dart`, `admin_pharmacy_screen.dart`,
`lib/features/delivery/**`) and none had it — those already have a correct,
working back button (`farmer_pharmacy_screen.dart` already uses exactly the
canPop/pop/fallback pattern this fix replicates).

**Test covering the fix:** `flutter analyze` (0 issues in changed files) —
see `PHARMACY_MARKETPLACE_FIX_REPORT.md` for why a full widget-test pass
wasn't added for this specific fix (documented there as a scope decision, not
a skipped/broken test).

---

## Design consistency — spot-checked, not overhauled

All 6 pharmacy staff screens already share one theme file
(`pharmacy_theme.dart`: `PhColors`, `phCard()`, `phChip()`, `phInput()`,
`showPharmacyNotice()`), so the *tokens* are already centralized — there is
no separate/forked pharmacy design language to unify. Spot-checked and found
consistent: AppBar color (`PhColors.appBar` / dark-green nav surface with
white foreground — no green-on-green), card radius/border/shadow via
`phCard()`, status chip colors via `phChip()`, `taka()`-equivalent currency
formatting (`৳` + `toStringAsFixed(0)`, consistent across dashboard/orders/
catalogue/analytics). Not independently re-audited pixel-by-pixel in this
pass: farmer-side pharmacy screen's typography scale vs. the rest of the
farmer app, and the admin pharmacy oversight screen's card styling vs. the
rest of the admin panel — flagged in the fix report as deferred, not claimed
fixed.

## Order / delivery / Cost Management workflows

Not re-audited from scratch here — these were the subject of the prior
`PHARMACY_PANEL_AUDIT.md` + `PHARMACY_PANEL_REPORT.md` pass (medicine
visibility filtering, order status machine, delivery assignment/calling/maps,
and the `expenses` mirroring fix), which is still current: re-ran all of that
pass's backend tests in this session (`test_pharmacy_flow.py`,
`test_labour_payment.py`) with no regressions, plus `manage.py check` /
`migrate --check` clean. See the fix report for the consolidated test run.
