# F-015 fix report - `seed_research_demo` never reactivates or rewrites an existing account

Written for: the engineer owning the repair work. HEAD is still `6a036eb`; **nothing was committed**. This closes the F-015 residual only; the project remains in repair status.

## 1. The problem (reproduced)

The post-repair retest found that `seed_research_demo` run 1 changed `research.sabiha@example.com` from **suspended to active**. The pre-fix command (taken from `git show HEAD:...`) was re-run on a clone of the retest database with a suspended Sabiha (`audit_logs/f015/snapshots_seed_research_demo_head.json`):

| | Sabiha status | password hash |
|---|---|---|
| before run 1 | suspended | `9a796b58` |
| after run 1 | **active** | `6e17bf4c` (rewritten) |
| after run 2 | **active** | `a33d38d0` (rewritten again) |
| after run 3 | **active** | `4663667f` (rewritten again) |

So the old seed both reactivated the account and reset the password on every run.

## 2. The fix (`backend/research/management/commands/seed_research_demo.py`)

Most of the create-only conversion was already in the working tree from the earlier repair turn (users looked up first; profiles, articles, bookmarks, applications and reports through `get_or_create`). This pass finishes it:

* **Existing accounts are never modified.** An existing user (status, verification, password, profile) is left alone, and **its roles are no longer touched either**: the role link is created only for a user the seed itself creates.
* **Seed-created users are distinguishable.** When the seed creates an account it also writes one `backend_admin_records` row (`module='seed-accounts'`, `record_id=<email>`, payload `{source: 'seed_research_demo', user_id, role, created_at}`). No schema change; the unique `(module, record_id)` constraint also makes it idempotent. Real accounts never get a marker, so demo accounts can be listed (and removed) with one query.
* **No access for non-active accounts.** The premium subscription for the two verified demo researchers is only granted if that account is `active`; a suspended, banned or pending account gets none.
* **Idempotent, no duplicates.** Articles are keyed by (author, title, type): an existing submission - even one an admin archived or sent back - is found and left intact (status, notes, version), never recreated.

## 3. Regression test

`backend/scripts/test_seed_research_demo.py` (31 assertions; refuses the main dev DB; each scenario is rolled back; registered in `scripts/run_all_tests.py` so it runs on a clean scratch clone).

**A. real accounts exist first:** a **suspended `research.sabiha@example.com`** with her own archived submission (using the same title the seed would create, version 4, reviewer note) and a second pending submission; a banned `research.fariha@example.com`; a pending `research.mahmud@example.com`. After three runs: status and verification unchanged, password hashes identical, profile unchanged, no marker created for any of them, no subscription granted, her archived submission still archived with its note and version (no duplicate), her other submission intact, roles unchanged, row counts and all status/password/role/article rows identical after runs 2 and 3, run 1 only added rows.

**B. clean database:** run 1 creates the demo data and exactly one marker per created account (3 researchers, admin, farmer); runs 2 and 3 change nothing; then an admin suspends Sabiha, bans Fariha, un-verifies Mahmud and sends his paper back with a note - three more runs reactivate nobody, keep every status and note, add no rows, and leave no duplicate article or email.

Result: **31 passed, 0 failed**.

## 4. Three-run snapshot comparison on a database clone

`audit_logs/tools/f015_snapshots.py` on `featherflow_f015` (a clone of `featherflow_retest` with Sabiha set to suspended), fixed command:

| | Sabiha | password hash | users | articles | subscriptions | markers |
|---|---|---|---|---|---|---|
| before run 1 | suspended | `9a796b58` | 109 | 24 | 9 | 0 |
| after run 1 | **suspended** | `9a796b58` | 109 | 24 | 9 | 0 |
| after run 2 | **suspended** | `9a796b58` | 109 | 24 | 9 | 0 |
| after run 3 | **suspended** | `9a796b58` | 109 | 24 | 9 | 0 |

All table counts (users, user_roles 110, researcher_profiles 4, articles 24, version snapshots 13, bookmarks 18, change applications 3, reports 1, subscriptions 9) and every research-user / profile / article row (status, version, title, password-hash digest) are identical before run 1 and after runs 1, 2 and 3 (`snapshots_seed_research_demo.json`). Markers stay 0 because every demo account already existed on that clone, i.e. the seed created nothing.

## 5. Full suites

* `python scripts/run_all_tests.py`: `manage.py test` 31 tests OK; **52 script files, 2075 assertions, 0 failed** (includes `test_seed_platform_demo.py` 46 and `test_seed_research_demo.py` 31).
* `manage.py check`: no issues.

## 6. Limits

* The `featherflow_retest` and dev databases were not modified; the clone `featherflow_f015` and the scratch test databases were throw-away.
* Existing demo accounts created by *earlier* seed runs have no marker (the marker exists only for accounts created from now on), so they cannot be told apart from real users by this mechanism; they keep the `@example.com` addresses.
* Other seeds were made create-only earlier (`seed_farmer_demo_data`, `seed_feed_marketplace_demo`, `seed_news_demo`, `seed_platform_demo`); they do not write markers.
