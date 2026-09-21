# Pharmacy Panel Report — 2026-09-21

See [`PHARMACY_PANEL_AUDIT.md`](PHARMACY_PANEL_AUDIT.md) for the full existing-state
audit. Summary of that finding: the pharmacy panel (staff module, farmer
marketplace, admin oversight, delivery assignment/calling/maps) was already
complete and working end-to-end. This report covers the one real gap found
and fixed: **Cost Management integration**.

## Root cause of the missing piece

Pharmacy orders lived entirely on the `pharmacy-orders` JSON bridge
(`AdminPanelRecord`) and the relational catalogue tables, neither of which
had any code path into `expenses`. The `Medicines` expense category
(`linked_module='pharmacy'`) had been seeded since `farmers_panel_extension.sql`
but nothing ever wrote to it — a farmer's medicine spend was invisible to
Cost Management, the expense list, and the dashboard cash balance.

## Models / migrations added

No new tables. One column added to the existing (`managed=False`) `expenses`
table, following the exact precedent of `source_intent_id`
(`farmer_panel_integrity_extension.sql`):

- `backend/pharmacy_cost_management_extension.sql` — `ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS source_pharmacy_order_id TEXT;` plus a partial
  unique index (`WHERE source_pharmacy_order_id IS NOT NULL`) — the
  exactly-once mirroring guard. Applied directly to the live Postgres DB.
- `backend/expenses/models.py` — added the matching `source_pharmacy_order_id`
  field to `Expense`. No Django migration file added, matching the existing
  drift pattern already present for `source_intent_id` (this project's
  `managed=False` cost tables are schema-migrated via the `*_extension.sql`
  files, not `manage.py makemigrations`; `migrate --check` does not inspect
  unmanaged-model field state, so this doesn't create an unapplied-migration
  warning — verified below).

## Backend code added/changed

- `backend/pharmacy/services.py` — added `mirror_pharmacy_expense(payload)`:
  resolves the farmer's `Farm` via the existing `workers.views.farm_for`
  helper, looks up the `Medicines` category, and `get_or_create`s an `Expense`
  keyed on `source_pharmacy_order_id`. Guards against non-UUID demo
  `farmer_id` placeholders (`'F001'` etc. from the seeded legacy orders) and
  a missing category, returning `None` rather than raising, so the delivery
  itself is never blocked by a Cost Management failure.
- `backend/pharmacy/catalogue_views.py::order_status` — calls
  `mirror_pharmacy_expense(payload)` on the `delivered` transition (the
  pharmacist-direct-confirm path), inside the existing `transaction.atomic()`
  block so the mirror and the status change commit together.
- `backend/delivery/views.py::_sync_pharmacy_order` — calls the same mirror
  function on the rider's OTP-confirmed delivery path (the more common real
  path), also inside `update_status`'s existing atomic block.
- `backend/pharmacy/management/commands/seed_pharmacy_demo_data.py` — new,
  idempotent seed command populating `pharmacy_suppliers` for every
  pharmacy-role user (that table was empty in the live DB with no seeder,
  leaving the Suppliers screen with nothing to show).

No new API endpoints — the mirroring is a side effect of the existing
`PATCH /api/pharmacy/orders/{id}/status/` and
`PATCH /api/delivery/orders/{id}/status/` endpoints.

## Medicine-to-farmer visibility flow

Confirmed unchanged and already correct: `pharmacy/farmer_views.py` filters
every farmer-facing query (`pharmacies`, `pharmacy_medicines`,
`medicine_search`, `medicine_detail`) on `is_active=True, is_approved=True`,
so inactive or admin-unapproved medicines never reach the farmer marketplace.
No changes needed here.

## Delivery assignment / calling

Already fully implemented (see audit). Not modified beyond the expense-mirror
hook, which was added into both routes that reach `delivered`.

## Cost Management integration (this fix)

- A delivered pharmacy order now mirrors into `expenses` **exactly once**,
  category `Medicines`, `payment_status='paid'`, amount = the order's
  `total_amount`, `created_by` = the farmer. This makes it flow through the
  existing Cost Management totals, category breakdown, recent-transactions
  list, and monthly charts the same way a manually-entered "Medicines"
  expense would — no new UI or serializer needed on the Flutter side.
- Idempotency: enforced at the database level via the partial unique index
  on `source_pharmacy_order_id`, identical to the labour-payment precedent.
  A duplicate/replayed delivered call is additionally blocked earlier by the
  existing order status machine (`_BRIDGE_TRANSITIONS`), which rejects a
  second `delivered` transition with 409 before the mirror code is even
  reached.
- Cancelled/rejected orders never mirror (mirror is only ever called from
  the `delivered` branch).
- COD orders mirror on delivery (money changes hands physically at that
  point); digitally-paid orders were already marked `paid` earlier via
  `order_pay`, but the expense record itself is still created once, at
  delivery, since that's when the medicine has actually left the pharmacy.

## Authorization behaviour

No change to permission classes. The mirror function runs server-side as a
side effect of an already-authorized status-change call
(`IsPharmacyUser` for the pharmacist path, `IsDeliveryUser` for the rider
path); farmers cannot trigger it directly, and it silently no-ops rather than
erroring if the category or a valid farmer can't be resolved.

## Seed data and idempotency

`seed_pharmacy_demo_data` run three times against the live DB:

```
Seeded 6 new supplier row(s) across 3 pharmacy user(s).
Seeded 0 new supplier row(s) across 3 pharmacy user(s).
Seeded 0 new supplier row(s) across 3 pharmacy user(s).
```

No duplicates, no crash, no overwritten real user data (only inserts new
`PharmacySupplier` rows via `get_or_create`).

## Backend test results

New E2E script `backend/scripts/test_pharmacy_flow.py` (live DB,
`pharmtest+`-prefixed throw-away accounts, matches the repo's
`test_labour_payment.py` / `test_doctor_flow.py` convention since
`manage.py test` cannot build a Postgres test database in this environment —
see Known Limitations):

```
21 passed, 0 failed
```

Covers: order placement decrements stock; pharmacist-direct delivered
transition mirrors exactly once into `expenses` (correct amount, category,
payment_status, farmer ownership); a repeated delivered call is rejected by
the existing status machine and does not double-mirror; a cancelled order
mirrors nothing; and the separate rider/OTP delivery path
(`_sync_pharmacy_order`) also mirrors exactly once with the correct amount.
Re-run twice back-to-back with identical results (idempotent cleanup).

Regression-checked: `backend/scripts/test_labour_payment.py` (the existing
`source_intent_id` mirroring precedent this fix's pattern is copied from)
still passes 27/27 — confirms the shared `Expense` model change didn't
disturb the labour-payment mirror.

## Flutter test results / analyze / build

Not run. No Flutter files were changed by this fix — the gap was entirely
backend (Cost Management mirroring), and the audit already confirmed the
Flutter pharmacy screens are real, working, and calling live endpoints. If
you want the quality gates re-confirmed anyway, run:

```
flutter pub get && flutter analyze && flutter test && flutter build web --release
```

## Backend quality gates

```
backend/venv/Scripts/python manage.py check          -> System check identified no issues (0 silenced).
backend/venv/Scripts/python manage.py migrate --check -> exit code 0 (no unapplied migrations)
```

## Manual verification

Exercised via the E2E script above against the live Postgres DB (not the
Flutter UI, which wasn't changed): medicine creation/visibility, order
placement with stock decrement, pharmacist confirm→ship→deliver, rider
accept→pick up→on the way→OTP-deliver, admin queue/assign, and the resulting
`Expense` row — all verified programmatically end to end.

## Known limitations

- `manage.py test` cannot run in this environment: creating the Postgres test
  database fails (`relation "users" does not exist`), because several core
  tables in this project are provisioned via raw `*_extension.sql` files
  rather than Django migrations, and the test-database bootstrap only runs
  migrations. This is a pre-existing environment limitation, not something
  introduced by this change — it's also why the repo already has a
  `backend/scripts/test_*_flow.py` convention (live-DB scripts) instead of
  relying solely on `APITestCase`. `backend/pharmacy/tests.py`'s existing
  `PharmacyEcosystemTests` could not be run to confirm no regression there;
  its logic was read and cross-checked by hand against the two delivered-path
  code changes (the non-UUID `farmer_id` guard added specifically because
  that test's seeded demo orders use placeholder ids like `'F001'`).
- Flutter smoke-test coverage for pharmacy screens (identified in the audit
  as a pre-existing gap, unrelated to this fix) was not added — out of scope
  for a backend-only Cost Management fix; flagged for a follow-up pass.
- Pharmacy-side revenue (the pharmacy's own P&L) was intentionally not mapped
  to the farmer's `Revenue` table — pharmacy already has its own analytics
  surface (`pharmacy_analytics_screen.dart` / `/api/pharmacy/analytics/*`)
  reading order data directly, and there is no `Farm`-equivalent business
  entity for a pharmacy to attach a `Revenue` row to. See the Assumptions
  section of the audit doc.

## Confirmation

Nothing in this session was committed. All changes are in the working tree.
