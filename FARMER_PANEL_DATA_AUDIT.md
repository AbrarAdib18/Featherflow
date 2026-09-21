# Farmer Panel — Data Integrity Audit

Produced during the four-phase farmer-panel fix pass (backend unblocking → Flutter fixes →
Cost Management charts → visual polish/tests/reports). Maps every farmer-visible value to its
endpoint, backend service, database table, whether it opens something real, and its test status.
All citations are file:line against the working tree at the end of Phase 4 — nothing here is
assumed from documentation.

## Method

For each farmer screen: identify every displayed value → its API call → the Django view/serializer
that produces it → the underlying model/table → whether the value is SQL-real or a placeholder →
whether tapping it opens a real destination → what test (if any) exercises it.

**Headline finding, unchanged since Phase 1:** the farmer panel was never a demo-data mock. Every
value below traces to a real query. What read as "fake" was dead taps (no `onTap`) and
zero-defaults masking loading/error states — both fixed in Phase 2 — plus one genuinely hardcoded
value (`rating: 0` in labour performance, removed) and one hardcoded backend constant
(`due_tax: None`, replaced with a real computation in Phase 1).

---

## Dashboard (`farmer_dashboard_screen.dart`)

| Value | Endpoint | Backend | Table/model | Interactable | Test |
|---|---|---|---|---|---|
| Welcome name/farm/birds/batches | `GET /api/farmers/dashboard/` | `farmers/dashboard_views.py:dashboard` | `FarmerProfile`, `Farm`, `Flock` (via `farm_for`) | Yes → `/farmer/profile` (Phase 2 fix; was dead) | `test_data_integrity.py`, `farmer_dashboard_navigation_test.dart` |
| `total_birds_source` (profile vs flocks) | same | `dashboard_views.py:39-52` | flags self-reported vs live flock count | n/a (label only) | `test_data_integrity.py`, `test_dashboard_integrity_and_seed_idempotency.py` |
| Total Revenue / Expense / Net Profit / Cash Balance | same | `dashboard_views.py:78-82` | `Revenue`, `Expense`, `Payment`, `Loan` | Card → `/farmer/cost-management`; 3 mini-cells → expenses/reports (Phase 2 fix; were dead) | `farmer_dashboard_navigation_test.dart` |
| `due_tax` | same | `tax.views.pending_tax` (Phase 1) | `TaxProfile`, `TaxPayment` | Not directly tappable here (full detail via Cost Management → Tax) | `test_dashboard_integrity_and_seed_idempotency.py` |
| Alerts (bill due / loan due / feed low) | same | `farmers/cost_views.py:_alerts` | `Expense`, `Loan`+`LoanInstallment`, `FeedStock` | Yes, routed by kind (Phase 2 fix; were dead) | manual (backend data verified by `test_farmer_panel.py`) |
| Recent activity (expense/revenue rows) | same | `dashboard_views.py:56-65` | `Expense`, `Revenue` | Yes → expense/revenue list (Phase 2 fix; were dead) | `farmer_dashboard_navigation_test.dart` (nav pattern) |
| Notification bell + unread count | `GET /api/notifications/` (3s poll) | `notifications/views.py:inbox` | `Notification` | Yes; unknown `reference_type` now opens a detail dialog instead of doing nothing (Phase 2 fix) | manual |
| Quick-action badges (consultations/pharmacy) | same dashboard call | `dashboard_views.py:52-54,47-50` | `Consultation`, `AdminPanelRecord` | Yes, all 8 tiles | existing smoke tests |

## Cost Management (`cost_management_screen.dart`, `cost_charts.dart`)

| Value | Endpoint | Backend | Table/model | Interactable | Test |
|---|---|---|---|---|---|
| Total Revenue/Expense/Net Profit/Cash/Estimated Tax | `GET /api/farmers/costs/dashboard/?period=` | `cost_views.py:dashboard` | `Revenue`, `Expense`, `Loan`, `Payment`, `pending_tax` | All 4 mini-cells tappable (Phase 2 fix); period selector now includes `custom` with a date-range picker (Phase 3) | `test_farmer_panel.py`, `test_cost_dashboard_charts.py` |
| Expense category grid | same, `expense_sections` | SQL `.values().annotate(Sum)` per `STANDARD_CATEGORIES` | `Expense`+`ExpenseCategory` | Manage/Add buttons (pre-existing, real) | `test_farmer_panel.py` |
| Revenue list | same, `revenue_sections` | SQL aggregate per `STANDARD_SOURCES` | `Revenue`+`RevenueSource` | Rows → revenue list (Phase 2 fix; were dead) | `test_farmer_panel.py` |
| Loans | same, `loans` | `_loan_json` | `Loan`+`LoanInstallment` | Cards → loans screen (Phase 2 fix; were dead) | `test_farmer_panel.py` |
| Recent transactions | same, `transactions` | merged expense+revenue query | `Expense`, `Revenue` | Rows → expense/revenue list (Phase 2 fix; were dead) | `test_farmer_panel.py` |
| **Monthly revenue/expense/profit chart** | same, `charts.monthly` | `cost_views.py:_monthly_series` — `TruncMonth`+`Sum`, zero-filled 6 months | `Expense`, `Revenue` | fl_chart bar+line, tooltips, legend | `test_cost_dashboard_charts.py` (20 checks), `cost_charts_test.dart` (13 checks) |
| **Expense category breakdown (donut)** | same, `charts.category_breakdown` | derived from the same `sections` (no extra query) | `Expense` | fl_chart pie, legend | same |
| **Feed/Labour/Medicine comparison** | same, `charts.category_comparison` | same `sections`, filtered to 3 categories, always all 3 (zero included) | `Expense` (Labor now includes mirrored wages) | fl_chart bar | same |

## Find Vet / Discover Vets / Consultations / Chat

| Value | Endpoint | Backend | Table/model | Interactable | Test |
|---|---|---|---|---|---|
| Vet list + filters | `GET /api/consultations/vets/` | `consultations/views.py:vets` | `DoctorProfile` | Card → detail dialog → booking | existing |
| Nearby vets (map) | `GET /api/vets/nearby/` | `views.py:vets_nearby`, bounding-box + haversine (Phase 1) | `DoctorProfile` (lat/lng) | Marker → detail sheet, "Open in Google Maps" | `test_vets_nearby.py` (12) |
| Location banner (denied/timeout/unavailable/service-off) | on-device `Geolocator` calls | n/a (client-only, Phase 4) | n/a | "Try again" / "Open settings" — never silently fails | `discover_vets_location_test.dart` (3) |
| Booking form (flock, bird-type dropdown, optional date/time) | `GET .../booking-options/`, `POST /api/consultations/` | `consultations/views.py:booking_options`, `booking.py:create_booking` | `Farm`, `Flock`, `Consultation`, `CaseDetail` | Submits with no availability and no time (Phase 1); bird-type dropdown replaces free-text breed (Phase 2) | `test_consultation_booking_rules.py` (29) |
| Consultation list | `GET /api/consultations/` | `views.py:consultations`, `_farmer_consultation_row` | `Consultation`, `CaseDetail` | Now exposes `doctor_id`/`doctor_profile_id`; single flattened TabBar with Consultations pane | `test_consultation_booking_rules.py`, `find_vet_screen_test.dart` |
| Chat (incl. completed consultations) | `GET/POST /api/consultations/chats/` | conversation always resolved for accepted/in_progress/completed (Phase 1 `_conversation_for`) | `Conversation`, `Message` | "Post-consultation chat" button resolves live instead of silently no-op'ing (Phase 2) | `test_consultation_chat_access.py` (13) |

## Labour Management (`labor_management_screen.dart`, `labour_payment_flow_screens.dart`)

| Value | Endpoint | Backend | Table/model | Interactable | Test |
|---|---|---|---|---|---|
| Worker payroll row | `GET /api/workers/` | `workers/views.py:workers` | `Worker`, `WorkerAttendance`, `WorkerPayment` | Pay button disabled at zero due (Phase 2); Status chip (paid/partial/unpaid) now shown (Phase 2) | `test_labour_payment.py` (27) |
| Payment status/earned/last payment | same | `payment_status`, `earned_this_month`, `last_payment_date` (Phase 1 additions) | `WorkerPayment` | n/a (display) | `test_labour_payment.py` |
| Pay / Pay All | `POST /api/workers/payments/` → `/api/payments/<id>/{method,confirm,cancel}/` | `billing/services.py` | `PaymentIntent` → `WorkerPayment` on success | Pay All now filters to active+due workers only (Phase 2); per-intent outcomes reported instead of one generic failure (Phase 2) | `test_labour_payment.py` |
| Mirrored labour expense | (server-side, on payment success) | `billing/services.py:_mirror_labour_expense` (Phase 1) | `Expense` (category "Labor"), keyed on `source_intent_id` | Feeds directly into Cost Management's Labor totals and charts | `test_labour_payment.py`, `test_cost_dashboard_charts.py` |
| Performance "Earned this month" | `GET /api/workers/` | same `earned_this_month` | `WorkerPayment` aggregate | Fake `rating: 0` star removed (Phase 2) | `test_labour_payment.py` |

## Feed Management, Profile (visual-only touches in Phase 4)

No data-flow changes; Phase 4 fixed: back-button fallback (`context.canPop()` pattern), a
dark-on-green button (`Colors.black` on `AppColors.secondary` was already *correct* — see
Fix Report's "reverted a mis-fix" note), raw `'৳...'` strings replaced with the shared `taka()`
helper (moved to `lib/core/format/currency.dart`), and an error state without Retry now has one.

## Seed data

`backend/users/management/commands/seed_demo_data_for_phone.py --phone 01713018156 --reset`
seeds every table referenced above with real, linked rows: 2 sheds, 2 flocks, 24 expenses
(across all 9 categories, including a mirrored labour wage), 15 revenue, 2 loans+installments,
3 feed stock, 3 workers with mixed paid/unpaid state, 11 notifications, 12 community posts,
3 pharmacy orders, 13 consultations spanning all 8 statuses (including one open-ended request
with no preferred time), 5 tax payments, 6 disease scans, 18 chat messages across 4
conversations, 1 settled labour payment (mirrored to an expense), and 2 locally-generated
profile images. Verified idempotent (re-running adds nothing) and collision-safe against other
seeded farmers (`test_dashboard_integrity_and_seed_idempotency.py`, 13 checks).

## Test status summary

| Layer | Count | Result |
|---|---|---|
| Backend live-DB suites (13 files) | 456 checks | 456 passed, 0 failed |
| Flutter widget/unit tests | 135 tests | 135 passed, 0 failed |
| `flutter analyze` | — | clean (6 pre-existing infos in an untouched file) |
| `flutter build web --release` | — | succeeds |
| `manage.py check` / `migrate --check` | — | clean |

## Known limitations (see Fix Report for detail)

- Booking form dropdown/checkbox interaction, populated labour payment chips, and populated
  chat UI cannot be exercised as Flutter widget tests without a real authenticated session —
  this project's established convention (every existing test file) only exercises the
  no-session/error-retry path for authenticated screens. Correctness for these is instead
  verified live-DB on the backend (`test_consultation_booking_rules.py`,
  `test_labour_payment.py`, `test_consultation_chat_access.py`).
- `category_comparison` always returns all three categories (Feed/Labor/Medicines) even at
  zero, by design, for a stable comparison axis.
- A human click-through of the running app has not been performed by the assistant — see the
  Fix Report's Manual Verification section for exactly what is and isn't covered by automated
  evidence.
