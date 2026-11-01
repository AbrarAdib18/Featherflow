# NF-5 / NF-6 fix report

Written for: the engineer owning the Featherflow repair work.

Baseline: `FEATHERFLOW_POST_REPAIR_VERIFICATION_REPORT.md` and `NF-3_NF-4_NF-7_FIX_REPORT.md`. HEAD is still `6a036eb`; **nothing was committed**. **The project remains in repair status; this report covers NF-5 and NF-6 only.**

## 1. Result

| Item | Result |
|---|---|
| NF-5 Research Admin Request Revision | Implemented; browser workflow **7/7** steps pass, UI controls only |
| NF-6 editable doctor case notes | Implemented; browser workflow **11/11** steps pass, UI controls only |
| Backend | `manage.py test`: Ran 31 tests in 13.825s OK; 51 script files, **2044 assertions, 0 failed** (new `test_research_revision.py`: 39; `test_nf_repairs.py`: 104, of which 19 are new case-note checks) |
| Flutter | `flutter analyze`: no issues; `flutter test`: **315 passed, 0 failed** (new: `nf5_research_revision_test.dart` 6, `nf6_case_notes_test.dart` 7) |
| Release build | `flutter build web --release` succeeded (`audit_logs/nf56/flutter_build.log`) |

## 2. NF-5 - Research Admin "Request revision"

**Backend** (`api/admin_views.py`, `api/urls.py`):
* Permission: the PATCH goes through the existing RBAC gate (`request_revision` is mapped to the `reject` permission) and then `_is_research_content_admin`; farmers, authors, admins without research/articles permission and anonymous callers are refused (401/403) and nothing changes.
* **Eligibility (new, server-enforced):** only a submission in `pending_review` can be sent back; anything else returns `409 not_revision_eligible` (previously drafts, published and archived content could be flipped to "needs revision", and a second request silently overwrote the first reason).
* **Reason required:** missing/blank -> `400 revision_reason_required`; longer than 2000 characters -> `400 revision_reason_too_long`.
* **History:** every request writes an `article_version_snapshots` row (admin, timestamp, reason). New read endpoint `GET /api/admin-panel/articles/<id>/revision-history/` returns the current status, the open reason, `can_request_revision`, and the entries (needs `view` on research/articles).
* **Notification:** the platform's existing `notifications` table is used - the author gets "Revision requested on your submission" with the reason (one per request). There is no email/push channel for this in the platform, so none was added. An activity-log entry is written as before.

**Flutter** (`admin_content_screen.dart`, `admin_api_service.dart`):
* The orange **Request revision** chip appears only on `Pending` submissions and only when `AdminSession.can(researchArticles, reject)`.
* The dialog requires a reason (disabled until at least 3 non-blank characters, inline message, 2000-character counter), shows a saving spinner, performs the request itself and, on a server refusal (e.g. 409/403), shows the server message **and keeps the typed reason**.
* Every card has a **History** chip (needs `view`): current status, open request, and the revision entries (note, admin, time) with loading, error and Retry states. Cards in `Needs Revision` show the open reason (orange line).

## 3. NF-6 - editable doctor case notes

**Backend** (`doctor/views.py`, `doctor/serializers.py`):
* **Authorization:** `IsDoctor` + ownership by `consultation__doctor == request.user`: another doctor gets 404 (edit and history), the patient (farmer) 403, anonymous 401. Editing needs an accepted / in-progress / completed consultation (`409 case_not_editable` otherwise) and a closed case is locked (`409 case_closed`) until it is reopened.
* **No accidental replacement (new):** (a) the editor sends **only the changed fields**; (b) `base_revision` (the number of recorded edits) is an optimistic-concurrency token - if the notes changed since they were loaded the server answers `409 note_conflict` with the current values instead of overwriting; (c) a recorded **diagnosis / treatment plan cannot be blanked** (`400 note_cannot_be_cleared`; optional notes may be cleared deliberately and the change is recorded); (d) every text note is limited to 5000 characters and trimmed.
* **Audit history:** every change writes `consultation_note_history` (author, role, timestamp, per-field `{from, to}`, action `edit`/`status`) and an `activity_logs` entry; identical re-saves add nothing; rows are never deleted. `GET /api/doctor/cases/<id>/history/` returns them newest first with a revision number; the case row exposes `notes_revision`.

**Flutter** (`doctor_case_notes_screen.dart`, `doctor_session.dart`, `doctor_models.dart`, `doctor_api_service.dart`):
* **Edit notes** dialog with the existing values loaded; Save is disabled until something changes and then reads "Save N change(s)"; per-field validation (character counter, cannot blank a recorded diagnosis/treatment); saving spinner; server errors shown inline without losing the edit; success snackbar "Case notes saved".
* **Conflict state:** "These notes were changed after you opened them" with **Reload the latest notes (discard my edits)**; after reloading the editor shows the newer text and the next save carries the new revision.
* **Notes history** dialog: revision, author, timestamp and previous -> new value per field, with loading, error and Retry (this also fixed a real bug found by the new widget test: the Retry handler returned a Future from `setState`).
* A closed case shows the disabled "Closed - reopen to edit notes" button; changing the case **status now sends only the status** (it used to resend every note field, which could overwrite newer text); the empty red "Warning" box is hidden when there is no warning.

## 4. Browser verification (Chrome, isolated DB `featherflow_nf` cloned from `featherflow_retest`)

API on `127.0.0.1:8000`, release web build on `:8080`, Playwright against the Flutter semantics tree. Every functional step is a UI action; API traffic is only observed. The retest DB and the dev DB were not modified. API-level negative checks are in section 5 and are labelled as such.

### 4.1 Research Admin (NF-5)

#### `ResearchAdmin-1` Login - **PASS**

* **Role / route:** Research Admin / `/login -> /admin`
* **Test data:** research.admin@example.com
* **UI action:** type credentials, press Log In
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"research.admin@example.com","password":"***"}` -> `200 {"user":{"id":"8d54395d-66b5-4013-bfad-9c60979dd8fa","email":"research.admin@example.com","phone":"+8801711000608","full_name":"Research Admin","profile_photo_url":null,"date_of_birth":"1990-01-15","present_address":"Dha`
* **Screenshot:** [ResearchAdmin-1.png](audit_logs/nf56/shots/ResearchAdmin-1.png)

#### `ResearchAdmin-2` NF-5: the action is offered only for submissions pending review - **PASS**

* **Role / route:** Research Admin / `/admin/content`
* **Test data:** All Content tab
* **UI action:** open Research & Articles -> All Content, inspect cards
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Screenshot:** [ResearchAdmin-2.png](audit_logs/nf56/shots/ResearchAdmin-2.png)

#### `ResearchAdmin-3` NF-5: Request revision requires a reason (empty / too short / blank rejected, nothing sent) - **PASS**

* **Role / route:** Research Admin / `/admin/content (Pending Review)`
* **Test data:** Chicken Disease Detection
* **UI action:** Pending Review tab -> Request revision -> type nothing, "ab", spaces
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `article`: `pending_review | notes= | v1` -> `pending_review | notes= | v1`
  * `snapshots`: `1` -> `1`
  * `notifications`: `0` -> `0`
* **Screenshot:** [ResearchAdmin-3.png](audit_logs/nf56/shots/ResearchAdmin-3.png)
* **Note:** short-reason message shown=true

#### `ResearchAdmin-4` NF-5: request revision with a reason - **PASS**

* **Role / route:** Research Admin / `/admin/content (Pending Review)`
* **Test data:** Chicken Disease Detection / "Please add the sample size and a 95% confidence interval."
* **UI action:** type the reason -> Request revision
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/admin-panel/articles/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action":"request_revision","review_notes":"Please add the sample size and a 95% confidence interval."}` -> `200 {"id":"8d8f93f7-d32e-47b3-a336-9fa75af02c53","title":"Chicken Disease Detection","author":"Fariha Tasnim","author_id":"c4c3c338-ae3a-42d0-af03-46ae4a3955d8","type":"Research","status":"Needs Revision","date":"","summary"`
* **Database before -> after:**
  * `article`: `pending_review | notes= | v1` -> `needs_revision | notes=Please add the sample size and a 95% confidence interval. | v1`
  * `snapshots`: `1` -> `2`
  * `notifications`: `0` -> `1`
* **Screenshot:** [ResearchAdmin-4.png](audit_logs/nf56/shots/ResearchAdmin-4.png)

#### `ResearchAdmin-5` NF-5: the card now shows the status and the open request; the action is gone - **PASS**

* **Role / route:** Research Admin / `/admin/content (All Content)`
* **Test data:** Chicken Disease Detection
* **UI action:** reload -> All Content (the orange "Revision requested: <reason>" line is visible in the screenshot; the semantic label of a card is truncated, so the text itself is asserted by the Flutter test and the History step)
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Screenshot:** [ResearchAdmin-5.png](audit_logs/nf56/shots/ResearchAdmin-5.png)

#### `ResearchAdmin-6` NF-5: History shows the current status and the revision entry - **PASS**

* **Role / route:** Research Admin / `/admin/content (History dialog)`
* **Test data:** Chicken Disease Detection
* **UI action:** History -> read dialog
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Screenshot:** [ResearchAdmin-6.png](audit_logs/nf56/shots/ResearchAdmin-6.png)

#### `ResearchAdmin-7` NF-5: the author is told (notification) and sees the reason on the paper - **PASS**

* **Role / route:** Research Admin / `/research/papers`
* **Test data:** research.fariha@example.com
* **UI action:** log in as the author (separate browser) -> My papers -> Needs Revision filter
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"research.fariha@example.com","password":"***"}` -> `200 {"user":{"id":"c4c3c338-ae3a-42d0-af03-46ae4a3955d8","email":"research.fariha@example.com","phone":"+8801700001401","full_name":"Fariha Tasnim","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/e`
* **Database before -> after:**
  * `notifications`: `1` -> `1`
  * `article`: `needs_revision | notes=Please add the sample size and a 95% confidence interval. | v1` -> `needs_revision | notes=Please add the sample size and a 95% confidence interval. | v1`
* **Screenshot:** [ResearchAdmin-7.png](audit_logs/nf56/shots/ResearchAdmin-7.png)

### 4.2 Doctor (NF-6)

#### `Doctor-1` Login - **PASS**

* **Role / route:** Doctor / `/login -> /doctor`
* **Test data:** dr.samira.rahman@example.com
* **UI action:** type credentials, press Log In
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"dr.samira.rahman@example.com","password":"***"}` -> `200 {"user":{"id":"c83d42ae-07db-4fad-af49-669506f04e29","email":"dr.samira.rahman@example.com","phone":"+8801711000201","full_name":"Dr. Samira Rahman","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-docume`
* **Screenshot:** [Doctor-1.png](audit_logs/nf56/shots/Doctor-1.png)

#### `Doctor-2` NF-6: a closed case cannot be edited ("reopen to edit notes") - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case`
* **Test data:** case 8e78e6c1-a2fd-456e-b041-133f8fd77d20 (closed)
* **UI action:** open the closed case, try to press the edit button
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `notes`: `dx= | tx= | warn= | next=` -> `dx= | tx= | warn= | next=`
  * `status`: `closed` -> `closed`
  * `history`: `0` -> `0`
  * `activity`: `0` -> `0`
  * `lastchange`: `-` -> `-`
* **Screenshot:** [Doctor-2.png](audit_logs/nf56/shots/Doctor-2.png)

#### `Doctor-3` NF-6: reopen the case (status only - no notes are resent) - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case (menu)`
* **Test data:** Closed -> Mark In Progress
* **UI action:** three-dot menu -> Mark In Progress
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","status":"in_progress"}` -> `200 {"id":"8e78e6c1-a2fd-456e-b041-133f8fd77d20","appointment_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","farmer_name":"Md. Rashed Karim","farm_name":"Rashed Poultry Farm","flock_size":500,"bird_age_weeks":6,"breed":"broiler`
* **Database before -> after:**
  * `notes`: `dx= | tx= | warn= | next=` -> `dx= | tx= | warn= | next=`
  * `status`: `closed` -> `in_progress`
  * `history`: `0` -> `1`
  * `activity`: `0` -> `1`
  * `lastchange`: `-` -> `Dr. Samira Rahman | status | {"status": {"to": "in_progress", "from": "closed"}}`
* **Screenshot:** [Doctor-3.png](audit_logs/nf56/shots/Doctor-3.png)

#### `Doctor-4` NF-6: editor opens with existing values; Save is disabled until something changes - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes`
* **Test data:** 
* **UI action:** press Edit notes
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `notes`: `dx= | tx= | warn= | next=` -> `dx= | tx= | warn= | next=`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `1` -> `1`
  * `activity`: `1` -> `1`
  * `lastchange`: `Dr. Samira Rahman | status | {"status": {"to": "in_progress", "from": "closed"}}` -> `Dr. Samira Rahman | status | {"status": {"to": "in_progress", "from": "closed"}}`
* **Screenshot:** [Doctor-4.png](audit_logs/nf56/shots/Doctor-4.png)

#### `Doctor-5` NF-6: record diagnosis and treatment (first save) - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes`
* **Test data:** diagnosis "Infectious bronchitis (suspected)", treatment "Supportive care, electrolytes in drinking water"
* **UI action:** type diagnosis + treatment -> Save 2 changes
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","diagnosis":"Infectious bronchitis (suspected)","treatment_plan":"Supportive care, electrolytes in drinki` -> `200 {"id":"8e78e6c1-a2fd-456e-b041-133f8fd77d20","appointment_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","farmer_name":"Md. Rashed Karim","farm_name":"Rashed Poultry Farm","flock_size":500,"bird_age_weeks":6,"breed":"broiler`
* **Database before -> after:**
  * `notes`: `dx= | tx= | warn= | next=` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `1` -> `2`
  * `activity`: `1` -> `2`
  * `lastchange`: `Dr. Samira Rahman | status | {"status": {"to": "in_progress", "from": "closed"}}` -> `Dr. Samira Rahman | edit | {"diagnosis": {"to": "Infectious bronchitis (suspected)", "from": ""}, "treatment_plan": {"to": "Supportive care, electrolytes in drinking water", "from": ""}}`
* **Screenshot:** [Doctor-5.png](audit_logs/nf56/shots/Doctor-5.png)

#### `Doctor-6` NF-6: a recorded diagnosis cannot be blanked (validation, nothing sent) - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes`
* **Test data:** clear Diagnosis
* **UI action:** Edit notes -> clear Diagnosis
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `notes`: `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `2` -> `2`
  * `activity`: `2` -> `2`
  * `lastchange`: `Dr. Samira Rahman | edit | {"diagnosis": {"to": "Infectious bronchitis (suspected)", "from": ""}, "treatment_plan": {"to": "Supportive care, electrolytes in drinking water", "from": ""}}` -> `Dr. Samira Rahman | edit | {"diagnosis": {"to": "Infectious bronchitis (suspected)", "from": ""}, "treatment_plan": {"to": "Supportive care, electrolytes in drinking water", "from": ""}}`
* **Screenshot:** [Doctor-6.png](audit_logs/nf56/shots/Doctor-6.png)

#### `Doctor-7` NF-6: partial edit sends only the changed field; other notes are preserved - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes`
* **Test data:** Next steps = "Recheck in 3 days"
* **UI action:** restore diagnosis by cancelling -> Edit notes -> change only Next steps -> Save 1 change
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","next_steps":"Recheck in 3 days","base_revision":2}` -> `200 {"id":"8e78e6c1-a2fd-456e-b041-133f8fd77d20","appointment_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","farmer_name":"Md. Rashed Karim","farm_name":"Rashed Poultry Farm","flock_size":500,"bird_age_weeks":6,"breed":"broiler`
* **Database before -> after:**
  * `notes`: `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=Recheck in 3 days`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `2` -> `3`
  * `activity`: `2` -> `3`
  * `lastchange`: `Dr. Samira Rahman | edit | {"diagnosis": {"to": "Infectious bronchitis (suspected)", "from": ""}, "treatment_plan": {"to": "Supportive care, electrolytes in drinking water", "from": ""}}` -> `Dr. Samira Rahman | edit | {"next_steps": {"to": "Recheck in 3 days", "from": ""}}`
* **Screenshot:** [Doctor-7.png](audit_logs/nf56/shots/Doctor-7.png)

#### `Doctor-8` NF-6: a concurrent edit from another device is not overwritten (conflict) - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes (two browsers)`
* **Test data:** device B saves Warnings "Isolate the flock"; device A (stale) tries to save Next steps "STALE OVERWRITE"
* **UI action:** A: open editor; B: edit + save Warnings; A: change Next steps -> Save
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","next_steps":"STALE OVERWRITE","base_revision":3}` -> `409 {"detail":"These notes were changed after you opened them. Reload the latest notes and re-apply your edit.","code":"note_conflict","notes_revision":4,"current":{"diagnosis":"Infectious bronchitis (suspected)","treatment_`
* **Database before -> after:**
  * `notes`: `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn= | next=Recheck in 3 days` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn=Isolate the flock | next=Recheck in 3 days`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `3` -> `4`
  * `activity`: `3` -> `4`
  * `lastchange`: `Dr. Samira Rahman | edit | {"next_steps": {"to": "Recheck in 3 days", "from": ""}}` -> `Dr. Samira Rahman | edit | {"warnings": {"to": "Isolate the flock", "from": ""}}`
* **Screenshot:** [Doctor-8.png](audit_logs/nf56/shots/Doctor-8.png)

#### `Doctor-9` NF-6: reload the latest notes, re-apply the edit, save - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Edit notes`
* **Test data:** Next steps = "Recheck in 3 days, then weigh 20 birds"
* **UI action:** Reload the latest notes -> change Next steps -> Save 1 change
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","next_steps":"Recheck in 3 days, then weigh 20 birds","base_revision":4}` -> `200 {"id":"8e78e6c1-a2fd-456e-b041-133f8fd77d20","appointment_id":"47b0bd7e-14ad-4003-aae4-3a32f1d038b6","farmer_name":"Md. Rashed Karim","farm_name":"Rashed Poultry Farm","flock_size":500,"bird_age_weeks":6,"breed":"broiler`
* **Database before -> after:**
  * `notes`: `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn=Isolate the flock | next=Recheck in 3 days` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn=Isolate the flock | next=Recheck in 3 days, then weigh 20 birds`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `4` -> `5`
  * `activity`: `4` -> `5`
  * `lastchange`: `Dr. Samira Rahman | edit | {"warnings": {"to": "Isolate the flock", "from": ""}}` -> `Dr. Samira Rahman | edit | {"next_steps": {"to": "Recheck in 3 days, then weigh 20 birds", "from": "Recheck in 3 days"}}`
* **Screenshot:** [Doctor-9.png](audit_logs/nf56/shots/Doctor-9.png)

#### `Doctor-10` NF-6: audit history shows revision, author, timestamp, previous and new value - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes -> case -> Notes history`
* **Test data:** 
* **UI action:** press Notes history
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `history`: `5` -> `5`
* **Screenshot:** [Doctor-10.png](audit_logs/nf56/shots/Doctor-10.png)

#### `Doctor-11` NF-6: another doctor does not see this patient case - **PASS**

* **Role / route:** Doctor / `/doctor/case-notes`
* **Test data:** dr.mahfuz.kabir@example.com
* **UI action:** log in as another doctor -> Case Notes
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"dr.mahfuz.kabir@example.com","password":"***"}` -> `200 {"user":{"id":"571fe8c9-3f96-443b-9c83-8685406d0db0","email":"dr.mahfuz.kabir@example.com","phone":"+8801700001602","full_name":"Dr. Mahfuz Kabir","profile_photo_url":null,"date_of_birth":"1988-05-20","present_address":"`
* **Database before -> after:**
  * `notes`: `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn=Isolate the flock | next=Recheck in 3 days, then weigh 20 birds` -> `dx=Infectious bronchitis (suspected) | tx=Supportive care, electrolytes in drinking water | warn=Isolate the flock | next=Recheck in 3 days, then weigh 20 birds`
  * `status`: `in_progress` -> `in_progress`
  * `history`: `5` -> `5`
  * `activity`: `5` -> `5`
  * `lastchange`: `Dr. Samira Rahman | edit | {"next_steps": {"to": "Recheck in 3 days, then weigh 20 birds", "from": "Recheck in 3 days"}}` -> `Dr. Samira Rahman | edit | {"next_steps": {"to": "Recheck in 3 days, then weigh 20 birds", "from": "Recheck in 3 days"}}`
* **Screenshot:** [Doctor-11.png](audit_logs/nf56/shots/Doctor-11.png)

## 5. API checks made by the harness (negative / permission evidence, not UI steps)

`audit_logs/tools/nf56_evidence.py` -> `audit_logs/nf56/api_evidence.json`. Every request must be rejected.

| Area | Check | Request | Status | Expected |
|---|---|---|---|---|
| NF-5 | anonymous cannot request a revision | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 401 | 401 ok |
| NF-5 | a farmer cannot request a revision | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 403 | 403 ok |
| NF-5 | the author cannot send their own paper back | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 403 | 403 ok |
| NF-5 | an admin without research permission (pharmacy admin) cannot | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 403 forbidden_module_action | 403 ok |
| NF-5 | a research admin must give a reason (missing) | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 400 revision_reason_required | 400 ok |
| NF-5 | a research admin must give a reason (blank) | `PATCH /api/admin-panel/research-papers/8d8f93f7-d32e-47b3-a336-9fa75af02c53/ body={"action": "request_revision` | 400 revision_reason_required | 400 ok |
| NF-5 | a published paper is not revision-eligible | `PATCH /api/admin-panel/research-papers/3a0983d2-f3fa-4396-b47f-e716a3bb1abf/ body={"action": "request_revision` | 409 not_revision_eligible | 409 ok |
| NF-5 | revision history is not readable by a farmer | `GET /api/admin-panel/articles/8d8f93f7-d32e-47b3-a336-9fa75af02c53/revision-history/` | 403 | 403 ok |
| NF-5 | revision history is not readable by a pharmacy admin | `GET /api/admin-panel/articles/8d8f93f7-d32e-47b3-a336-9fa75af02c53/revision-history/` | 403 forbidden_module_action | 403 ok |
| NF-6 | anonymous cannot edit case notes | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 401 | 401 ok |
| NF-6 | the patient (farmer) cannot edit the doctor notes | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 403 | 403 ok |
| NF-6 | another doctor cannot edit this case | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 404 | 404 ok |
| NF-6 | another doctor cannot read the audit history | `GET /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/history/` | 404 | 404 ok |
| NF-6 | the patient cannot read the audit history | `GET /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/history/` | 403 | 403 ok |
| NF-6 | anonymous cannot read the audit history | `GET /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/history/` | 401 | 401 ok |
| NF-6 | the owner doctor: a recorded diagnosis cannot be blanked | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 400 note_cannot_be_cleared | 400 ok |
| NF-6 | the owner doctor: a stale base_revision is refused | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 409 note_conflict | 409 ok |
| NF-6 | the owner doctor: an over-long note is refused | `PATCH /api/doctor/cases/8e78e6c1-a2fd-456e-b041-133f8fd77d20/ body={"consultation_id": "47b0bd7e-14ad-4003-aae` | 400 | 400 ok |

Data unchanged by the rejected requests: NF-5 `pending_review||1|12` -> `pending_review||1|12` (identical); NF-6 `Infectious bronchitis (suspected)|Recheck in 3 days, then weigh 20 birds|5` -> `Infectious bronchitis (suspected)|Recheck in 3 days, then weigh 20 birds|5` (identical).

## 6. Tests (exact results)

```
manage.py test: Ran 31 tests in 13.825s OK
test_admin_consultations_null_time.py                27 passed, 0 failed
test_admin_dashboard_metrics.py                      12 passed, 0 failed
test_admin_earnings.py                               29 passed, 0 failed
test_admin_pagination_performance.py                 99 passed, 0 failed
test_admin_panel.py                                  66 passed, 0 failed
test_admin_row_builder_performance.py                35 passed, 0 failed
test_articles_feed.py                                28 passed, 0 failed
test_community.py                                    56 passed, 0 failed
test_community_feed_performance.py                   20 passed, 0 failed
test_consultation_booking_rules.py                   29 passed, 0 failed
test_consultation_chat_access.py                     13 passed, 0 failed
test_consultation_transitions_and_receipts.py        53 passed, 0 failed
test_cost_dashboard_charts.py                        20 passed, 0 failed
test_dashboard_integrity_and_seed_idempotency.py     13 passed, 0 failed
test_data_integrity.py                               11 passed, 0 failed
test_delivery_multi_active.py                        34 passed, 0 failed
test_delivery_proof_and_earnings.py                  27 passed, 0 failed
test_delivery_proof_review.py                        75 passed, 0 failed
test_delivery_route.py                               29 passed, 0 failed
test_disease_detection.py                            25 passed, 0 failed
test_doctor_flow.py                                  58 passed, 0 failed
test_farmer_panel.py                                 39 passed, 0 failed
test_feed_catalogue.py                               22 passed, 0 failed
test_feed_marketplace_ux.py                          20 passed, 0 failed
test_feed_order_delivery.py                          28 passed, 0 failed
test_feed_owner_flow.py                              32 passed, 0 failed
test_feed_stock_integrity.py                         29 passed, 0 failed
test_finance_admin.py                                35 passed, 0 failed
test_find_vet_discovery.py                           38 passed, 0 failed
test_flock_feed_management.py                        17 passed, 0 failed
test_labour_payment.py                               27 passed, 0 failed
test_nf_repairs.py                                   104 passed, 0 failed
test_pharmacy_admin.py                               132 passed, 0 failed
test_pharmacy_flow.py                                25 passed, 0 failed
test_pharmacy_locked_session.py                      104 passed, 0 failed
test_pharmacy_marketplace_card_fields.py             13 passed, 0 failed
test_pharmacy_medicine_edit.py                       7 passed, 0 failed
test_pharmacy_medicine_images.py                     20 passed, 0 failed
test_pharmacy_no_fabricated_data.py                  32 passed, 0 failed
test_pharmacy_profile.py                             32 passed, 0 failed
test_private_documents.py                            31 passed, 0 failed
test_profile_photo.py                                58 passed, 0 failed
test_research_revision.py                            39 passed, 0 failed
test_seed_platform_demo.py                           46 passed, 0 failed
test_signup_documents.py                             46 passed, 0 failed
test_signup_flows.py                                 107 passed, 0 failed
test_subscription_payment.py                         65 passed, 0 failed
test_tax_calculator.py                               64 passed, 0 failed
test_verification_flows.py                           36 passed, 0 failed
test_verification_status.py                          25 passed, 0 failed
test_vets_nearby.py                                  12 passed, 0 failed
TOTAL 51 script files, 2044 assertions, 0 failed
```

* `test_research_revision.py` (39): reason missing / empty / blank / over-long -> 400 with nothing changed; permissions (anonymous 401; farmer, the author, a doctor admin, a view-only admin -> 403); eligibility (draft, published, archived, needs_revision -> 409 and unchanged); success (200, status "Needs Revision", DB row, **exactly one notification** naming the reason, snapshot with admin/reason/time, activity log); a second request is refused and does not overwrite the first reason; a content admin can also do it; the history endpoint (status, reason, `can_request_revision`, 401/403/404 cases); a second round after resubmission.
* `test_nf_repairs.py` NF-6 additions (19): partial edit preserves the other notes; history entry has author, timestamp, `{from,to}` and revision number; stale `base_revision` -> 409 and nothing changes; blanking diagnosis/treatment -> 400; optional note can be cleared and is recorded; over-long / negative revision / malformed id -> 400; text trimmed; the patient, another doctor and anonymous cannot read or edit; the case is absent from another doctor's list.
* Flutter `nf5_research_revision_test.dart` (6): action only for Pending, hidden without `reject`, reason required (empty / 2 characters / spaces) and the PATCH carries `action` + reason, server refusal keeps the reason, Cancel sends nothing, History shows status/entries and recovers with Retry. `nf6_case_notes_test.dart` (7): existing notes loaded and Save disabled, only the changed field + `base_revision` sent, cannot blank a recorded diagnosis, server failure shown, conflict then reload then re-save, closed case locked, history entries and Retry.

## 7. Known limits / disclosures

* **Several browser attempts were harness failures and are archived** in `audit_logs/nf56/aborted_runs/` (run 1 of the NF-5 script, which failed on a bad SQL column, was overwritten by run 2 and is not archived): wrong assertions about card semantics (the semantic label of a card is truncated, so the orange "Revision requested: ..." line is asserted by the Flutter test, by the History dialog step and by the screenshot, not by the card label), scrolling windows that mixed sidebar buttons into cards, and a success snackbar that had already disappeared by the time it was read. In every case the application behaviour was correct; only the script was changed. The database was re-cloned before each rerun, so the final runs started from the same state.
* The NF-5 browser run does not repeat the **author resubmission -> second revision round** through the UI; the second round is covered by `test_research_revision.py`. The author-side check is the paper list showing "Needs Revision" plus the notification row (`notifications`: 1) - the researcher app has no dedicated notification-centre step in this run.
* NF-6 browser: the second device is a second Chrome instance logged in as the same doctor; "another doctor" is checked in the UI (case list empty of this patient) and by API for edit/history (404).
* Roles: `admin_content` and `admin_research` (and `admin_operations`/`admin`) hold `reject` on articles and can request revisions; a view-only admin can only read history. This follows the existing role matrix; I did not change it.
* A pre-existing behaviour kept: the legacy "Hide" action still moves published content to "Needs Revision" without a reason or snapshot; it is not part of this request.
* No commit was made. Still open elsewhere: the full 8-workflow rerun, the remaining medium/low faults, and NF-3/4/7 browser re-checks after later backend changes.

## 8. Screenshots

* [Doctor-1.png](audit_logs/nf56/shots/Doctor-1.png)
* [Doctor-10.png](audit_logs/nf56/shots/Doctor-10.png)
* [Doctor-11.png](audit_logs/nf56/shots/Doctor-11.png)
* [Doctor-2.png](audit_logs/nf56/shots/Doctor-2.png)
* [Doctor-3.png](audit_logs/nf56/shots/Doctor-3.png)
* [Doctor-4.png](audit_logs/nf56/shots/Doctor-4.png)
* [Doctor-5.png](audit_logs/nf56/shots/Doctor-5.png)
* [Doctor-6.png](audit_logs/nf56/shots/Doctor-6.png)
* [Doctor-7.png](audit_logs/nf56/shots/Doctor-7.png)
* [Doctor-8.png](audit_logs/nf56/shots/Doctor-8.png)
* [Doctor-9.png](audit_logs/nf56/shots/Doctor-9.png)
* [Doctor-after-reload.png](audit_logs/nf56/shots/Doctor-after-reload.png)
* [Doctor-closed-case.png](audit_logs/nf56/shots/Doctor-closed-case.png)
* [Doctor-conflict.png](audit_logs/nf56/shots/Doctor-conflict.png)
* [Doctor-editor-filled.png](audit_logs/nf56/shots/Doctor-editor-filled.png)
* [Doctor-editor-open.png](audit_logs/nf56/shots/Doctor-editor-open.png)
* [Doctor-history.png](audit_logs/nf56/shots/Doctor-history.png)
* [Doctor-saved.png](audit_logs/nf56/shots/Doctor-saved.png)
* [Doctor-status-menu.png](audit_logs/nf56/shots/Doctor-status-menu.png)
* [Doctor-validation.png](audit_logs/nf56/shots/Doctor-validation.png)
* [OtherDoctor-case-notes.png](audit_logs/nf56/shots/OtherDoctor-case-notes.png)
* [ResearchAdmin-1.png](audit_logs/nf56/shots/ResearchAdmin-1.png)
* [ResearchAdmin-2.png](audit_logs/nf56/shots/ResearchAdmin-2.png)
* [ResearchAdmin-3.png](audit_logs/nf56/shots/ResearchAdmin-3.png)
* [ResearchAdmin-4.png](audit_logs/nf56/shots/ResearchAdmin-4.png)
* [ResearchAdmin-5.png](audit_logs/nf56/shots/ResearchAdmin-5.png)
* [ResearchAdmin-6.png](audit_logs/nf56/shots/ResearchAdmin-6.png)
* [ResearchAdmin-7.png](audit_logs/nf56/shots/ResearchAdmin-7.png)
* [ResearchAdmin-after-request.png](audit_logs/nf56/shots/ResearchAdmin-after-request.png)
* [ResearchAdmin-all-content.png](audit_logs/nf56/shots/ResearchAdmin-all-content.png)
* [ResearchAdmin-card-needs-revision.png](audit_logs/nf56/shots/ResearchAdmin-card-needs-revision.png)
* [ResearchAdmin-dialog-empty.png](audit_logs/nf56/shots/ResearchAdmin-dialog-empty.png)
* [ResearchAdmin-dialog-filled.png](audit_logs/nf56/shots/ResearchAdmin-dialog-filled.png)
* [ResearchAdmin-dialog-short.png](audit_logs/nf56/shots/ResearchAdmin-dialog-short.png)
* [ResearchAdmin-history.png](audit_logs/nf56/shots/ResearchAdmin-history.png)
* [Researcher-sees-revision.png](audit_logs/nf56/shots/Researcher-sees-revision.png)
