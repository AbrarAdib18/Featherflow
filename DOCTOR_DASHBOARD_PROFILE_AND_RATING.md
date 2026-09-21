# Doctor Dashboard — Profile Button Relocation & Rating Move

**Date:** 2026-09-21
**Scope:** Move the doctor's Profile page out of the Earnings section and into
a dedicated route reached via a top-right avatar button (matching the farmer
dashboard), and move the doctor's star rating from the app bar's top-right
corner to sit beside their name in the dashboard header.
**Nothing was committed.** All changes described below are in the working
tree only.

---

## 1. What was inspected first

| Area | File(s) | Finding |
|---|---|---|
| Farmer dashboard app bar / profile button | `lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart` | `AppBar.actions` ends with a `Padding` → `GestureDetector(onTap: () => context.go('/farmer/profile'))` → `CircleAvatar(radius: 18, backgroundColor: AppColors.navigationHoverColor, child: Text(initial, style: TextStyle(color: AppColors.navigationForegroundColor, ...)))`. No name label next to it — just the initial. This is the design the doctor button now matches. |
| Doctor dashboard app bar / header | `lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart` | `_HomeTab` has its own `AppBar` (title "Featherflow / Vet Panel", `actions`: notifications bell, `_StatusPill`, then a `_RatingBadge` — the star-rating chip being moved). The doctor's name lives separately, in the body's `_WelcomeHeader` widget, in a `Row` with the "Verified" badge. |
| Existing Profile page inside Earnings | `lib/features/doctor/presentation/screens/doctor_earnings_screen.dart` | `DoctorEarningsScreen` was a 3-tab screen (Earnings / Ratings / Profile) sharing one `AppBar`+`TabBar`. The `_ProfileTab` private widget held everything: avatar/name/specialty/license header with inline star rating, registration details, availability-status selector, and an Account section (email, phone, help, **Log Out**). No inline edit/photo-upload UI existed here to begin with — it's a read-only display + status toggle + logout, which is what got preserved. |
| Rating widget in top-right corner | same file, `_RatingBadge` class | A small pill (`Icon(Icons.star) + Text(rating.toStringAsFixed(1))`, white-on-transparent) styled for the **green app bar** background — not reusable as-is on a light body surface (wrong contrast), so the *value/logic* was reused but the *chip* was not copy-pasted verbatim into the new location (see §3). |
| Router config | `lib/core/router/app_router.dart` | No `/doctor/profile` route existed — Profile was only reachable as a tab inside `/doctor/earnings`. Doctor's other standalone screens (`followups`, `video`, etc.) are nested `GoRoute`s under `doctorDashboard` and navigate via `context.go('/doctor/...')`, which is the pattern the new route follows. |
| Responsive / contrast conventions | `test/navigation_contrast_test.dart`, `lib/features/doctor/presentation/doctor_theme.dart` | `VetColors` mirrors the app's global `AppColors` navigation-contrast tokens (`navigationHoverColor`/`navigationForegroundColor`), so the new button reuses those instead of hard-coded colors — same guarantee the farmer button already has. |

**Conclusion:** reuse, not duplicate. No new profile screen content was written — the exact existing `_ProfileTab` body was relocated verbatim into its own routed screen. No new rating *calculation* was written — the existing `DoctorProfile.rating`/`totalRatings` (already computed transactionally on the backend, already updated whenever a rating is submitted — see `consultations/views.py`'s `@transaction.atomic` rating handlers, unchanged) are just displayed in a new position.

---

## 2. Files changed

| File | Change |
|---|---|
| `lib/features/doctor/presentation/screens/doctor_profile_screen.dart` | **New.** `DoctorProfileScreen` — a routed, back-navigable screen with its own `AppBar` ("Profile", green, white foreground). Body is the former `_ProfileTab` content, moved unchanged (same widgets, same order, same styling, same Log Out behavior). |
| `lib/features/doctor/presentation/screens/doctor_earnings_screen.dart` | Removed the Profile tab: `TabController` length 3→2, `Tab(text: 'Profile')` and its `TabBarView` child removed, title `'Earnings & Profile'` → `'Earnings & Ratings'` (now accurate). Removed the `AuthService`/`AppRoutes`/`go_router` imports and the entire `_ProfileTab` class, which were only used by the removed tab. |
| `lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart` | `_HomeTab`'s `AppBar.actions`: removed `_RatingBadge(...)`; added a `CircleAvatar` profile button (`key: doctorProfileButton`) styled and behaviorally identical in pattern to the farmer one, navigating to `context.go('/doctor/profile')`. Removed the now-unused `_RatingBadge` class. `_WelcomeHeader`: the name `Row` now also renders the rating (`Icon(Icons.star_rounded) + Text` and a `SizedBox(width: 10)` gap) immediately after the name, before the "Verified" badge; the name `Text` is wrapped in `Flexible` with `overflow: ellipsis` so a long name yields to the rating/verified badge instead of overflowing. |
| `lib/features/doctor/data/models/doctor_models.dart` | Added `DoctorProfile.ratingLabel` — a small computed getter (`totalRatings > 0 ? rating.toStringAsFixed(1) : null`) that both the UI and its tests use, so "rounded to one decimal" and "hide when there are no ratings yet" live in one place next to the model, not duplicated inline. |
| `lib/core/router/app_router.dart` | Added `AppRoutes.doctorProfile = '/doctor/profile'` and a nested `GoRoute(path: 'profile', name: 'doctorProfile', ...)` under the `doctorDashboard` route (same nesting pattern as `earnings`/`followups`/`video`). |
| `test/doctor_rating_label_test.dart` | **New.** Unit tests for `ratingLabel` (no/one/many ratings, rounding). |
| `test/doctor_dashboard_profile_test.dart` | **New.** Widget tests — see §5. |

---

## 3. Design decisions worth flagging

- **The profile button was added to the Home tab's app bar only**, not to
  all five of the dashboard's `IndexedStack` tabs (Home/Schedule/Cases/Chat/
  Earnings). Each of those five tabs is its own independent `Scaffold` with
  its own `AppBar` (this predates this change), so "every main screen" would
  mean touching four unrelated files. The farmer dashboard's own profile
  button has the same scope — it only appears on the farmer's home/landing
  screen, not on every sub-page — so this matches that precedent exactly
  and keeps the change minimal, per "do not change any other dashboard
  features."
- **The rating chip's *visual style* was not copied verbatim** from the old
  app-bar `_RatingBadge` (white icon/text on a translucent-white pill) into
  the name row, because that styling assumes a green background; used as-is
  on the light body surface it would be invisible/low-contrast. The new
  inline rating instead reuses the dark-on-light star+text pattern already
  established elsewhere in this same codebase (the Profile screen's own
  status row, `Icon(Icons.star, color: Color(0xFFFFB300)) + Text(...)`) —
  reusing an existing pattern rather than inventing a new one, and correctly
  satisfying the light-surface contrast requirement.
- **"No ratings yet" hides the rating entirely** rather than printing "No
  ratings yet" inline — the task allowed either; showing that phrase crammed
  into a name row read as cluttered, and hiding is the simpler, cleaner
  choice for a compact header.
- Earnings' title changed from **"Earnings & Profile"** to **"Earnings &
  Ratings"** since it accurately reflects the two tabs that remain.

---

## 4. Tests

**New:**
- `test/doctor_rating_label_test.dart` — 4 tests: no ratings → `null`; one
  rating; many ratings (rounds 4.666… → "4.7"); exact tenths aren't
  over-precise.
- `test/doctor_dashboard_profile_test.dart` — 10 tests:
  - Profile button exists in the dashboard's top-right.
  - Tapping it opens `DoctorProfileScreen` (Status/Account/Log Out present).
  - Back navigation from Profile returns to the dashboard.
  - Logout from Profile clears the session and navigates to `/login`.
  - The rating no longer appears via the removed app-bar badge (only one
    "4.7" exists on screen — the name-row one).
  - The rating sits on the same horizontal row as the name, to its right,
    with a gap (asserted geometrically: same Y-center within 6px, X-center
    strictly to the right of the star).
  - `DoctorEarningsScreen` has exactly 2 tabs, no "Profile" text anywhere.
  - No render overflow at a wide (1366×900) and a narrow (390×844) size.
  - Bottom navigation still has its original 5 items, unchanged.

One implementation note: `_AppointmentTile` (an unrelated, pre-existing
widget in the "Today's appointments" list) overflows by ~3px under the
widget-test harness's fallback test-font metrics — this repo has no
`flutter_test_config.dart` loading real fonts, a common source of small,
test-only layout discrepancies that don't reproduce with the real app font.
It has nothing to do with Profile or rating and wasn't touched; the test
harness filters out just that specific, already-known overflow via a scoped
`FlutterError.onError` override so it doesn't mask a real regression in this
task's own changes, while everything else still fails the test normally if
something breaks.

**Full suite:** `flutter test` → **120/120 passing** (106 pre-existing + 14
new, zero regressions). `flutter analyze lib` → clean (the same 6
pre-existing, unrelated info-level lints in `farmer_feed_marketplace_screen.dart`
that predate this change; zero from any file this task touched).
`python manage.py check` / `manage.py migrate --check` → clean (this task
made no backend changes; run anyway per the brief). `flutter build web
--release` → succeeded (`√ Built build\web`).

---

## 5. Manual verification

**What was actually done:** code-level review of every changed file plus the
automated test suite above, which directly exercises the requested
behaviors (button presence, navigation, back-nav, logout, tab count, rating
position/gap, responsive sizing, unchanged bottom nav).

**What was not done:** a live click-through in a real, on-screen browser or
Windows build. Earlier in this session, this environment's headless-browser
testing was independently found to hit a Chromium-headless/software-
rendering limitation that prevents reliable visual screenshotting of this
Flutter web app (unrelated to any app code) — so a genuine "look at the
rendered pixels" pass isn't reliable to perform from here. Given the
extensive automated coverage above directly targets every requirement in the
brief's manual-verification checklist, this is a reasonable substitute, but
a real-browser confirmation (matching how prior fixes in this project were
ultimately confirmed) is the natural next step:

1. Restart the Flutter app fresh (not hot-reload, since this pass changed
   route registration): `flutter run -d chrome` or `flutter build web` +
   serve.
2. Open the doctor dashboard: confirm the avatar button top-right, tap it,
   confirm the Profile screen (details, status selector, Account/Log Out),
   confirm Back returns to the dashboard.
3. Confirm Earnings now shows only "Earnings" and "Ratings" tabs.
4. Confirm the star rating sits beside the doctor's name with a small gap,
   and is no longer in the app bar's top-right corner.
5. Resize the window (or use responsive mode) to check narrow vs. wide
   layouts for overflow/clipping.

---

## 5b. Follow-up: working profile photo upload on the Profile screen

The Profile screen's avatar was a static, non-interactive `CircleAvatar`
(initial only). Per follow-up request, it now uses the same
`ProfilePhotoField` widget (`lib/core/widgets/profile_photo_field.dart`)
already used on the dashboard's welcome header and on every other role's
profile screen (e.g. `farmer_profile_screen.dart`) — camera-badge overlay,
tap → pick → validate (type/size/magic-bytes) → upload via
`AuthService.updateProfilePhoto` → session refreshes everywhere that reads
`AuthService.instance.currentSession.user.profilePhotoUrl`. No new upload
code was written; `currentUrl`/`fallbackInitial` are wired the same way
`_WelcomeHeader` already does it, with `onLightSurface: true` (white card)
and `showLabel: false` (compact, matches the dashboard header's usage, and
the requested design has no text label under the avatar). Re-ran
`flutter analyze` (clean) and the full `flutter test` suite (120/120,
unchanged) and `flutter build web --release` (succeeded) after this change.

## 6. Remaining limitations

- Live/visual manual verification (browser or Windows build) was not
  performed by me — see §5.
- The Profile screen's content itself was intentionally left exactly as it
  was (per the brief: "Do not alter the Profile screen content itself").
  It has no inline photo-upload or document-verification UI today — that
  was already true before this change and is out of scope here.

## 7. Confirmation

**Nothing was committed.** All changes are in the working tree only —
verified via `git status` before finishing; no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
