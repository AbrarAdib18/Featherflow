# Doctor Prescription Authority — Audit

**Date:** 2026-11-01
**Reported:** on the Case page, submitting *Issue Prescription and Advice* showed **"Prescription authority has not been approved."** and no prescription was created.

The PDF and email work is in [DOCTOR_PRESCRIPTION_PDF_EMAIL.md](DOCTOR_PRESCRIPTION_PDF_EMAIL.md). The Case page workflow is in [DOCTOR_CASE_PAGE_FIX.md](DOCTOR_CASE_PAGE_FIX.md).

## 1. Failure path

```
Case page (stage "completed") → Issue prescription & advice → form → Save and email PDF
→ DoctorSession.issueCasePrescription()
→ POST /api/doctor/prescriptions/
     {consultation_id, medicines:[{name,dosage,duration,notes}], case_advice, dosage_notes,
      follow_up_instructions, follow_up_date?, follow_up_time?}
→ doctor/views.py:prescriptions   (IsDoctor passed: authenticated, doctor role, active)
     if not _doctor_profile(request.user).prescription_authority:
         return Response({'detail': 'Prescription authority has not been approved.'}, status=403)
→ HTTP 403 (logged as "WARNING Forbidden: /api/doctor/prescriptions/"; a handled refusal, no traceback)
→ DoctorApiService throws AuthException(detail)
→ the prescription form shows it in red (the screenshot)
```

The check ran **before** the ownership and consultation-state checks, so it refused every doctor whatever the case was.

## 2. Data

| Item | Value |
|---|---|
| Doctor account | `dr.samira.rahman@example.com`: doctor role, `account_status=active`, `is_verified=True` |
| `doctor_profiles.prescription_authority` | **False** |
| All real doctor accounts in the dev DB | 5 of 5 have **False** (`adminpaneltest+vet`, `dr.pending.kabir`, `dr.samira.rahman`, `samira@gmail.com`, `test@gmail.com`) |
| Accounts with True | Only the throwaway accounts created by test scripts, which set `prescription_authority=True` explicitly |
| Prescriptions ever issued (dev DB) | **0** |

The live reproduction uses the same code path: with the check restored, the new suite gets exactly this response for the assigned doctor of a completed consultation (see §5).

## 3. What "prescription authority" is

| Question | Finding |
|---|---|
| Model | `profiles.DoctorProfile.prescription_authority`, a nullable boolean, `DEFAULT FALSE` in `featherflow_schema.sql` |
| Intent | A professional credential or approval flag, meaning the doctor may prescribe. Plausibly a future regulatory or admin approval |
| How it gets set at signup | **It never does.** The signup form has a free-text "Prescription Authority" field ("e.g. Licensed to prescribe Schedule H"), but the backend's doctor field allow-list doesn't include it and `users/serializers.py:_create_doctor` never maps it. The DB default `FALSE` always wins |
| How an admin sets it | **No way.** No admin screen, endpoint or approval queue references it |
| Other readers | Only the farmer's vet-detail dialog, which displays "Prescription authority: Yes/No" |

**Classification:** a doctor-profile field that is never populated, used as a hard gate. Every real doctor was permanently blocked, which is why the dev DB has never had a prescription.

It is not:
- a role permission (`IsDoctor` handles the role);
- a case-state problem (the state check came after it);
- a serializer bug or a wrong role identifier.

## 4. Decision

The task's preferred option: **made optional and non-blocking**.

* The field and its data are kept, so it can become a real compliance or admin approval later. That needs a signup mapping or an admin approval step first; reintroducing the gate is then a one-line check.
* It is removed from the prescription-issuance check only. Nothing else is relaxed.

Eligibility to prescribe is now:

| Rule | Enforced by | Refusal |
|---|---|---|
| Authenticated | DRF default `IsAuthenticated` | 401 |
| Doctor role and active account | `IsDoctor` | 403 |
| Assigned doctor of this consultation | `_create_prescription` | 404 `not_found` (same answer for "no such consultation" and "not yours") |
| Consultation completed (Case page stage *completed*) | `_create_prescription` | 409 `consultation_not_completed` |
| Valid fields: medicine name, dosage and duration required, column length limits, ≤30 medicines, case advice required, a follow-up both date and time and in the future, follow-up conflict checks | `PrescriptionSerializer` and the view | 400 `invalid` with field `errors` / 409 |

`is_verified` is **not** required. That is consistent with every other doctor workflow action (accept, complete, case edits), and unverified doctors are not listed to farmers in the first place.

## 5. Tests

| Test | Result |
|---|---|
| `backend/scripts/test_prescription_pdf_email.py` | A doctor with `prescription_authority = False`, and one with `NULL`, are covered. The assigned doctor gets 201. Another doctor 404, a farmer 403, unauthenticated 401, a nonexistent consultation 404, a not-yet-completed consultation 409. Refused requests write nothing and send no email |
| **Negative control** (old check restored) | The same suite fails with the exact screenshot message: `{"detail":"Prescription authority has not been approved."}` for the assigned doctor, the nonexistent consultation and the not-completed consultation. File restored byte-for-byte afterwards |
| Flutter `test/doctor_prescription_pdf_email_test.dart` | Issuing from the Case page succeeds, shows the reference and "PDF emailed to the farmer", and never shows "Prescription authority…" |

## 6. Follow-ups (not done)

* **Fix the signup field:** map the signup "Prescription Authority" text to a stored field (it is currently dropped), or remove the field from the form.
* **Vet detail wording:** the farmer's vet-detail dialog still shows "Prescription authority: No" for every doctor, because no doctor has the flag. Hide the line or reword it until the flag is actually managed.
* **Before reinstating any gate:** add an admin approval step for the flag first.
