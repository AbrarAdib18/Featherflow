# Farmer ↔ Doctor Workflow — End-to-End Audit

Companion to `FIND_VET_DISCOVERY_FIX.md` (root cause + fix) and
`CONSULTATION_LIFECYCLE_VERIFICATION.md` (test evidence). Nothing in this work
was committed.

## 1. Headline

The reported break — *"a farmer cannot see doctors in Find Vet even though an
eligible doctor exists"* — was **not a code defect in the discovery path**. The
endpoint, serializer, Flutter service, model parsing and state handling were all
correct. The database simply contained **zero verified doctors**, because a
shared admin test suite was suspending the seeded demo doctor on every run.

Two genuine defects were found and fixed, both of the same family
(**test isolation / determinism**):

1. `test_admin_panel.py` hijacked and de-verified whatever real verified doctor
   existed → broke farmer discovery platform-wide. (`FIND_VET_DISCOVERY_FIX.md`)
2. `test_doctor_flow.py` had a calendar-dependent self-conflict that made it
   **crash** on certain weekdays. (`CONSULTATION_LIFECYCLE_VERIFICATION.md` §4)

A third, structural gap was closed: **there was no test asserting that a farmer
can actually discover a doctor**, which is why #1 went unnoticed indefinitely.

## 2. What was inspected

| Area | Files |
|---|---|
| Find Vet screens/services | `lib/features/farmer/presentation/screens/find_vet_screen.dart`, `widgets/discover_vets_tab.dart`, `data/vet_discovery_service.dart` |
| Discovery endpoint | `backend/consultations/views.py:vets()`, `vet_detail`, `booking_options`, `vets_nearby`; `consultations/urls.py` |
| Doctor profile/verification | `backend/profiles/models.py:DoctorProfile`; `backend/doctor/models.py:AvailabilitySlot`, `DoctorEarning`, `PayoutRequest` |
| Admin verification path | `backend/api/admin_views.py:admin_record`, `backend/api/admin_approvals.py:_do_suspend` |
| Booking/state machine | `backend/consultations/` + suites in §4 |
| Seed data | `backend/users/management/commands/seed_platform_demo.py` |
| Existing tests | `scripts/test_doctor_flow.py`, `test_consultation_booking_rules.py`, `test_consultation_transitions_and_receipts.py`, `test_consultation_chat_access.py`, `test_vets_nearby.py`, `test_admin_panel.py` |

## 3. Data source of every Find Vet field

`GET /api/consultations/vets/` → `consultations/views.py:_doctor_row()`.
**Every field is database-derived; no field is defaulted, faked, or computed
client-side.**

| Card field | Source |
|---|---|
| `id` / `user_id` | `DoctorProfile.id` / `DoctorProfile.user_id` |
| `name` | `User.full_name` |
| `photo_url` | `User` profile photo |
| `clinic` / `address` / `district` | `DoctorProfile.clinic_hospital_name` / `practice_address` |
| `latitude` / `longitude` / `distance_km` | `DoctorProfile.latitude`/`longitude`; distance computed only when the caller supplies coordinates (else `null`) |
| `degree` / `specialty` / `focus_area` / `experience_years` | corresponding `DoctorProfile` columns |
| `mode` | `DoctorProfile.consultation_mode` |
| `emergency` | `DoctorProfile.emergency_on_call_availability` |
| `available` / `availability_status` | `DoctorProfile.is_available` / `availability_status` |
| `verified` | `DoctorProfile.is_verified` |
| `fee` | `DoctorProfile.service_fee` |
| `rating` | `DoctorProfile.rating` (updated on farmer rating) |
| `summary.*` | computed from the returned rows, not stored counters |

Detail (`/vets/<id>/`) adds `availability_slots` from `AvailabilitySlot`.
Booking options adds the farmer's own `farms` (+ flocks), `slot_minutes`,
`bird_types`, `requires_availability`.

**Privacy:** verified by test that the card and detail payloads do **not**
contain `license_number`, `council_registration_proof_url`, `cv_url`, or the
doctor's `email`. `phone` *is* exposed — this is the clinic contact a farmer is
expected to be able to call; flagged here as a policy decision to confirm, not
changed.

## 4. Authoritative discoverable-doctor rule

Active account **and** doctor role **and** doctor profile exists **and**
`is_verified = True`. Availability/“available now”/distance are **optional
filters**, never part of the default list. Full statement in
`FIND_VET_DISCOVERY_FIX.md` §6.

## 5. Changes made

| File | Change |
|---|---|
| `backend/scripts/test_admin_panel.py` | Suspend-test now uses its own `_make_test_doctor()` instead of hijacking any verified doctor in the DB. **The actual fix.** |
| `backend/scripts/test_doctor_flow.py` | Availability-CRUD block picks a provably free weekday instead of hard-coded `weekday=2`. |
| `backend/scripts/test_find_vet_discovery.py` | **New** — 38-check discovery regression suite. |
| `FIND_VET_DISCOVERY_FIX.md`, `CONSULTATION_LIFECYCLE_VERIFICATION.md`, `FARMER_DOCTOR_END_TO_END_AUDIT.md` | **New** documentation. |

**No application code was changed.** No models, migrations, endpoints,
serializers, permissions, or Flutter widgets were modified — because the
application logic was correct. No API contract changed.

**No mock UI data was added.** No hard-coded doctor cards, no dummy API
fallback, no client-side bypass. Data was restored by re-running the existing
idempotent `manage.py seed_platform_demo`.

## 6. Results

203 backend checks green across six suites (table in
`CONSULTATION_LIFECYCLE_VERIFICATION.md` §1), including the previously-crashing
`test_doctor_flow` (now 58/58) and the new discovery suite (38/38, with a
negative control proving it detects the original bug).

## 7. Remaining limitations — stated plainly

- **No real payment provider.** Payment is sandbox/manual; `mark-paid` is a
  server-side state transition, correctly persisted and idempotent, but no money
  moves. Nothing was changed to imply otherwise.
- **Manual browser verification was not performed.** Verification here is
  automated-suite based against the live DB, plus code review of the Flutter
  state handling. The task's §10 browser walkthrough remains outstanding.
- **`seed_consultation_demo_data` was not created.** `seed_platform_demo`
  already provides an eligible verified doctor with availability and a farmer
  with an active farm. The seeded farm has **no flocks**, so flock-specific
  manual testing needs one added.
- **Flutter widget tests for Find Vet were not added** — the discovery
  regression is guarded at the API layer, which is where the defect actually
  lived.
- **The underlying fragility is broader than the one fix.** Suites share one
  live development database, so any suite that mutates ambient records can break
  another. Two instances were fixed here; a systematic move to isolated
  fixtures/transactional tests would prevent the whole class.

## 8. Recommendation

The highest-value follow-up is the last bullet above: shared-live-DB test
suites that mutate whatever records they find will keep producing bugs that look
like product failures. Both defects fixed here were exactly that.
