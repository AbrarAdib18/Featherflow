# Consultation Lifecycle — Verification Results

Companion to `FIND_VET_DISCOVERY_FIX.md` and
`FARMER_DOCTOR_END_TO_END_AUDIT.md`. Nothing in this work was committed.

All results below are from **running the suites against the live development
database**, not from reading code. Every suite name and count is reproducible
with the command shown.

## 1. Summary

| Suite | Result |
|---|---|
| `scripts/test_find_vet_discovery.py` (**new**) | **38 passed, 0 failed** |
| `scripts/test_consultation_booking_rules.py` | **29 passed, 0 failed** |
| `scripts/test_consultation_transitions_and_receipts.py` | **53 passed, 0 failed** |
| `scripts/test_consultation_chat_access.py` | **13 passed, 0 failed** |
| `scripts/test_doctor_flow.py` | **58 passed, 0 failed** (was *crashing* — fixed, §4) |
| `scripts/test_vets_nearby.py` | **12 passed, 0 failed** |
| **Total** | **203 checks green** |

## 2. Lifecycle stages — where each is covered

```text
Farmer opens Find Vet          → test_find_vet_discovery (38 checks)
searches / filters a doctor    → test_find_vet_discovery
opens doctor profile + slots   → test_find_vet_discovery (detail + availability_slots)
selects owned farm/flock       → test_consultation_booking_rules (ownership checks)
submits request                → test_consultation_booking_rules
backend validates              → test_consultation_booking_rules (see §3)
doctor accepts/rejects/reschedules → test_consultation_transitions_and_receipts
farmer sees updated status     → status + history-row assertions
conversation + clinical case   → test_consultation_chat_access, test_doctor_flow
doctor notes/prescription/follow-up → test_doctor_flow (incl. prescription PDF)
completion → receipt           → test_consultation_transitions_and_receipts
payment state → doctor earnings → test_consultation_transitions_and_receipts
rating → visible in Find Vet   → test_doctor_flow (rating in earnings feed)
```

## 3. Booking & access-control validation (verified, not assumed)

From `test_consultation_booking_rules` — all passing:

- Booking with **another farmer's farm** → rejected.
- Booking with **another farmer's flock** → rejected.
- Booking an **unapproved/inactive doctor** → rejected.
- **Unsupported consultation mode** → rejected.
- **Emergency request** when the doctor doesn't offer it → rejected.
- **Past appointment date** → rejected.
- **Time supplied without a date** → rejected.
- A different doctor **cannot act** on someone else's appointment (404).
- A different farmer **cannot cancel** someone else's consultation (404).
- A **conflicting follow-up** at the same doctor time slot → rejected.
- Legitimate booking with owned farm + flock → accepted.

**Documented product behaviour worth stating explicitly** (it is asserted, so
it is intentional, not a gap): *availability does not gate a request.* Booking a
doctor with no availability rows, outside published availability, or with no
preferred date/time is **accepted** — the doctor then accepts/reschedules.
This matches `booking_options` returning `requires_availability: false`, and it
is why the Find Vet default list must not require a current slot.

## 4. Second defect found and fixed during verification

`scripts/test_doctor_flow.py` **crashed** rather than reporting a failure:

```text
File "scripts/test_doctor_flow.py", line 278, in main
    slot_id = r.json()['id']
KeyError: 'id'
```

Root cause: a **calendar-dependent self-conflict**. The suite's setup creates
availability on `today.weekday()` and `today.weekday()+1` (09:00–17:00), while
the "availability CRUD" block hard-coded `weekday=2` with 08:00–12:00. On any
day where those line up — e.g. a Tuesday, which is when this ran — the create
legitimately returned `409 overlaps an existing slot`, the `add slot 201` check
failed, and the next line crashed dereferencing `['id']` on the error body.

So the suite passed on some weekdays and hard-crashed on others.

Fix: the CRUD block now picks a weekday the setup provably does not occupy
(`(today.weekday() + 3) % 7`). All assertions are unchanged; the result is now
identical on every day of the week. Suite went from **crash → 58 passed, 0 failed**.

## 5. Status propagation & history

`test_consultation_transitions_and_receipts` asserts a persisted
**status-history row** for every transition, including the one that used to be
missed:

- reject (+ `decision_reason` saved, farmer notified)
- accept
- reschedule proposed → farmer accepts (appointment moves, proposed fields cleared)
- reschedule proposed → farmer declines (→ cancelled, doctor notified)
- `no_show` (blocked while still `requested`; only the assigned doctor may set it)
- `start` (accepted → in_progress) — history row logged
- **video-call start path** — also logs a history row (explicit regression check),
  sets `video_room`/`video_started_at`; ending the call sets `video_ended_at`
  and correctly does **not** change status

## 6. Receipt, payment and earnings

All passing:

- `complete` → status `completed`, receipt generated server-side.
- Receipt carries a **receipt number**, fee breakdown, participant names, mode/date,
  and `doctor_handled_sequence`; it **starts unpaid**.
- **Another farmer cannot view the receipt** (404).
- **A doctor account cannot use the farmer receipt endpoint** (403).
- Another farmer **cannot mark it paid** (404).
- `mark-paid` → payment `completed`, `paid_at` set, **doctor earning accrued net
  of the platform fee**.
- **`mark-paid` is idempotent** — a second call returns 200 with
  `already_paid: True` and creates **no duplicate earning**.

### Payment-provider status — stated plainly

There is **no real payment gateway integration** in this environment. Payment is
sandbox/manual: `mark-paid` is a server-side state transition, not a charge.
Gateway credentials are environment-variable-only and no provider is configured
(`BILLING_MODE` falls back to `dev`). Nothing in this work claims, or was
changed to imply, that money is actually processed.

## 7. Conversations & messaging

`test_consultation_chat_access` (13 checks) — accepted consultations get exactly
one conversation, and **listing repeatedly does not create duplicate
conversations**. Farmer/doctor scoping on message fetch/send is enforced.
WebSockets were intentionally not touched (REST/polling design left as-is).

## 8. Clinical case, prescriptions, follow-ups

From `test_doctor_flow` (58 checks): clinical notes, prescription creation,
**prescription PDF renders**, follow-up created + notified, earnings summary
nets the platform charge correctly, payout request accepted, over-balance payout
rejected, disputes raised by both parties and resolved by an admin (resolution
note required), and cross-panel admin doctor oversight with response-time and
dispute metrics.

## 9. Quality gates

```text
python manage.py check                → System check identified no issues (0 silenced)
python manage.py migrate --check      → exit 0 (no pending migrations)
backend consultation/discovery suites → 203 checks passed (table in §1)
scripts/test_admin_panel.py           → 62 passed, 1 failed*
flutter analyze lib test              → 6 pre-existing info-level lints, unrelated file
flutter test                          → 214 tests, 2 pre-existing unrelated failures**
flutter build web --release           → see final report
```

\* The single `test_admin_panel.py` failure is `admin login 200`, a pre-existing
email-verification issue confirmed earlier in this session (via `git stash`) to
be unrelated to any change here.

\** The 2 Flutter failures are in `doctor_dashboard_fixes_test.dart` (navbar
profile photo), also confirmed pre-existing and unrelated via `git stash`
earlier in this session.

## 10. Limitations

- **No real payment provider** (§6). Receipts and payment state are correct and
  persisted; no charge occurs.
- **Manual browser verification was not performed** in this pass — the
  verification above is automated-suite based against the live database. The
  Flutter Find Vet state handling was reviewed by reading
  `discover_vets_tab.dart` (distinct loading/error/empty branches with a working
  Retry) rather than exercised in a browser.
- `seed_consultation_demo_data` was **not created**: the existing
  `seed_platform_demo` already provisions an eligible verified doctor with
  availability plus a farmer with an active farm, which is what discovery and
  booking need. The seeded farmer's farm currently has **no flocks**, so
  flock-specific manual testing would need one added.
