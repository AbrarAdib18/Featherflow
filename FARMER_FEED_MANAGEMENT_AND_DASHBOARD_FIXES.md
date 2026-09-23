# Farmer Feed Management & Dashboard Fixes

**Date:** 2026-09-23
**Scope:** Fix the feed-stock-doesn't-update bug, remove the Supplier feature
from farmer-facing Feed Management, rename/improve "Add Feed," and correct
two dashboard text issues (farm-name contrast, "(from profile)" suffix).
**Nothing was committed.** All changes described below are in the working
tree only.

---

## 1. Root cause of the stock-update bug

Two independent investigations converged on the same finding: **the write
and read paths already agree on where "current stock" lives** — both are
the exact same `FeedStock.quantity_available` row, read live everywhere
(Feed Management, the cost dashboard's low-stock alerts, everywhere). There
is no stale cache, no second disagreeing table, no missing refetch (the
Flutter form already correctly calls `_load()` after a successful POST).

**The actual bug:** `backend/feed/views.py`'s POST handler looked up the
feed via `FeedType.objects.get_or_create(name=, brand=, unit=)` — an
**exact string match**. Any difference between how a farmer typed the same
feed this time vs. last time (different case, extra whitespace, an empty
vs. non-empty brand) failed that match and silently created a **brand-new
`FeedType` and `FeedStock` row starting at 0**, instead of incrementing the
existing one. The write genuinely succeeded — a new row really was created
— but the row the farmer was looking at on screen never moved, which is
exactly "current stock does not update."

```text
Flutter Add Feed form → POST /api/farmers/feed/inventory/
  → FeedType.objects.get_or_create(name=EXACT, brand=EXACT, unit=EXACT)  ← bug
  → FeedStock.objects.get_or_create(farm, feed_type)  → += quantity → save()
  → response
  → Flutter _load() (already correct, already refetches)
  → GET /api/farmers/feed/inventory/ → same FeedStock table (already correct)
  → displayed current-stock value — unchanged, because the increment landed
    on a DIFFERENT row than the one being displayed
```

Also found along the way, all fixed (§2):
- No `transaction.atomic()` / `select_for_update()` anywhere in the
  purchase or consumption write paths — a real race-condition risk on
  concurrent submissions.
- No DB-level protection against negative stock (only a runtime clamp in
  the consumption view).
- No idempotency/duplicate-submit protection on the Add Feed form (the
  Save button had no busy-state guard at all).
- "Feed History" wasn't real purchase history — it re-labeled the current
  stock rows as if they were purchase entries (there was no purchase ledger
  model at all; `FeedPurchase = None` is explicitly nulled out in
  `feed/models.py` with a comment explaining the concept doesn't exist in
  the schema).
- Deleting a consumption log entry didn't restore the stock it had drawn
  down — cancelling a mistaken entry left "current stock" permanently wrong.
- A second, differently-routed stock-delete endpoint
  (`DELETE /api/farmers/feed/inventory/<id>/`, separate from
  `DELETE /api/feed/stock/`) existed with no audit logging.

---

## 2. Backend fixes

### 2.1 The actual fix — case/whitespace-insensitive feed matching (`backend/feed/views.py`)

```python
feed_type = FeedType.objects.filter(
    name__iexact=name, brand__iexact=brand, unit=unit,
).first()
if feed_type is None:
    feed_type = FeedType.objects.create(name=name, brand=brand, unit=unit)
```

`unit` stays an exact match deliberately — kg and bag are genuinely
different units and no conversion is implemented anywhere in this codebase,
so buying "the same feed" in a different unit intentionally remains a
separate stock line (verified by a dedicated test — see §5).

### 2.2 Atomicity + row locking

The whole purchase (`feed/views.py`), the consumption log-and-decrement
(`farmers/feed_views.py`), both stock-delete endpoints, and the
consumption-delete-and-restore path are now wrapped in `transaction.atomic()`
with `select_for_update()` on the `FeedStock` row being modified — two
concurrent requests against the same stock line can no longer race and lose
an update.

### 2.3 Negative-stock protection (defense in depth)

`feed_stock_integrity_extension.sql` adds a DB-level
`CHECK (quantity_available >= 0)` on `feed_stock`, on top of the existing
application-level `max(Decimal('0'), ...)` clamp in the consumption view.
Applied to the live dev database as part of this pass.

### 2.4 Real stock-history / audit trail — new `FeedStockMovement` model

New table `feed_stock_movements` (same file), one immutable row per
purchase/consumption/adjustment/removal event: `quantity_delta`,
`quantity_after` (a snapshot, for audit), `unit_cost`, `note`, `created_by`,
`created_at`. `feed_stock.quantity_available` remains the **one** source of
truth for current stock — this table is never read to compute it, only to
show genuine history. It replaces the old fake "history" (current-stock
rows relabeled as purchases). Every stock-changing action now logs one:
purchase, consumption, cancelling a consumption entry (an `adjustment` that
restores stock), and removing a stock line entirely (a `removal`).

### 2.5 Consumption-delete now restores the correct amount

A consumption request can exceed what's on hand and gets clamped at 0 (a
farmer logging "fed 500kg" against a stock line that only had 300kg left).
The linked `FeedStockMovement` records what was **actually** drawn down
(300, not 500). Deleting that consumption entry restores based on that
recorded movement, not the raw requested quantity — otherwise cancelling a
mistaken over-large entry would over-restore stock. *(Caught by this pass's
own test suite — an early version of this fix restored the raw requested
amount and over-credited stock; fixed before it shipped.)*

### 2.6 Idempotent/duplicate-submit protection

Interpreted deliberately as **client-side duplicate-tap prevention**
(disable the Save button while the request is in flight — see §3), not a
server-side request-dedup mechanism. A farmer legitimately can buy the same
feed twice in a row (two real deliveries); a backend idempotency key would
risk silently dropping a genuine second purchase. What the backend
guarantees instead is that concurrent/repeated requests are individually
**correct** (§2.2's atomicity + locking) — each real request is applied
exactly once, never lost, never double-applied by a race.

### 2.7 Validation added

`quantity` must be a positive number, `cost_per_unit` must be non-negative,
both must parse as numbers — all return `400` with a clear message
(previously a non-numeric or negative/zero quantity/cost was passed through
uncaught, or produced a generic exception-string 400).

---

## 3. Frontend fixes (`lib/features/farmer/presentation/screens/feed_management_screen.dart`)

### 3.1 "Add Feed" (renamed, rebuilt as a proper dialog widget)

- Renamed everywhere: the button and the dialog title now both say
  **"Add Feed"** (was "Add Feed Purchase"). Accounting/history behavior is
  unchanged beyond what §2 required to actually fix stock updates.
- Converted from an inline `showDialog` + `StatefulBuilder` closure into a
  dedicated `_AddFeedDialog` `StatefulWidget` — the same pattern this
  codebase already uses for the farmer cost-tracking dialogs
  (`cost_dialogs.dart`), so it can own real busy/validation/error state
  instead of popping immediately and finding out about failure after the
  dialog is already gone.
- **Fields:** Feed name\*, Brand (optional), Quantity\* + Unit\* (side by
  side on wide dialogs, stacked on narrow ones via `LayoutBuilder`), Cost
  per unit\*, Notes (optional — new; wired to the `FeedStockMovement.note`
  audit field added in §2.4, so it's a real, persisted field, not a UI
  element that silently discards what's typed). Fields are separated by
  consistent `AppSpacing.sm` gaps (was zero gap — the six fields ran
  directly into each other before).
  - **"Purchase date" and "Expiry date" were deliberately not added** —
    neither concept exists anywhere in the feed data model
    (`FeedStock`/`FeedType` have no such columns), and the task's own field
    list qualified expiry as "if present." Inventing UI fields that don't
    persist anywhere would be actively misleading, not a fix. Flagged here
    per the report requirement rather than silently dropped.
  - **Supplier name was removed** (see §4) — confirmed with the requester
    before implementing.
- **Validation:** required-field and numeric (`quantity > 0`,
  `cost_per_unit >= 0`) validators via a real `Form`/`TextFormField` setup,
  matching the backend's own validation exactly (§2.7) so a client-side
  rejection and a server-side rejection never disagree.
- **Duplicate-submit protection:** a `_busy` flag disables every field and
  both dialog buttons during the in-flight request and swaps the Save
  button for a spinner — a second tap during submission is now a no-op
  instead of firing a second request.
- **Error state:** a failed submission keeps the dialog open (previously it
  had already closed before the request even started) and shows the error
  inline, so the farmer doesn't lose what they typed and can immediately
  retry.
- **Responsive width:** `ConstrainedBox(maxWidth: 420)` — previously
  unconstrained, relying entirely on `AlertDialog`'s default sizing.

### 3.2 Feed History table

Rebuilt from the new real `FeedStockMovement` data (§2.4). The **Supplier**
column is gone (§4); replaced with an **Event** column — a small colored
badge (Purchase / Used / Removed / Adjusted) using the app's existing
semantic colors (`AppColors.secondary` for additions, `AppColors.error` for
reductions), so a farmer can now actually see what each entry was, not just
a re-listing of current stock dressed up as "history."

### 3.3 A pre-existing, unrelated bug found and given a minimal safety fix

The "Change status" menu on each Current Stock row (Good/Low/Out) calls
`_setStockStatus`, which `PATCH`es a status the backend has never accepted
— `feed/views.py`'s `stock_detail` PATCH branch always returns `400`
("Stock status is calculated from quantity and is not stored"), and
`_setStockStatus` had **no error handling at all**, so selecting any of
those menu options threw an unhandled exception. This is unrelated to the
reported stock-update bug and the menu options don't conceptually make
sense to keep now that status is correctly computed live from quantity
(exactly what the "single source of truth" requirement in this task asks
for) — redesigning or removing that menu is out of this pass's scope, but
leaving an unhandled-exception trap in place isn't a defensible "don't
touch it," so a minimal `try/catch` + SnackBar was added, matching every
other error-handling call in this file. Documented here rather than fixed
further, per "targeted fixes... do not redesign unrelated features."

---

## 4. Supplier removed from farmer Feed Management

Per your explicit confirmation, removed everywhere in the farmer-facing UI:

- The `_SupplierSection` card (header, "No supplier recorded" /
  supplier-name rows, "Suppliers used: N", the "Order Now" button) —
  deleted entirely, along with its `_SupplierInfoRow` helper.
- The "Place Supplier Order" dialog (`_orderFeed()`) — deleted. (It was
  already non-functional: the backend's `POST /api/feed/orders/` has always
  returned `501 Not Implemented` — "Feed orders are not part of the current
  PostgreSQL schema" — so this button never actually worked; removing it
  removes a dead end, not a working feature.)
- The "Supplier name" field in the Add Feed form — removed (§3.1); the
  backend POST handler no longer sets `stock.supplier_name` on new
  purchases (existing historical values on old rows are left alone, not
  force-cleared).
- The "Supplier" column in Feed History — removed (§3.2), replaced with a
  genuinely useful Event-type badge.

**No route change was needed** — there is no standalone farmer-facing
supplier route or screen; everything above was inline widgets/dialogs
inside `feed_management_screen.dart`. No dead link is created.

**Confirmed untouched, as required:** Feed Admin's `FeedCompany`/client
management (`lib/features/admin/presentation/screens/admin_feed_clients_screen.dart`
and friends) is a completely separate system serving the marketplace
catalogue — not read, not modified. The Feed Marketplace entry point inside
Feed Management (`_MarketplaceQuickAccess`, linking to
`/farmer/feed-management/marketplace`) is unaffected and still the sole
feed-ordering entry point, as its own existing code comment already states.

---

## 5. Farmer dashboard text corrections (`lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart`)

### Farm name contrast

The farm name (and its adjacent icon, same row, same problem) used
`AppColors.onSecondaryContainer` — a near-black green — on the welcome
card's dark-green gradient background. Illegible, effectively green-on-green.
Changed both to `AppColors.navigationForegroundColor` (white; the token this
codebase already uses everywhere else for text/icons on a green nav
surface, per `navigation_contrast_test.dart` and its usage across every
other role's theme file). Visually identical to the plain `Colors.white`
already used by the greeting text directly above it and the bird-count text
directly below it in the same card — now all three lines are consistently
white. Rest of the card's design (layout, gradient, icons, verified badge)
is unchanged.

### "(from profile)" suffix

Removed the visible `" (from profile)"` / `" (প্রোফাইল)"` suffix from the
bird-count line. The underlying fallback logic it was describing (`'profile'`
source means no flock batches exist yet, so the count shown is the number
the farmer entered at signup rather than a live flock total) is completely
unchanged — the `birds` value, its computation, and the `birdsSource` prop
threading it through from `farm['total_birds_source']` are all untouched.
Only the now-dead local boolean (`selfReported`) that existed solely to
drive the removed suffix text was cleaned up; `flutter analyze` confirmed
this was the only thing that became unused.

---

## 6. Frontend consistency audit (focused, not a redesign)

Checked: Farmer Dashboard, Feed Management landing page, Add Feed dialog,
Current Stock / Feed History cards, Feed Marketplace entry point.

- **Green-on-green**: the farm-name bug (§5) was the only instance found in
  the areas audited; fixed.
- **Dark-on-light**: Feed Management's cards (Current Stock, Feed History,
  Feed Schedule) already use dark text (`Colors.black87`/`black54`) on white
  card backgrounds correctly — no changes needed.
- **Consistent cards/buttons/spacing**: the Add Feed dialog was the one
  clear outlier (zero inter-field spacing, no width constraint) — fixed
  (§3.1). Current Stock and Feed History already shared a consistent card/
  table style before this pass and still do (History's new Event badge
  reuses the same small-pill pattern `_StockRow`'s status chip already
  established, not a new visual language).
- **Loading/empty/error/retry**: Feed Management's top-level load already
  had all four states; the Add Feed dialog didn't (no busy/error state at
  all) — fixed (§3.1). The Current Stock and Feed History sections don't
  have their own independent empty-state messaging distinct from the
  parent screen's — this was already the case before this pass and wasn't
  reported as broken, left as-is per "targeted fixes only."
- **Overflow/clipping**: none found in the areas touched; the Add Feed
  dialog's new `ConstrainedBox` + `SingleChildScrollView` combination
  guards against overflow on both narrow and wide layouts.
- **Marketplace cards/cart/order views**: not modified, and confirmed
  unaffected — Feed Management's link into the marketplace is unchanged.

---

## 7. Tests

### Backend — new/updated, all passing

- **`backend/scripts/test_feed_stock_integrity.py`** (new, 29 checks) — the
  centerpiece: repeating a "purchase" with different casing/whitespace
  accumulates onto the *same* stock row (the actual bug, now fixed and
  regression-tested); a different unit stays a deliberately separate line;
  input validation (zero/negative quantity, negative cost, non-numeric);
  real per-event history (not the old fake redisplay); consumption reduces
  stock and clamps at 0; deleting a consumption entry restores exactly what
  was drawn down, not the raw requested amount; ownership isolation (a
  second farmer can't see, delete, or log consumption against another
  farmer's stock/flock); deleting a stock line logs a removal movement.
- **`backend/scripts/test_flock_feed_management.py`** — re-run, still
  17/17 (no regression from the `farmers/feed_views.py` consumption-path
  changes).
- **`backend/scripts/test_farmer_panel.py`** — re-run, still 39/39
  (broader farmer-panel regression, including feed consumption log/list —
  no regression).

### Flutter — new

- **`test/farmer_dashboard_and_feed_fixes_test.dart`** (new, 6 tests):
  farm-name text color is the nav-foreground token (not the old literal);
  no "(from profile)"/"(প্রোফাইল)" text anywhere on the dashboard while the
  rest of the bird-count line still renders; Feed Management still shows
  loading → error → Retry correctly (no crash) after the Add Feed/Supplier
  changes; Retry works; app bar title intact.

**A real limitation, stated plainly:** `FeedManagementScreen` (and its
`_AddFeedDialog`) require a live backend data fetch to reach their loaded
body — there is no injectable test client or `@visibleForTesting` seam on
this screen (unlike `DeliverySession`/`DoctorSession`, which are public
singletons built for this), and the dialog class is private to its file.
This pass could not add a widget test that directly exercises "Supplier UI
is absent" or "Add Feed dialog's fields/validation" through the real
widget tree — only the screen's loading/error/retry shell, which has no
such dependency, is directly testable. The backend test suite above
exercises every actual behavior the dialog triggers; the dialog's own
structure was verified by code review and `flutter analyze`, and manual
verification (§8) is the way to see it rendered. Adding a test seam to this
screen (mirroring `DeliverySession`'s pattern) would be a reasonable
follow-up if this screen gets touched again, but doing so here would have
gone beyond "targeted fixes."

---

## 8. Manual verification

**Not performed live** — this environment's headless-browser testing was
independently found in an earlier session to hit a Chromium-headless/
software-rendering limitation that prevents reliable visual screenshotting
of this Flutter web app. Combined with §7's noted constraint (this screen
needs a live backend + session to reach its real body), a genuine
click-through isn't reliable to perform from here. The backend suite (46
new/re-verified checks) directly exercises the actual stock-update logic;
the Flutter suite covers what's mechanically testable without a backend.
A real-browser pass is the natural next step:

1. Open Feed Management — confirm no Supplier card/section anywhere, and
   the Feed Marketplace quick-access cards are still there and still work.
2. Tap **Add Feed** — confirm the dialog title says "Add Feed," fields have
   visible gaps between them, the layout doesn't clip on a narrow window.
3. Try submitting with an empty required field — confirm inline validation
   errors appear, nothing is sent.
4. Add a valid feed purchase — confirm Current Stock updates immediately
   with the new total, and a new "Purchase" row appears in Feed History.
5. Add the *same* feed again, typed with different capitalization — confirm
   it adds to the same stock line (not a new row) — this is the actual bug
   fix.
6. Refresh the page, then log out and back in — confirm the stock figure is
   unchanged (persisted, not just an optimistic local update).
7. Log feed consumption against a flock — confirm stock decreases and a
   "Used" row appears in Feed History.
8. Double-tap **Add Feed**'s Save button quickly — confirm it doesn't submit
   twice (button should show a spinner and be unresponsive to the second
   tap).
9. On the Farmer Dashboard: confirm the farm name is white and readable on
   the green header, and the bird-count line reads "Total Birds Capacity"
   (or just the birds/batches line, depending on exact copy) with no
   "(from profile)" text, at both a wide and a narrow window width.

## 9. Remaining limitations

- Live/visual manual verification wasn't performed — see §8.
- No Flutter widget test directly exercises the Add Feed dialog's fields or
  the Supplier UI's absence — see §7's stated constraint.
- The Current Stock row's "Change status" menu (Good/Low/Out) calls an
  endpoint that has never accepted a manual status override; given a
  minimal safety fix (no more unhandled exception) but not redesigned or
  removed — see §3.3.
- "Purchase date" and "Expiry date" fields were not added to Add Feed since
  neither exists in the underlying data model — see §3.1.
- The distance-bonus-style nuance doesn't apply here, but similarly: the
  Supplier field was removed from the payload/API usage but the
  `FeedStock.supplier_name` column itself was left in the schema
  (historical data preserved, no destructive migration) — purely dormant
  going forward.

## 10. Confirmation

**Nothing was committed.** All changes are in the working tree only —
verified via `git status` before finishing; no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
