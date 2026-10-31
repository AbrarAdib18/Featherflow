# FEATHERFLOW — Data Restoration Report

Date: 2026-10-01. Scope: undo the unintended side effects documented in `FEATHERFLOW_FAULT_REGISTER.md` (S-3 … S-6) in the live dev database `featherflow` (PostgreSQL 17.11, `localhost:5432`). **No product code was changed. Nothing was committed** (HEAD still `6a036eb`; tracked-file diff unchanged at 37 modified files).

## 1. Backup (taken before any change)

| Item | Value |
|---|---|
| File | `D:\Featherflow Final\audit_logs\db_backup\featherflow_pre_restore_20261001.dump` |
| Command | `pg_dump.exe -h localhost -p 5432 -U postgres -Fc -f <file> featherflow` (password via `PGPASSWORD`, not recorded) |
| Size / SHA-256 | 2,290,971 bytes / `35038AEEB9D42B814875D383928C46DA39F54A5BBA67C58DBCAE4092E0338AB2` |
| Validation | `pg_restore -l` lists 927 TOC entries; `pg_dump` exit 0 |
| Restore if needed | `pg_restore -U postgres -d featherflow --clean --if-exists <file>` |
| Row-level safety copies | `audit_logs/db_backup/restore_before_values.json` (before values + deleted notification/history rows), `removed_fabricated_pharmacy_records.json` (all 29 deleted rows, full payloads), `restore_after_and_sql.json` (SQL log + after values) |

Note: the backup contains the damaged state (taken after the crawl), by design — it is the rollback point for *this* restoration. The un-damaged pre-audit state was reconstructed from audit-log rows, earlier status counts and row signatures (below).

## 2. Method and evidence

Schema was read from `information_schema` first (e.g. `delivery_orders(status, failure_reason, …)`, `reports(status, reviewed_by, …)`, `consultation_status_history(from_status, to_status, …)`, `activity_logs(user_id, action, old_value, new_value, …)`, `backend_admin_records(module, record_id, payload JSON, …)`) — no column names were guessed. The restore ran as one Postgres transaction (`transaction.atomic`) with **row-count assertions** (the script aborts and rolls back unless each statement affects exactly the expected rows) — script kept at `audit_logs/tools/restore.py`.

## 3. Records restored

| # | Record | Before (audit-damaged) | After (restored) | Evidence for the original value |
|---|---|---|---|---|
| 1 | `delivery_orders` `1590748f-d9d4-4f60-9763-b270985d546c` (medicine, QA fixture) | `status='cancelled'`, `failure_reason='Cancelled by admin.'` | `status='pending'`, `failure_reason=NULL` | Audit rows "Cancel queued request / Cancel" 10:13–10:15 UTC; before the crawl the table held exactly **4 `pending`** rows (status count captured earlier: pending 4, cancelled 7) and after the crawl **0 pending / 11 cancelled**; all four ids were the ones cancelled; delivery queue = status `pending` |
| 2 | `5e3dd2a1-b5ec-42da-a5cd-0d32d69e23e8` (feed order #FD-E50E96) | same | same restore | same |
| 3 | `1b2c9453-f03e-4205-b94b-e15100972c81` (feed order #FD-E8CF1D) | same | same restore | same |
| 4 | `09463453-e9d4-4017-a158-83d1af8dc078` (medicine, Manual Verify Farm) | same | same restore | same |
| 5 | `notifications` ×4 titled "Delivery cancelled" (ids `be857288…`, `2871bcd6…`, `486e12f1…`, `3f179eff…`, created 10:13–10:15, all `is_read=false`) | present | **deleted** (created only by the crawl's cancel action) | `reference_id` = the four order ids |
| 6 | `reports` `1b99d316-5dff-4f8e-b3f9-f7117e8efe33` (article report) | `status='reviewed'`, `reviewed_by=f63ef25c…` (10:11:11 UTC "Report dismiss") | `status='pending'`, `reviewed_by=NULL` | earlier status count: `reports: pending 1`; this is the only report row |
| 7 | `consultations` `c31dd3fb-05f7-476e-bbf0-c50919adf20c` | `status='no_show'` | `status='accepted'` | `consultation_status_history` row `2dd29184…` recorded `accepted → no_show` at 10:10:08 UTC |
| 8 | `consultation_status_history` `2dd29184-3b31-4c0c-a4e1-a2412797dd0c` | present | **deleted** (the crawl-generated transition) | — |
| 9 | `notifications` "Consultation no_show" to the farmer (10:10:08) | present | **deleted** | — |
| 10 | `users` `research.sabiha@example.com` | `account_status='active'` (re-activated by `seed_research_demo`) | `account_status='suspended'` | pre-seed login → 401; `users` table verified first (`account_status` column exists). Exact SQL used below |
| 11 | `backend_admin_records` — **29 fabricated pharmacy rows** (see §4) | present | **deleted** | strict fixed-id signature, see §4 |

Verification after commit: delivery status counts `delivered 13, rejected 9, cancelled 7, pending 4, failed 2, on_the_way 1` (identical to the pre-crawl counts); `reports: pending 1`; consultations `accepted 5, no_show 2, …` (identical to pre-crawl); non-active users = `bookrule+inactive-vet` (pending), `smoke.pharmacy` (suspended), `research.sabiha` (suspended); 0 rows with the fabricated ids remain; 0 orphan status-history rows.

## 4. Fabricated pharmacy records removed (GET-handler fallback `_seed()` in `pharmacy/views.py`)

Signature (all must match): `module ∈ {pharmacy-products, pharmacy-orders, medicines}` **and** `payload.id ∈ {MED-001, VAC-001, SUP-001, EQP-001}` (products/medicines) or `{ORD-001, ORD-002, ORD-003}` with `payload.farmer_id ∈ {F001, F002, F003}` (non-UUID demo farmer ids, "Karim Hossain / Jamal Mia / Salma Akter"), and `record_id` = `<owner-uuid>:<id>` for per-owner rows. No other table references these rows (`expenses.source_pharmacy_order_id`, `notifications.reference_id`, `payments.reference_id`, `delivery_orders.order_reference_id`: 0 hits; `medicine_order_items` empty).

| Group | Created | Rows deleted |
|---|---|---:|
| `admin.super@example.com` ("Owner Admin") — 4 products + 3 orders | 2026-10-01 09:58:23 (**this audit's GET sweep**) | 7 |
| `pharmacy.agrocare@example.com` — 4 products + 3 orders | 2026-10-01 09:58:24 (**this audit's GET sweep**; AgroCare had none before) | 7 |
| `pharmacy.greenvet@example.com` — 4 products + 3 orders (ORD-001 was later edited by a developer test on 09-20, still fabricated) | 2026-09-10 12:47:20 (earlier fallback, pre-audit) | 7 |
| deleted test user `378f6127-…` (no `users` row exists) — 4 products | 2026-09-20 18:22:23 (earlier fallback, pre-audit) | 4 |
| shared `medicines` admin-approval records MED/VAC/SUP/EQP-001 (owner overwritten to AgroCare by the audit sweep, status "Approved") | first created 2026-09-10, last overwritten 2026-10-01 09:58:24 | 4 |
| **Total** | | **29** |

Effect: `pharmacy-orders` 316 → 307, `pharmacy-products` 18 → 2, `medicines` 10 → 6. Real data kept: GreenVet's other 32 orders (`ORD-<hex>` ids), AgroCare/others' real catalogue, `SMOKE-MED` and `Playwright…` test products (test fixtures, **not** fabricated by `_seed`, left in place — see F-011), `PRIVDOC-ORD-…` fixtures.

**Caveat:** `_seed()` is still in the code. The next `GET /api/pharmacy/{dashboard,orders,medicines,…}` by a pharmacy (or admin) with no `pharmacy-products` records will recreate the fabricated rows (this will happen to AgroCare as soon as its owner opens the panel) until fault F-004 is fixed in code. Fixing the product behaviour is the next task and was deliberately not done here.

## 5. Exact SQL / commands

```sql
-- all inside one transaction, each with an asserted row count
UPDATE delivery_orders SET status='pending', failure_reason=NULL
 WHERE id::text = ANY(<4 ids>) AND status='cancelled' AND failure_reason='Cancelled by admin.';              -- 4
DELETE FROM notifications WHERE id::text = ANY(<4 "Delivery cancelled" ids>);                                -- 4
UPDATE reports SET status='pending', reviewed_by=NULL
 WHERE id::text='1b99d316-5dff-4f8e-b3f9-f7117e8efe33' AND status='reviewed';                                -- 1
UPDATE consultations SET status='accepted'
 WHERE id::text='c31dd3fb-05f7-476e-bbf0-c50919adf20c' AND status='no_show';                                 -- 1
DELETE FROM consultation_status_history
 WHERE id::text='2dd29184-3b31-4c0c-a4e1-a2412797dd0c' AND from_status='accepted' AND to_status='no_show';   -- 1
DELETE FROM notifications WHERE id::text = ANY(<1 "Consultation no_show" id>);                               -- 1
UPDATE users SET account_status = 'suspended' WHERE email = 'research.sabiha@example.com';                   -- 1
DELETE FROM backend_admin_records
 WHERE id::text = ANY(<29 ids>) AND module IN ('pharmacy-products','pharmacy-orders','medicines');           -- 29
```
Python/Django cursor was used (`backend/venv`, `audit_logs/tools/restore.py`); the full parameter log is in `audit_logs/db_backup/restore_after_and_sql.json`. Read-only inspection queries (schema, audit rows, signatures) are in the audit scratch tooling; `activity_logs` rows were only read.

## 6. Records intentionally left unchanged

* **Audit trail:** all `activity_logs` rows for the cancel / dismiss / assign actions and my logins are kept (they truthfully record what happened). They now show actions whose effects were reversed; `reports.updated_at` (10:11:11) and `consultations.updated_at` (10:10:08) still carry the audit time because the original timestamps were not recorded.
* **Seed-created data (identified, left in place):** `seed_finance_demo_data` created users `financedemo+user1..4@example.com` (role farmer) and, at 2026-10-01 10:01:51: `payments` +4 (1200/3400/2500 pending, 800 completed, bkash), `revenue_entries` +4 (299, 599, 4999, −4999), `cashout_reviews` +4 (requested, under_review, approved, paid), `subscription_plans` +4 (ids 7–10: Free, Monthly Basic, Monthly Premium, Yearly), plus matching `subscriptions`; `seed_pharmacy_demo_data` created `pharmacy_suppliers` +2 (`sales@agrovetdist.example.com`, `orders@poultryhealth.example.com`, 10:01:47). These are demo fixtures with no link to real farms/orders, but they are indistinguishable from real rows to any report, so the owner should decide whether to keep them. Not deleted: the brief limited removals to fabricated pharmacy data and forbids touching financial records.
* **Real/legit data not touched:** all farms, flocks, expenses, revenues, loans, consultations (other than c31dd3fb), real pharmacy orders, users, roles.
* **Admin shifts** (S-1) and **rider availability** (S-2) were already reversed earlier through the product API and not changed again. `ops.nusrat` stale shift (since 2026-09-16) is pre-existing and untouched (F-020).
* Pre-existing test pollution (`Playwright…`, `Smoke…` medicines, `selftestfc6b19@x.com`, duplicate farms) — untouched.
* Notifications marked read by the crawl (farmer/doctor bell) — untouched (not recoverable, harmless).

## 7. Could not be safely restored

| Item | Why |
|---|---|
| Delivery-queue record `DQ-TEST-974864` (`backend_admin_records`, module `delivery-queue`) — **hard-deleted** by the crawl's "Cancel queued request" (HTTP 204) | The row's payload exists only in the deleted row; no backup predates the deletion. The id (`DQ-TEST-…`) and the 0-row `delivery-queue` module indicate a test fixture; no other table referenced it. Re-create via the app/test script if needed. |
| `users.created_at` overwritten by `seed_research_demo` for 5 existing users: `farmer.rashed`, `research.fariha`, `research.mahmud`, `research.sabiha`, `admin.research@example.com` (all now `2026-10-01 10:02:10.422167`) | Original values were not captured before the seed (only `farmer.rashed`'s `2026-08-21T03:52:00.091645` was seen in a login response). Not changed; flagged as seed overwriting real data (F-015). |
| Original `updated_at` of report `1b99d316…` and consultation `c31dd3fb…` | never recorded (see §6) |
| `medicines` records MED/VAC/SUP/EQP-001: original owner before the sweep overwrote it | rows were fabricated and deleted wholesale, so no value to restore |
| Exact pre-crawl `failure_reason` of the four delivery orders | inferred `NULL` (pending orders; no non-terminal row carries a reason) — not directly recorded |

## 8. Confirmation

No product code was modified; no files other than reports/evidence under `D:\Featherflow Final\audit_logs\` and this report were created; **nothing was committed** (`git log -1` = `6a036eb`).
