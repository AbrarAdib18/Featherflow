# Consultation Workflow Audit — Booking, Clinical Data, Receipts, Payments

**Date:** 2026-09-23
**Scope:** Audit the full farmer↔doctor consultation flow (booking → status
transitions → clinical notes/prescriptions/follow-ups → receipt →
payment) against `CONSULTATION_INTEGRATION_AUDIT.md`'s and
`DOCTOR_FARMER_WORKFLOW.md`'s earlier work, find gaps, and fix what's
actually broken.
**Nothing was committed.** All changes described below are in the working
tree only.

---

## 1. Headline finding

Before writing any code, four parallel read-only investigations covered:
consultation status transitions/endpoints, prescriptions/follow-ups/receipts/
payments (backend + Flutter), and the two dashboard-facing items covered in
[DOCTOR_DASHBOARD_FIXES.md](DOCTOR_DASHBOARD_FIXES.md).

**The consultation/prescription/receipt/payment pipeline already works
end-to-end on both backend and Flutter.** This is not a "build it" task —
`ConsultationNote`, `ClinicalPrescription`, `PrescriptionItem`, `FollowUp`,
and the cash `Payment`/receipt flow all exist, are wired to real endpoints,
are displayed on both the farmer (`farmer_consultations_screen.dart`) and
doctor (`doctor_case_notes_screen.dart`, `doctor_prescriptions_screen.dart`,
`doctor_followups_screen.dart`) sides, and are covered by
`backend/scripts/test_doctor_flow.py`. The actual gaps found were narrower:
missing test coverage for a handful of status transitions, and one real
consistency bug in how one of those transitions was logged. Both are fixed
below.

---

## 2. What was inspected

| Area | Files | Finding |
|---|---|---|
| Status model | `backend/consultations/models.py` | `status` is a bare `CharField`, **no `choices=`** — every value (`requested/accepted/rejected/reschedule_proposed/in_progress/completed/cancelled/no_show`) is a string literal enforced only in view-layer guard dicts, not the model. Pre-existing; not changed here (changing it risks touching every consumer of this unmanaged table for a task that didn't ask for a schema change). |
| Transition logic | `backend/consultations/workflow.py`, `backend/doctor/views.py:appointment_action`, `backend/consultations/views.py:consultation_action` | All 8 statuses are reachable. Doctor-side transitions (`accept/reject/reschedule/start/complete/no_show`) live in `doctor/views.py:appointment_action`'s `allowed`/`target` dicts. Farmer-side (`cancel/accept_reschedule/decline_reschedule/rate`) live in `consultations/views.py:consultation_action`. Both filter their queryset by `doctor=request.user` / `farmer=request.user` — ownership isolation confirmed correct (verified by test, see §4). |
| A second `in_progress` path | `backend/doctor/views.py:video` | Starting a video call also flips `accepted → in_progress`, independently of `appointment_action`'s `start` action. **Bug found:** this path wrote `item.status = 'in_progress'` directly and called a partial `item.save(update_fields=...)`, skipping `record_transition` entirely — so this specific transition never wrote a `ConsultationStatusHistory` row, unlike every other transition in the app. Fixed (see §3). |
| Prescriptions/notes/follow-ups | `backend/doctor/models.py` (`ConsultationNote`, `ClinicalPrescription`, `PrescriptionItem`, `FollowUp`), `backend/doctor/views.py` (`cases`, `prescriptions`, `followups`) | All exist, all scoped to the doctor's own consultations, all require `consultation.status == 'completed'` before a prescription can be issued (verified `409` if not). Farmer views them via `GET /api/consultations/<id>/clinical-results/`, gated the same way (`409` until completed) and scoped to `farmer=request.user`. |
| Receipts | `backend/consultations/payments.py` (`ensure_cash_receipt`, `receipt_row`, `payment_breakdown`) | Auto-generated the moment a consultation is marked `complete` (`doctor/views.py:appointment_action`, action `complete`, calls `ensure_cash_receipt(item)`), and defensively re-created if missing when the farmer requests it. Full field set already present: receipt number, farmer/doctor, consultation date/type, `doctor_handled_sequence`, gross/platform/net, status, `paid_at`. |
| Payments | `backend/consultations/payments.py` (`confirm_cash_payment`), `POST /api/consultations/<id>/mark-paid/` | **Cash-only, by design** — the farmer self-attests "I paid cash," which creates/updates the `Payment` row and a `DoctorEarning` row. This already matches the brief's "payment gateway is not implemented yet, don't claim real payment processing" requirement, since it never claims to charge a card or move real money through a gateway — it's a same-day, in-person cash record. A separate, unrelated `billing/` app has real `PaymentIntent`/webhook plumbing (Stripe/bKash/Nagad-shaped), but it's wired only to subscriptions and labour payments, not consultations — left as-is; wiring a gateway into consultation payments is a product decision beyond "targeted fixes." |
| Flutter — farmer | `farmer_consultations_screen.dart` (1211 lines), `farmer_consultation_service.dart` | Already displays clinical notes, prescriptions + medicines, case advice, follow-up date/time/status, a receipt dialog with every required field, and a "I have paid cash" Pay button. Nothing added or changed here. |
| Flutter — doctor | `doctor_case_notes_screen.dart`, `doctor_prescriptions_screen.dart`, `doctor_followups_screen.dart` | Already let the doctor enter clinical notes, issue a prescription (with medicines + optional follow-up in the same submit), and manage follow-ups independently. Nothing added or changed here. |
| Existing tests | `backend/scripts/test_doctor_flow.py`, `test_consultation_booking_rules.py` | Cover: discovery → booking → accept → case notes → complete → receipt → mark-paid → rating → prescription+PDF → follow-up → earnings → availability CRUD → chat; and booking validation, ownership isolation, follow-up conflicts, `max_distance_km`. **Not covered:** reject-with-reason, reschedule (propose/accept/decline), no-show, `appointment_action`'s own `start` action, the video-call `start` path, and receipt/payment *access control* (only the happy path was tested). |

---

## 3. The one real bug fixed

**`backend/doctor/views.py`, `video()` (around line 434).** Starting a video
call on an `accepted` consultation flips it to `in_progress` — a real status
transition — but did so with a bare field write instead of going through
`record_transition`, the function every other transition in the app uses to
also write a `ConsultationStatusHistory` row. Result: a consultation that
went `accepted → in_progress` via "start video call" had no audit trail for
that step, while the same transition via the appointment-actions "start"
button did. Since a `ConsultationStatusHistory` row is how the farmer's
"track the consultation state end-to-end" (this task's own requirement) is
backed, this was a real, if narrow, gap.

```python
# before
if item.status == 'accepted':
    item.status = 'in_progress'
item.save(update_fields=['video_room', 'video_started_at', 'video_ended_at', 'status', 'updated_at'])

# after
if item.status == 'accepted':
    record_transition(item, request.user, 'in_progress')
else:
    item.save(update_fields=['video_room', 'video_started_at', 'video_ended_at', 'updated_at'])
```

`record_transition` was already imported in this file (used by
`appointment_action`), so this is a one-line behavioral fix, not a new
dependency. Regression-tested directly — see §4.

No other transition bugs, permission gaps, or missing endpoints were found.
`accept_consultation`/`appointment_action`/`consultation_action` all correctly
scope every query to the acting user and reject cross-account access with a
`404` (not a `403`, consistent with the rest of the app's not-found-not-
forbidden convention for other users' rows).

---

## 4. New backend tests

**`backend/scripts/test_consultation_transitions_and_receipts.py`** (new,
53 checks, all passing) — closes exactly the gaps found in §2's table:

- **Reject with reason** — 200, `decision_reason` persisted, history row
  logged, farmer notified, ownership isolation (`404` for another doctor).
- **Reschedule → farmer accepts** — doctor proposes a new date/time (checked
  against the doctor's published availability + slot conflicts), farmer
  `accept_reschedule` moves `appointment_date`/`appointment_time` to the
  proposed slot, clears the proposal fields, returns a `conversation_id`.
- **Reschedule → farmer declines** — `decline_reschedule` cancels the
  consultation and clears the proposal, doctor notified.
- **No-show** — blocked outside `accepted` (`409`), ownership-isolated,
  succeeds from `accepted`, history logged.
- **`appointment_action`'s own `start` action** — `accepted → in_progress`,
  history logged (this path already worked; now it has coverage).
- **The video-call `start` path — the exact regression test for the fix in
  §3.** Confirms `status` flips to `in_progress` *and* a
  `ConsultationStatusHistory` row is now created, where before it silently
  wasn't. Also confirms `video end` doesn't fabricate a second status change.
- **Receipt generation + access control** — full field set matches
  `payment_breakdown()`'s own math (not hardcoded numbers), and confirms a
  receipt is farmer-scoped: a different farmer gets `404`, a doctor account
  hitting the farmer-only endpoint gets `403`.
- **Payment status updates** — `mark-paid` is confirmed idempotent (second
  call returns `already_paid: true`, no duplicate `DoctorEarning` row), and
  the *same* receipt endpoint reflects the new `completed` status afterward —
  i.e. both sides see the same underlying `Payment` row update, not two
  independent copies of "paid" state.

Availability slots in this new script are computed from `date.today()`
relative to every weekday actually used (deduped, one slot per weekday,
near-full-day) specifically so the suite doesn't inherit the date-dependent
flakiness described in §5 below.

Run: `backend/venv/Scripts/python.exe backend/scripts/test_consultation_transitions_and_receipts.py`
→ **53 passed, 0 failed.**

---

## 5. Pre-existing issues found, not fixed (out of scope for "targeted fixes")

Both confirmed **unrelated to any change in this pass** — reproduced against
the original, unmodified `doctor/views.py` too before touching anything.

- **`backend/scripts/test_doctor_flow.py`, "availability CRUD" section** —
  hardcodes `weekday: 2` (Wednesday) for a new slot, while its own setup
  computes `appt_date = date.today() + timedelta(days=7)` and seeds an
  availability slot for `appt_date.weekday()`. Since `+7 days` always lands
  on the *same* weekday as today, whenever this script happens to run on a
  Wednesday, the hardcoded slot collides with the seeded one and the script
  crashes with an unhandled `KeyError` instead of a clean test failure. This
  is a test-script bug (date-dependent flakiness), not an application bug —
  the API's overlap rejection (`409 This availability slot overlaps an
  existing slot.`) is working exactly as intended. Left as-is: fixing a
  pre-existing, unrelated test script wasn't part of the brief, and the new
  test file in §4 deliberately avoids the same mistake rather than
  papering over this one.
- **`backend/scripts/test_consultation_booking_rules.py`, "open-ended
  request" checks (6 of 29)** — booking with no preferred date/time hits
  `"This slot was just booked. Please choose another time."`, which then
  cascades into 5 further failures in the same script that depend on that
  booking having succeeded. This looks like leftover-state/ordering
  flakiness in the script itself (an earlier booking in the same run claims
  the slot the open-ended-request step also reaches for), not a regression —
  confirmed identical with `git stash` against the unmodified `video()`.
  Flagging it here rather than silently leaving it unexplained; a real fix
  would need its own investigation into the script's slot-selection logic,
  which is outside "targeted fixes" for this pass.

---

## 6. Frontend design consistency (brief spot-check)

A full pixel-level pass across every doctor/farmer screen wasn't attempted —
this environment's headless-browser testing was already found in an earlier
session to hit a Chromium-headless/software-rendering limitation that
prevents reliable visual screenshotting of this Flutter web app (unrelated to
app code), so a genuine "look at the rendered pixels" pass isn't reliable to
perform from here (same limitation noted in
`DOCTOR_DASHBOARD_PROFILE_AND_RATING.md`).

What *was* checked, code-level:

- The two new UI surfaces this pass touches (the navbar avatar, the Articles/
  Community tiles — see `DOCTOR_DASHBOARD_FIXES.md`) both reuse existing
  `VetColors` tokens and the dashboard's own established tile pattern; no new
  hardcoded colors were introduced, and neither is a green-surface/green-text
  pairing.
- `test/navigation_contrast_test.dart` (pre-existing, unmodified) already
  locks in white-on-green for every app bar/tab bar/nav-rail token at the
  theme level — still passing, untouched by this pass.
- Receipt screen, chat/conversation screen, notification screens, and
  prescription/follow-up screens were not modified in this pass and were not
  re-audited pixel-by-pixel; they were already covered by the existing test
  suite's smoke tests (`farmer_screens_smoke_test.dart` and friends), which
  continue to pass unchanged (see §7).

If a full visual/contrast audit across every screen is wanted, that's a
larger, separate pass — this one stayed scoped to the fixes actually
requested.

---

## 7. Tests and quality gates (full run, this pass)

```
python manage.py check                 → System check identified no issues (0 silenced)
python manage.py migrate --check       → (no backend schema change this pass; not needed)
backend/scripts/test_doctor_flow.py    → passes through "earnings summary"; crashes in the
                                          pre-existing, unrelated "availability CRUD" flakiness
                                          described in §5 (confirmed pre-existing via git stash)
backend/scripts/test_consultation_booking_rules.py
                                        → 23 passed, 6 failed — same 6, confirmed pre-existing
                                          via git stash (§5), unrelated to this pass's changes
backend/scripts/test_consultation_transitions_and_receipts.py (new)
                                        → 53 passed, 0 failed
flutter analyze lib test               → 6 issues (same pre-existing info-level lints in
                                          farmer_feed_marketplace_screen.dart; zero from any
                                          file this pass touched)
flutter test                           → 169 passed, 0 failed
flutter build web --release            → √ Built build\web
```

---

## 8. Manual verification

**Not performed live** — this pass's actual application-code changes are a
one-line backend transition fix (§3) plus the dashboard-facing items in
`DOCTOR_DASHBOARD_FIXES.md`; everything else in this audit found *existing,
already-working* functionality rather than new UI to click through. The new
backend test (§4) exercises the fixed transition directly, including the
exact `ConsultationStatusHistory` assertion that would have caught the
original bug. As with prior passes in this project, a real-browser
confirmation is the natural next step if you want to see it live:

1. Restart the backend (picks up the `doctor/views.py` change) and the
   Flutter app.
2. As a doctor: accept a consultation, start a video call from it, then check
   (e.g. via Django admin or a DB query) that a `ConsultationStatusHistory`
   row now exists for that `in_progress` transition.
3. The reject/reschedule/no-show flows can be exercised from the doctor's
   appointment actions UI and the farmer's consultation screen; all three
   were already reachable in the UI before this pass (this pass only added
   backend test coverage for them, not new UI).

---

## 9. Confirmation

**Nothing was committed.** All changes are in the working tree only —
verified via `git status` before finishing; no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
