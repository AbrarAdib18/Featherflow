# Featherflow post-gate / final release-gate report

**Status - Ready for commit review: yes. Ready to push: NO (the Maps key must be revoked/rotated at Google and the final diff reviewed). Ready for production release: NO. Complete: NO.**

**Verdict: ready for COMMIT REVIEW of the working tree - NOT release-ready and NOT "complete".** Every repository-side item is resolved and verified, but three release blockers need owner action that I cannot perform: rotating the exposed Google key, owner sign-off on the deferred faults, and (before production) F-026 / F-037 / F-022-if-refunds. Nothing was committed, staged or pushed.

```
Baseline commit:   6a036eb "Sub-admin roles fixed"  (re-checked at the end: unchanged, 0 files staged)
Working tree:      103 modified tracked files (+6,706 / -1,430), 119 untracked paths; audit_logs/ is git-ignored
Databases:         full matrix on a FRESH database `featherflow_matrix` (bootstrap + demo seeds, not a clone); tests on throw-away
                   databases built by the F-014 bootstrap. Development DB `featherflow` and `featherflow_retest` unchanged (proof below).
                   ALL scratch databases dropped (only `featherflow` and the preserved baseline `featherflow_retest` remain).
Servers:           uvicorn API :8000 + release web build :8080 (Maps key from the git-ignored web/config.js); all stopped.
Date/time:         2026-10-02, final checks ~23:40 BST
```

## Gate commands (`audit_logs/final/`)

| Command | Result |
|---|---|
| `python manage.py check` | no issues (exit 0) |
| `python manage.py migrate --check` | exit 0 |
| `python manage.py test` | `COLLECTED 40 \| RAN 40 \| PASSED 40 \| FAILURES 0 \| ERRORS 0 \| SKIPPED 0` |
| `flutter analyze` | No issues found |
| `flutter test` | 316 passed, 0 failed |
| `flutter build web --release` | built (`build\web`) |

## Script suites

```
Command:    python scripts/run_all_tests.py   (throw-away databases only)
Output:     audit_logs/final/run_all_tests.log   (EXIT=0, RUNTIME_SECONDS=233, "RESULT: all green")
Suites:     52 script files + the Django suite
Assertions: 2082 passed
Failures:   0     Errors: 0     Skips: 0 (no skip mechanism)     Flakes: none
```

## Full eight-role matrix (`FEATHERFLOW_FULL_MATRIX_REPORT.md`, evidence `audit_logs/matrix/`)

166 of 184 recorded steps pass; the 18 that do not are all explained in that report (script assertions tied to the old retest data; the application state was verified correct each time). Roles: Farmer, Suspended pharmacy, Pharmacy Admin (+ active owner, empty pharmacy), Feed Admin, Feed Inventory Owner, Doctor, Researcher, Delivery person - each driven through the Chrome UI on the fresh database. All nine explicit checks pass: empty pharmacy does not fabricate records after repeated GETs (UI x3 + 5 API repetitions, zero rows); suspended pharmacy stays suspended after every demo seed was run three times on the used database (0 table changes, identical user rows); correct map order with several deliveries (chooser, A, B, refresh keeps B, stale-ID); feed checkout persists the location (six orders); expired assignments are released, idempotently; research revision request through the UI; doctor notes edited and audited; proof approval idempotent (409, one earning, one expense, one sale/commission); null appointment time does not crash Doctors & Patients.

**The matrix found and I fixed six defects (each with a regression test; details in the matrix report):** (1) **delivered pharmacy orders created no sale/commission - the pharmacy Sales & Settlements screens were empty (this is F-024; a regression of the F-005 proof workflow)** - fixed in `delivery/views.py`, plus a `backfill_pharmacy_sales` command; (2) prescriptions for a consultation with no case-detail row returned 500 after the transaction; (3) `seed_farmer_demo_data` was not idempotent when another farmer existed; (4) `seed_research_demo` created users that could not sign in and crashed after real revision snapshots; (5) demo seeds (known-password admin accounts) could run in production - now refuse unless DEBUG or `ALLOW_DEMO_SEED=1`; (6) the shared Maps key (below). **Existing databases:** run `python manage.py backfill_pharmacy_sales --dry-run` then without `--dry-run` to repair financial records for orders delivered since F-005.

## Maps key (`MAPS_KEY_SECURITY_REPORT.md`)

Repository side **done**: no key in `web/index.html` (loaded from the git-ignored `web/config.js`, template `web/config.example.js`), Android reads `MAPS_API_KEY` (manifest placeholder; **Android build not run here**), the backend no longer falls back to the browser key (dedicated `GOOGLE_ROUTES_API_KEY`), `build/web` contains the key only in `config.js`. **Owner action outstanding:** I could not touch the Google Cloud Console. The key has been in published git history since 2026-09-06 and a test showed it has **no HTTP-referrer restriction** (it answered a Routes API call with a foreign Referer). **Decision recorded: rotate (create three restricted keys - browser / Android / server - then delete the old key).** Not verifiable here: production behaviour after rotation.

## Deferred faults (`FEATHERFLOW_FAULT_REGISTER.md`, "Final disposition")

Every deferred fault now has severity, user impact, security/data impact, workaround, owner (role), target, acceptance criteria and a "blocks" decision. **Blocks production:** F-026 (login throttle), F-037 for admin roles (2FA), F-022 if refunds/receipts are offered (financial records kept in the JSON bridge). **Do not block:** F-016, F-018, F-021 (release note: calls unaudited), F-027, F-028 (all endpoints verified to require a token), F-031, F-032. Verified closed in this pass: F-023, F-024 (fixed), F-036, F-029 (code/seed; legacy dev rows need a data fix). None is marked "accepted" - the owner must sign off.

## Unsafe-file and hygiene review

* **Ignored and not staged:** `audit_logs/` (92 MB, database dumps), `backend/scripts/_create_*.py`, `web/config.js`, `backend/.env`, build output (`/build/`), logs. 0 files staged.
* **Helper scripts:** `_create_missing_admin_accounts.py`, `_create_pharmacy_admin.py`, `_create_pharmacy_admin_2.py` no longer contain a default password (they require `ADMIN_BOOTSTRAP_PASSWORD` or an interactive prompt, minimum 12 characters) and are git-ignored.
* **Removed:** a stray log file `x` created at the repository root by one of my helper scripts (twice; the script paths are fixed and `/x` is ignored). **`pubspec.lock` was modified by `flutter pub get`/test runs (transitive minor version bumps) and was restored to HEAD; it will drift again whenever Flutter re-resolves - do not commit it unless you intend to upgrade dependencies.**
* **Secrets scan:** no key or credential added to tracked/untracked code. The only `AIza...` strings are obviously fake test values in `scripts/test_delivery_route.py`; demo passwords exist only in the demo seed commands, which are now guarded.
* `.env.example` (two variables, no secrets) and `DATABASE_SETUP.md` (points to the SQL manifest) are accurate. `git diff --check`: no whitespace errors (only the repository's LF->CRLF warnings).
* **Changed tracked files outside `backend/`, `lib/`, `test/`:** `.gitignore`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `web/index.html` (all Maps-key related) - review these three Android/web edits together.

## Database safety

| Database | Before | After | Verdict |
|---|---|---|---|
| `featherflow` (development) | 122 tables, 37,125 rows, schema hash H | same counts per table, same schema hash | unchanged (`audit_logs/final/fp_featherflow.json`) |
| `featherflow_retest` (preserved baseline) | 36,081 rows | identical per-table counts | unchanged |
| scratch (`featherflow_matrix`, `_nf`, `_f015`, `_clean`, runner DBs) | - | **dropped** | none remain |

**Disclosure:** while editing the seed guard I ran `seed_research_demo` once, by mistake, without selecting a scratch database, so it executed against the development database (it is create-only). A fingerprint taken immediately afterwards shows no row-count or schema change (`audit_logs/gate/fp_featherflow_after_seed_slip.json`), and the final fingerprint is identical to the pre-work one.

## API-assisted steps / test-data side effects / aborted runs

* **ORM set-up (labelled):** fresh farmer and riders, suspended and empty pharmacies, doctor prescription authority, verified contacts for three seeded research users. **API checks (labelled):** duplicate proof approval, negative permission calls, API repetition for F-004; HTTP 500 / empty-list stubs in Doctors & Patients. No NF-3..NF-7 verification relied on an API call.
* **Side effects:** all matrix data lived in the dropped `featherflow_matrix`. Earlier disclosed one-offs stand (`close_stale_shifts` closed `ops.nusrat`'s stale shift on the dev DB; an accidental pharmacy proof approval inside `featherflow_retest`).
* **Aborted runs** are preserved, not counted: `audit_logs/{nf,nf56,regr,matrix,retest}/aborted_runs` (harness faults: wrong product in the two-column grid, expired offers, wrong rider regex, missing fixture files, assertion literals).

## Release gate checklist

| Condition | Status |
|---|---|
| All six gates pass | **yes** |
| All 52 script suites pass | **yes** (2082 assertions, 0 failures) |
| Full matrix passes | **yes** (166/184 steps; all 18 non-passes explained; six defects found and fixed) |
| Maps key restricted or rotated | **NO - repository fixed, owner must rotate in Google Cloud** |
| Deferred faults have explicit dispositions | **yes** (decisions written; owner sign-off still required) |
| No unsafe helper scripts, credentials, dumps or logs staged | **yes** (0 staged; helpers sanitised and ignored) |
| Development database unchanged | **yes** (and the one slip disclosed) |
| Scratch databases dropped | **yes** |
| HEAD remains `6a036eb` | **yes** |

## Recommendation

1. Review the diff for commit **now** (suggested split: backend fixes + SQL; Flutter fixes + tests; test infrastructure/`TESTING.md`; Maps-key/config files; reports - and never `audit_logs/`, `web/config.js`, `.env`, `pubspec.lock`).
2. **Before any push:** rotate the Google key (the published history already exposes it); the commit does not make that worse but the push of new history changes nothing about the old exposure.
3. Get the owner's sign-off on the deferred table; schedule F-026 and F-037 (admin) before production, and F-022 if refunds/receipts ship.
4. Run `backfill_pharmacy_sales` on any existing database that has delivered pharmacy orders.
5. Do not describe the project as complete until items 2-3 are done.

## Owner decisions applied (post-gate)

* **Maps key:** treated as compromised. **Not yet done (needs the Google Cloud Console, which I cannot access):** create the browser / Android / server keys, update deployment secrets, delete or disable the old key, show that the old key fails with a foreign Referer, verify web routing, Android configuration and backend routing with the new keys. Repository search done: the **only** key-shaped string anywhere in Git history is the one old key (1 distinct value); the working tree (tracked + untracked, ignored files excluded) contains only the fake test keys in `scripts/test_delivery_route.py`. No new exposure.
* **F-026, F-037 (admin), F-022 (while refunds/receipts are offered): production blockers, not accepted.** **F-029 stays open** until the legacy-row data correction is run and verified. **F-016, F-018, F-021, F-027, F-028, F-031, F-032:** scheduled work with owner, target, workaround, acceptance criteria and release decision in the register, **awaiting the project owner's explicit sign-off.** (`FEATHERFLOW_FAULT_REGISTER.md`, "Release decisions".)

## Pre-commit checks run now (rotation-independent)

* `git ls-files` for `audit_logs/`, `.env`, `web/config.js`, `_create_*.py`, `build/web/`, dumps: **only one hit - `backend/db.sqlite3` is a TRACKED file** (a legacy SQLite data snapshot committed in `e57cbda`, 197 KB, unmodified in the working tree). It is a database file and `.gitignore` already lists `*.sqlite3`, so it is tracked only because it was added before the rule. It is not part of this diff; decide separately whether to `git rm --cached` it (it contains legacy user data, so I would). Nothing else matches; 0 files staged; `pubspec.lock` is unchanged (left uncommitted); `git diff --check` clean; HEAD `6a036eb`.
* **Not rerun on purpose:** the final gate/suite rerun the owner asked for is scheduled *after* key rotation and configuration verification (the new keys change `web/config.js`, `backend/.env` and Android configuration). The last full run (previous section) predates only report edits.
* **`backfill_pharmacy_sales --dry-run` on the development database** (read-only; target `featherflow`, development, no production database touched): it would create **128** sales for delivered pharmacy orders that have none (0 already exist). I did **not** run the real backfill. Run it only on a database you have explicitly confirmed and backed up; do not run it against production until the target and backup are confirmed.
