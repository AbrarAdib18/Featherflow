# Consultation Integration Audit — Find Vet / My Consultations merge

**Date:** 2026-09-18
**Scope:** Merge the farmer-facing "My Consultations" and "Find Vet" features into
one unified "Find Vet" feature (Discover Vets + My Consultations tabs), and
integrate the complete doctor–farmer consultation workflow end-to-end, reusing
existing architecture wherever it already covers the requirement.
**Method:** Full inspection of the existing consultation/doctor/messaging/
notification/payment backend and the farmer/doctor Flutter screens *before*
writing any code, per the task brief. **Nothing was committed** — every change
below is in the working tree only.

---

## 1. Bottom line

The backend consultation/doctor workflow was **already almost entirely built** —
a prior engineering pass had implemented essentially the full lifecycle
(booking validation, status transitions, conversations, prescriptions + PDF +
email, follow-ups with DB-level conflict protection, ratings, cash payments +
doctor earnings, disputes, video calls, notifications) to a standard that
matches this task's brief closely. **The actual gap was almost entirely on the
Flutter side**: the rich discovery/booking backend (`VetDiscoveryService`) had
no screen calling it at all — **a farmer could not book a consultation through
the app UI**, full stop. The old "Find Vet" tile only opened a bare map
(call/directions, no filters, no booking). "My Consultations" was otherwise a
fully-featured screen (chat, prescriptions, receipts, ratings, disputes,
video) with nothing to feed it new bookings.

This pass:

1. Built the missing **Discover Vets** screen (filters, list, map toggle,
   doctor detail, booking dialog) that was never written — the actual
   blocking gap.
2. **Merged** it with the existing My Consultations screen into one "Find Vet"
   feature with tabs, replacing the two separate dashboard tiles and adding
   redirects for the old deep links.
3. Closed a small number of genuine backend gaps found during inspection
   (a missing distance filter; a handful of untested validation/isolation
   edge cases) — added with tests, not by rewriting what already worked.
4. Left every already-correct piece of architecture untouched and reused it
   (see §2) — no duplicate models, no parallel workflow, no second
   `Consultation`-like table.

---

## 2. What was inspected, and what it found

| Area | Files | Finding |
|---|---|---|
| Consultation model + lifecycle | `backend/consultations/models.py`, `workflow.py`, `booking.py` | Complete: `requested → accepted/rejected → reschedule_proposed → in_progress → completed/cancelled/no_show`, permanent `ConsultationStatusHistory` per transition (status, actor, timestamp, reason), doctor-availability + double-booking validation, DB-level unique partial indexes (`uq_doctor_active_consultation_slot`, `uq_farmer_active_consultation_slot`) as a backstop under the application-level check. |
| Doctor availability | `doctor/models.AvailabilitySlot`, `doctor/views.availability` | Weekly recurring slots per mode, overlap-checked on create, referenced by both booking and rescheduling. |
| Farmer booking UI / doctor queue | `lib/features/farmer/data/vet_discovery_service.dart`, `lib/features/doctor/presentation/screens/doctor_appointments_screen.dart` | The **Dart service already had `discover()`, `detail()`, `bookingOptions()`, `book()`** matching the backend one-for-one — but **zero screens called any of them**. The doctor's request queue + accept/reject/reschedule/start/complete/no-show UI was already complete and wired. |
| Conversations/messaging | `backend/doctor/models.Conversation/Message`, `backend/messaging/realtime.py`, `lib/core/network/realtime_chat_service.dart` | Complete: one conversation per (farmer, doctor) pair (`uq_conversation_participant_pair`), created on accept, REST-persisted messages with a Socket.IO real-time layer on top (not required by the task, already present), unread/read-state, notifications on new messages. A separate general-purpose `messaging` Django app also exists (community DMs) — distinct table, not reused for consultations, correctly kept apart. |
| Prescriptions / follow-ups / clinical notes | `backend/doctor/models.{ClinicalPrescription,PrescriptionItem,FollowUp,ConsultationNote}`, `backend/doctor/prescription_pdf.py` | Complete: prescription gated on `status == 'completed'`, medicines + case advice + follow-up instructions stored relationally, PDF generated with `reportlab` and emailed via `transaction.on_commit` (so an SMTP failure — logged to `email_error` — never rolls back the clinical record), farmer-only/doctor-only PDF access check. Follow-up scheduling already had DB-level conflict protection: `uq_doctor_pending_follow_up_slot`, `uq_consultation_pending_follow_up`, plus row-locking (`select_for_update`) and application checks against both existing follow-ups and consultations for the same doctor/farmer/time. |
| Payments / earnings / ratings | `backend/consultations/payments.py`, `backend/doctor/models.DoctorEarning`, DB `uq_consultation_payment` | Complete: cash-only receipt created on completion, "I have paid" confirmation creates the `DoctorEarning` exactly once (unique index + `select_for_update`), platform-fee-above-threshold calculation, rating 1–5 with a DB `CHECK` constraint (`consultations_rating_check`), one rating per consultation, doctor average recalculated transactionally on submit. |
| Notifications | `backend/notifications/`, `lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart`, `lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart` | Coverage for every event in the brief (requested/accepted/rejected/reschedule/completed/cancelled/conversation/message/prescription/follow-up/payment/rating) already existed. Doctor-side tap-through to the ratings area and "refresh before opening, mark read after viewing" were **already implemented exactly as specified**. Farmer-side tap-through to the consultation area existed but pointed at the old `/farmer/consultations` route (updated, §4). |
| PDF generation / email config | `backend/doctor/prescription_pdf.py`, `backend/featherflow_backend/settings.py` (`EMAIL_*`) | Reused as-is; no new PDF or mail code needed. |
| RBAC / permissions | `backend/consultations/permissions.IsFarmer`, `backend/doctor/permissions.IsDoctor` | Simple, correct role + `account_status == 'active'` checks; every endpoint scopes by `farmer=request.user` / `doctor=request.user`, so a different farmer/doctor gets a 404, never another user's data. Verified with new tests (§4). |
| Tests / seed data | `backend/scripts/test_doctor_flow.py` (58 checks), `backend/scripts/test_vets_nearby.py` (12 checks) | Already covered the full happy path plus several negative cases (double-booking, prescription-before-completion, overlapping slots, over-balance payout, invalid disputes). Gaps identified and closed in §4. |

**Conclusion of the inspection:** reuse, not rebuild, was overwhelmingly the
right call. No new `Consultation`-equivalent model, no second chat system, no
second payment ledger was created.

---

## 3. Backend changes made

Small, additive, all covered by new tests — nothing here duplicates existing
logic.

1. **`backend/consultations/views.py::vets`** — added a `max_distance_km` query
   parameter (post-computed from the already-calculated `distance_km`, since
   distance only exists once the caller's coordinates are known). The brief
   explicitly lists distance as a farmer-facing filter; only *sorting* by
   distance existed before.

That is the only production code change on the backend. Everything else the
brief asks for (§2–§8 of the task) was already correct and is exercised by
existing + new tests.

---

## 4. Backend tests added

**`backend/scripts/test_consultation_booking_rules.py`** (new, 19 checks, all
passing) — fills the specific gaps `test_doctor_flow.py` didn't already cover:

| Check | What it proves |
|---|---|
| Booking with another farmer's flock / farm rejected | Farm/flock ownership enforced, not just "any flock ID" |
| Booking an unapproved/inactive doctor rejected | `account_status='active'` is enforced on the doctor, not assumed |
| Unsupported consultation mode rejected | A doctor offering only `online` refuses an `offline` request |
| Emergency request rejected when the doctor doesn't support it | `emergency_on_call_availability` is enforced |
| Past appointment date rejected | Serializer-level date-range check |
| A different doctor cannot act on another doctor's appointment (404) | `doctor=request.user` scoping holds under a real cross-account attempt |
| A different farmer cannot cancel another farmer's consultation (404) | `farmer=request.user` scoping holds |
| The assigned doctor/farmer *can* act | Positive control for the two checks above |
| A conflicting follow-up at the same doctor+time is rejected (409) | The DB-level follow-up uniqueness + application check actually fires across two *different* consultations for the same doctor |
| `max_distance_km` excludes a doctor beyond the radius, includes one within it, and widening the radius includes both | The new filter (§3) behaves correctly in both directions |

Run: `venv/Scripts/python.exe scripts/test_consultation_booking_rules.py` —
**19/19 passing**. Also re-ran the two pre-existing suites to confirm no
regression: `test_doctor_flow.py` **58/58**, `test_vets_nearby.py` **12/12**.
`manage.py check` and `manage.py migrate --check` both clean.

---

## 5. Flutter changes made

### New files
- **`lib/features/farmer/presentation/widgets/discover_vets_tab.dart`** — the
  actual missing piece. Filters (search, specialty, mode, availability,
  emergency, verified, max fee, min rating, max distance), a doctor card list,
  and an optional map toggle that reuses the existing `VetMap`/`VetPoint`
  widgets (from the old `vet_map_screen.dart`) to plot the *same filtered
  results* — this is what "merge" means for the map capability: it didn't
  disappear, it became a view mode inside Discover Vets instead of a separate,
  filter-less, booking-less screen. Location is fetched best-effort in the
  background and never blocks the first list render (the old screen blocked
  the entire UI on a location permission prompt).
- **`lib/features/farmer/presentation/widgets/vet_detail_dialog.dart`** — full
  doctor-detail view (profile, verification, specialties, modes, fee, weekly
  availability, recent reviews) with a "Book consultation" action.
- **`lib/features/farmer/presentation/widgets/vet_booking_dialog.dart`** — the
  booking form: farm (owned, active only) → optional flock (active only,
  auto-fills breed/age/count when selected) → mode/urgency (constrained to
  what the doctor actually offers) → date (≤90 days) → time (only the
  doctor's actually-published, actually-free slots, fetched fresh per
  date+mode) → symptoms/mortality/notes, then `POST /api/consultations/`
  through the existing, unmodified booking pipeline.
- **`lib/features/farmer/presentation/screens/find_vet_screen.dart`** — the
  unified container: one `AppBar` + `TabBar` (**Discover Vets** / **My
  Consultations**) over the two pieces above.
- **`test/find_vet_screen_test.dart`** — 6 new widget tests (§6).

### Modified files
- **`lib/features/farmer/presentation/screens/farmer_consultations_screen.dart`**
  — added an `embedded` constructor flag so it can render without its own
  `Scaffold`/`AppBar` inside the new tab container while keeping its own
  Consultations/Chats sub-tabs unchanged. Refresh interval bumped from 4s to
  **8s** per the task's §8 timing table.
- **`lib/core/router/app_router.dart`** — new nested route
  `/farmer/find-vet` → `discover` / `consultations`; the old `/farmer/vet-map`
  and `/farmer/consultations` routes now `redirect:` to the new paths
  (preserving the old `?disease=` query string) instead of 404ing.
- **`lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart`**
  — the two separate tiles collapsed into one "Find Vet" tile (carries the
  upcoming-consultations badge); the consultation-notification tap target now
  points at `/farmer/find-vet/consultations`; added a dedicated, lightweight
  **3-second** notification-count poll (hitting the cheap `/api/notifications/`
  endpoint) decoupled from the heavier 4s dashboard-data poll, per §8.
- **`lib/features/farmer/presentation/screens/disease_detection_screen.dart`**
  — its two "Find a Vet" links now go straight to `/farmer/find-vet/discover`
  (carrying the disease context, rendered as a banner inside Discover Vets,
  same as the old map screen did).
- **`lib/features/farmer/data/vet_discovery_service.dart`** — added the
  `maxDistanceKm` parameter to match the backend change.

### Removed
- **`lib/features/farmer/presentation/screens/vet_map_screen.dart`** — deleted.
  Its only capability (plot nearby vets on a map, call, open in Google Maps)
  is now the map-view mode inside Discover Vets; nothing it did is lost, and
  keeping it around unreferenced would have been exactly the "parallel
  workflow" the brief says not to create.

### Deliberately not changed
- **Ratings & Reviews tab** — the brief allows showing this inside My
  Consultations instead of a separate tab ("optional, if not shown inside My
  Consultations"). It already was — every consultation card shows the
  farmer's submitted stars/rating/review. No third tab was added.
- **Doctor-detail "available slots for a date range"** — the existing
  `booking-options` endpoint already does this (per date+mode, which is what a
  booking flow actually needs); it wasn't folded into `vet_detail` itself
  since that would duplicate the same computation under two URLs for no
  behavioural gain.
- **Doctor-side screens** (appointments, case notes, prescriptions, follow-ups,
  earnings, messenger) — already complete per §2; not touched.

---

## 6. Flutter tests added

**`test/find_vet_screen_test.dart`** (new, 6 tests, all passing):
`FindVetScreen` builds with both tabs and defaults to Discover Vets; opens
directly on My Consultations via `initialTab`; surfaces the disease-detection
banner; `DiscoverVetsTab` renders all its filters and falls back to a
retryable error state (not a crash or infinite spinner) with no session;
`VetDetailDialog` and `VetBookingDialog` do the same. These follow the
existing `farmer_screens_smoke_test.dart` convention (no session → the
network call fails → the screen must degrade gracefully).

One implementation note worth recording: Discover Vets makes a best-effort,
real platform-channel call (`Geolocator`) with its own internal timeout. In
the widget-test harness, with no location plugin mocked, that call can
genuinely hang until its own timeout fires — which showed up as Flutter's
"Timer still pending after dispose" test-teardown failure, not as an app bug.
Two changes fixed this cleanly: (1) the app code now starts the location
lookup as a non-blocking background task rather than gating the first list
load on it (a real UX improvement, not just a test workaround — the old map
screen blocked its entire UI on the location permission prompt); (2) the
affected tests run under `tester.runAsync` and either wait for a specific
result or explicitly drain background timers before the widget tree is
disposed, which is the standard pattern for testing a widget that touches a
real plugin channel.

Full suite: **`flutter test` → 106/106 passing** (100 pre-existing + 6 new).
`flutter analyze lib test` → 6 pre-existing info-level lints in
`farmer_feed_marketplace_screen.dart` (untouched by this pass), **zero** from
any file this pass added or changed. `flutter build web --release` →
succeeded (`√ Built build\web`; the same two advisory-only notes as the prior
platform audit — MaterialIcons tree-shaking, a `socket_io_common` wasm
dry-run note — neither a failure, neither new).

---

## 7. Manual verification performed

**Backend, over real HTTP against a running server** (not just the Django
test client): created a throwaway doctor + farmer + farm + flock + weekly
availability slot, then, exactly as the new Flutter screens do —

1. `GET /api/consultations/vets/?mode=online&max_distance_km=50&verified=true&latitude=…&longitude=…`
   → 200, the seeded doctor found, correctly shaped for the discovery cards.
2. `GET /api/consultations/vets/<id>/` → 200, full detail incl. weekly
   availability slots.
3. `GET /api/consultations/vets/<id>/booking-options/?date=…&mode=online` →
   200, farms + flocks + free time slots.
4. `POST /api/consultations/` with a selected flock → **201**, case detail
   correctly auto-derived from the flock (breed, current bird count, age in
   weeks from `start_date`) exactly as the brief requires ("the doctor can
   later add diagnosis... without re-entering farmer information").
5. `GET /api/consultations/` → the new booking appears with its case data.
6. `GET /api/notifications/` → the farmer's "Consultation requested"
   notification is present with `unread_count: 1`, confirming the endpoint
   the new 3-second dashboard poll relies on.

All test/throwaway rows created for this check were deleted afterward; the
database was left exactly as found otherwise.

**Not performed:** a full scripted real-browser (Playwright) walkthrough of
every screen across all roles, of the kind the 2026-09-11 platform audit ran.
Given the scope of this task, verification instead combined (a) 90 backend
checks across three test scripts, all passing, (b) 106 Flutter widget tests,
all passing, (c) a live end-to-end HTTP run of the exact new discovery→
booking flow, and (d) a successful release web build. A follow-up real-browser
pass through Discover Vets → book → doctor accepts → chat → complete →
prescription → follow-up → payment → rating, on both the farmer and doctor
side, is recommended before this ships to real users, per the task's own
manual-verification checklist (§11 of the brief) — this pass did not click
through the live Flutter UI by hand.

---

## 8. RBAC changes

None. `IsFarmer` / `IsDoctor` were already correct; the new tests (§4) are the
first to actually exercise cross-account isolation for `appointment_action` /
`consultation_action` under a live request rather than by code review alone.

---

## 9. Remaining limitations / follow-ups

- **No real-browser walkthrough** of the new screens — see §7.
- **Discover Vets' map view** does not yet cluster overlapping markers or
  support tapping a marker to jump straight into booking (it opens the detail
  dialog first, matching the existing card-tap behaviour) — a small polish
  item, not a correctness gap.
- **The bare `/farmer/find-vet` route** renders the same content as
  `/farmer/find-vet/discover` via its default tab index rather than issuing an
  HTTP redirect to that path — behaviourally identical to what the brief asks
  for, just without an extra navigation hop; noted here in case a literal URL
  redirect is later required for analytics/link-tracking reasons.
- Everything flagged as "documented, not fixed" in the repo's own prior
  `PRODUCTION_READINESS_REPORT.md` (payment webhook signature verification,
  object storage, Docker/CI, error-tracking dashboards) is **unrelated to this
  task's scope** and unchanged.

---

## 10. Confirmation

**Nothing was committed.** All changes described above are in the working
tree only (`git status` reflects them); no `git commit`, `git push`, or
destructive git operation was run at any point during this pass.
