# Tax integration (farmer panel)

Bangladesh tax **estimation + record-keeping** for FeatherFlow farmers. Logic is
ported from the TaxEase PHP project (rules only — no PHP/HTML/CSS imported); see
[`TAX_RULES_FROM_TAXEASE.md`](TAX_RULES_FROM_TAXEASE.md).

Added 2026-09-10. Nothing here is enforced — it is a planning tool. No NBR
integration, no payment gateway.

---

## 1. What a farmer gets

| Screen | Route | Purpose |
|---|---|---|
| **Tax** (summary) | `/farmer/tax` | YTD paid, estimated tax for the year, pending; per-type breakdown |
| **Tax estimate** | `/farmer/tax/calculator` | Real-time estimate as revenue / expenses / income-type change; full "how this was worked out" breakdown |
| **My tax details** | `/farmer/tax/profile` | Land area + unit + use + location, vehicles, income type, exemptions/rebate, senior flag |
| **Tax payments** | `/farmer/tax/payments` | Record a payment (type, amount, date, challan no., receipt photo); payment history; optional mirror into Cost Management as a "Tax" expense |

**Entry points**
- Farmer dashboard → "Tax & Estimates" quick-action tile.
- Cost Management top card → the "Estimated Tax" mini-stat now shows the live
  estimate and opens `/farmer/tax` on tap (was "Coming soon").

---

## 2. Tax rules implemented

All the tunable numbers live at the top of
[`backend/tax/calculator.py`](backend/tax/calculator.py) — change them there when
the Finance Act changes; nothing else needs to move.

### Individual income tax (from `TaxEase/Calculator.php`)
- Tax-free threshold: **BDT 350,000** (**400,000** if senior / age 65+).
- Progressive slabs on income **above** the threshold: 5% / 10% / 15% / 25% / 30%
  over band widths 100k / 400k / 500k / 500k / rest.
- **Agricultural income exemption (Bangladesh-specific, added):** first
  **BDT 200,000** of farming income is tax-free.
- Poultry/livestock sales count as agricultural income; farm revenue is netted
  against farm expenses first.
- `exemptions` reduce taxable income; `rebates` reduce the computed tax (floored at 0).

### Corporate / business tax (from `TaxEase/businesscalcu.php`)
- `tax = max(net_profit × 27.5%, revenue × 0.6%)`; a loss still owes the
  0.6%-of-turnover minimum tax. Exposed as `calculate_business_tax()` for
  completeness — the farmer flow uses the personal slabs.

### Land development tax (reference rates, added)
- Agricultural land: **first 25 bighas (825 decimal) exempt**, then BDT 2/decimal/year (rural).
- Residential: 6 (rural) / 22 (urban) per decimal. Commercial: 15 / 60.
- Units supported: katha, bigha, decimal, shotangsho, acre, kani.

### Vehicle tax (BRTA annual advance tax, added)
- Motorcycle / bicycle: 0. **Power tiller / tractor: exempt.**
- CNG 1,500 · pickup/van 4,000 · truck 10,000 · bus 16,000 · microbus/jeep 30,000.
- Private car by engine: ≤1500cc 25,000 · 1501–2000 50,000 · 2001–2500 75,000 · >2500 125,000.

Full detail + the Bangladesh provisions are in `TAX_RULES_FROM_TAXEASE.md` §2–6.

---

## 3. Backend

New Django app **`backend/tax/`** (registered in `INSTALLED_APPS`; owns its two
tables via ordinary migrations — not part of `featherflow_schema.sql`).

```
backend/tax/
  calculator.py     pure functions, no Django — the single source of tax rules
  models.py         TaxProfile (1 per user), TaxPayment
  serializers.py    DRF validation
  views.py          the 6 endpoints below
  urls.py           mounted at /api/farmers/tax/
  migrations/0001_initial.py
```

### Endpoints (all require an active `farmer` role)

| Method + path | Body | Returns |
|---|---|---|
| `POST /api/farmers/tax/calculate/` | `{revenue_breakdown?, expenses?, income_type?, exemptions?, rebates?, is_senior?, assets?}` — anything omitted falls back to the saved profile + this year's cost-management revenue | `{tax_year, total_revenue, net_income, income_tax, land_tax, vehicle_tax, total, income:{tax,breakdown,…}, land:{…}, vehicle:{…}, breakdown:[str]}` |
| `GET /api/farmers/tax/profile/` | – | `TaxProfile` (auto-created on first read) |
| `PUT /PATCH /api/farmers/tax/profile/` | any profile field | updated `TaxProfile` |
| `POST /api/farmers/tax/payment/` | `{tax_type, amount, payment_date, reference_number?, notes?, receipt_url?, log_as_expense?}` | created `TaxPayment` |
| `POST /api/farmers/tax/payment/upload-receipt/` | multipart `image`/`file` | `{image_url}` |
| `GET /api/farmers/tax/payments/` | `?tax_type=&year=` | `{results:[TaxPayment], count, total_paid}` |
| `GET /api/farmers/tax/summary/` | – | `{year, tax_year, estimated_total, total_paid, pending, lines:[{tax_type,label,estimated,paid,pending}], estimate:{…}, disclaimer}` |

### Calculator functions

```python
calculate_income_tax(income, income_type='agricultural', exemptions=0, rebates=0,
                     is_senior=False, agricultural_income=None) -> {tax, taxable_income, threshold,
                     exemptions_applied, rebate_applied, breakdown}
calculate_business_tax(revenue, expenses=0, deductions=0) -> {tax, net_profit, minimum_tax, breakdown}
calculate_land_tax(land_area, land_unit='katha', location='rural', land_use='agricultural')
                     -> {tax, decimals, taxable_decimals, rate_per_decimal, exempt, breakdown}
calculate_vehicle_tax([{type, count}, ...]) -> {tax, items, breakdown}
calculate_total_tax(revenue_breakdown, assets, income_type='agricultural',
                     exemptions=0, rebates=0, is_senior=False, expenses=0)
                     -> {income_tax, land_tax, vehicle_tax, total, breakdown, income, land, vehicle, ...}
```

Every function returns a farmer-friendly `breakdown` (list of plain-language
lines, e.g. `"Less: agricultural income exemption (first BDT 200,000 tax-free): -BDT 200,000"`).

---

## 4. Frontend

```
lib/features/farmer/data/
  tax_api_service.dart                    calculateTax / getTaxProfile / updateTaxProfile /
                                          recordTaxPayment / getTaxPayments / uploadReceipt / getTaxSummary
  models/tax_profile.dart                 TaxProfile, TaxVehicle
  models/tax_payment.dart                 TaxPayment
  models/tax_calculation_result.dart      TaxCalculationResult
  models/tax_summary.dart                 TaxSummary, TaxSummaryLine
lib/features/farmer/presentation/screens/
  tax_summary_screen.dart                 TaxSummaryScreen        (/farmer/tax)
  tax_calculation_screen.dart             TaxCalculationScreen    (/farmer/tax/calculator)
  tax_profile_screen.dart                 TaxProfileScreen        (/farmer/tax/profile)
  tax_payment_screen.dart                 TaxPaymentScreen        (/farmer/tax/payments)
```

> Note: FeatherFlow's farmer feature folder is `lib/features/farmer/` (singular);
> the task brief said `farmers/` — the existing singular convention was kept for
> consistency with every sibling file.

Calls go through the existing `FarmManagementService` (auth, trailing slash,
error surfacing). Screens use the farmer-panel style (white background, dark-green
`AppColors.primary` app bar, English-only). The calculator recalculates with a
~550 ms debounce as the farmer edits.

Routes were added as children of `/farmer` in
[`lib/core/router/app_router.dart`](lib/core/router/app_router.dart).

---

## 5. Demo data

`backend/users/management/commands/seed_platform_demo.py` now creates, for each
demo farmer (`farmer.rashed@example.com`, `farmer.nasima@example.com`):
- a `TaxProfile`: 50 katha rural agricultural land, 1 motorcycle + 1 van, agricultural income;
- two `TaxPayment` rows: land BDT 5,000 and vehicle BDT 2,000 (mid-February).

Result on the Tax screen: income tax **BDT 0** (agricultural exemption + threshold),
land tax **BDT 0** (under the 25-bigha exemption), vehicle tax **BDT 4,000**
(van 4,000 + motorcycle 0); BDT 7,000 recorded as paid.

---

## 6. Tests

- **Backend:** `backend/scripts/test_tax_calculator.py` — **64 checks, all pass.**
  Covers every income slab, the senior threshold, agricultural exemption,
  business/minimum tax, land tax (units, location, exemption), vehicle tax
  (types, aliases, agri-exempt, unknown), the combined calculation, edge cases
  (zero / negative / garbage / very-high income), and all 6 endpoints.
- **Frontend:** `test/tax_flow_test.dart` — **8 tests, all pass.** Model parsing
  round-trips (incl. DRF string-decimals) + each screen builds without a session
  (falls back to loading/error, no exceptions). Full suite: 49 tests pass.
- Regression: `test_farmer_panel.py` (35) and `test_disease_detection.py` (27)
  still pass; `flutter analyze` clean for the tax files.
- **Live run verified:** Django (`:8000`) + Flutter web release build, driven via
  headless Chrome with a seeded auth session. All four screens render live data
  from the backend (summary, calculator prefilled from cost-management revenue,
  payments list, profile). One bug found and fixed during this run — DRF
  serialises `DecimalField` to a JSON **string** (`"50.00"`); the Flutter models
  now parse numbers defensively (`asDouble()` in `tax_profile.dart`, reused by
  `tax_payment.dart`) instead of casting `as num?`.

---

## 7. How to update tax rates / slabs in the future

1. Edit the constants at the top of `backend/tax/calculator.py`:
   - `TAX_FREE_THRESHOLD`, `TAX_FREE_THRESHOLD_SENIOR`, `INCOME_TAX_SLABS`
   - `AGRICULTURAL_EXEMPTION`, `CORPORATE_TAX_RATE`, `MINIMUM_TAX_ON_TURNOVER`
   - `LAND_TAX_PER_DECIMAL`, `AGRI_LAND_EXEMPT_BIGHA`, `LAND_UNIT_TO_DECIMAL`
   - `VEHICLE_TAX`, `VEHICLE_ALIASES`
   - bump `TAX_YEAR`
2. Update the expected numbers in `backend/scripts/test_tax_calculator.py` and re-run it.
3. No migration, no frontend change — the breakdown strings and the API shape are
   generated from these tables.

---

## 8. Limitations / future work

- Estimate only — **not a tax assessment**. No NBR / iBAS integration, no e-filing,
  no challan validation, no online payment.
- Investment rebate is a flat BDT figure the farmer enters, not computed from an
  investment schedule.
- No net-wealth surcharge, no area-based minimum tax on the personal estimate.
- Land tax rates for non-agricultural land are public-domain approximations, not
  gazette-exact per city corporation / municipality.
- Vehicle tax uses type/engine bands, not the exact BRTA fee schedule with
  fitness / registration components.
- Future: pull the farmer's district/upazila from the farm profile automatically;
  link tax deadlines to notifications; a vet/agri-officer "review my estimate" flow.
