# Doctor ↔ Farmer Consultation Workflow

**Companion to:** `CONSULTATION_INTEGRATION_AUDIT.md` (what changed and why).
This document is the reference for how the whole doctor–farmer consultation
feature works end to end, for whoever touches it next.

---

## 1. Where it lives

| Layer | Farmer side | Doctor side |
|---|---|---|
| Flutter feature | `lib/features/farmer/presentation/screens/find_vet_screen.dart` (**Find Vet**: Discover Vets + My Consultations tabs) | `lib/features/doctor/presentation/screens/*` (dashboard, appointments, case notes, prescriptions, follow-ups, earnings, messenger) |
| Flutter data services | `vet_discovery_service.dart` (discover/detail/booking-options/book), `farmer_consultation_service.dart` (list/action/chat/receipt/dispute/PDF) | `doctor_api_service.dart` |
| Django app(s) | `backend/consultations/` (the farmer-facing endpoints + the shared `Consultation`/`ConsultationDispute` models) | `backend/doctor/` (everything doctor-facing: `CaseDetail`, `ConsultationNote`, `ClinicalPrescription`, `PrescriptionItem`, `FollowUp`, `DoctorEarning`, `PayoutRequest`, `AvailabilitySlot`, `ConsultationStatusHistory`, `Conversation`, `Message`) |
| Shared support | `backend/notifications/` (in-app inbox), `backend/payments/` (the legacy `Payment` ledger, reused for cash consultation receipts), `backend/messaging/realtime.py` (Socket.IO broadcast, optional real-time layer over the REST-persisted chat) | |

`consultations` and `doctor` split the way the rest of the codebase splits
farmer-facing vs. doctor-facing apps (`farmers`/`workers` vs. `pharmacy` etc.)
— **one `Consultation` row is the single source of truth** for both sides;
neither app has its own copy.

---

## 2. The farmer journey (Find Vet)

```
Find Vet
├── Discover Vets tab
│   ├── filters: search, specialty, mode, available now, emergency,
│   │   verified, max fee, min rating, max distance
│   ├── list of doctors (card) ── tap ──▶ Vet detail dialog
│   │                                       ├── profile, credentials,
│   │                                       │   weekly availability,
│   │                                       │   recent reviews
│   │                                       └── "Book consultation" ──▶ Booking dialog
│   │                                             ├── farm (owned, active)
│   │                                             ├── flock (optional; auto-fills
│   │                                             │   breed/age/count if picked)
│   │                                             ├── mode + urgency (constrained
│   │                                             │   to what the doctor offers)
│   │                                             ├── date (≤90 days) + time
│   │                                             │   (only the doctor's real,
│   │                                             │   currently-free slots)
│   │                                             └── symptoms/mortality/notes
│   │                                                   │
│   │                                                   ▼
│   │                                          POST /api/consultations/
│   │                                          → Consultation(status='requested')
│   │                                            + CaseDetail
│   └── optional map view of the same filtered list (tap a pin → same detail dialog)
│
└── My Consultations tab (unchanged, pre-existing)
    ├── Consultations sub-tab: one card per Consultation, showing status,
    │   reschedule proposals (accept/decline), cancel, video-call join,
    │   dispute, clinical results, payment receipt, rating, prescriptions +
    │   follow-ups inline
    └── Chats sub-tab: one conversation per doctor once accepted
```

Everything below "Book consultation" already existed before this pass; only
Discover Vets and the booking dialog were newly built (see the audit doc §5).

---

## 3. The doctor journey

```
Doctor dashboard
├── Today's appointments + urgent-request count + pending follow-ups
├── Appointments (request queue)
│   ├── accept  → Conversation created/reused, farmer notified
│   ├── reject  → optional reason, farmer notified
│   ├── reschedule → proposes a new date/time (must itself be published +
│   │                free); farmer must accept/decline
│   ├── start   → status → in_progress
│   ├── complete → case closed, cash receipt row created, clinical
│   │              results become visible to the farmer
│   └── no_show → attendance preserved, no auto-refund/charge
├── Case notes (diagnosis, treatment plan, warnings, next steps) — attached
│   to the same CaseDetail the farmer's booking created
├── Prescriptions — only after status == 'completed'; medicines + case
│   advice + follow-up instructions + optional follow-up date/time in one
│   call; PDF generated + emailed (failure logged, never blocks the record)
├── Follow-ups — from case notes, the prescription flow, or the dedicated
│   screen; reschedules a consultation's existing pending follow-up instead
│   of creating a duplicate
├── Earnings — gross/platform-fee/net per consultation, aggregated by
│   mode+urgency, payout requests against the pending balance
└── Messenger — one thread per accepted consultation (same Conversation
    the farmer's chat tab shows)
```

---

## 4. Status lifecycle

```
requested ──accept──▶ accepted ──start──▶ in_progress ──complete──▶ completed
    │                    │                                              │
  reject             reschedule                                    (rating,
    │                    │                                        prescription,
    ▼                    ▼                                          receipt)
 rejected      reschedule_proposed ──accept_reschedule──▶ accepted
                         │
                    decline_reschedule
                         │
                         ▼
                     cancelled

accepted ──cancel (farmer) or no_show (doctor)──▶ cancelled / no_show
```

Every transition writes one `ConsultationStatusHistory` row
(`from_status`, `to_status`, `actor`, `reason`, `created_at`) — permanent,
never overwritten. `record_transition()` in `consultations/workflow.py` is
the single place this happens; both the farmer-side and doctor-side action
endpoints call it, so there is exactly one code path that can move a
consultation's status.

**Who can do what:**

| Action | Who | Endpoint |
|---|---|---|
| Book, cancel, accept/decline reschedule, rate | the assigned farmer only | `POST /api/consultations/`, `POST /api/consultations/<id>/action/` |
| Accept, reject, reschedule, start, complete, no-show | the assigned doctor only | `POST /api/doctor/appointments/<id>/action/` |

Both endpoints scope every query by `farmer=request.user` /
`doctor=request.user` — a different account gets a plain 404, never another
user's consultation (see the isolation tests in
`test_consultation_booking_rules.py`).

---

## 5. Booking validation (server-authoritative; the Flutter dialog only adds
early, friendlier client-side checks — the backend is what actually enforces
every rule)

`consultations/booking.py::validate_booking` checks, in order:

1. The selected doctor profile exists, belongs to an **active** doctor
   account.
2. The doctor is currently available (`is_available` and
   `availability_status != 'offline'`).
3. The doctor offers the requested **mode** (`online`/`offline`, or `both`).
4. If `urgency == 'emergency'`, the doctor supports emergency requests.
5. The **farm** belongs to the requesting farmer and is active.
6. If a **flock** is given, it belongs to that farm and is active; mortality
   can't exceed its current count.
7. The appointment time is in the **future**.
8. The time falls inside one of the doctor's **published availability
   slots** for that weekday + mode.

Then `create_booking` (still inside the same DB transaction, with the farmer
and doctor profile rows locked via `select_for_update`) checks:

9. No pending follow-up reserves that exact doctor+time or farmer+time.
10. No other consultation already occupies that doctor+time
    (`requested`/`accepted`/`in_progress`).

...before creating the `Consultation` + `CaseDetail` together. A duplicate
attempt that races past the application checks is still caught by the
database's own unique partial indexes
(`uq_doctor_active_consultation_slot`, `uq_farmer_active_consultation_slot`,
`uq_doctor_pending_follow_up_slot`, `uq_consultation_pending_follow_up`) —
belt and suspenders, not either/or.

---

## 6. Case data → clinical workflow

Booking a consultation creates one `CaseDetail` row up front (from the
selected flock, or from the manually-entered bird age/breed/flock count when
no flock is picked). The doctor's case-notes screen reads and updates the
**same row** — nothing is re-entered. When the doctor adds a diagnosis/
treatment plan, that goes into a separate `ConsultationNote` (append-only per
edit, latest one shown); when they issue a prescription, that's a separate
`ClinicalPrescription` + `PrescriptionItem` rows. All three hang off the one
`Consultation`, which is how "the doctor can later add diagnosis, treatment,
warnings, disease tags, and next steps without re-entering farmer
information" is satisfied.

---

## 7. Money: consultation payments and earnings

There is **no online payment provider** in this flow — it's cash-only, by
design (see `PAYMENT_RUNBOOK.md` for the subscription-billing app, which is
unrelated). The flow:

1. On `complete`, `ensure_cash_receipt()` creates one `Payment` row
   (`payment_type='consultation'`) with `gross`/`platform_charge`/`net`
   computed from `CONSULTATION_PLATFORM_THRESHOLD`/`_RATE` — the platform
   charge only applies to the portion of the fee above the threshold.
2. The farmer sees the receipt in My Consultations and taps **"I have paid
   cash"** after physically paying the doctor → confirmation dialog →
   `POST /api/consultations/<id>/mark-paid/`.
3. `confirm_cash_payment()` (locked, idempotent) marks the `Payment`
   `completed` and creates/updates exactly one `DoctorEarning` row. A repeated
   tap returns the same receipt, never a second earning — enforced by
   `uq_consultation_payment` at the DB level *and* `select_for_update` +
   `update_or_create` in application code.
4. The doctor's Earnings screen aggregates `DoctorEarning` by mode+urgency and
   supports payout requests against the pending balance.

---

## 8. Notifications

Every event below creates a `Notification` row (`backend/notifications/`);
the farmer dashboard and doctor dashboard each poll it independently.

| Event | Notified |
|---|---|
| Consultation requested | doctor + farmer (confirmation) |
| Accepted / rejected / rescheduled / started / completed / cancelled / no-show | farmer (doctor is the actor, so doesn't need telling itself) |
| Reschedule accepted / declined | doctor |
| Conversation created | doctor (chat ready) |
| New message | the other participant |
| Clinical results ready | farmer (folded into the "completed" notification) |
| Prescription issued | farmer |
| Follow-up scheduled/rescheduled | farmer |
| Cash payment confirmed | doctor |
| Receipt updated | farmer |
| Rating + review submitted | doctor |
| Dispute raised | the *other* party + every doctor-admin role |

**Polling cadence** (Flutter):

| What | Interval | Where |
|---|---|---|
| Farmer notification badge count | 3s | `farmer_dashboard_screen.dart` |
| Farmer consultation list + chats (My Consultations) | 8s | `farmer_consultations_screen.dart` |
| Doctor notifications | 4s | `doctor_session.dart` |
| Doctor dashboard workflow data | 12s | `doctor_dashboard_screen.dart` |

All four are independent timers — a slow/failed tick on one never blocks or
delays another, and a failed background refresh always keeps showing the
last-good data rather than clearing the screen.

---

## 9. Access control on shared resources

- **Prescription PDF** (`GET /api/consultations/prescriptions/<id>/pdf/`):
  only the consultation's farmer or doctor — checked against
  `prescription.doctor_id` / `prescription.consultation.farmer_id` directly,
  not role membership alone.
- **Conversation / messages**: scoped to `participant_one`/`participant_two`
  on every read and write.
- **Disputes**: the raising party, the other party, and doctor-admin roles
  only.

---

## 10. Extending this later

- If a real payment provider is ever wanted for consultations (as opposed to
  subscriptions, which already has one in `billing/`), it plugs in at
  `consultations/payments.py::confirm_cash_payment` — that's the one place a
  "payment confirmed" transition happens today.
- If group/family accounts are ever added, `CaseDetail.flock` and `Farm`
  ownership are the two places "does this farmer actually own this" is
  checked — both already reused correctly by booking; a new ownership model
  would need to update both.
- Video calls (`Consultation.video_room`/`video_started_at`/`video_ended_at`,
  Jitsi-based) already exist and are wired to notifications + the
  conversation's real-time channel; they're separate from and don't block
  the core status lifecycle.
