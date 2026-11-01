# `seed_platform_demo` fix report

**Nothing was committed** (HEAD is still `6a036eb`). A pre-change backup of the dev DB is at `audit_logs/db_backup/featherflow_pre_seedfix_20261001.dump`; run output and row-count snapshots are in `audit_logs/seedfix/`.

## 1. Cause

**Farm uniqueness rules (actual):** the `farms` table had only its primary key and a `farmer_id → farmer_profiles` FK (`ON DELETE CASCADE`). No unique constraint, so a farmer may own several farms *and* several farms with the same name. `workers.farm_for` therefore picks "the" farm by an ordering rule rather than by key.

**Why the command crashed (reproduced on the dev DB, rolled back by its `@atomic`):**

```
OLD SEED FAILED: MultipleObjectsReturned get() returned more than one Farm -- it returned 2!
```

* `Farm.objects.get_or_create(farmer=fp, farm_name=farm_name, …)` assumes (farmer, name) is unique — but the dev DB held two farms named *"Rashed Poultry Farm"* for `farmer.rashed@example.com`. Both rows existed because earlier runs/tests and `farm_for` created farms with different code paths and **no `created_at`/`updated_at`** (the unmanaged model has no `auto_now_add`), so nothing could tell them apart or stop the second insert.
* `farmer.nasima@example.com` also owns two farms, but with **different** names ("Nasima Akter Farm" — created by the farmer panel, with data — and "Shapla Layer Farm" from the seed). That is legitimate (a farmer may own several farms) and was left alone.

**Dependents of the four farms involved** (all 11 FK tables checked): the dated Rashed farm and "Nasima Akter Farm" hold the real data (workers, sheds, flocks, feed stock, expenses, revenues, loans, 20 disease scans, …); the **duplicate Rashed row and "Shapla Layer Farm" had zero dependents**.

**Other idempotency defects found in the same command** (they violated the stated requirements): every `update_or_create` overwrote existing rows — `account_status`/`is_verified` (this is what re-activated suspended users), passwords (`set_password` on every run), farmer/doctor/pharmacy/rider/researcher/admin profiles incl. approval flags, tax profiles and medicine price/stock; and a demo phone already used by another account would crash the whole run.

## 2. Cleanup decision (existing data)

* **No blind deletes.** New `python manage.py dedupe_farms` is dry-run by default. `--apply` deletes a farm only if it is an **exact duplicate** (same farmer + same name, case/space-insensitive) of the canonical farm **and no row in any FK table references it**. A duplicate with dependents is reported `REVIEW` and never deleted or merged. Differently named farms are reported as legitimate and untouched.
* Applied to the dev DB (after the backup): **exactly 1 row deleted** — the empty duplicate `99fc88fd-…` of "Rashed Poultry Farm". The kept farm (`71fc8906-…`) retains all its dependents (verified: 0 orphans). Nasima's two differently named farms were left as they are.

## 3. Changes

| File | Change |
|---|---|
| `backend/farms/services.py` (new) | `canonical_farm()` (active first, oldest, NULL `created_at` last, id — the rule `farm_for` always used), `ensure_farm()` (reuse the farmer's farm if any, create only when none, never modify), `dependent_counts()`. |
| `backend/workers/views.py` | `farm_for` uses the shared `canonical_farm` and now stamps `created_at/updated_at` on farms it creates. |
| `backend/farms/management/commands/dedupe_farms.py` (new) | the safe duplicate report/cleanup above. |
| `backend/farms_natural_key_extension.sql` (new, idempotent) | `CREATE UNIQUE INDEX uq_farms_farmer_name ON farms (farmer_id, lower(btrim(farm_name)))` — natural key; a farmer may still own several differently named farms. Applied to the dev DB after the dedupe and to the scratch DB. |
| `backend/users/management/commands/seed_platform_demo.py` | **Create-only.** Users matched by e-mail and returned untouched when they exist (status, verification, password, name preserved); every profile/tax/medicine row is `get_or_create` (medicines on the natural key `(pharmacy_user, legacy_record_id)`); the farm goes through `ensure_farm` (deterministic, never a second row); the rider approver lookup is ordered; a demo phone owned by another account no longer aborts the run — a stable unused phone is derived from the e-mail and a `note:` is printed. |

No Django migration is involved (all these tables are unmanaged; schema changes live in the `*_extension.sql` files).

## 4. Tests — `backend/scripts/test_seed_platform_demo.py` → **46 passed, 0 failed**
Runs only on a scratch DB (it refuses the main DB) and rolls every scenario back, so it is repeatable: `POSTGRES_DB=featherflow_clean python scripts/test_seed_platform_demo.py`.

* **A. clean slate:** first, second and third run; row counts identical after run 1; two farmers → one distinct farm each; one farmer profile each; 6 catalogue medicines once; pending accounts stay pending; no duplicate e-mails/farms/medicine products.
* **B. existing records:** a *suspended* demo farmer with her own password, edited profile and an edited farm with a dependent shed, plus an unrelated farmer with two farms: all three runs succeed; stays suspended/unverified; password/name/profile/farm unchanged; no second farm; dependent still points at the same farm, 0 orphans; unrelated farmer untouched; only the missing demo rows are added.
* **C. legacy exact-duplicate farms (the original crash):** three runs succeed and create nothing; canonical farm deterministic; `dedupe_farms` dry-run deletes nothing; `--apply` removes only the empty duplicate; a duplicate with dependents is never deleted; the unique index refuses to build while one remains, then builds and blocks new (case-insensitive) duplicates; seed still succeeds with the index.
* **D. phone collision:** three runs succeed; the other account keeps its phone; demo account created once.
* **Mutation check:** with the old command restored, the suite fails (suspended user reactivated, password/profile overwritten, `MultipleObjectsReturned`); with the fix 46/0.

Regression: `manage.py check` clean, `migrate --check` exit 0, all 48 other `backend/scripts/test_*.py` pass, `flutter analyze` unchanged (6 pre-existing infos).

## 5. Three runs on the real dev DB (after cleanup + index)

```
=== RUN 1 ===  exit 0   note: demo phone for admin.pharmacy@example.com was taken by another account; used +880195424114
=== RUN 2 ===  exit 0
=== RUN 3 ===  exit 0
```
Row counts vs. before the first run (`counts_0N_*.json`, every table compared):

| After | Tables changed |
|---|---|
| run 1 | `users 107→108`, `user_roles 108→109`, `admin_profiles 35→36` (the one demo account `admin.pharmacy@example.com` that had never been created because the old command always crashed) and `farms 14→13` (the single deleted empty duplicate) |
| run 2 | identical to run 1 → **0 changes by the seed** |
| run 3 | identical to run 1 → **0 changes by the seed** |

The set of non-active users is byte-identical before and after (`research.sabiha@example.com` and `smoke.pharmacy@featherflow.dev` stay **suspended**, the pending vet stays pending). Farms: Rashed → `['Rashed Poultry Farm']`, Nasima → `['Nasima Akter Farm', 'Shapla Layer Farm']`. The dev DB's `admin.pharmacy@example.com` phone is `+880195424114` because `+8801711000606` belongs to the real `pharmacy.admin@featherflow.local`.

## 6. Notes
* `seed_research_demo` (which re-activated `research.sabiha` in the original audit) uses the same `update_or_create` pattern and was **not** changed here; it is outside this task and F-015 stays open for the other seeds.
* Because the seed no longer updates existing rows, changes to the demo definitions apply only to *new* accounts; to refresh an old demo account, edit it or delete it deliberately.

## 7. Confirmation
Verified by the new regression suite (with a mutation check), the existing suites, and three real runs against the dev database with before/after row-count comparison. **Nothing was committed.**
