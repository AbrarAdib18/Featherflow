# Pharmacy Panel Audit — 2026-09-21

Verified directly against the current codebase and a live Postgres connection
(`manage.py shell`), not from prior session memory.

## Headline finding

The pharmacy area is **not** broken or missing. It is a complete, real,
end-to-end implementation: relational Postgres tables, DRF endpoints wired
into `urls.py`, a full pharmacy-staff Flutter module (6 screens), a full
farmer-facing marketplace module, an admin-oversight module, and working
delivery assignment/calling/maps. `manage.py check` and `manage.py migrate
--check` both pass clean. Live DB has 8 medicines, 129 pharmacy-orders bridge
records, 5 pharmacy users, 2 delivery-queue records.

The one confirmed, real gap is **Cost Management integration**: pharmacy
orders never mirror into the farmer's `expenses` table, even though the
`Medicines` expense category (`linked_module='pharmacy'`) has been seeded and
waiting, unused, since `farmers_panel_extension.sql`.

## Existing pharmacy-related files (all present and wired)

- `backend/pharmacy/models.py` — `PharmacyMedicine` (`pharmacy_catalogue_medicines`),
  `PharmacySupplier` (`pharmacy_suppliers`), `PharmacyExpiryAlert`
  (`pharmacy_expiry_alerts`) — real relational tables, `managed=False`,
  defined in `backend/postgres_backend_extension.sql:494-580`.
- `backend/pharmacy/catalogue_views.py` — medicines CRUD, stock/price patch,
  inventory summary/low-stock/expiring/alerts, suppliers CRUD, analytics, and
  the full order state machine (`order_confirm`, `order_cancel`,
  `order_ready_for_delivery`, `order_status`).
- `backend/pharmacy/farmer_views.py` — browse pharmacies/medicines, search,
  prescription upload, place/cancel/pay orders. Order placement uses
  `transaction.atomic()` + row locks (`order_items_from_cart(..., lock=True)`).
- `backend/pharmacy/services.py` — shared serializers, `order_items_from_cart`,
  `regenerate_expiry_alerts`.
- `backend/api/admin_pharmacy.py` — admin oversight (approve/reject medicines,
  suspend pharmacy, analytics), RBAC-gated via `can_perform_action`.
- Delivery bridge: `backend/api/admin_views.py::_assign_from_queue` turns a
  `delivery-queue` JSON record into a real `DeliveryOrder`
  (`is_pharmacy_delivery=True`) and writes `delivery_order_id` back onto the
  source order.
- Flutter: `lib/features/pharmacy/**` (staff module, 3190 lines),
  `lib/features/farmer/presentation/screens/farmer_pharmacy_screen.dart` +
  `lib/features/farmer/data/pharmacy_marketplace_service.dart` (farmer
  marketplace, real HTTP, no mocks), `lib/features/admin/.../admin_pharmacy_screen.dart`.
  All routed in `lib/core/router/app_router.dart`.
- Calling/maps already implemented: `pharmacy_orders_screen.dart` (call
  farmer, call rider), `farmer_pharmacy_screen.dart` (call rider, call
  pharmacy), `delivery_detail_screen.dart` ("Open in Maps").

## Missing functionality (the real gap)

**Cost Management integration.** Confirmed by grep: zero references to
`pharmacy` anywhere in `backend/expenses/*.py` or the Flutter cost-management
screens. No code creates an `Expense` row when a farmer's medicine order is
delivered/paid. The `Medicines` `ExpenseCategory` (`linked_module='pharmacy'`)
already exists in `farmers_panel_extension.sql:88` but nothing writes to it.

Secondary, lower-priority gaps:
- `pharmacy_suppliers` (0 rows) and `pharmacy_expiry_alerts` (0 rows) are
  empty in the live DB — no seed command exists (compare
  `seed_farmer_demo_data.py`, `seed_feed_marketplace_demo.py`).
- No `backend/scripts/test_pharmacy_flow.py` E2E script, unlike
  `test_doctor_flow.py`, `test_farmer_panel.py`, `test_labour_payment.py`.
- Flutter smoke-test suites (`farmer_screens_smoke_test.dart`,
  `admin_screens_smoke_test.dart`) have zero pharmacy coverage.

## Reusable services/components

- `workers.views.farm_for(user)` — resolves/creates the farmer's `Farm`, the
  established way every farmer-side cost-writing endpoint gets a `Farm` row.
- `billing/services.py::_mirror_labour_expense` — the exact precedent for
  idempotent order→expense mirroring: `get_or_create` keyed on a dedicated
  nullable+partially-unique-indexed column (`source_intent_id` there),
  category looked up by name, `payment_status='paid'`, `paid_at=now()`.
- `farmer_panel_integrity_extension.sql:44-64` — the SQL pattern for adding
  that idempotency column via `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` +
  `CREATE UNIQUE INDEX ... WHERE col IS NOT NULL`.
- `taka()` formatter already used throughout farmer cost-management Flutter
  screens — no new currency formatting needed.

## Authentication roles

Role membership via `User.roles` M2M / `Role.name` string keys:
`'pharmacy'`, `'farmer'`, `'delivery'`, `'admin_super'` (confirmed live and in
`backend/pharmacy/tests.py:11-14`). Permission classes: `IsPharmacyUser`,
`IsFarmerUser`, `IsAdminUser` + `can_perform_action(user, 'pharmacy', action)`
RBAC. No new role needed.

## Implementation plan

1. Add `source_pharmacy_order_id` column to `expenses` (SQL extension file +
   model field), mirroring the `source_intent_id` precedent exactly.
2. Add `mirror_pharmacy_expense(payload)` to `pharmacy/services.py`: resolves
   the farmer's `Farm` via `farm_for`, looks up the `Medicines` category,
   `get_or_create`s the `Expense` keyed on the order id.
3. Call it from `catalogue_views.py::order_status` at the `delivered`
   transition (the point at which money has definitively changed hands,
   including COD collected on delivery).
4. Add a seed command for pharmacy suppliers/expiry-alert demo data
   (idempotent, `get_or_create`-based).
5. Add `backend/scripts/test_pharmacy_flow.py` covering the new mirroring
   behaviour (exactly-once, correct category/amount, cancelled orders don't
   mirror).
6. Add minimal Flutter smoke coverage for the pharmacy route.

## Assumptions

- Cost Management mirroring belongs to the **farmer** side (an `Expense`),
  since that is the only Cost Management surface in the product; pharmacy's
  own revenue reporting already exists via `pharmacy_analytics_screen.dart`
  reading order/analytics endpoints directly, so no `Revenue` table row is
  added for the pharmacy side — adding one would require a `Farm`-equivalent
  concept for pharmacy businesses that doesn't currently exist, which is out
  of scope for this fix.
- Mirroring happens once, at `delivered`, regardless of payment method
  (COD is collected physically at delivery; digital payments were already
  marked `paid` earlier via `order_pay` but the expense itself is only
  recorded once stock has actually left the pharmacy).
- Cancelled/rejected/refunded orders never mirror an expense.
