"""Bangladesh tax estimation for the FeatherFlow farmer panel.

The two real formulas are ported from the TaxEase project
(see ``TAX_RULES_FROM_TAXEASE.md``):

* individual income-tax slabs + tax-free threshold  -> ``TaxEase/Calculator.php``
* corporate / minimum-tax rule                       -> ``TaxEase/businesscalcu.php``

TaxEase only *recorded* land & vehicle tax (the user typed the amount), so those
rate tables here are standard Bangladesh reference figures. Everything a farmer
sees is an **estimate, not a tax filing** — there is no NBR integration.

All the tunable numbers live at the top of this module so they can be updated in
one place when the Finance Act changes.
"""
from __future__ import annotations

# ── knobs: update these when tax law changes ─────────────────────────────────

TAX_YEAR = '2024-25'

# Individual income tax — TaxEase/Calculator.php
TAX_FREE_THRESHOLD = 350_000.0
TAX_FREE_THRESHOLD_SENIOR = 400_000.0            # age 65+ / women (TaxEase: "Above 60")
INCOME_TAX_SLABS = [                             # (band width above threshold, rate)
    (100_000.0, 0.05),
    (400_000.0, 0.10),
    (500_000.0, 0.15),
    (500_000.0, 0.25),
    (None, 0.30),                                # remainder
]

# Bangladesh-specific: agricultural income exemption (Income Tax Act 2023,
# 6th Schedule Part 1). First BDT 200,000 of agricultural income is tax-free.
AGRICULTURAL_EXEMPTION = 200_000.0

# Corporate / business — TaxEase/businesscalcu.php
CORPORATE_TAX_RATE = 0.275
MINIMUM_TAX_ON_TURNOVER = 0.006

# Land development tax — annual BDT per decimal (1 decimal = 1 shotangsho).
AGRI_LAND_EXEMPT_BIGHA = 25.0                    # farming-family exemption
LAND_TAX_PER_DECIMAL = {
    ('agricultural', 'rural'): 2.0,
    ('agricultural', 'urban'): 5.0,
    ('residential', 'rural'): 6.0,
    ('residential', 'urban'): 22.0,
    ('commercial', 'rural'): 15.0,
    ('commercial', 'urban'): 60.0,
}
LAND_UNIT_TO_DECIMAL = {
    'decimal': 1.0, 'shotangsho': 1.0, 'katha': 1.65,
    'bigha': 33.0, 'acre': 100.0, 'kani': 120.0,
}

# Vehicle tax — annual BRTA advance tax (BDT). Agricultural vehicles exempt.
VEHICLE_TAX = {
    'motorcycle': 0.0,
    'bicycle': 0.0,
    'rickshaw_van': 0.0,
    'power_tiller': 0.0,          # agricultural — exempt
    'tractor': 0.0,              # agricultural — exempt
    'cng_autorickshaw': 1_500.0,
    'pickup': 4_000.0,
    'van': 4_000.0,
    'car_upto_1500cc': 25_000.0,
    'car_1501_2000cc': 50_000.0,
    'car_2001_2500cc': 75_000.0,
    'car_above_2500cc': 125_000.0,
    'microbus': 30_000.0,
    'jeep': 30_000.0,
    'truck': 10_000.0,
    'bus': 16_000.0,
}
# friendly / legacy names -> canonical key above
VEHICLE_ALIASES = {
    'car': 'car_upto_1500cc',
    'private_car': 'car_upto_1500cc',
    'motorbike': 'motorcycle',
    'bike': 'motorcycle',
    'cng': 'cng_autorickshaw',
    'auto_rickshaw': 'cng_autorickshaw',
    'autorickshaw': 'cng_autorickshaw',
    'lorry': 'truck',
    'covered_van': 'truck',
    'minibus': 'bus',
    'powertiller': 'power_tiller',
}

INCOME_TYPES = ('agricultural', 'business', 'mixed')
LAND_UNITS = tuple(LAND_UNIT_TO_DECIMAL)
LAND_USES = ('agricultural', 'residential', 'commercial')
LOCATIONS = ('rural', 'urban')
VEHICLE_TYPES = tuple(VEHICLE_TAX)


# ── small helpers ───────────────────────────────────────────────────────────

def _f(value):
    try:
        return round(float(value), 2)
    except (TypeError, ValueError):
        return 0.0


def _money(value):
    return 'BDT {:,.0f}'.format(round(_f(value)))


def _pct(rate):
    return ('%g%%' % (rate * 100))


# ── income tax ──────────────────────────────────────────────────────────────

def calculate_income_tax(income, income_type='agricultural', exemptions=0.0,
                         rebates=0.0, is_senior=False, agricultural_income=None):
    """Individual income tax (TaxEase slab rules + BD agricultural exemption).

    Returns ``{tax, taxable_income, threshold, exemptions_applied,
    rebate_applied, breakdown}`` where ``breakdown`` is a list of farmer-friendly
    lines.
    """
    income = max(0.0, _f(income))
    exemptions = max(0.0, _f(exemptions))
    rebates = max(0.0, _f(rebates))
    income_type = (income_type or 'agricultural').lower()
    if income_type not in INCOME_TYPES:
        income_type = 'agricultural'

    lines = ['Gross annual income: %s' % _money(income)]

    # 1. agricultural income exemption (first BDT 200,000)
    agri_exempt = 0.0
    if income_type in ('agricultural', 'mixed'):
        if income_type == 'mixed':
            agri_base = max(0.0, _f(agricultural_income if agricultural_income is not None else 0.0))
        else:
            agri_base = income
        agri_exempt = min(agri_base, AGRICULTURAL_EXEMPTION)
        if agri_exempt > 0:
            lines.append('Less: agricultural income exemption (first %s tax-free): -%s'
                         % (_money(AGRICULTURAL_EXEMPTION), _money(agri_exempt)))

    # 2. other exemptions / deductions the farmer entered
    if exemptions > 0:
        lines.append('Less: other exemptions / deductions: -%s' % _money(exemptions))

    threshold = TAX_FREE_THRESHOLD_SENIOR if is_senior else TAX_FREE_THRESHOLD
    income_after_exemptions = max(0.0, income - agri_exempt - exemptions)
    lines.append('Income after exemptions: %s' % _money(income_after_exemptions))
    lines.append('Less: tax-free threshold%s: -%s'
                 % (' (senior citizen)' if is_senior else '',
                    _money(min(income_after_exemptions, threshold))))

    above_threshold = max(0.0, income_after_exemptions - threshold)
    exemptions_applied = round(agri_exempt + exemptions, 2)

    if above_threshold <= 0:
        lines.append('Taxable income: %s' % _money(0))
        lines.append('Income tax payable: %s' % _money(0))
        lines.append('You are below the taxable limit — estimated income tax is zero.')
        return {
            'tax': 0.0, 'taxable_income': 0.0, 'threshold': threshold,
            'exemptions_applied': exemptions_applied, 'rebate_applied': 0.0,
            'breakdown': lines,
        }

    lines.append('Taxable income (amount above the threshold): %s' % _money(above_threshold))

    tax = 0.0
    remaining = above_threshold
    for width, rate in INCOME_TAX_SLABS:
        if remaining <= 0:
            break
        piece = remaining if width is None else min(remaining, width)
        slab_tax = piece * rate
        tax += slab_tax
        lines.append('  %s @ %s: %s' % (_money(piece), _pct(rate), _money(slab_tax)))
        remaining -= piece

    lines.append('Income tax before rebate: %s' % _money(tax))
    rebate_applied = min(rebates, tax)
    if rebate_applied > 0:
        lines.append('Less: investment rebate: -%s' % _money(rebate_applied))
    tax = max(0.0, tax - rebate_applied)
    lines.append('Income tax payable: %s' % _money(tax))

    return {
        'tax': _f(tax), 'taxable_income': _f(above_threshold), 'threshold': threshold,
        'exemptions_applied': exemptions_applied, 'rebate_applied': _f(rebate_applied),
        'breakdown': lines,
    }


def calculate_business_tax(revenue, expenses=0.0, deductions=0.0):
    """Corporate / business tax — TaxEase/businesscalcu.php.

    ``tax = max(net_profit * 27.5%, revenue * 0.6%)``; a loss still owes the
    0.6%-of-turnover minimum tax. Kept for completeness — the farmer flow uses
    :func:`calculate_income_tax` (personal slabs).
    """
    revenue = max(0.0, _f(revenue))
    expenses = max(0.0, _f(expenses))
    deductions = max(0.0, _f(deductions))
    net_profit = revenue - expenses - deductions
    minimum_tax = revenue * MINIMUM_TAX_ON_TURNOVER

    lines = [
        'Gross revenue: %s' % _money(revenue),
        'Less: expenses and deductions: -%s' % _money(expenses + deductions),
        'Net profit: %s' % _money(net_profit),
        'Minimum tax (%s of revenue): %s' % (_pct(MINIMUM_TAX_ON_TURNOVER), _money(minimum_tax)),
    ]
    if net_profit > 0:
        on_profit = net_profit * CORPORATE_TAX_RATE
        lines.append('Tax on profit (%s): %s' % (_pct(CORPORATE_TAX_RATE), _money(on_profit)))
        tax = max(on_profit, minimum_tax)
    else:
        lines.append('Business made no profit — minimum tax applies.')
        tax = minimum_tax
    lines.append('Business tax payable: %s' % _money(tax))
    return {'tax': _f(tax), 'net_profit': _f(net_profit),
            'minimum_tax': _f(minimum_tax), 'breakdown': lines}


# ── land tax ────────────────────────────────────────────────────────────────

def calculate_land_tax(land_area, land_unit='katha', location='rural',
                       land_use='agricultural'):
    """Annual land development tax estimate.

    Returns ``{tax, decimals, taxable_decimals, rate_per_decimal, exempt, breakdown}``.
    """
    area = max(0.0, _f(land_area))
    land_unit = (land_unit or 'katha').lower()
    location = (location or 'rural').lower()
    land_use = (land_use or 'agricultural').lower()
    if location not in LOCATIONS:
        location = 'rural'
    if land_use not in LAND_USES:
        land_use = 'agricultural'

    per_unit = LAND_UNIT_TO_DECIMAL.get(land_unit, 1.0)
    decimals = area * per_unit

    lines = ['Land: %g %s = %s decimal (%s, %s area)'
             % (area, land_unit, '{:,.1f}'.format(decimals), land_use, location)]

    rate = LAND_TAX_PER_DECIMAL.get((land_use, location),
                                    LAND_TAX_PER_DECIMAL.get((land_use, 'rural'), 5.0))

    taxable_decimals = decimals
    if land_use == 'agricultural':
        exempt_decimals = AGRI_LAND_EXEMPT_BIGHA * LAND_UNIT_TO_DECIMAL['bigha']
        applied = min(decimals, exempt_decimals)
        taxable_decimals = max(0.0, decimals - applied)
        lines.append('Less: farming-family exemption (first %g bigha = %s decimal): %s decimal exempt'
                     % (AGRI_LAND_EXEMPT_BIGHA, '{:,.0f}'.format(exempt_decimals),
                        '{:,.1f}'.format(applied)))

    tax = taxable_decimals * rate
    if taxable_decimals <= 0:
        lines.append('Your land is fully exempt from land development tax.')
    else:
        lines.append('%s decimal @ BDT %g per decimal per year: %s'
                     % ('{:,.1f}'.format(taxable_decimals), rate, _money(tax)))

    return {
        'tax': _f(tax), 'decimals': _f(decimals), 'taxable_decimals': _f(taxable_decimals),
        'rate_per_decimal': rate, 'exempt': taxable_decimals <= 0, 'breakdown': lines,
    }


# ── vehicle tax ─────────────────────────────────────────────────────────────

def _vehicle_key(raw):
    key = str(raw or '').strip().lower().replace(' ', '_').replace('-', '_')
    if key in VEHICLE_TAX:
        return key
    return VEHICLE_ALIASES.get(key)


def calculate_vehicle_tax(vehicles):
    """Annual vehicle tax estimate.

    ``vehicles`` is a list of ``{"type": str, "count": int}``. Unknown types are
    skipped (listed in the breakdown); agricultural vehicles are 0.
    Returns ``{tax, items, breakdown}``.
    """
    vehicles = vehicles or []
    total = 0.0
    items = []
    lines = []

    for entry in vehicles:
        entry = entry or {}
        raw_type = entry.get('type') or entry.get('vehicle_type') or ''
        try:
            count = int(entry.get('count', 1) or 1)
        except (TypeError, ValueError):
            count = 1
        count = max(0, count)
        key = _vehicle_key(raw_type)
        pretty = str(raw_type).strip() or 'unknown'

        if key is None:
            lines.append('%d x %s: not a recognised vehicle type — skipped' % (count, pretty))
            continue

        rate = VEHICLE_TAX[key]
        line_total = rate * count
        total += line_total
        items.append({'type': key, 'count': count, 'rate': _f(rate), 'amount': _f(line_total)})
        label = key.replace('_', ' ')
        if rate == 0:
            lines.append('%d x %s: exempt (BDT 0)' % (count, label))
        else:
            lines.append('%d x %s @ %s/year: %s' % (count, label, _money(rate), _money(line_total)))

    if not lines:
        lines.append('No vehicles recorded.')
    return {'tax': _f(total), 'items': items, 'breakdown': lines}


# ── combined ────────────────────────────────────────────────────────────────

def calculate_total_tax(revenue_breakdown=None, assets=None, income_type='agricultural',
                        exemptions=0.0, rebates=0.0, is_senior=False, expenses=0.0):
    """Estimate a farmer's total tax for the year.

    ``revenue_breakdown`` — ``{"Bird Sales": 500000, "Egg Sales": 200000, ...}``
    ``assets`` — ``{"land_area", "land_unit", "location", "land_use", "vehicles"}``

    Poultry/livestock sales are agricultural income, so the total revenue is
    netted against ``expenses`` and taxed with the personal slab rules.
    Returns ``{income_tax, land_tax, vehicle_tax, total, breakdown, ...}``.
    """
    revenue_breakdown = revenue_breakdown or {}
    assets = assets or {}

    total_revenue = sum(max(0.0, _f(v)) for v in revenue_breakdown.values())
    expenses = max(0.0, _f(expenses))
    net_income = max(0.0, total_revenue - expenses)

    income = calculate_income_tax(
        net_income, income_type=income_type, exemptions=exemptions,
        rebates=rebates, is_senior=is_senior,
        agricultural_income=(net_income if income_type == 'mixed' else None))
    land = calculate_land_tax(
        assets.get('land_area', 0), assets.get('land_unit', 'katha'),
        location=assets.get('location', 'rural'),
        land_use=assets.get('land_use', 'agricultural'))
    vehicle = calculate_vehicle_tax(assets.get('vehicles', []))

    total = _f(income['tax'] + land['tax'] + vehicle['tax'])

    breakdown = []
    if revenue_breakdown:
        breakdown.append('REVENUE')
        for name, value in revenue_breakdown.items():
            breakdown.append('  %s: %s' % (name, _money(value)))
        breakdown.append('  Total revenue: %s' % _money(total_revenue))
        if expenses:
            breakdown.append('  Less: farm expenses: -%s' % _money(expenses))
        breakdown.append('  Net farm income: %s' % _money(net_income))
        breakdown.append('')
    breakdown.append('INCOME TAX')
    breakdown += ['  ' + line for line in income['breakdown']]
    breakdown += ['', 'LAND DEVELOPMENT TAX']
    breakdown += ['  ' + line for line in land['breakdown']]
    breakdown += ['', 'VEHICLE TAX']
    breakdown += ['  ' + line for line in vehicle['breakdown']]
    breakdown += ['', 'ESTIMATED TOTAL TAX FOR THE YEAR: %s' % _money(total)]

    return {
        'tax_year': TAX_YEAR,
        'total_revenue': _f(total_revenue),
        'net_income': _f(net_income),
        'income_tax': income['tax'],
        'land_tax': land['tax'],
        'vehicle_tax': vehicle['tax'],
        'total': total,
        'income': income,
        'land': land,
        'vehicle': vehicle,
        'breakdown': breakdown,
    }
