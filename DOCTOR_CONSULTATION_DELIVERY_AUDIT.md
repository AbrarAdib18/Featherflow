# Doctor Consultation Delivery — Audit

**Date:** 2026-10-30
**Symptom:** A farmer's consultation request showed in the farmer's *My Consultations*, and both farmer and doctor got a notification. The doctor never saw the request anywhere: not in Consultations/Schedule, the request queue, or the dashboard.
**Verdict:** The backend was correct. The bug was in the **Flutter doctor client**: a contract/parsing mismatch on `scheduled_at: null`, amplified by an all-or-nothing refresh that failed silently.

Fixes are described in [DOCTOR_CONSULTATION_QUEUE_FIX.md](DOCTOR_CONSULTATION_QUEUE_FIX.md).

---

## 1. Reproduction with real accounts (dev DB)

| Item | Value |
|---|---|
| Farmer | `farmer.rashed@example.com` |
| Doctor | `dr.samira.rahman@example.com`, user id `9a675aea-7673-4415-a7a8-96d8d25c39c9` (the doctor-profile id is different, `1eb67c6a-…`) |
| Consultation | `a74f9fe9-7f84-43f0-b767-f2e97d54126f`, booked with **"Request any available time"** (no date/time) |
| DB row | `status = requested`, `doctor_id = 9a675aea-…` (the doctor **user**: correct), `appointment_date = NULL`, `appointment_time = NULL` |

### Backend responses (as the doctor)

* `GET /api/doctor/appointments/` returned **200** and **included** the consultation:
  ```json
  {"id": "a74f9fe9-…", "status": "pending", "scheduled_at": null,
   "has_preferred_slot": false, "urgency": "routine", "farmer_name": "Md. Rashed Karim", …}
  ```
* `GET /api/doctor/dashboard/` returned **200** with `today_appointments = []` (correct, since the request has no date). There was **no** counter for pending requests, so even a working client had no dashboard number for this request.
* `GET /api/notifications/` included the "New consultation request" notification, with `reference_id = a74f9fe9-…`, `reference_type = consultation`, routing to `/doctor/appointments`.

### Queryset

`appointments()` uses `Consultation.objects.filter(doctor=request.user)`, ordered by date/time with nulls handled. `requested` is included and exposed as `pending`; `?status=pending` maps to `requested`. **The queryset was correct.**

### Flutter parsing

Feeding that exact row to `DoctorAppointment.fromJson` threw:

```
FormatException: Invalid date format
null
```

`fromJson` did `DateTime.parse('${j['scheduled_at']}')`, which parses the string `"null"`.

### UI result

The appointments list kept showing whatever was loaded before. On a fresh session that was the **hard-coded demo appointments** the session was constructed with. No error was shown.

---

## 2. Full path trace

| Step | Layer | Result |
|---|---|---|
| Farmer submits booking (`POST /api/consultations/`) | Farmer API to `create_booking` | ✅ Row created with `doctor = DoctorProfile.user` (the user id, not the profile id that was sent) |
| Doctor + farmer notifications | `consultations/views.py` | ✅ Both created, `reference_id` = consultation id |
| Farmer's My Consultations | `GET /api/consultations/` | ✅ Lists it, with `date`/`time` null |
| Doctor queue API | `GET /api/doctor/appointments/` | ✅ Returns it as `pending` with `scheduled_at: null` (the documented contract for open-ended requests) |
| Doctor app parse | `DoctorAppointment.fromJson` | ❌ **Throws** on `scheduled_at: null` |
| Doctor app state | `DoctorSession.refresh()` | ❌ One `try` around all six fetches, so the throw aborted the refresh before cases, earnings, chats or notifications were assigned. The error was stored but **not shown** on the Schedule screen |
| Doctor UI | Schedule/dashboard | ❌ Kept stale data (initially **fake demo appointments**). The new request never appeared |
| Doctor notifications | Separate 4-second poller (`_refreshNotifications`) | ✅ Unaffected by the crash, which is why the bell still showed the request |

---

## 3. Root cause

**Layer: Flutter client, model parsing (API contract mismatch).**

When the farmer picks "Request any available time", the backend deliberately sends `scheduled_at: null`. The doctor model required a non-null `DateTime` and parsed the literal string `"null"`. Every doctor with even one open-ended request in their history had **every** appointment refresh fail.

## 4. Compounding defects found on the same path

1. **All-or-nothing refresh.** One bad row blanked six sections and raised no visible error.
2. **Fake demo data in the session.** `DoctorSession` started with demo appointments, cases, chats, earnings and ratings, so a failed refresh showed fabricated patients instead of an error.
3. **Status mapping.** `in_progress` and `cancelled` fell through to **pending**. A cancelled request still looked actionable, and a started consultation looked like a new request.
4. **No pending-requests counter.** The dashboard's only request card counted *urgent* requests, so a routine request appeared in no counter at all.
5. **No queue refresh when a notification arrives.** A new-consultation notification updated the bell but not the queue.
6. **No refresh on entering the screen or returning to the foreground.** Only the dashboard's 12-second timer refreshed.
7. **Optimistic actions not reverted.** Accept, complete and no-show changed the card immediately, showed a success snackbar *before* the server answered, and left the change in place when the server refused it.
8. **Refresh requests dropped.** A refresh requested while one was in flight was silently ignored, so a notification-triggered refresh could be lost.

## 5. What was not wrong

* The consultation's doctor link: `consultation.doctor` is the doctor's **user**, which is the correct relation.
* Doctor queryset, status filter, access isolation (another doctor gets a 404), and the lifecycle transition rules.
* Notification creation, targeting and routing.
* There were no missing migrations (the schema is managed through `*_extension.sql`, and `migrate --check` is clean).
