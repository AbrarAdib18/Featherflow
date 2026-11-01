# Doctor Case Workflow — Audit

**Date:** 2026-10-31
**Reported:** on an open case the doctor could not enter a diagnosis, treatment plan or the other case fields (reference image 1: empty Diagnosis / Treatment Plan / Warning / Farm Management Notes / Next Steps cards). "Mark Complete" and "Issue prescription & advice" were on the Schedule page (reference images 2–3) instead of the case.

The fix is in [DOCTOR_CASE_PAGE_FIX.md](DOCTOR_CASE_PAGE_FIX.md); the Schedule changes are in [DOCTOR_SCHEDULE_PAGE_AUDIT.md](DOCTOR_SCHEDULE_PAGE_AUDIT.md).

---

## 1. What was inspected

| Area | Files |
|---|---|
| Routes / navigation | `lib/core/router/app_router.dart` (`/doctor`, `/doctor/appointments`, `/doctor/case-notes`, …); the dashboard `IndexedStack` tabs Home · Schedule · Cases · Chat · Earnings (`doctor_dashboard_screen.dart`) |
| Schedule page | `doctor_appointments_screen.dart` |
| Case list + Case page | `doctor_case_notes_screen.dart` (`DoctorCaseNotesScreen`, `CaseDetailScreen`); also opened from `doctor_followups_screen.dart` and `doctor_prescriptions_screen.dart` |
| Client state / API | `doctor_session.dart`, `doctor_api_service.dart`, `doctor_models.dart` |
| Models | `consultations` (status), `consultation_case_details` (`CaseDetail.case_status`, farmer intake, feed/vaccine/biosecurity notes, disease tags), `consultation_notes` (`ConsultationNote`: diagnosis, treatment_plan, warnings, next_steps), `clinical_prescriptions` + items, `follow_ups`, `consultation_status_history`, `doctor_earnings`, `payments`, `activity_logs` |
| Endpoints | `GET/POST/PATCH /api/doctor/cases/[<id>/]`, `POST /api/doctor/appointments/<id>/action/`, `POST /api/doctor/prescriptions/`, `/api/doctor/follow-ups/`, farmer `GET /api/consultations/<id>/clinical-results/`, `/receipt/`, `/mark-paid/`, rating `PATCH /api/consultations/` |
| Completion side effects | `doctor/views.py:appointment_action` → `record_transition` (history), case → `closed`, `ensure_cash_receipt` (payment row, idempotent), "Clinical results ready" notification; earnings accrue in `confirm_cash_payment` on mark-paid |
| Tests / reports | `test_doctor_flow.py`, `test_consultation_transitions_and_receipts.py`, `test_doctor_consultation_queue.py`, `test_consultation_booking_rules.py`, `test/doctor_consultation_queue_test.dart`, `CONSULTATION_WORKFLOW_AUDIT.md`, `DOCTOR_FARMER_WORKFLOW.md`, `DOCTOR_CONSULTATION_QUEUE_FIX.md` |

## 2. Real data behind reference image 1

Dev DB, read-only query (`dr.samira.rahman@example.com`):

| Case | Consultation | Case status | Consultation status | `consultation_notes` diagnosis / treatment | Prescriptions |
|---|---|---|---|---|---|
| `7616c4be…` | `5b981779…` (image 3, second card) | closed | completed | `''` / `''` | 0 |
| `edd846fd…` | `81b1710a…` (image 3, first card) | closed | completed | `''` / `''` | 0 |
| `6cb3f56c…` | `a74f9fe9…` | closed | completed | `''` / `''` | 0 |
| `fca083c1…` | `2997b784…` (image 2) | open | requested | no note | 0 |

Completed consultations had a clinical note made of empty strings. The Case page showed a section whenever the value was not `null`, so `''` produced exactly the empty cards in image 1. The farmer got empty clinical results.

## 3. Root cause: the case fields were not editable

1. **No input widgets existed.** `CaseDetailScreen` rendered Diagnosis, Treatment Plan, Warning, Farm Management Notes and Next Steps through `_DetailSection` / `_WarningSection` / `_FarmNotes`, which are plain `Text`. There was no `TextField` anywhere on the page, for any case status.
2. **No save path from the page.** `DoctorSession.updateCase()` existed but no screen ever called it. The only writes were the status buttons (Start Case / Follow-Up / Close Case / the ⋮ menu) via `updateCaseStatus()`.
3. **Status changes blanked the clinical record.** `updateCaseStatus()` → `_saveCase()` re-sent *every* field from the client model, sending `''` for any that were `null`. The backend PATCH was not partial either: it rebuilt the note from `data.get(field, '')`, so any field missing from a request was overwritten with `''`. Pressing "Close Case" on a case with no notes created the `''`/`''` note seen above. A correct single-field save would also have wiped the other fields and the symptoms.
4. **Fire-and-forget writes.** `updateCaseStatus` was a `void … async` that applied the change locally, popped the page, and put any server refusal into the session-wide error string. The doctor never saw a failure.

## 4. State machine — before

**Consultation** (`consultations.status`, enforced in `appointment_action`):
`requested → accepted → in_progress → completed`, plus `rejected`, `reschedule_proposed`, `cancelled`, `no_show`. Completing a completed consultation returned **409**.

**Case** (`consultation_case_details.case_status`): `open / in_progress / follow_up / closed`, with **no rules**.
- Any value could be set at any time via PATCH, including on a requested, cancelled or completed consultation.
- `complete` forced `closed`.
- Scheduling a follow-up forced `follow_up`.
- "Close Case" on the Case page was unrelated to completion. Completion happened only from the Schedule page's "Mark Complete" (no confirmation), and the prescription only from the Schedule card's dialog (one medicine only).

| Where | Before |
|---|---|
| Edit diagnosis / treatment / … | Nowhere (read-only text) |
| Close case | Case page (fire-and-forget, any status, blanked notes) |
| Mark Complete | **Schedule** card, no confirmation, 409 on repeat |
| Issue prescription & advice | **Schedule** card dialog |
| Case page after completion | Empty cards, no next step |

## 5. State machine — after

One derived **stage** (`backend/doctor/case_workflow.py:case_stage`) drives both the Case page and what the server accepts:

```
consultation requested / reschedule_proposed        → awaiting_acceptance   (read-only; accept on Schedule)
consultation accepted / in_progress, case not closed → open                  (edit fields, Save, Close case)
consultation accepted / in_progress, case closed     → closed                (Mark as Complete, or Reopen)
consultation completed, no prescription              → completed             (Issue prescription & advice)
consultation completed, ≥1 prescription              → prescribed            (prescription shown; revision allowed)
consultation rejected / cancelled / no_show          → ended                 (read-only)
```

| Transition | Who / where | Rule |
|---|---|---|
| edit fields | assigned doctor, Case page | stage `open` only (else 409 with a `code`) |
| open → closed | assigned doctor, Case page | diagnosis and treatment plan must be filled in (400 `case_incomplete` + field errors) |
| closed → open (reopen) | assigned doctor, Case page | until the consultation is completed |
| closed → completed | assigned doctor, Case page "Mark as Complete" (confirmation dialog) | existing `complete` action: history, receipt, notification; **idempotent** on repeat |
| completed → prescribed | assigned doctor, Case page | existing prescriptions endpoint (only after completion) |

Consultation statuses, the history table, receipts, earnings, ratings, follow-ups and notifications are unchanged. The case stage is computed, so there is no new column and no migration.

## 6. Other defects found and fixed while auditing

| Defect | Fix |
|---|---|
| `GET /api/doctor/cases/<id>/` ignored the id and returned the full list | Returns that one case (404 if it isn't the doctor's) |
| Repeated `complete` returned 409; a double tap or retry showed an error after a success | Returns 200 `already_completed: true` and runs no side effects again |
| Dashboard "Completed" counted *closed* cases | Counts completed consultations; "Active" counts accepted / in-progress |
| Case list "New Case" button was a stub ("connect to your backend") | Removed; cases are created by farmer bookings |
| No audit trail for clinical edits | `activity_logs` row per change (module `doctor_cases`, old and new values) |

## 7. What was not wrong

* Farmer privacy: clinical results are released only after completion (`clinical-results` returns 409 before), and only to that farmer. Kept as is.
* Receipt / payment / earnings idempotency (`ensure_cash_receipt`, `confirm_cash_payment`).
* Prescription and follow-up rules: completion required, future time, conflict checks, one pending follow-up.
