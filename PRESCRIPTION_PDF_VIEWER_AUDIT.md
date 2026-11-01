# Prescription PDF Viewer — Audit

**Date:** 2026-11-01
**Reported:** opening a prescription PDF, as the farmer or the doctor, showed an error screen, *"Could not satisfy the request Accept header."*, with Retry, instead of the PDF.

The fix is in [PRESCRIPTION_PDF_FIX.md](PRESCRIPTION_PDF_FIX.md).

## 1. Reproduction (real data, dev DB)

There is one real prescription: `RX-20261101-1A37DBF2` (`1a37dbf2-e57e-4dee-97f4-79e5a254b4cb`), consultation `11a947fd-cc0d-42ee-a736-d3207f11cb78`. Its PDF is stored, and its email status is `sent`.

| | Farmer | Doctor |
|---|---|---|
| Account | `farmer.rashed@example.com` (consultation farmer) | `dr.samira.rahman@example.com` (assigned doctor) |
| Screen | Find Vet → My Consultations → prescription card → *View prescription PDF* | Case page → Prescription & Advice → *View PDF* |
| Flutter code | `PrescriptionPdfService.fetch` → `PrescriptionPdfViewer` (shared) | same |
| Request | `GET /api/consultations/prescriptions/1a37dbf2-…/pdf/` | same |
| Headers | `Authorization: Bearer <JWT>` (present, valid); `Accept: application/pdf` | same |
| Status | **406 Not Acceptable** | **406** |
| Response | `application/json` `{"detail":"Could not satisfy the request Accept header.","error":{"code":"NOT_ACCEPTABLE",…}}` | same |
| Backend log | `WARNING django.request: Not Acceptable: /api/consultations/prescriptions/…/pdf/` (no traceback) | same |
| Flutter | The non-2xx status was turned into an exception carrying the server's `detail`, which the viewer displayed verbatim (the screenshot) | same |
| Same request **without** the `Accept` header | **200** `application/pdf`, `inline; filename="featherflow-prescription-RX-20261101-1A37DBF2.pdf"`, a valid `%PDF-1.4 … %%EOF` | **200** |

Web and Windows behave the same, because the response is decided on the server before any platform code runs.

## 2. Trace

```
tap View PDF ─► URL built correctly ─► JWT attached ✔
  ─► DRF APIView.initial():
       perform_content_negotiation()  ✘  NotAcceptable (406)
       (authentication / permissions / the view body never ran)
  ─► JSON error returned ─► viewer shows the server detail
```

**Failing stage: backend content negotiation, before authorization and before the view.**

## 3. Root cause

The PDF endpoints were DRF function views (`@api_view`). DRF picks a renderer *before* running a view, and this project only has `JSONRenderer` and `BrowsableAPIRenderer`.

The app correctly asks for `Accept: application/pdf`. No renderer produces `application/pdf`, so DRF raised `NotAcceptable` and answered 406.

The view itself returns the PDF as a plain `HttpResponse`, so it never needed a PDF renderer. Negotiation simply ran first.

**Classification:** response negotiation (a headers problem) between the Flutter request and the DRF view configuration. It was **not**:
- authorization (the JWT was valid and the checks were never reached);
- PDF generation or storage (the stored file is valid);
- CORS, the PDF package, or web/Windows file handling.

### Why the tests didn't catch it

* The backend suites called the endpoint with Django's test client and **no `Accept` header**. DRF then falls back to JSON, which is acceptable, and the view returned the PDF.
* The Flutter tests used a fake server that **ignored request headers**.
* The bug predates the prescription work: the farmer's original fetch already sent `Accept: application/pdf`. It was never seen because no prescription could be issued until the authority fix.

## 4. Everything else inspected

| Item | Finding |
|---|---|
| URL construction | Correct (`{baseUrl}/api/consultations/prescriptions/<uuid>/pdf/`). Now also percent-encodes the id |
| Auth header | Correct Bearer JWT, from the current or restored session |
| Access control | Farmer, assigned doctor or `is_staff` admin; others 403; unauthenticated 401 |
| Storage | `private_media/clinical_prescriptions/<id>.pdf` present and valid. Missing files were regenerated; **corrupt or truncated** files were not, which is now fixed |
| Response headers | `application/pdf`, a safe `inline` filename built from the reference, `no-store`, `nosniff`. **No `Content-Length`**, now added |
| CORS | Dev (`DEBUG`) allows any origin with credentials. The preflight for `Authorization` + `Accept` passes (tested). Production must list the web origin in `CORS_ALLOWED_ORIGINS` |
| Flutter HTTP handling | A 200 PDF was handled correctly. Non-2xx responses showed the raw server `detail`, which the spec forbids; now mapped to fixed messages |
| PDF package (`printing` 5.14.3) | Bytes are passed straight to `PdfPreview`, with no file path, which is correct for web and Windows. `onError` was not used, so a render failure showed the package's own error; now handled |
| Web | `printing` loads **pdf.js from `https://unpkg.com/pdfjs-dist`** at runtime (`printing_web.dart`), because `web/index.html` doesn't provide it. Works online; offline or with the CDN blocked, the render fails, which now shows a clear message with Retry. No CSP blocks it |
| Windows | `printing` rasterises with its bundled PDFium from bytes; no temp file is needed, so there is no path handling to secure |
| Retry | A failure before the next frame was reported as an unhandled async error (found by the new tests); fixed |
| Double tap | Could push two viewers and send two requests; now guarded |

## 5. Related finding (not changed)

The admin CSV exports (`/api/admin-panel/<module>/export/`, `/admin-payments/export/`) are also DRF `@api_view`s, and the admin app calls them with `Accept: text/csv`. By the same mechanism they will most likely answer 406.

This was **not verified**: running it needs a super-admin token, and minting one for a real admin account was not permitted in this session. Fixing it is a one-line change: give those views `content_negotiation_class = FileDownloadNegotiation` (`api/negotiation.py`), or call them with `Accept: text/csv, application/json;q=0.9`.
