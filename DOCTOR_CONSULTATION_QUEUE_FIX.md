# Doctor Consultation Queue — Fix

The root cause and trace are in [DOCTOR_CONSULTATION_DELIVERY_AUDIT.md](DOCTOR_CONSULTATION_DELIVERY_AUDIT.md). In short, the doctor app crashed while parsing an open-ended request (`scheduled_at: null`). That aborted the whole refresh and silently kept stale or demo data on screen.

## Files changed

| File | Change |
|---|---|
| `lib/features/doctor/data/models/doctor_models.dart` | `scheduledAt` is now nullable (`DateTime.tryParse`). New fields `requestedAt` (UTC) and `urgency`. New getters `hasPreferredSlot` and `sortKey`. The enum gains `inProgress` and `cancelled`, and every backend status is mapped explicitly. |
| `lib/features/doctor/data/services/doctor_session.dart` | No demo consultation data (only the placeholder **profile** remains until the real profile loads). The refresh now loads each section independently, so one failure keeps that section's last real data and reports an error. Refreshes are queued rather than dropped. A refresh stuck for more than 30s is superseded (timer-free, generation-guarded). A newly arrived notification triggers a refresh. New: `appointmentsLoaded`, `pendingRequests`, `pendingRequestCount`, and `parseAppointments` (one parser, shared with the tests). `updateAppointmentStatus` returns the server's error, reverts the optimistic change, and resyncs. |
| `lib/features/doctor/presentation/screens/doctor_appointments_screen.dart` | Refreshes on entry (after the first frame), on returning to the foreground, and on pull-to-refresh. Shows a spinner until the first load succeeds or fails, never a premature empty state. An error banner shows the server's actual reason plus **Retry**, and keeps the loaded data. New In Progress and Cancelled tabs. Open-ended cards read "Any time — propose a slot when accepting" (or "No time was set" when not pending). Snackbars report the server's real result. |
| `lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart` | The **Pending requests** stat (`pendingRequestsStat`) counts every `requested` consultation and still calls out urgent ones ("Pending (N urgent)"); tapping it opens Schedule. Open-ended requests render without a time. Opening the Schedule tab refreshes. Null-safe status dots. |
| `backend/doctor/views.py` | Appointment rows add `requested_at` (aware ISO). The dashboard summary adds `pending_requests` and `consultation_counts`. |
| `backend/consultations/management/commands/seed_consultation_demo_data.py` *(new)* | Idempotent demo seed (see below). |
| `backend/scripts/test_doctor_consultation_queue.py` *(new)* | Backend visibility, lifecycle and access suite (43 checks). |
| `test/doctor_consultation_queue_test.dart` *(new)* | Flutter model, session and widget tests (13). |

**Models and migrations:** none. No schema change was needed, and `migrate --check` is clean.

## API contract changes (additive only)

`GET /api/doctor/appointments/`: each row gains

```json
"requested_at": "2026-10-29T19:28:32.497022+00:00"
```

`scheduled_at` stays `null` for open-ended requests, as before. The client now handles that.

`GET /api/doctor/dashboard/`: `summary` gains

```json
"pending_requests": 2,
"consultation_counts": {"requested": 2, "completed": 2}
```

`consultation_counts` comes from one aggregate over the same `doctor=request.user` queryset that the queue uses, so the counters and the queue cannot disagree. No fields were removed or renamed.

## Refresh triggers

| Trigger | Where |
|---|---|
| Login / profile load | `DoctorSession._loadRegisteredProfile` |
| Entering Schedule (route, or the dashboard tab) | `initState` post-frame, and `_selectTab(1)` |
| Pull-to-refresh, Retry | `RefreshIndicator`, error banner |
| App returns to the foreground | `didChangeAppLifecycleState(resumed)` on the dashboard and on Schedule |
| New notification arrives | `_refreshNotifications`, when an unseen id appears |
| Periodic | dashboard, every 12s |
| After every action | `updateAppointmentStatus`, `rejectAppointment` |
| Notification tap | routes to `/doctor/appointments` (existing navigation), which refreshes on entry |

## Request queue

* **Contents:** the farmer, farm, mode, urgency, symptoms (via the case), and the slot or "Any time". All of this is farmer-safe context only, already served by the API.
* **Actions:** Accept / Reject (with reason) / Reschedule (proposes a slot, defaulting to tomorrow 10:00 for open-ended requests). For accepted or in-progress consultations: Start / Complete / No-show.
* **States:** loading (spinner) / empty (per filter) / error with the real reason and Retry / stale data kept with a "showing last loaded data" banner. Permission errors (e.g. a suspended account) surface as the server's message.

## Seed command

```
python manage.py seed_consultation_demo_data
```

The command books through the real `create_booking` path and sends the real notifications, for the seeded demo pair only (`farmer.rashed@example.com` to `dr.samira.rahman@example.com`). It creates an open-ended and/or a dated pending request **only if that kind is missing**. It never edits or deletes rows, and a re-run is a no-op. On the dev DB the first run created one dated request (`2997b784-…`), because the real open-ended one (`a74f9fe9-…`) already existed.

## Verification

### Backend

`backend/scripts/test_doctor_consultation_queue.py` passes 43/43. It uses only throwaway `doctorqtest+` accounts and cleans up after itself. It covers:

* **Delivery:** an open-ended and a dated booking are stored against the doctor **user**, both appear as `pending`, the open-ended one has `scheduled_at: null` and an aware `requested_at`, and `?status=pending` filters correctly.
* **Dashboard:** `pending_requests`, `urgent_requests` and `consultation_counts` are correct and move through the lifecycle.
* **Notification:** `reference_id` is the consultation id, and the route is `/doctor/appointments` with the target available.
* **Isolation:** another doctor can't see the request or accept it (404). A suspended doctor gets 401, a farmer 403, an unauthenticated call 401. All errors are structured `{detail, …}`.
* **Lifecycle:** complete-before-accept and duplicate accept are rejected. accept → start → complete works and is recorded in status history. A farmer cancellation shows to the doctor as `cancelled`, the pending count drops, and a cancelled request can't be accepted.

Existing suites:

| Suite | Result |
|---|---|
| consultation_transitions_and_receipts | 53/53 |
| booking_rules | 29/29 |
| chat_access | 13/13 |
| doctor_flow | 58/58 |
| find_vet_discovery | 38/38 |
| notifications | 135/135 |
| admin_panel | 62/63 — known pre-existing "admin login 200" email-verification gate |

`manage.py check`: no issues. `migrate --check`: exit 0.

### Flutter

`test/doctor_consultation_queue_test.dart` passes 13/13:

* **Parsing:** the real-shaped open-ended row parses (it threw before), a whole payload parses, every status maps to its own state, and `sortKey` is correct.
* **Screen states:** spinner → load-failure banner with the real reason and Retry; a new open-ended request renders with Accept/Reject/Reschedule; a failed refresh keeps the data; a refused Accept is rolled back and success is never announced early; the Pending/Cancelled/In Progress tabs work; a 360px phone layout renders without overflow.
* **Counters:** `pendingRequestCount` includes the open-ended request and `todayAppointments` excludes it; the dashboard `pendingRequestsStat` shows "2" and "Pending (1 urgent)".
* **Guard:** no demo consultation lists are wired into the session.

Full `flutter test`: 288 passed, 2 failed. Both failures are the known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart`. `flutter analyze lib test`: only the 6 known infos in `farmer_feed_marketplace_screen.dart`.

### Live data (dev DB, `dr.samira.rahman@example.com`)

The API returns 4 rows. `a74f9fe9` is `pending` with `scheduled_at: null`; `2997b784` is `pending`, 2026-11-02 11:00. The dashboard reports `pending_requests=2`. All consultation notifications route to `/doctor/appointments`. The real payload parsed through `DoctorSession.parseAppointments` gives 4 rows, `pendingRequestCount=2`.

## Limitations

* **Payments:** no real payment gateway is active. Consultation payments remain the existing manual/dev "mark paid" flow, and this fix does not change that.
* **Delivery latency:** delivery is poll-based (4s notification poll that triggers a queue refresh, plus a 12s dashboard poll), not push.
* **Dashboard counter:** the count is computed from the loaded queue, so it always matches the list. Before the first load it falls back to the server's `pending_requests`.
* **Interactive browser check:** this still has to be done by hand (steps below). The API and widget-level checks above were automated.

### Manual check

1. `.\run_backend.bat`, then `flutter run -d chrome`.
2. Sign in as the farmer and choose **Find Vet → Dr. Samira → Request any available time**.
3. Sign in as `dr.samira.rahman@example.com` and check that:
   * the dashboard **Pending requests** count increments;
   * **Schedule → Pending** lists the request with "Any time — propose a slot when accepting";
   * the notification tap opens Schedule.
4. **Accept** it. The card moves to Accepted and the count drops.
