# Chat Duplicate Message & Timestamp — Audit

**Date:** 2026-10-30
**Reported:** in a doctor ↔ farmer chat, one tap on Send showed the sender's message twice, while the recipient got it once. Chat times did not match the real send time.

Fixes are described in [CHAT_MESSAGE_STATE_FIX.md](CHAT_MESSAGE_STATE_FIX.md).

---

## 1. Reproduction (real accounts, dev DB)

| Item | Value |
|---|---|
| Sender | `dr.samira.rahman@example.com` (doctor) |
| Recipient | `farmer.rashed@example.com` (farmer) |
| Conversation | `8f906e79-8a63-4cc0-bf77-ed2c9f892d77` |
| Message text | `hello` |
| Send taps | 1 |
| Flutter local id | `MSG-<millis>` (the doctor screen's optimistic id; unrelated to the server id) |
| Server message id | `4ff3d38e-a92a-40df-a1f7-af4ac563bd55` |
| Request | `POST /api/doctor/conversations/8f906e79-…/` `{"content":"hello","message_type":"text"}` (no idempotency key existed) |
| Response | `201 {"id":"4ff3d38e-…", "sent_at":"2026-10-30T10:48:20.203851+00:00", …}` |
| Socket.IO event | `message_created` with the same payload, emitted to room `conversation:8f906e79-…` **during** the POST |
| DB rows created | **1** (`messages.sent_at = 2026-10-30 10:48:20.203851`, i.e. UTC wall clock) |
| Sender UI | **2** bubbles: `hello 4:48 PM` and `hello 10:48 AM` (screenshot) |
| Recipient UI | 1 bubble |

**Verdict: the duplicate was UI-only. No duplicate database row was created.**

## 2. Duplicate: sender-side trace

```
Tap Send
 → doctor screen creates optimistic ChatMessage(id: "MSG-…", sentAt: DateTime.now())   [bubble #1, 4:48 PM]
 → POST /api/doctor/conversations/<id>/
     server: Message.objects.create(...)               (1 row)
     server: emit_to_conversation('message_created')   ← broadcast BEFORE the HTTP response returns
 → Socket.IO echo arrives first:
     dedup check: any(m.id == "4ff3d38e…")? → no (optimistic bubble is still "MSG-…")
     → APPENDED                                         [bubble #2, shown 10:48 AM]
 → HTTP 201 arrives:
     optimistic bubble renamed "MSG-…" → "4ff3d38e…"   (in place, nothing removed)
 → two list entries with the same server id → two bubbles
```

**Exact root cause:** deduplication was keyed only on the server id, but the optimistic bubble had no link to its server message until the HTTP response arrived. The server broadcasts the echo while still handling the POST, so the echo regularly wins that race. The farmer chat dialog had the identical logic (`local-…` id, `any(m['id'] == …)`).

Other contributing gaps:

* No client message id or idempotency key existed anywhere (schema, API, socket, Flutter), so a retry or double submit always created a new row.
* There was no in-flight guard. The doctor screen sent on every tap; the farmer screen cleared the field but the button stayed enabled.
* A failed farmer send silently **removed** the bubble. A failed doctor send left the bubble looking sent.
* The doctor messenger's background refresh replaced the whole thread list, which dropped any message still sending.
* The farmer dialog never polled; it relied entirely on the socket.

## 3. Timestamp trace

| Step | Finding |
|---|---|
| Storage | `messages.sent_at` is `timestamp without time zone`; Django writes UTC and the DB session runs in UTC. ✅ The stored value is correct UTC. |
| Read back | The ORM returns a **naive** datetime (`2026-10-30 10:48:20.203851`). |
| List APIs (`/api/doctor/conversations/`, `/api/consultations/chats/`) | `naive.isoformat()` → `"2026-10-30T10:48:20.203851"`, with **no offset**. ❌ |
| Send response / socket echo | Built from the freshly created aware value → `"…+00:00"`. ✅ |
| Flutter parse | `DateTime.parse` treats an offset-less string as **local time** → 10:48 **local**. ❌ |
| Flutter format | The doctor bubble formatted `dt.hour` without `toLocal()`, so `+00:00` values displayed UTC hours. ❌ |
| Display | Every server-sourced time showed UTC wall clock, **6 h early** in Dhaka (UTC+6). Only the optimistic device time was right, so the same message could show "4:48 PM" and "10:48 AM". |
| Farmer UI | Showed no times at all. |
| Format | `h:mm AM/PM` only: no "Yesterday" or date, so older messages were ambiguous. |

**Exact root cause:** a timezone contract break between the **serializer** and **Flutter parsing**. The API emitted naive UTC (no offset), and Flutter read naive values as local time and formatted aware values without converting to local. The stored data was always correct.

## 4. Roles with chat

| Role | Entry point | Status before |
|---|---|---|
| Doctor | Dashboard → Messages → conversation (`DoctorMessengerScreen` → chat screen) | Duplicate + wrong times |
| Farmer | My Consultations → Chat, and Find Vet → Chats (same dialog) | Duplicate + no times + failed sends dropped |
| Others | None: `/api/consultations/chats/` is restricted to farmer/doctor. Admin "Conversations"/"Messages" are read-only admin records. | n/a |

## 5. What was not wrong

* The database: exactly one row per send; `sent_at` stored correctly as UTC.
* Conversation access control (participants only) and mark-read.
* Recipient delivery (one message).
