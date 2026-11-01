# F-001 Fix Report — Admin Doctors & Patients 500 on NULL appointment time

Date: 2026-10-01. **Nothing was committed** (HEAD still `6a036eb`; `git stash list` empty; no `git add/commit`). Fix is in the working tree only. Raw logs/screenshots: `audit_logs/f001/`.

## 1. Root cause

`consultations.appointment_date` and `appointment_time` are nullable in PostgreSQL (`farmer_panel_integrity_extension.sql:23-24` dropped NOT NULL so a request with no preferred slot can exist until the doctor proposes one). Three layers had not followed:

| Layer | Defect |
|---|---|
| Model `consultations/models.py` | `DateField()` / `TimeField()` declared non-null, contradicting the DB. |
| Query `api/admin_views.py` `_collection_rows('consultations')` | `order_by('-appointment_date', '-appointment_time')` — in PostgreSQL `DESC` puts NULLs **first**, so unscheduled rows led the list. |
| Serialisers `api/admin_views.py` (consultations row **and** the dispute row `_dispute_admin_json`) | `f'{c.appointment_date} {c.appointment_time:%H:%M}'` → `TypeError: unsupported format string passed to NoneType.__format__` → HTTP 500 for the whole page (74 occurrences in the audit server log). The dispute serialiser had the same latent crash. |
| Flutter `admin_doctors_screen.dart` | `Future.wait` of 3 requests in one `try`; **any** failure only showed a transient snackbar and left the lists empty, so the screen displayed **"No doctors found."** (an error disguised as empty data). Consultations tab had no empty state at all; `time` was an untyped string. |

## 2. Files changed

| File | Change |
|---|---|
| `backend/consultations/models.py` | `appointment_date` / `appointment_time` → `null=True, blank=True` (unmanaged table: no migration; `migrate --check` still clean). |
| `backend/api/admin_views.py` | New null-safe helpers `_consultation_time_fields()` / `_appointment_label()`. Consultations list serialises `appointment_date`, `appointment_time` (`'HH:MM'` or **null**), `scheduled` (bool) and the legacy `time` (`"YYYY-MM-DD HH:MM"` or **null**). Dispute `appointment` label is null-safe (`"Time not scheduled"` / date only). Ordering is now `_unscheduled` (CASE: date or time NULL → 1) ASC, `appointment_date` DESC NULLS LAST, `appointment_time` DESC NULLS LAST, `-created_at`, `-id` — scheduled newest-first, every unscheduled request after them, deterministic. Imports `Case, F, IntegerField, Value, When`. |
| `lib/features/admin/presentation/screens/admin_doctors_screen.dart` | Three independent loads (one failing endpoint no longer blanks the others); per-list `String? error` rendered with the shared `ErrorStateView` + **Retry** (reloads all); doctors/consultations/disputes tabs show the error instead of an empty list; Consultations tab gained "No consultations yet."; `_ConsultData` now holds nullable `date`/`time`, with `scheduled` and `timeLabel` → `"<date> <time>"`, `"<date> · Time not scheduled"` or **"Time not scheduled"** (orange italic). |
| `backend/scripts/test_admin_consultations_null_time.py` | **New** backend regression suite (27 assertions). |
| `test/admin_doctors_consultations_test.dart` | **New** Flutter tests (6). |
| `F-001_FIX_REPORT.md`, `FEATHERFLOW_FAULT_REGISTER.md` (status), `audit_logs/f001/*`, `audit_logs/tools/{f001*.js,f001_api.py}` | Evidence/docs. |

## 3. API response (live DB, Doctor Admin token)

Live DB contains the real trigger row `665070c9-…` (status `requested`, no slot).

**Before** (original code, stashed): `GET /api/admin-panel/consultations/?page_size=200` → **HTTP 500** (`TypeError … at /api/admin-panel/consultations/`; HTML error page).

**After**: **HTTP 200**, `count = 29` (28 scheduled, 1 unscheduled), scheduled rows first newest→oldest, the unscheduled row last:
```json
{"id":"a66dfb3f-…","patient":"TT Farmer","doctor":"TT Doc","topic":"Routine",
 "appointment_date":"2026-10-18","appointment_time":"10:00","scheduled":true,
 "time":"2026-10-18 10:00","urgent":false,"status":"completed"}
…
{"id":"665070c9-df16-4d76-9af2-d217581dd073","patient":"Kaneda","doctor":"Dr. Mahfuz Kabir","topic":"Routine",
 "appointment_date":null,"appointment_time":null,"scheduled":false,"time":null,
 "urgent":false,"status":"requested"}
```
(full body: `audit_logs/f001/api_consultations_after.json`; ordering check "everything from index 28 on is unscheduled" = true.) Disputes: `appointment` for a consultation without a slot = `"Time not scheduled"`.

## 4. Tests

### 4.1 Backend — `backend/scripts/test_admin_consultations_null_time.py` (27 assertions, live DB, `nulltime+` throw-away rows, self-cleaning) → **27 passed, 0 failed**
| Required case | Assertions |
|---|---|
| 1. Consultation with appointment time | 200; `appointment_time == "10:30"`, ISO `appointment_date`, `scheduled true`, legacy `time` unchanged |
| 2. NULL appointment time | 200 (was 500); row returned (not dropped); `appointment_time`, `appointment_date`, `time` are JSON **null**; `scheduled false`; patient/doctor/status still populated; date-only row keeps its date, time null |
| 3. Mixed NULL / non-NULL | 7 mixed rows all returned; `count` includes unscheduled rows; `page_size=2` paging still 200 and bounded |
| 4. List returns 200 | every step above asserts 200 |
| 5. Correct ordering | scheduled rows exactly `[newer 15:45, new 08:00, +5d 10:30, −30d]` (date desc, time desc); across the **whole table** every scheduled row precedes every unscheduled row |
| 6. Correct serialised null | JSON `null` (not `"None"`, not a garbled string) |
| 7. Unauthorized stays denied | anonymous 401; farmer 403; admin without the doctors module (Finance) 403; Doctor Admin 200 |
| Extra | disputes list is also 200 for a null-slot consultation with a readable label |

Against the original code the script aborts with `TypeError: unsupported format string passed to NoneType.__format__` (the 500).

### 4.2 Flutter — `test/admin_doctors_consultations_test.dart` (6 tests; real `AdminDoctorsScreen` + `AdminApiService` over a mock HTTP client returning the fixed backend's JSON)
Valid appointment time → "2026-10-05 10:30"; missing time → "Time not scheduled" and date-only → "2026-10-07 · Time not scheduled" (all 3 rows rendered); **API error** (consultations 500) → "Admin request failed (500)." + Retry while doctors still render and "No doctors found." is absent; doctors endpoint 500 → error + Retry, not "No doctors found."; **empty** data → "No doctors found." / "No consultations yet." and no Retry; **Retry** → second request succeeds and the list appears. **5 of 6 fail against the original screen**, all pass now.

### 4.3 Commands requested
| Command | Result |
|---|---|
| `python manage.py check` | *System check identified no issues* (exit 0) |
| `python manage.py migrate --check` | exit 0 (no unapplied migrations; model nullability needed none) |
| `python manage.py test` | **Still cannot run** — `relation "users" does not exist` while creating the test DB (pre-existing F-014: schema is SQL-owned, 90 models `managed=False`); exit 1. Backend verification therefore uses the project script suites against the live DB |
| All backend scripts (`scripts/test_*.py`, 45 incl. the new one) | **45/45 exit 0, 1,639 assertions, 0 failed.** `test_admin_pagination_performance.py`, which crashed on F-001 in the audit, now passes |
| `flutter analyze` | 6 issues, all pre-existing `info` (`prefer_const_*` in `farmer_feed_marketplace_screen.dart`); 0 new; changed screen and new test clean |
| `flutter test` | **235 passed** (229 + 6), 0 failed |
| `flutter build web --release` | `√ Built build\web` (exit 0) |

## 5. Browser verification (real Chrome 154 + Playwright; release build of the fixed tree on :8080; fixed backend on :8000 against the live DB)
Log: `audit_logs/f001/browser_log.txt`; screenshots in `audit_logs/f001/`.

| Check | Result |
|---|---|
| Doctor Admin → `#/admin/doctors` → **All Doctors** | doctors listed (Dr. Samira Rahman, Dr. Mahfuz Kabir, Dr. Nabila Sultana, Audit doctor …); **no** "No doctors found", **no** 500 toast — `doctor_admin_all_doctors.png` (before the fix: "No doctors found." + "Admin request failed (500)." — `admin_doctor_d0_21.png` in the audit) |
| Network | `GET /api/admin-panel/doctors/ 200`, `/consultations/ 200`, `/consultation-disputes/ 200` |
| **Consultations** tab | 29 cards, newest first (2026-10-18 10:00 …); scrolled to the end: the unscheduled request ("Kaneda · Dr. Mahfuz Kabir · Routine") is last and reads **"Time not scheduled"** (orange italic) — `doctor_admin_consultations_bottom.png` |
| Same pages as Super Admin | 200s, renders — `super_admin_*.png` |
| **Error vs empty (injected 500 on the consultations call via the browser)** | Consultations tab shows the cloud-off icon, **"Admin request failed (500)."** and a **Retry** button — not "No consultations yet"/"No doctors found" — `injected_500_error_state.png` |
| **Retry** (backend healthy again) | click Retry → error disappears and the list loads — `after_retry_recovered.png` |

(Playwright's DOM-text probe only sees Flutter semantics nodes, so a couple of text probes in the log read `false` even though the screenshots show the text; screenshots are the evidence of record.)

## 6. Notes / not changed
* The consultation row itself (`665070c9…`) was left as is — it is valid data (a request with no slot) and is now displayed correctly.
* `doctor/views.py`, `consultations/views.py`, `consultations/payments.py` already handled NULL slots (`if … else None`); only the admin serialisers were unsafe.
* `consultations/serializers.py` still lets a farmer submit date+time together or neither (unchanged, correct).
* Servers started for verification (:8000, :8080) were stopped afterwards.

## 7. Confirmation
Verified with the actual tests, builds and a running browser against the real backend and live data — not by code review alone. **Nothing was committed.**
