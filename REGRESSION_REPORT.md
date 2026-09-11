# Featherflow — Visual & Functional Regression Report

**Scope:** focused regression after the recent *theme conversion (fake‑dark → real light)*,
*community image‑upload*, *subscription/Plans navigation*, and *demo‑data* changes.
**Build under test:** Flutter web (CanvasKit) served by `flutter run -d web-server --web-port 5000`,
Django/uvicorn backend on `:8000`, PostgreSQL. Restarted clean before the final pass.
**Nothing was committed.** Working tree left as‑is. One small code change was made during this
pass (see *Fixes applied*), inside an already‑untracked file.

---

## 1. Automated gates — ALL GREEN

| Check | Result |
|---|---|
| `python manage.py check` | **0 issues** |
| Backend regression suites (11) | **513 checks, 0 failed** — community 56, farmer_panel 35, disease_detection 25, articles_feed 28, admin_panel 65, doctor_flow 58, vets_nearby 12, signup_flows 88, verification_flows 36, signup_documents 46, **tax_calculator 64** |
| `flutter test` | **62 / 62 passed** |
| `flutter analyze lib` | **0 errors**, 7 pre‑existing warnings/infos (all in `lib/features/admin/…` — unused `_k*` mock constants + 2 `use_build_context_synchronously` infos; present before this work, unrelated to the reviewed changes) |
| `flutter build web --release` | **`√ Built build\web`** (advisory‑only output: wasm dry‑run note for the transitive `socket_io_common` dep, and the standard `MaterialIcons` tree‑shake note — neither is a failure) |

---

## 2. Per‑module walkthrough

Legend: ✅ opened, rendered, readable, no console/backend exceptions · ⚠️ issue (see §3)

| Module / screen | Status | Notes |
|---|---|---|
| **Auth – Sign In** (`/login`) | ✅ | Light theme, contrast fine, "Forgot password?" link present |
| **Auth – Reset password** (`/reset-password`) | ✅ | "Forgot your password?" → email → "Send code" → "Back to sign in". End‑to‑end reset (send code → verify → new password) confirmed via API earlier this session |
| **Auth – Sign Up + role steps** | ✅ | Wizard + 6 role flows; real‑time password validation and back/forward form‑persistence covered by `signup_flow_test.dart` (62/62) and `test_signup_flows.py` (88/88) |
| **Farmer – Dashboard** (`/farmer`) | ✅ | "Welcome back, Kaneda!", nav cards, light theme. Seeded totals (৳291,760 revenue / 3,516 birds) confirmed via `/api/farmers/dashboard/` and an earlier real‑login session |
| **Farmer – Cost Management** (`/farmer/cost-management`) | ✅* | Verified earlier this session via real login: 24 expenses / 15 revenue / 2 loans / alert cards, "Estimated Tax ৳4,000". *See §3‑D re: hard‑refresh.* |
| **Farmer – Expense list / Revenue / Loans / Reports / Inventory** | ✅ | Reached from Cost Management; `test_farmer_panel.py` 35/35 |
| **Disease Detection** (`/farmer/disease-detection`) | ✅ | Disclaimer banner, upload dropzone (camera/gallery/Choose File), "Recent Cases", paywall banner "Free scans used up → View Plans", "Find Vet Nearby". **ListTile ink‑splash assertion FIXED** (see §4) — console now clean |
| **Plans / Subscription** (`/subscription`) | ✅ | "Featherflow Plans", Monthly/Yearly toggle, Free/Pro cards, feature checklist, "Current Plan". Back arrow present. **`_FAQSection` ListTile assertion FIXED.** Back button = `canPop() ? pop() : go('/farmer')` |
| **Disease Detection → Plans → Back** (spec #2) | ✅ | "View Plans" = `context.push('/subscription')`; Plans back = `context.pop()` (falls back to `/farmer`). Both screens render; push/pop pairing returns to the entry point |
| **Community – Feed** (`/community`) | ✅* | Latest/Trending/Following tabs, "All Posts" filter, "Post" FAB. Feed content (posts/comments/reactions from the seed) confirmed via real‑login session earlier + `test_community.py` 56/56. *See §3‑D.* |
| **Community – Create post** (`/community/create`) | ✅ | Post/Question/Poll tabs, body field, **Topic dropdown** (white menu, dark text — the theming fix), "Add hashtag", "Add photos, video, or PDF", "Post anonymously" |
| **Community – Topic dropdown / sort dropdown** | ✅ | White background, `AppColors.primary` text, visible chevrons (was the green‑on‑green bug) |
| **Community – Image upload** (spec #1) | ✅ | **Verified from the real Flutter web app**, not just API: `POST /api/community/upload/ 201 Created` ×2 with the CORS `OPTIONS 200` preflight, driven through the actual file‑picker → `DOM.setFileInputFiles`. Content‑type fix (`MediaType` from `http_parser`) + backend magic‑byte validation both exercised |
| **Community – Image viewer** | ✅ | `_openViewer` dialog: `PageView` of `InteractiveViewer(Image.network)`, `1/N` badge, close button; `.gif` added to `isImage` |
| **Community – Comments / reactions** | ✅ | Seed adds 24 comments + 12 reactions on the demo account's posts; `test_community.py` covers threads/reactions |
| **Pharmacy** (`/pharmacy`) | ✅ | "GreenVet Pharmacy Ltd." header, stat cards (Total Products / Low Stock / Out of Stock / Expiring Soon — all 0, **genuine empty state, no endless spinner** — spec #5), bottom nav Home/Catalogue/Inventory/Orders/Suppliers |
| **Pharmacy – Browse / Catalogue / Orders / Analytics** | ✅ | Orders shows "No orders here"; analytics loads. The 403s seen in an earlier sweep were a test‑harness stale‑token artifact (navigating a pharmacy user through `/farmer`) — direct API with a fresh token returns 200 across the board |
| **Doctor** (`/doctor`) | ✅ | "Dr. Samira Rahman ✓ Verified · Avian Medicine", stat cards (6 clients / 2 today / 2 active / 1 completed / 1 urgent / 4 unread), Today's Schedule with real appointments (Fatema Begum ৳400 · Kamal Hossain URGENT ৳500), Pending Follow‑Ups. `test_doctor_flow.py` 58/58 |
| **Delivery** (`/delivery`) | ⚠️ | Renders correctly on a **fresh sign‑in** (Today's Overview, Attendance, "No active delivery", Quick Actions, ★4.7). **Hangs on a spinner after a page refresh / app reopen** — see §3‑A |
| **Research / News** (`/research`, `/research/papers`, `/research/analytics`, `/paper-portal`, +10 sub‑routes) | ✅ | "My Papers" filter chips + "No papers yet / Submit Paper" empty state, "New Paper" FAB. Earlier full sweep of all 13 research routes was clean. `test_articles_feed.py` 28/28 |
| **Tax – Summary** (`/farmer/tax`) | ✅ | "Estimated tax for 2026 (FY 2024‑25) ৳4,000", "Paid so far ৳15,300 / Still pending ৳0", Estimate/My details/Payments cards, "This year, tax by type" (Income ৳0 · Land ৳4,800 paid · Vehicle ৳4,000 est / ৳10,500 paid), disclaimer |
| **Tax – Estimate / Calculator** (`/farmer/tax/calculator`) | ✅* | Via the in‑app "Estimate" button: "Estimated tax for the year ৳4,000", Income/Land/Vehicle breakdown, **revenue field pre‑filled ৳291,760** from cost‑management, income‑type chips, "First BDT 200,000 … tax‑free", "Land & vehicles", "How this was worked out" expander. **ListTile assertion in `_breakdown()` FIXED.** *Deep‑link to this URL hangs — see §3‑D.* |
| **Tax – My details / Profile** (`/farmer/tax/profile`) | ✅ | Income type "Agricultural (farming)", exemptions/rebate fields, "65 or older" toggle, Land area 62 Katha / Agricultural / Rural, District "Mymensingh" / Upazila "Trishal", Vehicles list (1× Motorcycle, 1× Pickup), Save |
| **Tax – Payments** (`/farmer/tax/payments`) | ✅ | 5 seeded payments render cleanly: Land ৳4,800 (CH‑LAND‑2400118), Vehicle ৳9,000 / ৳1,500, Other ৳1,200, Income ৳0 (NBR‑AGRI‑EXEMPT), each with date + reference + note; "Record payment" FAB |
| **Admin panels** (`/admin` + profile/finance/support/team/audit) | ✅ | Left sidebar, "No urgent items — everything is up to date", Overview / Pending Tasks / Recent Activity empty states, "My Profile", "Sign Out". Readable under the light theme. **`admin_profile` `_SecurityTile` / `_NotifTile` ListTile assertions FIXED.** `test_admin_panel.py` 65/65 |

\* = the screen itself is confirmed good (via real‑login session earlier this pass and/or in‑app
navigation now); the only open question is the deep‑link/hard‑refresh path in §3‑D.

---

## 3. Remaining issues

### A. Delivery dashboard hangs on a spinner after a page refresh / app reopen — **MEDIUM**

- **Where:** `/delivery` (delivery/rider role).
- **Confirmed behaviour:**
  - **Fresh in‑app sign‑in → works.** Signing in as `rider.arif@example.com` /
    `FeatherflowDemo@2026` and landing on `/delivery` renders correctly: "Today's Overview"
    (0 New Requests / 0 Completed / ৳0 Earnings), "Attendance Status: not marked", "No active
    delivery" empty state, Quick Actions (Attendance / Performance / Support). ★4.7 in the bar.
  - **Restored session (refresh the page while on `/delivery`, or reopen the app already
    logged in) → the body never leaves `CircularProgressIndicator`.** No console exception, and
    **no `/api/delivery/*` request is ever sent**.
- **Root cause (from code):** `DeliveryDashboardScreen.initState()` does **not** call
  `DeliverySession.instance.refresh()` (contrast `DoctorDashboardScreen`, which calls
  `DoctorSession.instance.refresh()` in `initState`). Delivery data loading depends entirely on
  `DeliverySession._()`'s `AuthService` listener, which only fires on an in‑session
  `saveSession()` (i.e. an actual login). When the session is restored from storage on boot, the
  listener never fires, `_loadRegisteredProfile()` → `refresh()` is never invoked, and the
  dashboard's spinner condition (`session.isLoading && …`) — actually the *absence* of any load —
  leaves it stuck. All five delivery endpoints return **200 in <70 ms** directly, so the
  backend is fine.
- **Reproduction:**
  1. Sign in as `rider.arif@example.com` / `FeatherflowDemo@2026`.
  2. On `/delivery`, press browser refresh (or close the tab and reopen the app).
  3. Body spins indefinitely; pull‑to‑refresh does *not* recover it (guard `if (isLoading) return;`).
- **Not a regression** from the reviewed changes (theme / community upload / subscription nav /
  demo data don't touch delivery). Pre‑existing.
- **Suggested fix (1 line):** add `DeliverySession.instance.refresh();` to
  `DeliveryDashboardScreen.initState()`, mirroring the doctor dashboard.

### B. `৳` (BDT taka) glyph renders as tofu until fonts finish loading — **LOW** (cosmetic, pre‑existing)

- Visible on the farmer dashboard ("⌷0"), Plans "Free ⌷0", and briefly on Tax cards.
- The `MaterialIcons`/font bundle loads a beat after first paint; the Bengali taka sign has no
  glyph in the fallback system font. Resolves once fonts are in. Consider bundling a font with
  `৳` coverage (e.g. Noto Sans Bengali) or rendering `BDT` as a text prefix.

### C. `flutter analyze` — 7 pre‑existing admin warnings — **LOW** (pre‑existing, not in scope)

- `admin_finance_screen.dart` `_kPayments`, `admin_support_screen.dart` `_kTickets`/`_kFlags`,
  `admin_team_screen.dart` `_kStaff`/`_kAccessLog` — unused mock‑data constants.
- `admin_support_screen.dart:110` and `admin_team_screen.dart:187` — `use_build_context_synchronously`.
- None introduced by this work; listed for completeness.

### D. Hard‑refresh / direct‑URL navigation to some nested routes stalls on a transition/spinner — **MEDIUM** (partly harness‑suspected)

- **Affected in testing:** `/farmer/tax/calculator`, `/farmer/cost-management`, `/community`
  when reached by a **full page load at that URL** (browser refresh, pasted link, or CDP
  `Page.navigate` to the hash route). The page‑slide transition freezes ~90 % in with the
  previous screen still visible behind, and/or the screen's own loading spinner never clears.
- **Not reproducible via in‑app navigation:** the Tax calculator opens correctly every time from
  the Tax screen's "Estimate" button (fully rendered, revenue pre‑filled). Cost Management and
  the Community feed were both confirmed working earlier this session through a real login +
  normal navigation.
- **Likely contributors:** (1) the documented gap where a session that isn't established by an
  in‑session `AuthService.saveSession()` doesn't kick every data service/poller; (2) the
  `GoRouter(refreshListenable: UserUpdatesService.instance)` re‑evaluating `_redirect` (which is
  `async`) on every poll tick, which can rebuild the route subtree while a screen's `initState`
  load future is still in flight (`if (!mounted) return;` then leaves `_loading == true`).
  Screens that do a **single** await in `initState` (`/farmer/tax`, `/farmer/tax/payments`,
  `/farmer/tax/profile`, doctor, pharmacy, research) survive this; screens doing **two**
  sequential awaits or relying on a shared service (`tax/calculator`, cost‑management,
  community, delivery) are the ones that stick.
- **Reproduction (tax calculator, most reliable):**
  1. Sign in as `andrew26499@gmail.com` / `FeatherflowDemo@2026` (phone `01713018156`).
  2. In the address bar, go straight to `…/#/farmer/tax/calculator` (or refresh while on it).
  3. Spinner under the "Tax estimate" app bar never resolves, even though
     `GET /api/farmers/tax/profile/` and `/summary/` both return 200.
  4. Compare: from `/farmer/tax`, tap **Estimate** → screen loads normally.
- **Impact:** users who bookmark/refresh a deep link land on a stuck screen; the back button or
  a fresh in‑app navigation recovers. Worth a follow‑up (make the `initState` loaders
  `mounted`‑safe and idempotent, or gate `_redirect` so poll‑tick refreshes don't rebuild the
  subtree).
- **Please confirm** how much of D reproduces in a plain browser vs. only under CDP automation.

### E. Wide‑viewport cosmetic sparseness — **LOW** (pre‑existing)

- On desktop widths the pharmacy dashboard, feed‑management and research analytics stat‑card
  grids are tall and sparsely filled; admin "Joined" column can show an empty date; the expense
  list title reads "All expenses expenses"; admin audit filter dropdowns can overlap the app bar.
  All cosmetic, all pre‑existing.

---

## 4. Fixes applied during this pass (uncommitted, in working tree)

**`lib/features/farmer/presentation/screens/tax_calculation_screen.dart` — `_breakdown()`**
Converted the `Container(decoration: BoxDecoration(color: …))` wrapping the "How this was
worked out" `ExpansionTile` to a `Material(type: MaterialType.card, shape: RoundedRectangleBorder(…))`.
This clears the debug‑only assertion *"ListTile background color or ink splashes may be invisible"*
that fired on the Tax‑estimate screen — the same pattern already fixed this session on
disease‑detection (`_RecentCasesSection`), subscription (`_FAQSection`) and
admin‑profile (`_SecurityTile`/`_NotifTile`). Debug‑only (stripped in `--release`); screens
rendered fine regardless. `flutter analyze` clean, `flutter test` 62/62, release build OK
after the change.

---

## 5. Spec verifications (the 6 explicit asks)

| # | Ask | Result |
|---|---|---|
| 1 | Community image upload from the real Flutter web app | ✅ `POST /api/community/upload/ 201` ×2 via the actual picker + `OPTIONS 200` preflight |
| 2 | Disease Detection → Plans → Back from every entry point | ✅ `push('/subscription')` + `pop()`/`go('/farmer')` fallback; both screens render; assertion cleared |
| 3 | Login → Forgot password completes | ✅ Screen renders; full send‑code → verify → reset confirmed via API |
| 4 | Account `01713018156` shows seeded data | ✅ Dashboard ৳291,760 · Tax summary ৳4,000 / ৳15,300 paid · 5 tax payments · Tax profile (62 Katha, Mymensingh/Trishal, 2 vehicles) · Disease "Recent Cases" (6 scans) · community posts/comments/reactions |
| 5 | Pharmacy Browse: medicines **or** a clear empty state, not an endless spinner | ✅ Clear "0 Total Products" zero‑state; Orders "No orders here"; no spinner |
| 6 | All role panels readable under the new light theme | ✅ Auth, Farmer, Doctor, Pharmacy, Research, Admin all readable with proper empty states. **Delivery renders its chrome but see §3‑A.** |

---

## 6. Bottom line

The theme conversion, community upload, subscription navigation and demo‑data changes are
**solid**: every automated gate is green, the four `ListTile` ink‑splash assertions are cleared,
the taka‑sign dropdowns are fixed, the seeded demo account shows rich realistic data across
every module, and community image upload works end‑to‑end from the real web app.

Two pre‑existing robustness issues surfaced, both around **session‑restore / hard‑refresh** (not
fresh login) and neither introduced by the reviewed changes:
* **§3‑A** — Delivery dashboard hangs on refresh/reopen (works on fresh sign‑in). Root cause
  identified, 1‑line fix proposed.
* **§3‑D** — deep‑link / hard‑refresh into `tax/calculator`, `cost-management`, `community` can
  stall on a frozen transition/spinner. All three work via normal in‑app navigation after
  sign‑in. Worth a follow‑up to make the `initState` loaders `mounted`‑safe/idempotent and to
  stop poll‑tick router refreshes from rebuilding an in‑flight route subtree.

Recommend confirming §3‑D's exact blast radius in a plain browser (some of it may be amplified
by the CDP automation harness) and applying the §3‑A one‑liner.

**Nothing was committed.**
