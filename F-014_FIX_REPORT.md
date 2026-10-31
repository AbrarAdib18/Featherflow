# F-014 fix report - `manage.py test` can create its database

Written for: the engineer owning the repair work. HEAD is still `6a036eb`; **nothing was committed**. Production constraints were not weakened and no test was deleted.

## 1. Investigation

**Symptom (reproduced at the start of this pass, plain `python manage.py test`):**
`django.db.utils.ProgrammingError: relation "users" does not exist`. Django's test-database creation only runs migrations, but ~90 of the 108 models are `managed = False` (tables owned by `featherflow_schema.sql` + `backend/*_extension.sql`), `ExistingSchemaRouter` stops migrations touching those apps, and the managed apps' migrations have foreign keys into tables the SQL creates.

**Is "migrations" a supported fix?** No. Generating migrations for the unmanaged tables would create a second, divergent schema source and could not express the triggers (append-only `activity_logs`), partial unique indexes and CHECK constraints the SQL defines, i.e. it would **not** match production behaviour. Production itself is built by `backend/DATABASE_SETUP.md`: apply the SQL files in order, then `migrate`.

**Experiment:** I built an empty database by exactly that sequence (the 18 SQL files, then `migrate`) and compared its catalog with the development/retest database (`audit_logs/tools/f014_catalog_diff.py`, `audit_logs/f014/`):

| catalog object | bootstrap | development | differences |
|---|---|---|---|
| tables | 122 | 122 | 0 |
| columns (name, type, nullability, default) | 1295 | 1295 | 0 |
| constraints (PK / FK / UNIQUE / CHECK, definition) | 483 | 483 | 0 |
| triggers | 39 | 39 | 0 |
| functions | 25 | 25 | 0 |
| indexes | 386 | 386 | 1 |
| constraint names | 483 | 483 | 1 |

The two differences are immaterial and come from the development DB having been built incrementally: `idx_activity_logs_created` is `created_at DESC` there and plain `created_at` after a fresh build (the base schema file creates it twice with `IF NOT EXISTS`, so the first one wins), and one foreign key on `feed_owner_profiles` has a different auto-generated name.

**Conclusion - the supported fix is a combination:**
1. **A deterministic test-database bootstrap** that performs the production build sequence (SQL manifest -> migrations -> reference data) into a throw-away database, driven by
2. **a custom Django test runner**, plus
3. **a documented runner for the script suites** (`scripts/run_all_tests.py`, `TESTING.md`), because the 52 `scripts/test_*.py` files are custom PASS/FAIL scripts, not unittest, so Django cannot collect them.

## 2. What was implemented

* `backend/featherflow_backend/schema_bootstrap.py` - `SQL_MANIFEST` (single ordered list of the 18 SQL files; first five are the documented production order), `build_database()` (create DB, apply SQL with psycopg2 - no `psql` binary needed -, `migrate`, reference commands `seed_disease_reference` / `seed_feeding_guidelines`), `DEMO_FIXTURE_COMMANDS` (create-only seeds, used only by the script runner). It refuses to rebuild the configured database.
* `backend/featherflow_backend/test_runner.py` - `FeatherflowTestRunner`: builds `test_featherflow` (or reuses it with `--keepdb`), points the connection at it, drops it afterwards; refuses a test DB name equal to the configured one. New `--collect-only`. Ends with one line that reports **collected / ran / passed / failures / errors / skipped** separately.
* `settings.py`: `TEST_RUNNER` + `TEST.NAME`; the earlier template-clone switch (`TEST_TEMPLATE_DB`) and `scripts/make_test_template.py` are removed (they depended on the development database existing).
* `backend/featherflow_backend/tests.py` (+8 Django tests): the manifest lists every `*_extension.sql` on disk (a new SQL file that is not listed fails the suite); and the throw-away database really enforces production: >=120 tables, >=100 FKs, >=100 CHECKs, >=30 triggers, no `NOT VALID` constraints, an orphan foreign key is rejected, a bad `account_status` is rejected by its CHECK, a duplicate email is rejected, the append-only `activity_logs` trigger refuses a DELETE, reference data is loaded.
* `scripts/run_all_tests.py` rewritten: step 1 `manage.py test`; step 2 each `scripts/test_*.py` against `featherflow_scripts` (bootstrap + demo fixture) or `featherflow_scripts_clean` (bootstrap only) for the scripts that need an empty platform; all databases dropped afterwards (`--keep`, `--clone-dev`, `--only` available).
* `TESTING.md` rewritten.

### Real defects the stricter, fresh database exposed (fixed)

Because the old script runs used a clone of the development data, some assumptions were never exercised on a clean database:

| Where | Problem | Fix |
|---|---|---|
| `seed_feed_marketplace_demo` | wrote the **bird** type `chick` into `farmer_profiles.farm_type` / `farms.farm_type`, violating the production CHECK (`broiler|layer|breeder|hatchery|mixed|backyard`); it only "worked" in development because the farmer already existed | farm type is mapped (`chick` -> `mixed`); the flock keeps `chick` |
| `scripts/test_admin_panel.py` | its helper created admins without verified e-mail/phone, so sign-in (correctly) demanded verification | helper creates a fully verified admin |
| `scripts/test_admin_row_builder_performance.py` | required >= 10 delivery orders that only existed in the development data | the script tops the table up with clearly-prefixed filler rows and removes them in its cleanup |

Production constraints were not touched.

## 3. The three required commands (`audit_logs/f014/required_commands.log`)

```
$ python manage.py check
System check identified no issues (0 silenced).                      exit=0

$ python manage.py migrate --check
(no output: no unapplied migrations)                                 exit=0

$ python manage.py test
Ran 39 tests in 13.254s - OK
COLLECTED 39 | RAN 39 | PASSED 39 | FAILURES 0 | ERRORS 0 | SKIPPED 0 | EXPECTED-FAILURES 0 | UNEXPECTED-SUCCESSES 0
exit=0
```

`python manage.py test --collect-only` -> `COLLECTED 39`. `--keepdb` was also exercised (first run builds, second prints `Reusing test database "test_featherflow"`); the plain run drops its database.

**Collection vs failures, reported separately.** Before: collected 31, ran 0 (the database could not be created). Now: **collected 39** (31 existing + 8 new bootstrap guards), **ran 39, 0 failures, 0 errors, 0 skipped**.

## 4. Existing backend tests are collected and executed

`python scripts/run_all_tests.py` (`audit_logs/f014/run_all_final.log`), all on throw-away databases built by the bootstrap:

| Suite | Collected / files | Ran | Failed |
|---|---|---|---|
| `manage.py test` (Django unittest) | 39 | 39 | 0 |
| `scripts/test_*.py` (custom suites, one process each) | **52 files** | **2075 assertions** | 0 |

`RESULT: all green`. (The 52 script files are executed by the runner; Django does not collect them, which is why they are counted separately and not folded into the 39.)

## 5. Development database untouched

Row counts of all 122 tables and a hash of the column catalog of the `featherflow` database were captured read-only before and after a full run of the runner (`audit_logs/tools/f014_devdb_fingerprint.py`): **37,125 rows before and after, identical per-table counts, identical schema hash** (`audit_logs/f014/dev_before.json`, `dev_after.json`). The runner only reads the server connection settings from the development configuration; the databases it creates (`test_featherflow`, `featherflow_scripts`, `featherflow_scripts_clean`) are dropped at the end. I also dropped the leftover `featherflow_testtemplate` and scratch `ff_bootstrap` databases created during this work.

## 6. Limits

* The first five SQL files are the documented production order; the other thirteen were ordered by dependency and verified (all apply cleanly, schema identical to the development database as shown in section 1). `DATABASE_SETUP.md` still lists only the first five; it should be updated to point at `SQL_MANIFEST` (not done in this pass).
* Reference data comes from the two project seed commands, not from SQL. A fresh database therefore has fewer rows than the development database (for example 18 roles vs 19, 5 subscription plans vs 9 with case-variant duplicates, no `Equipment`/`Tax` expense categories). The Django suite and all 52 script suites pass without them; tests that need such rows create them.
* Building a test database takes about 6 s (SQL + 91 migrations); `--keepdb` skips it.
* Running tests needs a PostgreSQL role allowed to `CREATE DATABASE`, as Django's own runner does.
* I did not change `DATABASE_SETUP.md`, CI configuration, or the `featherflow_retest`/dev data.
