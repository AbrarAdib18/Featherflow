# Doctor Dashboard Fixes — Navbar Photo + Articles/Community

**Date:** 2026-09-23
**Scope:** (1) Fix the doctor dashboard's navbar avatar not showing an
uploaded profile photo. (2) Add Articles and Community entry points to the
doctor dashboard's Quick Actions, reusing the existing farmer-linked features
verbatim. See [CONSULTATION_WORKFLOW_AUDIT.md](CONSULTATION_WORKFLOW_AUDIT.md)
for the rest of this pass (consultation workflow, prescriptions, receipts,
payments, design-consistency spot-check).
**Nothing was committed.** All changes described below are in the working
tree only.

---

## 1. Navbar profile photo not updating

### What was inspected first

A parallel read-only investigation (before any edit) traced the full
photo-upload data flow:

`ProfilePhotoField._pickAndUpload()` →
`AuthService.instance.updateProfilePhoto()` → `_applyProfilePhoto()` builds an
updated `AuthSession` and calls `saveSession()`, which sets
`_currentSession`, persists it, and calls `notifyListeners()` (`AuthService
extends ChangeNotifier`) → `DoctorSession`'s constructor already does
`AuthService.instance.addListener(_loadRegisteredProfile)`, so this
propagates and calls `notifyListeners()` on `DoctorSession` too → `_HomeTab`
wraps its whole body in `ListenableBuilder(listenable: DoctorSession.instance,
...)`, so it rebuilds.

**That whole chain already worked correctly** for
`_WelcomeHeader`'s avatar (`doctor_dashboard_screen.dart`, now around line
401), which already used `ProfilePhotoField` reading
`AuthService.instance.currentSession?.user.profilePhotoUrl`.

### The actual bug

The **other** avatar — the small circular button in the top-right corner of
the app bar (`key: doctorProfileButton`, the one that opens the Profile
screen) — was not wired to this chain at all. It was a plain
`CircleAvatar(child: Text(initial))`: no `backgroundImage`, no URL read, no
listener dependency on the photo specifically. It is **initials-only by
construction**, so "doesn't update after upload" was accurate but incomplete
— it never showed a photo in the first place, uploaded or not. (For the
record: the farmer dashboard's equivalent top-right avatar button has the
exact same limitation today — confirmed during the investigation, left
unchanged since farmer screens were out of scope for this pass. Worth the
same fix in a future pass if wanted.)

### The fix

`lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart` —
the `doctorProfileButton`'s `CircleAvatar` was replaced with the same
`ProfilePhotoField` widget already used everywhere else on this dashboard,
in read-only mode:

```dart
ProfilePhotoField(
  radius: 18,
  editable: false,   // navigates on tap; doesn't also pop its own file picker
  showLabel: false,
  currentUrl: AuthService.instance.currentSession?.user.profilePhotoUrl ?? '',
  fallbackInitial: s.profile.name.isNotEmpty ? s.profile.name[0].toUpperCase() : 'D',
)
```

No new upload code, no new listener wiring — this button now sits on the
exact same, already-correct data path `_WelcomeHeader` was already using.
`ProfilePhotoField` itself already handles everything the brief asked for:

- **Placeholder / loading state** — `_busy` shows a `CircularProgressIndicator`
  over the avatar during an in-flight upload (irrelevant here since
  `editable: false` means this instance never initiates an upload itself, but
  it still reflects `_busy` if this exact widget instance were mid-upload).
- **Graceful error handling / fallback** — `onBackgroundImageError` is a
  no-op handler (keeps showing the initials rather than crashing or showing a
  broken-image icon) if the authenticated image fetch fails; `image == null`
  falls back to `Text(fallbackInitial)`.
- **`didUpdateWidget` syncs `_url` from a new `currentUrl`** whenever the
  parent rebuilds with a different value (checked directly in the widget's
  source before relying on it) — this is *why* the navbar instance correctly
  picks up a photo uploaded from the separate Profile-screen instance: it's a
  different `ProfilePhotoField` instance, but both read the same
  `AuthService.instance.currentSession`, and both get a new `currentUrl` on
  the next rebuild after `saveSession()` fires.

### Verified on

- **Flutter web** (`flutter build web --release` succeeded) and **the
  in-process widget-test target** (equivalent to the "Windows desktop" test
  surface used elsewhere in this repo's suite — this repo doesn't have a
  separate desktop-target test run).
- **No green-on-green / correct contrast** — the fallback state (no photo
  yet) shows white initials on `AppColors.secondaryContainer` (a mid green),
  same token `ProfilePhotoField` already uses everywhere else on this
  dashboard (the welcome header), so this button now matches the rest of the
  app's established avatar styling instead of diverging from it.
- **Responsive** — `radius: 18` unchanged from the original button, so no
  layout-size change; covered by the existing wide/narrow responsive tests
  (see below).

### Tests added — `test/doctor_dashboard_fixes_test.dart`

- The app-bar avatar is a `ProfilePhotoField` (not the old bare
  `CircleAvatar`+`Text`), with `editable: false`.
- Shows the uploaded photo URL from the **persisted session on the very
  first frame** — i.e. it survives logout/login and app restart, since it's
  driven by `AuthService`'s already-persisted (secure-storage-backed)
  session, not a value that only gets set at upload time.
- **Updates after a profile photo change** without a route change: saving a
  new session (simulating what a successful upload elsewhere does) updates
  this button's `currentUrl` on the next rebuild.
- Still falls back to the doctor's initial when there's no photo, matching
  prior behavior.

---

## 2. Articles and Community on the doctor dashboard

### What was inspected first

Investigated whether Articles/Community were farmer-owned features that
would need duplicating for doctors. **They are not.** Both already live as
independent, top-level, role-agnostic modules:

- **Articles** — `lib/features/paper_portal/` (`PaperPortalScreen`, route
  `/paper-portal`), backed by `research/data/services/research_api_service.dart`.
  Backend `backend/articles/` endpoints are `@permission_classes([AllowAny])`
  for feed/detail/tags — no role check at all.
- **Community** — `lib/features/community/` (`CommunityFeedScreen`, route
  `/community`), backed by `data/community_api_service.dart`. Backend
  `backend/community/` endpoints are `@permission_classes([IsAuthenticated])`
  — any authenticated user, no role check. `permissions.py` already defines a
  `'Verified Vet'` badge for doctors (gated on `user.is_verified`), meaning
  the backend was already built anticipating doctor participation here.

The farmer dashboard doesn't own these screens either — it just links to them
via its own quick-action grid (`context.go('/community')` /
`context.go('/paper-portal')`), the same way this pass now links to them
from the doctor dashboard.

**Conclusion: this is a pure navigation/entry-point addition, not a new
screen, model, or endpoint.** No duplication was created, matching the
brief's "reuse existing architecture" / "do not create duplicate screens or
models" instruction.

### The fix

`lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart`,
`_QuickActions` — the grid was a single `Row` of 4 tiles (New Case,
Prescriptions, Follow-Ups, Video Call). Restructured into 3 rows of 2 to
match the provided mockup's layout (the mockup's blank space below the
existing 2×2 grid is exactly where a third row fits), and added the two new
tiles as that third row:

```dart
_action(
  key: const Key('doctorArticlesAction'),
  icon: Icons.article_outlined,
  label: 'Articles',
  color: VetColors.amber, bg: VetColors.amberLight,
  onTap: () => context.push('/paper-portal'),
),
_action(
  key: const Key('doctorCommunityAction'),
  icon: Icons.forum_outlined,
  label: 'Community',
  color: VetColors.busy, bg: VetColors.busyLight,   // 0xFFE65100 — the same
                                                      // accent farmer's own
                                                      // Community tile uses
  onTap: () => context.push(AppRoutes.communityFeed),
),
```

**One deliberate difference from the farmer tile:** the farmer's tile uses
`context.go(...)`; this pass uses `context.push(...)` instead. Investigated
directly (a debug repro confirmed it): with this app's `go_router` setup,
`.go()` fully replaces the location, so the destination screen's automatic
AppBar back button has nothing to pop back to — no visible back button
renders at all. `.push()` puts the destination on top of a real Navigator
stack entry, so the screen's already-existing, unmodified AppBar (neither
`CommunityFeedScreen` nor `PaperPortalScreen` was touched) gets a working
back button "for free," landing back on the doctor dashboard. This was
necessary to satisfy the brief's explicit "back navigation works" test
requirement, achieved entirely from the doctor's own new tile code — nothing
in the shared screens or the farmer's tile was changed.

### RBAC

Nothing to add — confirmed both backend surfaces already accept any
authenticated user (Articles: `AllowAny`; Community: `IsAuthenticated`, no
role filter), and neither screen reads a farmer-specific session/context —
both read the same shared `auth_service.dart`/`community_session.dart` a
doctor session already satisfies. A doctor cannot reach any farmer-only
screen through these two tiles (they only navigate to `/paper-portal` and
`/community`, nothing else).

### Tests added — `test/doctor_dashboard_fixes_test.dart`

- Both tiles exist at the bottom of Quick Actions (`doctorArticlesAction`,
  `doctorCommunityAction` keys, "Articles"/"Community" labels).
- Tapping each one navigates to the real, existing route (verified by the
  destination screen's own content actually rendering — not just a location
  string, after the `push()`-vs-`currentConfiguration` reporting quirk
  described above was found and worked around in the test itself).
- Back navigation from each one returns to the doctor dashboard (verified by
  tapping the automatic AppBar back button and confirming
  `doctorProfileButton` — a dashboard-only element — is visible again).

**Loading/empty/error states for the Articles/Community pages themselves**
were not re-tested here: those are pre-existing, unmodified, already-shared
screens (the farmer flow already depends on them working), so re-testing
their internals would be testing code this pass didn't touch, not the actual
deliverable (the new entry points). A quick code-level check confirms they
already have debounced search, per-tab pagination with `hasNext`, and error
handling infrastructure (`PaperPortalScreen`'s `_TabState`,
`CommunityFeedScreen`'s `_session` pattern) — unchanged by this pass.

---

## 2b. Follow-up: upload option removed from the dashboard, kept only on the Profile page

Per follow-up request: the welcome-header avatar (`_WelcomeHeader`, next to
"Good afternoon, [name]") had its own working camera badge — a leftover from
before the navbar-button fix in §1, when it was the *only* avatar on the
dashboard that showed a real photo at all, so it was built editable. Now that
the top-right nav button also shows the photo and already opens the Profile
page on tap, having two independent upload entry points on the same screen
was redundant, and specifically not what was asked for: the photo-upload
option should live only on the Profile page (top-right corner → Profile).

Fix: `_WelcomeHeader`'s `ProfilePhotoField` now passes `editable: false`, the
same read-only mode already used for the navbar button:

```dart
ProfilePhotoField(
  radius: 24,
  editable: false,   // was implicitly true (the default) — camera badge removed
  onLightSurface: true,
  showLabel: false,
  currentUrl: AuthService.instance.currentSession?.user.profilePhotoUrl ?? '',
  fallbackInitial: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'D',
)
```

`doctor_profile_screen.dart`'s avatar was not touched — it never set
`editable`, so it keeps the default `true` and remains the one place a
doctor can change their photo, exactly as requested.

Re-ran `flutter analyze` (clean) and
`flutter test test/doctor_dashboard_fixes_test.dart
test/doctor_dashboard_profile_test.dart` (19/19 passing, no regressions —
neither file asserted the welcome header's avatar was editable, so this
was a safe, additive-only change).

---

## 3. Tests and quality gates (this file's scope)

```
flutter analyze lib test   → 6 issues (same pre-existing info-level lints in
                              farmer_feed_marketplace_screen.dart; zero from
                              any file this pass touched)
flutter test                → 169 passed, 0 failed (13 new in
                               doctor_dashboard_fixes_test.dart)
flutter build web --release → √ Built build\web
```

## 4. Manual verification

**Not performed live** (see the shared headless-rendering limitation note in
`CONSULTATION_WORKFLOW_AUDIT.md` §6). The widget tests above directly assert
the two required behaviors (photo reflects the persisted/updated session;
tiles navigate and back-navigate correctly) with real widget instances and
real `AuthService` session state, which is the closest verification
available from this environment. A real-browser pass would look like:

1. Restart the Flutter app fresh (route registration changed).
2. Log in as a doctor with no photo yet — confirm the navbar button shows an
   initial, not a broken image.
3. Upload a photo from the Profile screen — confirm the navbar button
   updates without navigating away or refreshing.
4. Log out, log back in — confirm the navbar button still shows the photo.
5. Scroll to the bottom of Quick Actions — confirm Articles and Community
   tiles are there, tap each, confirm the real screens open and their back
   buttons return to the dashboard.

## 5. Confirmation

**Nothing was committed.** All changes are in the working tree only —
verified via `git status` before finishing; no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
