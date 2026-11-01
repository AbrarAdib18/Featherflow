# Doctor Case Page — Fix

Root causes and the before/after state machine are in [DOCTOR_CASE_WORKFLOW_AUDIT.md](DOCTOR_CASE_WORKFLOW_AUDIT.md). The Schedule cleanup is in [DOCTOR_SCHEDULE_PAGE_AUDIT.md](DOCTOR_SCHEDULE_PAGE_AUDIT.md).

All case work now happens on the individual Case page:

```
Open case → enter / edit fields → Save (repeatable) → Close case
→ "Mark as Complete" window → confirm
→ "Issue Prescription and Advice" → prescription, medicines, advice, follow-up
→ prescription shown on the Case page (a revised one may be issued)
```

## Files changed

| File | Change |
|---|---|
| `backend/doctor/case_workflow.py` *(new)* | `case_stage()` (the single stage definition); `CaseFieldsSerializer` (partial; trims; length limits 5000 / tag 60 / 20 tags; de-duplicates tags; intake fields kept for compatibility); `update_case()` (stage rules, close requires diagnosis + treatment plan, reopen, in a transaction with a row lock, `activity_logs` audit of changed fields and status); `CaseWorkflowError` → `{detail, code, errors?}` |
| `backend/doctor/views.py` | `cases`: single-case GET; partial POST/PATCH through `update_case`; structured 400/409. `_case_row` adds `stage`, `editable`, `consultation_status`, `mode`, `scheduled_at`, `updated_at`, `prescription_count`. `appointment_action`: repeat `complete` → 200 `already_completed`. `appointments?scope=schedule`. Dashboard `completed_cases` / `active_cases` follow consultation status |
| `lib/features/doctor/data/models/doctor_models.dart` | `CaseStage`, `ScheduleSection`, `DoctorAppointment.scheduleSection`; `DoctorCase` gains `stage`, `editable`, `consultationStatus`, `mode`, `scheduledAt`, `updatedAt`, `prescriptionCount`, `fieldValue()` |
| `lib/features/doctor/data/services/doctor_api_service.dart` | Errors carry the HTTP status, per-field `errors` and the body (`AuthException.fieldErrors`) |
| `lib/features/doctor/data/services/doctor_session.dart` | Awaited calls returning the server's case: `loadCase`, `saveCaseFields`, `closeCase`, `reopenCase`, `completeCase`, `issueCasePrescription`; a per-case in-flight guard (`isCaseBusy`). Removed the fire-and-forget whole-case writers `updateCaseStatus`, `updateCase`, `addPrescription`, `_saveCase` and the single-medicine `issuePrescription`. Counters follow the stage. Test seam `debugLoadCasesPayload` |
| `lib/features/doctor/presentation/screens/doctor_case_notes_screen.dart` | Case list filters by stage, shows a stage chip, has pull-to-refresh and a load error with Retry; stub "New Case" button removed. **Case page rewritten** (below) |
| `lib/features/doctor/presentation/screens/doctor_appointments_screen.dart` | Schedule = Requests + Upcoming; Mark Complete and the prescription dialog removed; Open case; guarded Accept / No-show; narrow layout; contrast |
| `lib/features/doctor/presentation/doctor_theme.dart` | `VetColors.amberText` (readable amber) |
| Tests | `backend/scripts/test_doctor_case_workflow.py` *(new)*, `test/doctor_case_workflow_test.dart` *(new)*; one test in `test/doctor_consultation_queue_test.dart` replaced (see the Schedule audit) |

**No schema change and no migration.** The stage is derived from existing columns. The audit uses the existing append-only `activity_logs` table (`module='doctor_cases'`, `target_type='consultation_case'`, `target_id=<case id>`, `old_value` / `new_value` = only the changed fields). The farmer API is unchanged.

## API contract

| Endpoint | Before | After |
|---|---|---|
| `GET /api/doctor/cases/<id>/` | Returned the whole list (id ignored) | That case; 404 when it isn't yours |
| `PATCH /api/doctor/cases/<id>/` (and `POST /api/doctor/cases/` by `consultation_id`) | Full overwrite: omitted fields became `''`; any status at any time; `consultation_id` required | **Partial**: only the fields sent change. `consultation_id` is optional on PATCH (400 if it doesn't match). Stage rules: edits only in `open` (409 `consultation_not_accepted` / `case_closed` / `consultation_completed` / `consultation_ended`). `status: closed` requires diagnosis and treatment plan (400 `case_incomplete`, `errors: {diagnosis, treatment_plan}`). `status: open` on a closed case reopens it. Validation errors: 400 `{detail, code: 'invalid', errors: {field: message}}` |
| Case row (list / detail / PATCH response) | — | New keys: `stage`, `editable`, `consultation_status`, `mode`, `scheduled_at`, `updated_at` (ISO with offset), `prescription_count`. All old keys kept |
| `POST /api/doctor/appointments/<id>/action/ {action: complete}` on a completed consultation | 409 | 200 `{…row, already_completed: true}`; no new history, receipt or notification |
| `GET /api/doctor/appointments/?scope=schedule` | — | `{requests, upcoming, appointments}` |
| `GET /api/doctor/appointments/` (no scope) | All consultations | Unchanged |
| Dashboard `summary.completed_cases` / `active_cases` | Case status `closed` / `open, in_progress` | Consultation `completed` / `accepted, in_progress` |

Editable fields, as API name → storage:

| API field | Stored in |
|---|---|
| `diagnosis`, `treatment_plan`, `warnings`, `next_steps` | `consultation_notes` (one row per consultation, updated in place) |
| `feed_notes`, `vaccine_history`, `biosecurity_notes`, `disease_tags` | `consultation_case_details` |
| `farm_name`, `bird_age`, `breed`, `flock_count`, `mortality_count`, `symptoms` | `consultation_case_details` (farmer intake; still accepted for API compatibility; the page shows them read-only) |

Access: only the assigned doctor (`consultation.doctor`) can read or change a case. Another doctor gets 404, a farmer 403 (doctor role required), and an unauthenticated caller 401. Farmers have no clinical-field write path.

## Case page (`CaseDetailScreen`)

| Stage | Page shows |
|---|---|
| Awaiting acceptance | Banner: accept it on the Schedule page. Fields read-only |
| **Open** | Real inputs for each field, grouped as in reference image 1: **Diagnosis**, **Treatment Plan** (multiline; "Required to close"), **Warning** (red-bordered card), **Disease Tags** (single line, comma-separated), **Farm Management Notes** (Feed Notes, Vaccine History, Biosecurity as tinted inset textareas), **Next Steps**. A sticky **save bar** shows "Unsaved changes", "Saving…" (spinner, inputs locked, Save disabled), "All changes saved", or "Not saved: \<server reason\>" with **Retry**. When idle it shows "Last saved \<time\>". Below that: **Close case** ("Save and close case" when there are edits; confirmation dialog) and Set follow-up date |
| **Closed** | Fields read-only. **Mark as Complete** window: an explanation, a dark full-width button with a confirmation dialog, and "Reopen case to edit" |
| **Completed** | **Issue Prescription and Advice** window (reference image 3 style: dark full-width button). It opens an inline form with one or more medicines (name, dosage and duration required, optional instructions; add or remove), case advice (required), dosage notes, follow-up instructions, referral, and an optional follow-up date and time. **Save and email PDF** is disabled while sending, and errors show inline |
| **Prescribed** | Prescription & Advice card (medicines, advice, dosage notes, follow-up instructions and time, referral; "Latest of N") and "Issue revised prescription" |
| Ended | Banner; read-only |

Behaviour:

* **Server is the source of truth.** Every action awaits the server and swaps in the returned case. The server decides what the stage allows, and the page renders from `stage` and `editable`.
* **No duplicate submissions.** A per-case in-flight guard disables Save, Close, Complete and prescription submit while a request is running.
* **No data loss.**
  * Back navigation with unsaved edits asks "Discard unsaved changes?".
  * A background refresh, or a reload from another device, updates only the fields the doctor isn't editing.
  * A failed save keeps the text.
* **Read-only display.** Blank values show *Not recorded*, so empty cards no longer appear.
* **Refresh.** The page reloads the case on open, with pull-to-refresh and a reload button. A case that can't be loaded (for example another doctor's, 404) shows the reason and Retry.
* **Layout and contrast.**
  * Content is capped at 860px and centred for wide web and Windows.
  * Medicine fields sit in one row at 520px and wider, and stack below that.
  * Text is dark on light surfaces, and section titles use the existing tokens (blue, green, red, purple) on white, with no green-on-green.
  * The app bar keeps the dark green navigation surface with white text and icons.

## Farmer visibility (unchanged rules)

* **Before completion:** clinical results return 409, so the farmer sees only their own intake.
* **After completion:** `GET /api/consultations/<id>/clinical-results/` returns the saved diagnosis, treatment plan, warnings, next steps, the doctor-annotated case notes, every prescription and the follow-ups. The farmer UI ("Clinical results") already renders all of these.
* **Other farmers:** another farmer gets 404.

## Tests and results

| Gate | Result |
|---|---|
| `backend/scripts/test_doctor_case_workflow.py` *(new)* | **88/88** |
| `test/doctor_case_workflow_test.dart` *(new)* | **22/22** |
| Negative controls | Old non-idempotent completion restored → backend fails 2 checks (`4 simultaneous Mark as Complete` gave `[200, 409, 409, 409]`). Case page fields made read-only again → Flutter fails 10 of 22 |
| doctor_flow / transitions_and_receipts / booking_rules / doctor_consultation_queue | 58/58 · 53/53 · 29/29 · 43/43 |
| find_vet_discovery / chat_access / chat_message_state / notifications | 38/38 · 13/13 · 43/43 · 135/135 |
| admin_panel | 62/63 (known pre-existing "admin login 200" email-verification gate) |
| `manage.py check` / `migrate --check` | clean / exit 0 |
| `manage.py test doctor messaging consultations notifications` | 22 tests, 1 error: the known pre-existing `test_discovery_row_exposes_farmer_facing_fields` (`SimpleNamespace` has no `phone`) |
| `flutter test` | 334 passed, 2 failed (the known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart`) |
| `flutter analyze lib test` | only the 6 known infos in `farmer_feed_marketplace_screen.dart` |
| `flutter build web --release` | built |

**Backend: `test_doctor_case_workflow.py`.** Throwaway `casewf+` accounts against the live dev DB, cleaned up on entry and exit. Covers:

* **Access:** 401 / 403 farmer / 404 other doctor for read, edit, complete and prescribe.
* **Before acceptance:** edits are refused (409).
* **Partial saves:** diagnosis-only and treatment-only saves keep every other field; values are trimmed; persistence is checked in `consultation_notes` and `consultation_case_details`; tags are de-duplicated; there is only one note row; reload and list return the saved values; `updated_at` has an offset.
* **Audit:** one row per changed save, with actor and old/new values; an unchanged save writes no row.
* **Validation:** too long, negative, wrong type, bad status, mismatched consultation, and close without diagnosis/treatment are each refused with field errors, and nothing reaches the DB.
* **Close / reopen:** close → read-only and the consultation is not completed; editing is refused; the farmer still sees no results; prescription → 409; reopen → close again.
* **Completion:** **4 concurrent Mark as Complete → all 200**, exactly one history row, one receipt and one farmer notification; a repeat → 200 `already_completed` with no side effects; the stage becomes completed; editing and reopening after completion are refused.
* **Farmer view:** the farmer sees the results; another farmer gets 404; the farmer API cannot write clinical fields.
* **Prescription:** two medicines and a follow-up; stage prescribed; a revision is allowed (existing policy) with no duplicate pending follow-up; the farmer sees both and is notified.
* **Money and rating:** receipt; mark-paid twice → one earning net of the platform fee; rating; dashboard counters.
* **Ended:** a rejected consultation's case is read-only.
* **Schedule scope:** see the Schedule audit.

**Flutter: `doctor_case_workflow_test.dart`.** Real `DoctorSession` and `DoctorApiService` against a stateful fake doctor API with the server's stage rules. Covers:

* **Parsing:** stage and schedule-section parsing, plus the older-server fallback.
* **Open case:** an enabled input for each field (multiline vs single line); typing → "Unsaved changes" → Save sends **only the changed field** → "All changes saved" → the value survives a reopen.
* **Save states:** "Saving…" with Save disabled and inputs locked, and a double tap sends one request; a failed save shows the reason, keeps the text, and Retry sends the same body.
* **Close:** Close without diagnosis/treatment shows inline errors and sends no request; a server refusal maps field errors onto the inputs.
* **Navigation and refresh:** back with unsaved edits → discard dialog; a background refresh keeps unsaved typing.
* **Full flow:** open → close (the edits go with it) → Mark as Complete window (Cancel sends nothing) → confirm → Issue Prescription panel → form validation → submit → prescription card and revised button.
* **Reopen and read-only:** reopen; awaiting acceptance is read-only; a completed case shows "Not recorded" for blanks.
* **Inaccessible case:** 404 → error and Retry.
* **Layout:** 360px and 1400px with no overflow.
* **Schedule group:** see the Schedule audit.

## Manual verification checklist (not yet run by hand)

Run `.\run_backend.bat` and `flutter run -d chrome` (or `-d windows`). Use doctor `dr.samira.rahman@example.com` and farmer `farmer.rashed@example.com`.

**Doctor, Case page:**

1. Accept a request on Schedule.
2. Open Cases → the case shows "Open".
3. Type in Diagnosis, Treatment Plan, Warning, Disease Tags, Feed / Vaccine / Biosecurity and Next Steps. Save shows "All changes saved".
4. Pull to refresh, go back and reopen, then log out and back in: the values persist.
5. Close case → confirm → the Mark as Complete window appears.
6. Mark as Complete → confirm → Issue Prescription and Advice appears.
7. Issue the prescription with a follow-up → the Prescription & Advice card appears on the case.

**Doctor, Schedule:** only Consultation Requests and Upcoming Schedule are shown, with no Mark Complete and no prescription button. Accept, Reject and Reschedule work. Open case opens the case. With nothing pending, both empty states show.

**Farmer:** My Consultations → that consultation → Clinical results shows the diagnosis, treatment, warnings and next steps, and the prescription and follow-up after they are issued. The receipt and mark-paid work, and the doctor's earnings show the net amount. Rating works. A different farmer cannot open it.

## Limitations

* **Completion is not tied to a closed case in the API.** `POST …/action/ {complete}` still accepts `accepted` / `in_progress` consultations whether or not the case is closed. This preserves existing clients and suites, which complete without closing. The app only offers Mark as Complete after the case is closed.
* **Prescriptions.** Multiple prescriptions per consultation stay allowed (existing policy: revisions). Double submits are prevented in the UI; there is no server-side idempotency key for prescriptions.
* **Unsaved-changes protection.** It covers in-app back navigation. A browser refresh or tab close on web is not intercepted.
* **Follow-ups.** "Set follow-up date" on an open case still uses the existing fire-and-forget `setFollowUpDate`, unchanged.
* **Audit rows.** `activity_logs` is append-only, so audit rows written by test runs stay in the dev DB, each tied to a deleted throwaway case id.
* **Old serializer.** `CaseSerializer` remains in `doctor/serializers.py` because `doctor/tests.py` covers it, but the view no longer uses it.
* **Existing empty notes.** Completed cases that already have `''` notes stay as they are; no data was rewritten. They now show *Not recorded*.
