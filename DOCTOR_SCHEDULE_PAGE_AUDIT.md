# Doctor Schedule Page — Audit and Cleanup

**Date:** 2026-10-31
**Requirement:** the Schedule page shows only (1) incoming consultation requests and (2) upcoming schedules/appointments. Case work, Close, Mark as Complete and prescriptions belong on the individual Case page ([DOCTOR_CASE_PAGE_FIX.md](DOCTOR_CASE_PAGE_FIX.md)).

## 1. Before

`DoctorAppointmentsScreen` (dashboard tab "Schedule") listed **every** consultation from `GET /api/doctor/appointments/` behind status filter tabs: All · Pending · Accepted · In Progress · Completed · Rejected · No-Show · Cancelled.

| Card status | Actions on the card |
|---|---|
| Pending | Reject · Reschedule · Accept |
| Accepted / In progress | No-Show · **Mark Complete** (no confirmation) |
| Completed | **Issue prescription & advice** (dialog, one medicine) |
| Rejected / Cancelled / No-show | none, but still listed |

Also seen in reference image 2:

* **"Reschedul / e"**: on a phone-width card the three request buttons share one row, and the label wrapped.
* **"Pending" chip contrast**: amber `#F9A825` on `#FFF8E1`, about 1.9:1.
* **Fee contrast**: the fee was light green `#1DB584` on white, about 2.6:1.
* **Double Accept**: Accept had no in-flight guard, so a double tap could send two requests.

## 2. After

Two fixed sections, always shown:

| Section | Statuses | Card actions |
|---|---|---|
| **Consultation Requests** | `requested` (pending), `reschedule_proposed` ("Time proposed", waiting for the farmer) | Pending: Reject · Reschedule · Accept (one decision at a time; Accept shows a spinner). Time proposed: an explanatory line |
| **Upcoming Schedule** | `accepted`, `in_progress` | **Open case** (opens the Case page, where the case is worked, closed and completed) · No-Show (now with a confirmation) |

Not on the Schedule any more: completed, rejected, cancelled and no-show consultations; filter tabs; Mark Complete; the prescription dialog. They are case history, reachable from **Cases** (which now filters by Open · Closed · Completed · Awaiting acceptance · Ended).

Upcoming includes accepted appointments whose time has already passed but which have not been completed. They are still outstanding work, and Open case takes the doctor to finish them.

States:

| State | Behaviour |
|---|---|
| Loading | Spinner until the first real load (unchanged) |
| Empty | Per section: "No pending consultation requests" / "No upcoming schedules" |
| Error | Existing red banner with the server's reason and Retry; already-loaded data stays on screen |
| Refresh | Pull-to-refresh, on screen entry, on app resume, and after every action (unchanged) |

Visual fixes:

* **Narrow screens (below 400px):** Accept goes full width on its own row, and Reject and Reschedule share the row beneath. Labels are single-line.
* **"Pending" chip:** now uses `VetColors.amberText` `#8A6100`, about 5.5:1 contrast.
* **Fee:** now `VetColors.available` `#2E7D32`, about 5.1:1 on white.
* **Navigation:** the app bar is unchanged, with white title and icons on the dark green navigation surface.

## 3. Backend

`GET /api/doctor/appointments/?scope=schedule` returns `{requests, upcoming, appointments}` using the same status sets (`SCHEDULE_REQUEST_STATUSES`, `SCHEDULE_UPCOMING_STATUSES` in `doctor/views.py`, mirrored by `DoctorAppointment.scheduleSection` in Flutter).

Without `scope`, the endpoint is **unchanged**: it still returns every consultation. The dashboard counters and today's list depend on it, and existing clients keep working. The Flutter Schedule page classifies the full list it already polls rather than adding a second poll.

RBAC is unchanged: doctor role only (401 unauthenticated, 403 farmer), and each doctor sees only their own rows.

## 4. Tests

| Suite | Checks |
|---|---|
| `backend/scripts/test_doctor_case_workflow.py` (schedule part) | Scope returns requested and reschedule-proposed as requests and accepted / in-progress as upcoming. Completed, rejected and cancelled are excluded. Rows carry the date/time, mode, status and case id. The unscoped list is unchanged. Another doctor sees none of these rows. A farmer gets 403 and an anonymous caller 401. Accept still works. |
| `test/doctor_case_workflow_test.dart` (Schedule page group) | Only the two sections. 4 hidden statuses are never rendered. No Mark Complete, Mark as Complete or Prescription text. Open case on each upcoming card. Both empty states. Open case navigates to the Case page, which shows Mark as Complete, and Back returns. A 360px card has no overflow and a one-line Reschedule label. |
| `test/doctor_consultation_queue_test.dart` | Existing loading, error, retry, refused-Accept and narrow-layout tests pass unchanged. The old *"filter tabs: Pending, In Progress, Cancelled"* test asserted the behaviour this change removes (filter tabs, cancelled rows on Schedule). It is **replaced**, not deleted, by *"requests and upcoming only: cancelled and completed rows are not schedule items"*, which checks the opposite and keeps its "only a pending request invites a slot proposal" assertion. |

## 5. Not changed

* Accept, reject and reschedule rules, slot-conflict checks and availability checks.
* Notifications from schedule actions.
* The "Set consultation times" dialog and the availability toggle in the app bar.
* Video calls (`/doctor/video`).
