# Featherflow repair baseline

Captured 2026-10-02. Nothing was cleaned, reset, stashed or committed.

## Important caveat
This baseline was requested "before changing code", but the NF-3..NF-7 repairs had **already been
written (uncommitted) when it was taken**. It therefore records the repair-in-progress working tree
on top of `6a036eb`, **not** the pre-repair state. The pre-repair retest state is documented in
`FEATHERFLOW_POST_REPAIR_VERIFICATION_REPORT.md` (99/119, NF-1..NF-7) and in the database dump below.

## Preserved artefacts
| Item | Location |
|---|---|
| Post-repair verification report (kept unchanged) | `FEATHERFLOW_POST_REPAIR_VERIFICATION_REPORT.md` |
| Aborted/partial harness runs (5 files) | `audit_logs/retest/aborted_runs/` |
| Export of the isolated retest DB `featherflow_retest` (pg_dump -Fc) | `audit_logs/baseline/featherflow_retest_baseline.dump` |
| Tracked-file diff vs HEAD | `audit_logs/baseline/working_tree.diff` |
| `git status --short` | `audit_logs/baseline/status.txt` |

Note: the retest DB was dumped as it is now. It already contains the `repairs_nf_extension.sql` schema
additions (feed company coordinates, `consultation_note_history`) applied for the repair work, so it is
not byte-identical to the DB at the end of the retest run.

## Commit / working tree
* HEAD: `6a036eb Sub-admin roles fixed` (unchanged).
* Tracked files modified: 90 (`6038 insertions, 1402 deletions`); untracked files: 103; total 193 status entries.

## Test counts (current working tree, isolated clones - dev DB not used)
* `python scripts/run_all_tests.py`: `manage.py test` **31 tests OK**; 49 `scripts/test_*.py` files plus
  `test_seed_platform_demo.py` (46) - 1957 script assertions, **0 failed**. (An earlier runner pass showed
  `test_seed_platform_demo.py` failing only because it needs an empty platform; the runner now gives it a clean
  template clone.)
* Flutter: `flutter analyze` no issues; `flutter test` 283 tests passed before this turn, plus 5 new in
  `test/repairs_logic_test.dart` (NF-3 validation, F-007 guard) = 288.
* The previous retest verdict stands until the browser retest is rerun: **99/119 workflow records passing**.

## Seed results
* Retest report section 2: 30/30 seed runs exit 0 with zero row changes, **except** `seed_research_demo`
  run 1, which reactivated suspended `research.sabiha@example.com` (F-015 residual).
* Seeds were since changed to create-only (research, farmer, feed marketplace, news); not yet re-run on the
  retest DB in this baseline. `seed_platform_demo` is covered by its 46-assertion script.

## Open findings
| ID | Status |
|---|---|
| NF-3 feed checkout location | code + backend/Flutter validation written; backend tests pass; **UI not re-verified in browser** |
| NF-4 rider Map bound to selected order | code written; **not browser-verified**, no widget test yet |
| NF-5 Research "Request revision" UI | code written; **not browser-verified**, no widget test yet |
| NF-6 editable case notes + audit history | code written; backend tests pass; **no widget test, not browser-verified** |
| NF-7 routable pickup + expired offers released | code written; backend tests pass; **not browser-verified** |
| F-014 test infrastructure | repaired in the working tree via template-DB cloning (`TESTING.md`, `run_all_tests.py`); full run green |
| F-015 seed mutations | create-only seeds implemented; **needs rerun on the retest DB to close** |

## Disclosed test-data-only actions
* Accidental approval of pharmacy proof `c550874f-...` (order #PH-CF7DC2) through the API during diagnosis of
  the Pharmacy Admin proof UI - in `featherflow_retest` only; documented in report section 6.
* `manage.py close_stale_shifts` was run once on the **dev** DB `featherflow` and closed the stale
  `ops.nusrat` admin shift (a real dev-data change, from the F-030 repair).

## Status
Project remains in **repair status**. Not complete.
