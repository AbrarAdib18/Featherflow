# Prescription PDF Viewer — Share → Download

**Date:** 2026-11-01
**Request:** remove the Share button from the prescription PDF viewer (farmer and doctor) and add a Download button. Web downloads through the browser; Windows saves the PDF to a user-accessible location.

Builds on [PRESCRIPTION_PDF_FIX.md](PRESCRIPTION_PDF_FIX.md) (viewer and access control) and [DOCTOR_PRESCRIPTION_PDF_EMAIL.md](DOCTOR_PRESCRIPTION_PDF_EMAIL.md) (PDF generation and storage).

## What was there

* **One shared viewer.** `lib/core/documents/prescription_pdf_viewer.dart` is used by the farmer (My Consultations → *View prescription PDF*) and the doctor (Case page → *View PDF*, Prescriptions → *View PDF*).
* **Share came from the PDF package.** It was `printing`'s `PdfPreview` toolbar (`allowSharing: true`). On web that action downloads; on Windows it opens the system share flow. It wasn't a download on Windows, and it wasn't labelled.
* **The PDF is fetched once.** The viewer fetches it from the authenticated endpoint (`GET /api/consultations/prescriptions/<id>/pdf/`; farmer, assigned doctor or admin reviewer only) and renders the bytes in memory.

## What changed

| File | Change |
|---|---|
| `lib/core/documents/prescription_pdf_viewer.dart` | `allowSharing: false` (Print kept). A labelled **Download** button in the viewer's app bar, shown only once the authorised PDF has loaded. It saves the **same bytes already on screen**, so there is no second request. States: *Downloading…* (button disabled, spinner); success message; error message with **Retry**; *Download cancelled*. A double tap is ignored while a download runs. Test seam: `PrescriptionPdfViewer.debugSaverOverride` |
| `lib/core/documents/pdf_saver.dart` *(new)* | `savePdfToDevice` (conditional import per platform), `PdfSaveResult`, and `prescriptionPdfFileName` |
| `lib/core/documents/pdf_saver_web.dart` *(new)* | Browser download: `Blob(application/pdf)` → object URL → hidden `<a download="…">` click → URL revoked afterwards |
| `lib/core/documents/pdf_saver_io.dart` *(new)* | Windows / desktop: native **Save as** dialog (`file_picker`, already a dependency), then the app writes the bytes. Mobile: the picker writes them |
| `pubspec.yaml` | `web: ^1.1.1` declared directly (it was already resolved through `printing`). `pubspec.lock`: only the dependency kind changed (`transitive` → `direct main`), same version |
| `test/prescription_pdf_download_test.dart` *(new)* | See Tests |

Not changed: the backend, PDF generation, prescription persistence, email delivery, access-control rules, and the fetch itself.

## Platform behaviour

**Web**
* **How:** the bytes are handed to the browser as a download (Blob + `<a download>`). They land in the browser's download location (usually *Downloads*) or wherever the browser is set to ask. There is no local file path involved.
* **Validity:** the file is exactly the PDF the viewer loaded, which already passed the content-type and `%PDF-` checks.
* **After a refresh:** downloading needs no extra request, so it works whenever the viewer has loaded. The viewer fetches with the current or restored session after a refresh.

**Windows**
* **How:** the native **Save as** dialog opens, pre-filled with the file name and filtered to PDF. The app writes the file where the user chose.
* **No silent overwrite:** Windows' own dialog asks before replacing an existing file. Cancelling writes nothing and shows *Download cancelled*. A name typed without `.pdf` still saves as `.pdf`.
* **Success message:** shows the file name and the chosen folder's name (e.g. *Saved FeatherFlow_Prescription_RX-….pdf to Downloads*), not a full path.
* **Errors:** a write failure (permissions, missing folder) shows *"The PDF could not be saved. Please try again."* with Retry. The raw OS error, which can contain local paths, is never shown.

## File name

`FeatherFlow_Prescription_<reference>.pdf`, for example `FeatherFlow_Prescription_RX-20261101-1A37DBF2.pdf`. Characters outside `A–Z a–z 0–9 _ -` become `_`, so there are no path separators and no `..`. With no reference the prescription id is used, and with nothing at all the name is `FeatherFlow_Prescription_document.pdf`. Print keeps using the same name for print jobs.

## Access control

Download adds no new way to reach a PDF:

* **Only after an authorised load.** The button exists only after the viewer has loaded the PDF from the access-controlled endpoint.
* **Refused users never see it.** Another farmer or doctor gets 403, so the viewer shows *"You do not have permission…"* and **no Download button**, and nothing is saved (tested for both roles).
* **Same bytes, no new request.** Download saves the bytes from that authorised response; it makes no request of its own and never builds a URL.
* **Server rules unchanged.** Only the consultation's farmer, the assigned doctor and admin reviewers can fetch the PDF; others get 403 and unauthenticated users 401 (`backend/scripts/test_prescription_pdf_viewer.py`, 56/56 in the previous fix).
* **Nothing exposed.** No storage path, token or URL appears in the UI or the file name.

## Tests and results

`test/prescription_pdf_download_test.dart`: **15/15**.

| Area | What it checks |
|---|---|
| File name | Format, sanitising (`/`, `..`, `\`, spaces), empty fallback |
| Toolbar | Share is gone (`allowSharing` false, no share icon), Print is kept, the labelled Download appears only after the PDF loads |
| States | *Downloading…* with the button disabled; a double tap saves once; the success message; the button re-enables |
| Errors | A failed save shows a safe message (the injected error's local path is not shown) with Retry, which then succeeds; cancel is not an error |
| Farmer | My Consultations → View PDF → Download: **one** request to the authenticated endpoint (farmer JWT), and the saver receives exactly those bytes with the expected file name |
| Doctor | Case page → View PDF → Download: same, with the doctor's JWT |
| Access | Another farmer or another doctor gets 403: no PDF, no Download, nothing saved |
| Windows saver | Real file write through a fake Save dialog: exact bytes at the chosen path; suggested name and `.pdf` filter; `.pdf` appended; cancel writes nothing; an unwritable location fails, and the viewer shows the safe error with Retry |
| Layout | The app bar with Download fits at 360px and 1400px |

**Negative control:** with Share re-enabled, the "Share removed" test fails. The file was restored byte-for-byte.

The existing viewer and prescription tests (`prescription_pdf_viewer_test.dart`, `doctor_prescription_pdf_email_test.dart`) still pass: 39/39 together with the new file.

| Gate | Result |
|---|---|
| `manage.py check` / `migrate --check` | clean / exit 0 (no backend change) |
| `flutter analyze lib test` | only the 6 known infos in `farmer_feed_marketplace_screen.dart` |
| `flutter test` | **373 passed, 2 failed**: the 2 known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart`. Run one file per process: a single `flutter test` run reached 110/110 passing, then the test process ran out of machine memory, not a test failure |
| `flutter build web --release` | built |

## Manual verification (not run by hand)

There is no browser or desktop automation in this environment, so these steps are for you. Run `.\run_backend.bat`, then `flutter run -d chrome` and `flutter run -d windows`.

* **Farmer** `farmer.rashed@example.com`:
  1. Find Vet → My Consultations → View prescription PDF.
  2. Check there is no Share button and there is a **Download** button.
  3. Download. On web the browser downloads `FeatherFlow_Prescription_RX-….pdf`; on Windows the Save dialog opens and the file is saved.
  4. Open the file: it is the prescription.
* **Doctor** `dr.samira.rahman@example.com`: Case page → View PDF → Download, same checks.
* **Another farmer or doctor:** opening that prescription shows *"You do not have permission…"* and no Download button.

## Limitations

* **Web download location:** this is decided by the browser (default *Downloads* or the browser's "ask where to save" setting); the app can't choose it.
* **The PDF must be on screen:** Download is available only once the PDF has loaded. If loading fails, Retry must succeed first, because Download never fetches on its own.
* **Snackbar on the page beneath:** Flutter shows SnackBars on every visible page, so a confirmation may still be showing briefly on the page under the viewer after it closes.
* **Test machine memory:** during this work the machine was short on memory, so the Flutter compiler crashed until an orphaned test run of mine was stopped. Test files were then run one at a time (`--concurrency=1`). Your running `flutter run` session and the IDE tools were not touched.
