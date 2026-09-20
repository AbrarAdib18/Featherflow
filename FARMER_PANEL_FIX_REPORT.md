# Farmer Panel Fix Report

Four-phase pass: (1) backend unblocking + seed, (2) Flutter nav/dead-tap/booking/chat/labour
fixes, (3) Cost Management charts, (4) visual polish, tests, manual verification, reports.
**Nothing has been committed at any point** — confirmed by `git status`/`git log` before writing
this report (see bottom).

---

## Root causes

| Symptom reported | Root cause | Fix |
|---|---|---|
| Farmer panel "looks like a demo" | Not mock data — dead taps (no `onTap`) on real-data cards, plus zero-defaults masking loading/error states | Every dead tap wired to a real destination; explicit loading spinner + `ErrorStateView` (Phase 2) |
| Can't book a consultation | `booking.py` hard-required a published `AvailabilitySlot` and an online doctor | Availability made informational-only; date/time made optional end to end (Phase 1) |
| Completed consultation has no chat | `Conversation` rows only created by the accept workflow; seeded/legacy consultations skip it | `_conversation_for` resolves/creates a conversation for accepted/in_progress/completed (Phase 1) |
| Can't open vet from a consultation | Consultation rows never exposed `doctor_id`/`doctor_profile_id` | Both added to the row serializer (Phase 1) |
| Paid workers show unpaid | API returned only `salary_due`/`paid_this_month`; no explicit state; **no labour→expense mirroring existed at all** | `payment_status`/`earned_this_month`/`last_payment_date` added; `_mirror_labour_expense` added, keyed on `source_intent_id` (Phase 1) |
| Due tax always blank | Hardcoded `None` in two places | Real `tax.views.pending_tax()` (Phase 1) |
| Two nav bars on My Consultations | Two stacked `TabBar`s (Find Vet's + the embedded consultations screen's own) | Flattened to one `TabBar`, three tabs (Phase 2) |
| Cost Management "feels empty" | No charts existed at all | 4 fl_chart-based charts, SQL-aggregated, zero-filled trend (Phase 3) |
| (Found during Phase 4 testing) Seeding a second demo farmer crashed | `random.Random(1713018156)` hardcoded regardless of phone → every farmer picked the identical doctor+date for a given plan slot, colliding on a real global unique index | RNG seeded from the phone number; doctor/day picks shifted by a per-farmer hash; remaining rare collision caught via a savepoint and skipped with a warning, not a crash (Phase 4) |

---

## Files changed

**Backend** (Phase 1 unless noted): `consultations/booking.py`, `serializers.py`, `views.py`,
`workflow.py`, `payments.py`; `doctor/views.py`; `farmers/farm_views.py`, `dashboard_views.py`,
`cost_views.py` (charts added in Phase 3); `feed/models.py`, `feed_catalogue/models.py`;
`expenses/models.py`; `tax/views.py`; `workers/views.py`; `billing/services.py`;
`users/management/commands/seed_demo_data_for_phone.py` (extended Phase 1, RNG-collision fix
Phase 4). New: `farms/constants.py`, `farmer_panel_integrity_extension.sql`.

**Flutter**: `find_vet_screen.dart`, `farmer_consultations_screen.dart` (Phase 2 nav flatten);
`farmer_dashboard_screen.dart`, `cost_management_screen.dart` (Phase 2 dead taps, Phase 3
charts+custom range, Phase 4 back-button/currency); `vet_booking_dialog.dart`,
`vet_detail_dialog.dart` (Phase 2 dropdown/optional-time, Phase 4 image-error handling +
currency); `discover_vets_tab.dart` (Phase 4 explicit location states); `labor_management_screen.dart`,
`labour_payment_flow_screens.dart`, `labour_payment_models.dart` (Phase 2 status chips, Phase 4
polish); `feed_management_screen.dart`, `farmer_profile_screen.dart` (Phase 4 polish);
`app_router.dart` (Phase 2 `/chats` route). New: `lib/features/farmer/presentation/widgets/cost_charts.dart`,
`lib/core/format/currency.dart`.

**Tests**: new backend — `test_consultation_chat_access.py`, `test_cost_dashboard_charts.py`,
`test_dashboard_integrity_and_seed_idempotency.py`; extended — `test_consultation_booking_rules.py`
(19→29), `test_labour_payment.py` (18→27), `test_farmer_panel.py` (due-tax assertion fixed).
New Flutter — `farmer_bottom_nav_test.dart`, `cost_charts_test.dart`, `discover_vets_location_test.dart`,
`farmer_dashboard_navigation_test.dart`; extended — `find_vet_screen_test.dart` (rewritten for the
flattened TabBar), `navigation_contrast_test.dart` (period-selector regression lock).

## Migrations

`farmer_panel_integrity_extension.sql` (Phase 1, idempotent, applied and verified against the
live DB): `consultations.appointment_date`/`appointment_time` made nullable; `expenses.source_intent_id`
column + partial unique index added; `hatchery` flocks migrated to `other` and the bird-type CHECK
narrowed to the canonical 5-value set. No Django schema migrations needed (all affected models are
`managed=False`). `manage.py migrate --check` clean throughout.

## Seed counts

`seed_demo_data_for_phone --phone 01713018156 --reset`: 2 sheds, 2 flocks, 24 expenses, 15 revenue,
2 loans, 3 feed stock, 3 workers, 11 notifications, 12 posts, 3 pharmacy orders, 13 consultations
(all 8 statuses), 5 tax payments, 24 comments, 13 reactions, 8 follows, 15 bookmarks, 6 disease
scans, 18 chat messages, 1 labour payment (mirrored expense), 2 local images. Re-running (no
`--reset`) adds nothing — verified both manually and by `test_dashboard_integrity_and_seed_idempotency.py`
running the command three times in a row against a dedicated throwaway phone number.

## Test results

| Suite | Checks | Result |
|---|---|---|
| Backend (13 live-DB scripts) | 456 | 456 passed |
| Flutter (`flutter test`) | 135 | 135 passed |
| `flutter analyze` | — | clean (6 pre-existing infos, `farmer_feed_marketplace_screen.dart`, untouched) |
| `flutter build web --release` | — | succeeds |
| `manage.py check` / `migrate --check` | — | clean |

## Manual verification — what was and wasn't done

**This environment has no browser-automation tool** (no Playwright/chromium-cli registered, and
`WebFetch` cannot reach `localhost`). I did not click through the running app myself at any
point in this engagement. What "manual verification" means here is:

- The real backend (Django ASGI, `127.0.0.1:8000`) and the real Flutter app (Chrome, pointed at
  it) are both running right now, with the seeded farmer `01713018156` live in the database.
- I verified data correctness by calling the actual running API directly (not through the UI) —
  e.g. confirming `charts.monthly` for the seeded farmer returns 6 real months with correct
  revenue/expense figures, confirming a fresh farmer gets zero-filled (not empty) charts,
  confirming the custom date-range filter isolates the right records.
- Every UI *behavior* claim (nav bar count, dropdown values, disabled states, chat resolution,
  empty/error states) is backed by an automated Flutter widget test that pumps the real widget
  and asserts on the real rendered tree — not by me looking at a screenshot.
- I did **not** verify: visual appearance (colors, spacing, alignment as rendered pixels),
  Google Maps route opening in an actual browser tab, or the full click-through sequence listed
  in items 1–19 of the Phase 4C request. **Those require a human (or a browser-automation tool
  this session doesn't have) to actually drive the app.**

The app is up and ready for that walkthrough now: backend at `http://127.0.0.1:8000`, Flutter at
`http://127.0.0.1:5000` in Chrome, sign in as `+8801713018156` / `FeatherflowDemo@2026`.

## Remaining limitations

- Booking-dialog dropdown/checkbox interaction, populated labour-payment chips, and a populated
  chat thread cannot be exercised as Flutter widget tests without a real authenticated session —
  every existing test file in this project (before and after this pass) only exercises the
  no-session/error-retry path for authenticated screens; extending that would mean introducing a
  live-backend-authenticated test pattern with no precedent here. Covered instead by live-DB
  backend tests.
- `category_comparison`'s Feed/Labor/Medicines chart always shows all three even at zero, by
  design (stable comparison axis) — flagging in case that's not the intended UX.
- The pre-checkout method-selection step in the labour payment flow (`_continue` in
  `labour_payment_flow_screens.dart`) still retries atomically on failure rather than per-intent;
  left as-is since it's before any money moves and safely idempotent to retry (the actual
  confirm/cancel step, where money settles, was fixed to report per-intent outcomes in Phase 2).
- Two navigation contrast findings from the Phase 4A audit were investigated and found to be
  **correct as originally written**, not bugs: `Colors.black` text on the Cost Management period
  selector's `AppColors.secondary` fill, and on the Feed Management "Add Feed Purchase" button.
  `AppColors.secondary` is a bright accent green (luminance ≈0.35), not the dark navigation
  green the "white text on green" rule is about — white text there only reaches ~2.6:1 contrast
  vs. black's ~8:1. I initially "fixed" both to white based on the audit's pattern-match, then
  caught and reverted the regression via the new contrast test in `navigation_contrast_test.dart`,
  which now locks in the correct pairing.
- A real, if less severe, cross-farmer collision risk remains in `seed_farmer_demo_data.py`'s own
  `_seed_consultations` (used by the base farmer seeder) — it still uses `doctors[index % len(doctors)]`
  with no per-farmer jitter. Not fixed, since it's a separate seed command from the one this pass's
  idempotency test exercises; flagging for awareness.

## Confirmation

`git status` and `git log -1` were checked immediately before writing this report: `HEAD` is
unchanged from before this engagement began, and every file listed above is a working-tree
modification, not a commit. **Nothing has been committed.**
