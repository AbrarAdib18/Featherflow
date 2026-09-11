# Global navigation contrast — audit & enforcement

**Goal:** every text / icon / label / badge / tab / back button / menu item that sits
**directly on a brand-green navigation surface** resolves to white or a clearly-readable
near-white colour — enforced by shared theme constants + a regression test, not by
hand-painting `Colors.white` on every widget.

**Nothing committed.** All changes are in the working tree. `HEAD` unchanged.

---

## 1. What the audit found

Green navigation surfaces in this app:

| Surface | Where | Colour |
|---|---|---|
| App bars | **every** screen + full-screen dialogs (~70 `AppBar`s) | `0xFF01291E` (deep forest green) |
| Green tab bars | `bottom:` of green app bars (farmer, pharmacy, doctor, delivery, admin, inventory) + admin `Container(color: appBar)` strips | same green |
| Sidebar header | admin sidebar / drawer header | same green |
| Green "nav cards" | farmer "Become a Pro Farmer", disease-detection paywall → Plans | green gradient |
| Navigation rails | none currently (theme added defensively) | — |

Bottom navigation bars (farmer / doctor / delivery / pharmacy) are painted **white**, not
green — dark-green selected + grey unselected on white is correct contrast, so they were
out of scope and left unchanged.

**State of the code before this change:** ~90 % already rendered white-on-green, but by
hand-painting `color: Colors.white` on *each* title / icon / label. This was fragile:

- **32 green app bars set `backgroundColor` but no `foregroundColor`.** In Material 3 an
  `AppBar` with an explicit background and no `foregroundColor` falls back to
  `colorScheme.onSurface` (near-black) — so any action icon added without an explicit
  `color:` renders **dark-on-green**.
- **1 real defect:** `farmer_pharmacy_screen.dart` — the `TabBar` (`Browse / Cart /
  My Orders`) set no `labelColor`, so it inherited `colorScheme.primary` (dark green) +
  `onSurfaceVariant` (grey) → **dark-green + grey tabs on a green app bar, barely legible.**
  (That screen's `AppBar` also set no background at all, so it was inconsistently *white*
  while every sibling farmer screen is green.)
- **Green-on-green badges** on the green admin sidebar header and the admin/research
  app-bar avatars: the role chip and the user initial were drawn in
  `secondary` (`0xFF1DB584`, a mid-bright green) on the dark-green header — a green-on-green
  "badge on a green surface", exactly what rule 1 forbids.
- No shared constants — `Colors.white`, `Colors.white54/60/70`, `0xFF999999` scattered
  across ~40 files with no single source of truth and nothing preventing regressions.

---

## 2. Shared theme changes — `lib/core/theme/theme.dart`

### 2a. Shared navigation-contrast constants (`AppColors`)

```dart
static const Color navigationSurface           = primary;          // 0xFF01291E
static const Color navigationForegroundColor    = Color(0xFFFFFFFF);
static const Color navigationIconColor          = Color(0xFFFFFFFF);
static const Color navigationSelectedColor      = Color(0xFFFFFFFF);
static const Color navigationUnselectedColor    = Color(0xCCFFFFFF); // white @ 80 %
static const Color navigationHoverColor         = Color(0x1FFFFFFF); // white @ 12 %
static const Color navigationDisabledColor      = Color(0x8AFFFFFF); // white @ 54 %
static const Color navigationIndicator          = secondary;        // 0xFF1DB584 — visible lighter-green highlight
static const List<Color> navigationForegroundTokens = [ …the six above… ];
```

Contrast on the green surface (`#01291E`, luminance ≈ 0.013):

| Token | Composited contrast vs surface | Verdict |
|---|---|---|
| foreground / icon / selected (opaque white) | ~16.8 : 1 | ✅ AAA |
| unselected (white 80 %) | ~11 : 1 | ✅ AAA |
| disabled (white 54 %) | ~4.7 : 1 | ✅ readable, still white-hued (rule 1: "readable white with reduced opacity, never dark green on green") |
| indicator vs surface | lighter green, clearly separated | ✅ |

### 2b. Theme components (were **absent** — every screen was on its own)

| Component | Setting |
|---|---|
| `appBarTheme` | `backgroundColor: navigationSurface`, `foregroundColor / iconTheme / actionsIconTheme / titleTextStyle / toolbarTextStyle`: white, `surfaceTintColor` + `shadowColor` transparent, `elevation` 0, `systemOverlayStyle` = light status-bar icons |
| `tabBarTheme` (`TabBarThemeData`) | `labelColor` white, `unselectedLabelColor` white 80 %, `indicatorColor` = `navigationIndicator`, `dividerColor` transparent, `overlayColor` = hover token |
| `navigationRailTheme` | green background, white selected/unselected icons + labels, lighter-green `indicatorColor` (defensive — no rail in the app yet) |
| `drawerTheme` | white surface + transparent tint (drawers wrap a light sidebar whose only green band, the header, paints its own white) |

Because **every** app bar in the app is this green, a global white foreground is safe and
removes the 32-file class of "forgot `foregroundColor`" bugs in one move. `ColorScheme.onPrimary`
was already `#FFFFFF` (verified by test).

### 2c. Per-panel token re-export

Each panel keeps its own colour class (`AColors`, `DColors`, `VetColors`, `PhColors`,
`RColors`). Every one now re-exports the six tokens from `AppColors` so panel code has a
single shared source:

```dart
static const Color navigationForegroundColor = AppColors.navigationForegroundColor;
// …etc
```

Files: `admin_theme.dart`, `delivery_theme.dart`, `doctor_theme.dart`,
`pharmacy_theme.dart`, `research_theme.dart`.

---

## 3. Screens / components updated

| File | Change |
|---|---|
| `lib/core/theme/theme.dart` | + 8 nav constants, + `appBarTheme` / `tabBarTheme` / `drawerTheme` / `navigationRailTheme` |
| `admin_theme.dart`, `delivery_theme.dart`, `doctor_theme.dart`, `pharmacy_theme.dart`, `research_theme.dart` | + shared nav-token re-exports |
| `admin/presentation/widgets/admin_scaffold.dart` | app bar bg/fg/back → nav tokens; app-bar avatar → white initial on white-tint disc (was `secondary` green-on-green); `_ShiftChip` gains an `onGreen` flag — on the green app bar it renders white text + a brightened status dot; on the light wide-layout top bar it keeps its semantic colouring |
| `admin/presentation/widgets/admin_sidebar.dart` | green header: avatar initial, name **and** role chip → white nav tokens (role chip was `secondary`-on-green) |
| `research/presentation/widgets/research_scaffold.dart` | app bar bg/fg/back → nav tokens; small app-bar profile avatar → white on white-tint (was `secondary`-on-green) |
| `farmer/presentation/screens/farmer_dashboard_screen.dart` | app-bar user avatar → white initial on white-tint disc (was `secondary`-on-green) |
| `farmer/presentation/screens/farmer_pharmacy_screen.dart` | **auto-fixed** by the global theme — the un-styled `AppBar` is now green + white and its `TabBar` inherits white labels (no code change needed) |
| **~30 other green app bars** with a missing `foregroundColor` | **auto-fixed** — the global `appBarTheme` now supplies the white foreground / icon theme they relied on painting by hand |

Screens deliberately **not** rewritten: the ~40 screens that already hand-set
`color: Colors.white` on their app-bar title/icons. Those literals resolve to the identical
value and are now redundant belt-and-suspenders rather than the sole guarantee — the global
`appBarTheme` / `tabBarTheme` is the guarantee. Bulk-swapping 40 files of `Colors.white` →
`AppColors.navigationForegroundColor` is pure churn with zero behaviour change and was left
for a follow-up sweep to keep this diff reviewable.

---

## 4. Navigation surfaces audited (state variants checked)

| Panel | App bar | Green TabBar | Selected / unselected | Back / menu | Badge / chip | Result |
|---|---|---|---|---|---|---|
| **Auth** (login, signup steps, OTP, reset) | green + white (`_kInk`, explicit) | — | — | white | — | ✅ |
| **Farmer** (dashboard, cost mgmt, disease detection, subscription, tax ×4, expense/revenue/loan/reports/inventory/feed, consultations, vet map, profile, **pharmacy**) | green + white | white labels (consultations, pharmacy, inventory) | white / white 80 % | white | app-bar avatar → white (fixed); notif badge = error-red + white ✅ | ✅ |
| **Community** (feed, create, search, post, profile, notifications) | green + white | custom tab row white / white 60 % ✅ | white / white 60 % | white | notif bell badge = error-red + white | ✅ |
| **Pharmacy** (dashboard + catalogue/inventory/orders/suppliers/analytics) | green + white (explicit) | white labels | white / white 60 % | white | rating/status pills white on white-tint | ✅ · bottom `NavigationBar` is **white** (light surface, dark labels — correct) |
| **Doctor** (dashboard + appts/cases/messenger/earnings/followups/prescriptions/video) | green + white | white labels (earnings) | white / white 60 % | white | `_StatusPill` / `_RatingBadge` white on white-tint ✅ | ✅ · bottom bar white (correct) |
| **Delivery** (dashboard + orders/detail/earnings/map/performance/attendance) | green + white | white labels (orders) | white / white 54 % | white | online-toggle pill white + bright dot ✅ | ✅ · bottom bar white (correct) |
| **Research** (scaffold + 12 module screens, paper portal) | green + white (scaffold, tokens) | — | sidebar is light (dark-on-white, correct) | white | app-bar avatar → white (fixed); sidebar header is light | ✅ |
| **Admin** (scaffold + 15 module screens) | green + white (scaffold, tokens) | white / white 60 % (11 module TabBars, all explicit) | sidebar selected = green tint on white (light, correct) | white | sidebar header avatar + name + role chip → white (fixed); `_ShiftChip` white on green / semantic on light ✅ | ✅ |

State variants: **normal / selected / unselected** — covered above. **hover / pressed /
focused** — `appBarTheme` + `tabBarTheme.overlayColor` = white 12 % ripple on green.
**disabled** — `navigationDisabledColor` (white 54 %, still white-hued & ≥ 4.5:1).
**loading** — spinners inside green bars are unaffected (body content, not nav foreground).
**error / notification badge** — the app's badges use `colorScheme.error` (red) fill + white
text, which reads on both white and green; unchanged.

---

## 5. Regression test — `test/navigation_contrast_test.dart` (9 assertions, all pass)

| Test | Asserts |
|---|---|
| six nav tokens are white-hued | every channel ≥ 0.90 |
| foreground / selected / unselected read on green | composited WCAG contrast ≥ 4.5 : 1 vs `navigationSurface` |
| disabled token | white-hued **and** ≥ 3 : 1 (never dark-on-green) |
| indicator | not equal to the surface, clearly separated |
| `ColorScheme.onPrimary` | white, and `primary` really is a dark green (luminance < 0.1) |
| `AppBarTheme` | background = green; `foregroundColor` / `iconTheme` / `actionsIconTheme` / `titleTextStyle` all white & pass contrast |
| `TabBarThemeData` | `labelColor` + `unselectedLabelColor` white & pass contrast; indicator ≠ surface |
| `NavigationRailThemeData` | green background; selected/unselected icon + label themes white & pass contrast |
| **rendered** green `AppBar` (un-coloured title, action icons, back button, `TabBar` labels) | the inherited `DefaultTextStyle` + `IconTheme` in the app-bar subtree are near-white, and **every glyph actually painted** (title + icons + tab labels) is white-hued and ≥ 3 : 1 on green |

---

## 6. Test results

| Check | Result |
|---|---|
| `flutter test` | **71 / 71 passed** (was 62; + 9 new nav-contrast assertions) — no existing test regressed by the new `appBarTheme` / `tabBarTheme` |
| `flutter analyze lib test/navigation_contrast_test.dart` | **0 errors**, same 7 pre-existing admin warnings (`_k*` unused mock constants + 2 `use_build_context_synchronously` infos), none introduced here |
| `flutter build web --release` | **`√ Built build\web`** |
| Visual pass (real login, Chrome web build) | `/farmer` app bar + white-tint avatar ✅ · **`/farmer/pharmacy` — now a green app bar with white `Browse / Cart / My Orders` tabs** (was the one real defect) ✅ · `/community` green bar + white tab row ✅ · `/admin` green sidebar header with white avatar / name / role chip ✅ · `/admin/users` green TabBar white labels ✅ |

---

## 7. Remaining contrast issues

| # | Severity | Issue |
|---|---|---|
| 1 | **LOW** (cosmetic, pre-existing, out of nav scope) | The `৳` (BDT taka) glyph renders as a "tofu" box for a beat until the app font loads — a *font-coverage* gap, not a colour issue. Seen on the farmer dashboard, Plans card, tax cards, admin revenue. Fix = bundle a font with `৳` coverage (e.g. Noto Sans Bengali) or render a `BDT` text prefix. |
| 2 | **LOW** (app-wide, out of scope) | Primary CTA buttons (`ElevatedButton` / `FilledButton`) are `secondary` green (`#1DB584`) + white text ≈ 2.5 : 1 — below AA for a *button label*. This is the global button style used on every surface, not a navigation surface, so it's outside this task; flagged for a separate button-contrast pass (e.g. move button fill to `secondaryContainer` `#00896A`, ~4.6 : 1). |
| 3 | **INFO** | ~40 screens still hand-write `color: Colors.white` on their app-bar title/icons. Harmless (same value, now redundant) but a follow-up sweep should replace them with `AppColors.navigationForegroundColor` / the panel re-exports so the shared token is the only knob. A lint (`avoid_hard_coded_colors` style) could keep it honest. |

No dark-green / black / near-black text or icons remain on any green navigation surface.
