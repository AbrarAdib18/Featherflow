# Doctor Prescription — PDF and Email Delivery

Why prescribing was blocked, and what changed in eligibility: [DOCTOR_PRESCRIPTION_AUTHORITY_AUDIT.md](DOCTOR_PRESCRIPTION_AUTHORITY_AUDIT.md).

## Flow

```
Doctor: Case page (consultation completed) → Issue Prescription and Advice → Save and email PDF
  POST /api/doctor/prescriptions/
    ┌ one transaction ───────────────────────────────────────────────┐
    │ prescription + medicines + follow-up (+ follow-up notification) │
    │ reference RX-YYYYMMDD-XXXXXXXX · "Prescription added" notification│
    └──────────────────────────────────────────────────── committed ──┘
    then (never rolls the above back):
      1. generate the PDF from the persisted rows → private storage → pdf_file
      2. claim + send the email (PDF attached) → email_status sent | failed
  201 → Case page shows the prescription, reference, delivery status, View PDF
Farmer: Find Vet → My Consultations → prescription card → View prescription PDF
```

## What was already there, and what changed

| Area | Before | After |
|---|---|---|
| PDF | ReportLab, basic text, regenerated on every view. User text went into paragraph markup unescaped, so a `<` or `&` aborted the PDF | Branded, professional layout (below). All text escaped. Generated once and **stored privately**; every view and the email use the same file |
| Email | Sent in `on_commit` with a generic subject. Only `email_sent_at` / `email_error` recorded. A resend always re-sent | Subject "Your prescription from Dr. … – FeatherFlow" with a professional body. **Delivery record per prescription** (status, recipient, attempts, last attempt, message id, sanitised error). A send is claimed under a row lock, so it is never duplicated except by a deliberate doctor resend |
| Retry | None | `manage.py retry_prescription_emails` (idempotent), plus "Retry email" on the Case page for failed deliveries only |
| PDF access | Farmer and prescribing doctor only. Unauthenticated → 401 | Same, plus admin reviewers (`is_staff`), as the existing private-document policy allows (`verification/documents.py`). Added `GET /api/consultations/<consultation_id>/prescription/pdf/` (the latest prescription) |
| Doctor UI | No PDF access; "Share Rx" on the Prescriptions screen was a stub ("connect to your backend") | View PDF on the Case page and the Prescriptions screen, a delivery status line, and Retry email when it failed |
| Farmer UI | PDF opened in a dialog; on failure a passing snackbar showed `AuthException(...)` | The shared full-screen viewer (view / print / share) shows the reason with **Retry**. The card shows the doctor, date, reference and an accurate delivery line |

## Files

| File | Change |
|---|---|
| `backend/doctor/views.py` | Removed the `prescription_authority` gate. The prescription write is now `_create_prescription` (one transaction; structured 400 / 404 / 409); PDF and email run only after it commits. `_prescription_row` adds the delivery fields, with timestamps as ISO plus offset. The resend endpoint goes through the claimed sender |
| `backend/doctor/prescriptions.py` *(new)* | `ensure_pdf` (generate once, store privately), `deliver_email` (row-lock claim; no re-send of a sent email unless deliberate; a stale `sending` can be retried after 15 min; secrets scrubbed from errors), `issue_documents`, `retry_candidates`, `can_view`, `delivery_fields`, `build_email` |
| `backend/doctor/prescription_pdf.py` | Rewritten builder (below); `reference_for`, `doctor_display_name` |
| `backend/doctor/management/commands/retry_prescription_emails.py` *(new)* | Retries `failed`, `pending` and stale `sending` deliveries, `--max-attempts` (default 5), `--dry-run` |
| `backend/doctor/serializers.py` | Medicine validation: trimmed; name, dosage and duration required; column limits (150 / 100 / 50 / 2000); 1–30 medicines; text fields up to 5000 |
| `backend/doctor/models.py` | `ClinicalPrescription`: `reference_number`, `pdf_file`, `pdf_generated_at`, `pdf_error`, `email_status`, `email_recipient`, `email_attempts`, `email_last_attempt_at`, `email_message_id` |
| `backend/consultations/views.py`, `urls.py` | Shared `_farmer_prescription_row` with delivery fields (consultation list and clinical results); PDF endpoints served from storage with a structured 403/404 and `nosniff`; the new consultation-level PDF route |
| `backend/postgres_backend_extension.sql` | Idempotent `ALTER TABLE clinical_prescriptions ADD COLUMN IF NOT EXISTS …` (status `CHECK`), backfill of status and reference for older rows, unique index on `reference_number`. **Applied to the dev DB.** No Django migration (`managed = False`, as for every table here) |
| `lib/core/documents/prescription_pdf_viewer.dart` *(new)* | `PrescriptionPdfService.fetch` (JWT; 401 / 403 / 404 mapped to clear messages), `PrescriptionPdfViewer` (loading / error + Retry / `PdfPreview` with print and share), `showPrescriptionPdf` |
| `lib/features/doctor/data/models/doctor_models.dart` | `DoctorPrescription`: reference, email status, recipient, error, PDF availability; issue time parsed as a UTC instant |
| `lib/features/doctor/data/services/doctor_session.dart` | `retryPrescriptionEmail` (per-case in-flight guard) |
| `lib/features/doctor/presentation/screens/doctor_case_notes_screen.dart` | Prescription card: reference and issue time, delivery line, View PDF, Retry email (failed only). The success message reflects the actual delivery |
| `lib/features/doctor/presentation/screens/doctor_prescriptions_screen.dart` | "Share Rx" stub → **View PDF** |
| `lib/features/farmer/...` | `farmer_consultations_screen.dart`: richer prescription card plus the shared viewer. `farmer_consultation_service.dart`: `prescriptionPdf` delegates to the shared fetch |
| Tests | `backend/scripts/test_prescription_pdf_email.py`, `test/doctor_prescription_pdf_email_test.dart` |

## The PDF

Built only from persisted rows: the prescription and its items, consultation, case, clinical note, farmer and farm, doctor profile, and the pending follow-up.

* **Header band:** FeatherFlow / Veterinary Prescription, the **reference** `RX-YYYYMMDD-XXXXXXXX` and the **prescription date**.
* **Prescribed by:** Dr. name, qualification, specialty, licence number and authority, clinic. These come from the doctor's profile; no phone or email.
* **Issued to:** farmer, farm, flock (breed, size, age), consultation date, time and mode, case reference.
* **Body:**
  * the diagnosis, when recorded;
  * the **medicines table** (#, medicine, dosage, duration, instructions), with wrapping cells and a header that repeats on page breaks;
  * case advice, dosage notes, follow-up instructions, the **follow-up appointment date and time**, and referral.
* **Signature block:** a line, the doctor's name, qualification and licence, and "Issued electronically on …".
* **Footer on every page:** a short disclaimer, reference, **generation timestamp** in local time, and page number.
* **Robustness:**
  * Empty optional fields are omitted.
  * Long text and up to 30 medicines paginate. The test covers 5000-character advice and 30 long medicines, giving 3+ pages.
  * Markup characters print literally.

## Storage and access

* **Location:** `backend/private_media/clinical_prescriptions/<prescription id>.pdf`. This is the existing private storage: outside `MEDIA_ROOT` and never served statically. `/media/<path>` returns 404, which is tested.
* **Database record:** `pdf_file` holds the storage key; it is **never** in an API response. `pdf_generated_at` and `pdf_error` record the outcome.
* **Generated once:** the stored file is what was emailed and what is served. If it is missing, for example on rows issued before this change, it is generated and stored on first view.
* **Endpoints**, both authenticated:
  * `GET /api/consultations/prescriptions/<id>/pdf/`
  * `GET /api/consultations/<consultation_id>/prescription/pdf/` (the latest prescription)

  Allowed: the consultation's farmer, the prescribing doctor, or an admin reviewer (`is_staff`). Anyone else gets 403 `forbidden`, an unknown id 404 `not_found`, a consultation with none 404 `no_prescription`, and an unauthenticated caller 401.
* **Response headers:** `application/pdf`, `inline; filename="featherflow-prescription-RX-….pdf"`, `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff`.

## Email delivery

* **Recipient:** the farmer's registered email (`users.email`) at send time, recorded in `email_recipient`.
* **Subject:** `Your prescription from Dr. <name> – FeatherFlow`.
* **Body:**
  * a greeting, the doctor, the farm, the prescription date and reference;
  * "open the attached PDF";
  * where it lives in the app;
  * the FeatherFlow sign-off.

  There are no medical details, links, tokens or storage paths, which is tested. **Attachment:** the stored PDF.
* **When:** right after the prescription transaction commits, in the same request. The project has no task queue; the send is bounded by `EMAIL_TIMEOUT` (default 10 s). An SMTP failure **never** rolls back the prescription, medicines, follow-up, notification or PDF; it is recorded as `failed`.
* **States:** `pending → sending → sent | failed`, on the prescription row (one delivery record per prescription), plus `email_attempts`, `email_last_attempt_at`, `email_sent_at`, `email_message_id` (the Message-ID header) and `email_error`.
  * The error is prefixed with the exception class, truncated to 500 characters, and has the configured SMTP user and password replaced with `***`.
  * The same scrubbed text is logged; this is tested.
* **No duplicates:**
  * Each send first claims the row under `SELECT … FOR UPDATE`. A `sent` row is never re-sent automatically, and a `sending` row is skipped unless it is stale (15 min).
  * Viewing or fetching a prescription never sends anything.
  * **4 concurrent retries → 1 email** (tested). Without the guard, the same test sent 3.
* **Retry:**
  * **Doctor:** "Retry email" on the Case page, shown only when the delivery `failed`. It calls `POST /api/doctor/prescriptions/<id>/resend-email/`, which re-sends the same stored PDF and never creates a new prescription.
  * **That endpoint** remains a *deliberate* resend: the prescribing doctor can resend even after a success, which the existing `test_doctor_flow` asserts. An in-flight send is not duplicated.
  * **Ops:** `python manage.py retry_prescription_emails [--max-attempts 5] [--dry-run]`. It is idempotent; schedule it every 15–30 minutes.

### SMTP settings (existing, in `featherflow_backend/settings.py` and `.env`)

| Variable | Purpose / default |
|---|---|
| `EMAIL_BACKEND` | `django.core.mail.backends.smtp.EmailBackend` for real delivery. **If unset in DEBUG, it is the console backend: the email, with its attachment, is printed in the backend terminal and recorded as `sent`** |
| `EMAIL_HOST`, `EMAIL_PORT` | SMTP server (default `localhost`, `587`) |
| `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD` | Credentials, from the environment only; never stored, logged or returned |
| `EMAIL_USE_TLS` | Default `True` |
| `EMAIL_TIMEOUT` | Seconds (default `10`); bounds how long issuing waits on an SMTP outage |
| `DEFAULT_FROM_EMAIL` | Sender, e.g. `FeatherFlow <noreply@yourdomain>`; its domain is used for the Message-ID |

## API additions

* **Doctor rows, farmer rows and clinical results:** prescription rows add `reference_number`, `issued_at`, `doctor_name`, `pdf_available`, `pdf_generated_at`, `email_status`, `email_recipient`, `email_attempts`, `email_last_attempt_at` and `email_error` (only when failed). `created_at` and `email_sent_at` now carry a `+00:00` offset.
* **Errors:** prescription errors are structured: `{detail, code, errors?}`.

## Tests

| Gate | Result |
|---|---|
| `backend/scripts/test_prescription_pdf_email.py` *(new)* | **83/83** |
| `test/doctor_prescription_pdf_email_test.dart` *(new)* | **11/11** |
| doctor_case_workflow / doctor_flow / transitions_and_receipts / booking_rules | 88/88 · 58/58 · 53/53 · 29/29 |
| doctor_consultation_queue / find_vet_discovery / chat_access / chat_message_state | 43/43 · 38/38 · 13/13 · 43/43 |
| notifications / signup_documents | 135/135 · 46/46 |
| admin_panel | 62/63 (known pre-existing "admin login 200" email-verification gate) |
| private_documents | **Blocked by the environment:** crashes at its ML disease-scan section because `torch` is not installed in the venv (`ModuleNotFoundError`), independent of this change. The 6 checks before that pass (receipt access by owner / other / anonymous / admin) |
| `manage.py check` / `migrate --check` | clean / exit 0 |
| `manage.py test doctor messaging consultations notifications` | 22 tests, 1 error: the known pre-existing `test_discovery_row_exposes_farmer_facing_fields`. The PDF unit test (minimal fixture) passes with the new builder |
| `flutter test` | 345 passed, 2 failed (the known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart`) |
| `flutter analyze lib test` | only the 6 known infos in `farmer_feed_marketplace_screen.dart` |
| `flutter build web --release` | built |

**Backend suite: what it covers**
* **Authority and eligibility:** see the authority audit.
* **Validation:** missing advice, missing dosage, an over-long dosage (previously a DB 500) and more than 30 medicines are refused, and nothing is written.
* **Persistence:** all fields and medicines, the reference format, and the follow-up with its exact time.
* **Stored PDF:** a private path, not under `MEDIA_ROOT`, never exposed.
* **Email:** exactly one; recipient, subject, attachment name and type, the same bytes as the stored PDF; body contents and exclusions; the delivery record including a Message-ID matching the sent mail.
* **PDF contents (all 19 fields):** checked by inflating the PDF's text streams.
* **PDF edge cases:** empty optional fields, long multi-page prescriptions, literal markup.
* **Access:** farmer, doctor and admin get 200; another farmer or doctor 403; unauthenticated 401; missing 404; the consultation-level endpoint; `/media/` returns 404.
* **No duplicate sends:** views, fetches, automatic delivery and the retry command never re-send.
* **Farmer rows:** the consultation list and clinical results carry everything.
* **SMTP failure:** the provider error includes the password. The prescription, medicines, PDF and notification are kept; the record is `failed`; the secret is scrubbed from the DB, the API and the logs. A dry run lists the failed one; the retry command delivers it once; re-running sends nothing.
* **Concurrency:** 4 concurrent retries → one email.
* **Resend permissions:** doctor-only deliberate resend (another doctor 404, the farmer 403).
* **Farmer without an email:** 201, with a clear failed reason.

**Flutter suite: what it covers**
* **Parsing:** the delivery fields, plus the legacy fallback.
* **Issuing:** works with no authority block, and the success message names the reference and the email.
* **Failed send:** the reason is shown, plus Retry email. Retry is disabled while in flight; a double tap sends one request and never re-issues; it then shows "emailed" and the button goes away.
* **View PDF:** calls the protected endpoint with the JWT and opens the viewer.
* **Viewer:** an access error shows the reason, and Retry loads the PDF. That test found a real `setState`-returns-Future bug in Retry, now fixed. HTTP 401, 403 and 404 map to clear messages.
* **Farmer card:** shows the medicines, dosage, duration, instructions, advice, follow-up date and time, doctor and reference, plus the delivery line. View PDF uses the farmer's JWT. A failed email still offers the PDF.
* **Layout:** 360px and 1400px with no overflow.

**Negative controls**
* **Old authority gate restored:** the backend suite reproduces the screenshot error.
* **Automatic delivery allowed to re-send a sent email:** 4 checks fail, and the concurrent test sent 3 emails.
* **"Retry email" shown after a successful send:** 2 Flutter tests fail.

Every file was restored byte-for-byte afterwards.

## Manual verification checklist (not yet run by hand)

1. Set real SMTP values (`EMAIL_BACKEND` smtp, host, port, user, password, TLS, `DEFAULT_FROM_EMAIL`). Without them, in DEBUG, the email appears in the backend terminal.
2. Run `.\run_backend.bat` and `flutter run -d chrome` (or `-d windows`).
3. **Doctor** `dr.samira.rahman@example.com`:
   1. Open a case and close it, then Mark as Complete.
   2. Issue prescription & advice with a medicine, dosage, duration, instructions, advice, follow-up instructions and a follow-up date. **No authority error.**
   3. The card shows the reference, "PDF emailed to …" and View PDF; the PDF opens.
4. **Inbox:** the email "Your prescription from Dr. … – FeatherFlow" arrives with the PDF attached.
5. **Farmer** `farmer.rashed@example.com`:
   * The notification "Prescription added" appears.
   * Find Vet → My Consultations → the consultation shows the prescription.
   * View prescription PDF opens full screen with print and share.
6. **Negative:** another farmer can't open the PDF URL (403), and logged out it gets 401.
7. **SMTP outage:** set a wrong `EMAIL_HOST_PASSWORD` and issue. The prescription still appears, the card says "Email not delivered", and Retry email works once the password is fixed.

## Limitations

* **Synchronous email:** the send runs inside the issuing request after commit, because there is no task queue. An SMTP outage delays the response by up to `EMAIL_TIMEOUT` but never loses the prescription.
* **Development "sent":** with the console or locmem backend (the DEBUG default), `sent` means the backend accepted the message, not that a mailbox received it.
* **Multiple prescriptions:** still allowed per consultation (existing policy: revisions). The UI prevents double submits, but there is no server idempotency key for prescriptions.
* **Old rows:** prescriptions issued before this change get their PDF generated on first view. The SQL backfill sets their reference and status.
* **No retry scheduler:** the retry command must be scheduled by ops; nothing runs it automatically yet.
* **Signup and vet-detail wording:** see the follow-ups in the authority audit.
