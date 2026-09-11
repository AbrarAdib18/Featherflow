# Tax rules extracted from TaxEase

This document records the tax logic found in the **TaxEase** project
(`/TaxEase`, a PHP/HTML/CSS tax website) so it can be re-implemented in Python
inside the FeatherFlow backend. **No PHP/HTML/CSS was copied** — only the rules,
rates, thresholds and formulas below.

Audit date: 2026-09-10 · Source commit of TaxEase folder: as vendored.

---

## 1. Where the logic lives in TaxEase

| File | What it contains | Real calculation? |
|---|---|---|
| `TaxEase/Calculator.php` | Individual **income tax** calculator (JS in the page, lines 391-500) | ✅ Yes — full slab logic |
| `TaxEase/businesscalcu.php` | **Corporate / business tax** calculator (JS, lines 280-312) | ✅ Yes — rate + minimum tax |
| `TaxEase/ForIncome.php` | Income-tax *payment* form → `payment_incometax` table | ❌ No — records a manually typed amount |
| `TaxEase/ForLand.php` | Land-tax *payment* form → `payment_land` table (captures `land_amount`, `zone`, `land_usage`, `land_type`) | ❌ No — amount typed by user |
| `TaxEase/ForVehicle.php` | Vehicle-tax *payment* form → `payment_vehicle` table (captures `vehicle_type`, `vehicle_model`, `zone`) | ❌ No — amount typed by user |
| `TaxEase/asset_details.php` / `signup2.php` | Asset capture: `land_type` ∈ {Agricultural, Commercial, Residential}, `vehicle_type` ∈ {Car, Motorcycle, Truck} | ❌ No — data entry only |

**Conclusion:** TaxEase only implements formulas for **income tax** and
**corporate tax**. Land tax and vehicle tax in TaxEase are pure record-keeping
(the user types the amount). For FeatherFlow we keep TaxEase's two real formulas
verbatim and add **standard Bangladesh reference rate tables** for land and
vehicle tax, kept in one editable place (`backend/tax/calculator.py`).

---

## 2. Individual income tax  (from `TaxEase/Calculator.php`)

### Inputs
- `grossIncome` — gross annual income
- `extraIncome` — income from other sources
- `ageGroup` — `lessthan40` | `between40and60` | `greaterthan60`
- `deductions` — total applicable deductions

### Rules (exact, from the JS)

```
totalIncome   = grossIncome + extraIncome

taxFreeLimit  = 400,000   if ageGroup == "greaterthan60"   (senior citizen)
              = 350,000   otherwise

taxableIncome = totalIncome - deductions

if taxableIncome <= taxFreeLimit:
    tax = 0
else:
    taxableIncome -= taxFreeLimit          # tax only the amount ABOVE the threshold
    tax = progressive slabs on taxableIncome:
        first  100,000  @  5%
        next   400,000  @ 10%
        next   500,000  @ 15%
        next   500,000  @ 25%
        remainder       @ 30%

finalIncome = totalIncome - tax
```

The slab widths, read off the JS bracket conditions:

| Band (amount above the tax-free threshold) | Rate |
|---|---|
| 0 – 100,000 | 5% |
| 100,001 – 500,000 | 10% |
| 500,001 – 1,000,000 | 15% |
| 1,000,001 – 1,500,000 | 25% |
| above 1,500,000 | 30% |

### Edge cases in the TaxEase code
- Negative / non-numeric input → validation error, no calculation.
- `taxableIncome <= taxFreeLimit` (incl. after deductions) → **tax = 0**.
- No minimum tax, no surcharge, no rebate logic in TaxEase's personal calculator.

---

## 3. Corporate / business tax  (from `TaxEase/businesscalcu.php`)

### Inputs
- `grossRevenue`, `totalExpenses`, `deductions`

### Rules (exact, from the JS)

```
netProfit   = grossRevenue - totalExpenses - deductions
minimumTax  = grossRevenue * 0.6%           # 0.006
corporateRate = 27.5%                        # 0.275

if netProfit > 0:
    taxAmount = netProfit * corporateRate
    if taxAmount < minimumTax:
        taxAmount = minimumTax               # minimum tax floor
else:
    taxAmount = minimumTax                   # loss-making company still pays minimum tax
```

So: **tax = max(netProfit × 27.5%, revenue × 0.6%)**, and a loss still owes the
0.6%-of-turnover minimum tax.

---

## 4. Land development tax  (NOT in TaxEase — added for FeatherFlow)

TaxEase only stores a typed amount. FeatherFlow implements an **estimate** using
standard Bangladesh *Land Development Tax* (ভূমি উন্নয়ন কর) structure:

- **Agricultural land held by a farming family: first 25 bighas (~8.25 acres / 825 decimal) is exempt.** Above that, a low per-unit rate applies.
- Non-agricultural land is charged per *shotangsho* (= 1 decimal) by land use and
  whether the plot is in a rural (union) or urban (municipal / city corporation) area.

### Unit conversions used

| Unit | Decimals (= shotangsho) |
|---|---|
| 1 decimal / shotangsho | 1 |
| 1 katha | 1.65 |
| 1 bigha | 33 |
| 1 acre | 100 |
| 1 kani (trad.) | 120 |

### Reference annual rates (BDT per decimal per year) — editable in `calculator.py`

| Land use | Rural | Urban |
|---|---|---|
| Agricultural | 2 (after the 25-bigha exemption) | 5 |
| Residential | 6 | 22 |
| Commercial | 15 | 60 |

```
decimals       = land_area × unit_to_decimal[land_unit]
if land_use == agricultural:
    exempt     = min(decimals, 825)          # 25 bigha
    taxable    = decimals - exempt
else:
    taxable    = decimals
land_tax       = taxable × rate[land_use, location]
```

> These figures are a reasonable public-domain approximation for an *estimate*.
> They are all in one dict (`LAND_TAX_PER_DECIMAL`) so they can be corrected when
> the Land Ministry gazette changes.

---

## 5. Vehicle tax  (NOT in TaxEase — added for FeatherFlow)

TaxEase stores a typed amount and only knows `Car / Motorcycle / Truck`.
FeatherFlow estimates using the **BRTA annual advance income tax on motor
vehicles** (the yearly "token" tax), with **agricultural vehicles exempt**.

### Reference annual amounts (BDT/year) — editable in `calculator.py`

| Vehicle type | Annual tax |
|---|---|
| Motorcycle / bicycle / rickshaw-van | 0 |
| Power tiller / tractor (agricultural) | 0 — exempt |
| CNG / auto-rickshaw | 1,500 |
| Pickup / van (light commercial) | 4,000 |
| Truck | 10,000 |
| Bus | 16,000 |
| Microbus / Jeep | 30,000 |
| Private car ≤ 1500 cc | 25,000 |
| Private car 1501–2000 cc | 50,000 |
| Private car 2001–2500 cc | 75,000 |
| Private car > 2500 cc | 125,000 |

```
vehicle_tax = Σ  rate[type] × count      (unknown types skipped; agri types = 0)
```

---

## 6. Bangladesh-specific provisions added on top of TaxEase

TaxEase has **no** agricultural provisions. FeatherFlow adds the ones that matter
to a poultry farmer:

1. **Agricultural income exemption** — the first **BDT 200,000** of agricultural
   income is tax-free for a farming family (Income Tax Act 2023, 6th Schedule
   Part 1). Applied before the normal tax-free threshold.
   - `calculator.py`: `AGRICULTURAL_EXEMPTION = 200_000`
2. **Poultry / livestock farm sales are agricultural income** — so
   `calculate_total_tax` treats all farm revenue (bird sales, egg sales,
   by-products) as agricultural income and nets it against farm expenses before
   applying slabs.
3. **Farming-family land exemption** — first 25 bighas of agricultural land is
   exempt from land development tax (section 4 above).
4. **Agricultural vehicle exemption** — power tillers and tractors are not
   charged the annual vehicle tax.
5. **Senior-citizen threshold** — BDT 400,000 tax-free (TaxEase's "Above 60"
   rule; Bangladesh uses age 65+ and also 400k for women — both map to the same
   number here).

### Not modelled (documented limitations)
- Investment tax **rebate** is supported only as a flat BDT reduction the farmer
  enters (`rebates` argument), not computed from investment schedules.
- Surcharge on net wealth (for very high-net-worth individuals) — not modelled.
- Area-based **minimum tax** (Tk 3,000 / 4,000 / 5,000) — not applied to the
  personal estimate (TaxEase didn't either); noted for future.
- No NBR / iBAS integration, no e-filing, no challan validation.
