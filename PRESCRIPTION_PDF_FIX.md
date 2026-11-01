# Prescription PDF Viewer — Fix

Root cause ([PRESCRIPTION_PDF_VIEWER_AUDIT.md](PRESCRIPTION_PDF_VIEWER_AUDIT.md)): the viewer asked for `Accept: application/pdf`. The DRF endpoint had only JSON renderers, so DRF answered **406 "Could not satisfy the request Accept header."** before the view ran. Both farmer and doctor were affected, on web and Windows.

The fix is applied on both sides: the server no longer refuses that request, and the client no longer makes it in a refusable form.

## Files changed

| File | Change |
|---|---|
| `backend/api/negotiation.py` *(new)* | `FileDownloadNegotiation`: for endpoints that return a file themselves. It never answers 406: the file is served as-is, and errors render as JSON with their real status, whatever `Accept` asked for |
| `backend/consultations/views.py` | `prescription_pdf` and `consultation_prescription_pdf` are now small `APIView`s (same URLs and names) with `FileDownloadNegotiation` and JSON-only error rendering (no browsable-API HTML on a file URL). They add `Content-Length` |
| `backend/doctor/prescriptions.py` | `is_valid_pdf()`. A stored PDF that is missing, **truncated or corrupt** is regenerated from the persisted prescription. A freshly built PDF is validated before it is stored. Viewing never creates a prescription or sends an email |
| `lib/core/documents/prescription_pdf_viewer.dart` | See below |
| `test/doctor_prescription_pdf_email_test.dart` | Two viewer tests from the previous task updated to the messages and behaviour this task specifies (403 no longer offers Retry; new 401/403/404 wording) |
| Tests | `backend/scripts/test_prescription_pdf_viewer.py`, `test/prescription_pdf_viewer_test.dart` *(new)* |

No model, schema or migration change.

## API behaviour

`GET /api/consultations/prescriptions/<id>/pdf/` and `GET /api/consultations/<consultation_id>/prescription/pdf/`:

| Request | Before | After |
|---|---|---|
| Farmer, doctor or admin with `Accept: application/pdf` | **406** JSON | **200** `application/pdf`, complete bytes, `Content-Length`, `inline; filename="featherflow-prescription-RX-….pdf"`, `private, no-store`, `nosniff` |
| … `Accept: */*`, browser navigation, no Accept | 200 | 200 (unchanged) |
| Unauthenticated | 406 with `application/pdf`; 401 otherwise | **401** JSON for every Accept |
| Another farmer or doctor | 406 / 403 | **403** JSON `code: forbidden` for every Accept |
| Missing prescription or consultation | 406 / 404 | **404** JSON `code: not_found` / `no_prescription` |
| Stored file deleted or truncated | Deleted: regenerated; truncated: **served broken** | Regenerated from the database and served. No new prescription, no email, delivery record untouched |

Access control is unchanged: the consultation's farmer, the assigned doctor, or an `is_staff` admin reviewer (the existing private-document policy). Nothing exposes the storage path.

## Flutter viewer (shared by farmer and doctor)

* **Request:** `Accept: application/pdf, application/json;q=0.9` plus the Bearer JWT from the current or restored session; the id is percent-encoded. Even a server with default negotiation can now answer an error as JSON instead of 406.
* **Validation:** a 2xx must be `application/pdf` *and* start with `%PDF-`. Otherwise it is "could not be read" with Retry; a 200 non-PDF is never rendered.
* **States:**

| Situation | Shown |
|---|---|
| Fetching | Spinner + "Loading prescription…" |
| 200 valid PDF | Full-screen `PdfPreview` (view / print / download; Share replaced by Download, see PRESCRIPTION_PDF_DOWNLOAD_FIX.md) |
| 401 | "Your session has expired. Please sign in again." + **Sign in** (clears the stale session, goes to `/login`) |
| 403 | "You do not have permission to view this prescription." + Close |
| 404 | "Prescription not available." + Close |
| Corrupt or non-PDF body, render failure (`PdfPreview.onError`) | "The prescription file could not be read. Please try again." + **Retry** |
| 5xx / network | "The prescription PDF could not be loaded. Check your connection and try again." + **Retry** |

  Raw server text, `detail` strings and stack traces are never shown.
* **Double tap:** one viewer and one request. The guard follows the viewer route's `isActive`, so it can't get stuck after the stack is replaced (e.g. "Sign in"). The first version, a flag, did get stuck; the tests found it.
* **Retry:** an early failure is no longer reported as an unhandled async error.
* **Back:** the Close button or system back returns to the Case page or My Consultations.

## Platforms

* **Web:**
  * Bytes go straight to `PdfPreview`, rendered with pdf.js, with no file path.
  * Print opens the browser print dialog; share downloads the file.
  * CORS: dev allows any origin. **Production must list the web app's origin in `CORS_ALLOWED_ORIGINS`.**
  * `printing` fetches pdf.js from `unpkg.com` at runtime. If it is blocked, the viewer shows the "could not be read" state with Retry.
* **Windows:** bytes are rasterised by printing's bundled PDFium. There are no temp files, so there is no path handling or clean-up to secure.

## Tests and results

| Gate | Result |
|---|---|
| `backend/scripts/test_prescription_pdf_viewer.py` *(new)* | **56/56** |
| `test/prescription_pdf_viewer_test.dart` *(new)* | **13/13** |
| `test/doctor_prescription_pdf_email_test.dart` | 11/11 |
| _Other gates_ | _below_ |

**Backend: what it covers**
* **The reported request:** farmer and doctor with `Accept: application/pdf` get 200.
* **Every real client header:** `application/pdf`, the app's header, browser navigation, `*/*` and none, for farmer, doctor and admin, on both endpoints. Each returns complete bytes equal to the stored file, the `%PDF-` header and `%%EOF`, a matching `Content-Length`, the filename, `no-store` and `nosniff`.
* **Errors for every header:** unauthenticated 401, other farmer or doctor 403 `forbidden`, missing 404 `not_found`, all as JSON. A refusal never carries PDF bytes or a PDF content type.
* **No leaks:** headers and error bodies contain no storage path or secret.
* **CORS:** a cross-origin GET carries `Access-Control-Allow-Origin`, and the preflight allows `Authorization` (dev configuration).
* **Regeneration:** a deleted stored file and a truncated one are both regenerated and served. Repeated views create no prescription, send no email, and leave the delivery record untouched.

**Flutter: what it covers**
* **The fake server negotiates like DRF:** asking for the PDF alone gets the 406.
* **The request:** it is answerable, authenticated and correct.
* **Real screens:** the doctor Case page opens the PDF and Back returns to the case; the farmer's My Consultations screen opens it with the farmer's token.
* **States:** loading; 403 shows the permission message with no Retry; 404 shows "not available"; 401 shows the session message, and Sign in clears the session and lands on `/login` (GoRouter).
* **Failures:** a corrupt body shows Retry, which then succeeds. A 500 with traceback text shows a generic message and never the raw text. A 200 JSON body is never rendered.
* **Double tap:** one viewer and one request, and the guard resets after close.
* **Layout:** 360px and 1400px full screen.

**Negative controls**
* **Old negotiation restored (server):** 13 backend checks fail, all with the screenshot's 406.
* **Old `Accept: application/pdf` header (client):** 10 of 13 Flutter tests fail, including the farmer and doctor flows.

Both files were restored byte-for-byte afterwards.

## Manual verification (not run by hand)

There is no browser or desktop automation in this environment, so these steps are for you. Run `.\run_backend.bat`, then `flutter run -d chrome` and `flutter run -d windows`.

* **Farmer** `farmer.rashed@example.com`:
  * Find Vet → My Consultations → the consultation with `RX-20261101-1A37DBF2` → View prescription PDF. **The PDF renders.**
  * Refresh the page and open it again. Try print and share.
* **Doctor** `dr.samira.rahman@example.com`: Case page → View PDF. **The PDF renders.** Refresh, reopen, and press Back.
* **Negative:**
  * Another farmer: the PDF URL returns 403, shown as "You do not have permission…".
  * Logged out: 401, shown as "session expired" with Sign in.
  * Backend stopped: the "could not be loaded" message; Retry works once the backend is back.

The server half was verified against that real prescription: the exact app request, `Accept: application/pdf` with the farmer's and the doctor's JWT, now returns 200 with the stored PDF, where before it returned 406.

## Limitations

* **pdf.js on web:** it loads from `unpkg.com` at runtime, a property of the `printing` package. Offline or CDN-blocked deployments need pdf.js self-hosted in `web/` (`pdfjsLib` loaded in `index.html`); not done here.
* **Admin CSV exports:** they likely have the same 406 problem with `Accept: text/csv`. Not verified and not changed (see the audit, §5).
* **No token refresh:** the app has no token-refresh flow, so an expired session means signing in again, which the viewer now offers.
