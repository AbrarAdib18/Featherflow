# Chat Message State — Fix

The root causes are in [CHAT_DUPLICATE_MESSAGE_AND_TIMESTAMP_AUDIT.md](CHAT_DUPLICATE_MESSAGE_AND_TIMESTAMP_AUDIT.md). In short, the Socket.IO echo raced the REST response and was appended next to the optimistic bubble (UI-only duplicate), and the API sent naive UTC times that Flutter showed as local time.

## Files changed

| File | Change |
|---|---|
| `backend/messaging/chat.py` *(new)* | The one send path for every channel: `deliver_message()`, which is idempotent on `(sender, client_message_id)`, survives races, and notifies and updates `last_message_at` only on create. Also `message_payload()` (one wire format), `iso_utc()` (always `+00:00`), and `ordered_messages()` (by `sent_at, id`). |
| `backend/doctor/views.py` | Doctor send uses `deliver_message`: 201 on create, 200 on replay, 409 for an id reused in another conversation. Broadcasts only on create. The conversation list uses `message_payload` and `iso_utc`. |
| `backend/consultations/views.py` | The same for the farmer send and the farmer chat list. |
| `backend/messaging/realtime.py` | The Socket.IO `send_message` event goes through `deliver_message` and does not re-broadcast a replay. |
| `backend/doctor/models.py`, `backend/doctor/serializers.py` | `Message.client_message_id` (UUID, nullable); `MessageSerializer.client_message_id`. |
| `backend/postgres_backend_extension.sql`, `featherflow_schema.sql` | New column, plus partial unique index `uq_messages_sender_client_message_id`. |
| `lib/core/chat/chat_core.dart` *(new)* | Shared by every chat UI: `ChatTimeline` (upsert / mergePage / reconcile, matching on server id **or** client id), `ChatTime` (server parse into local time, display format, no-future clamp), `newClientMessageId()` (UUID v4), `ChatEntry` model, and the `ChatTimelineItem` contract. |
| `lib/core/chat/chat_widgets.dart` *(new)* | `ChatMessageMeta`: time / "Sending…" / "Not sent · Tap to retry". |
| `lib/features/doctor/data/models/doctor_models.dart` | `ChatMessage` gains `clientMessageId` and `status`. Times are parsed via `ChatTime`, and thread messages are ordered and de-duplicated. |
| `lib/features/doctor/data/services/doctor_session.dart` | `sendMessage(threadId, text)`, `retryMessage`, `isSendingIn`; an in-flight guard keyed by client id; socket echoes are upserted, never appended; refresh reconciles (keeps unsent bubbles). |
| `lib/features/doctor/presentation/screens/doctor_messenger_screen.dart` | Send is disabled while in flight, bubbles use stable keys, times are correct, and failed sends show Retry. `DoctorChatScreen` is now public (for tests). |
| `lib/features/farmer/presentation/screens/farmer_consultations_screen.dart` | The farmer chat (now `FarmerChatDialog`) uses the same core, shows times, polls every 4s, has the Send guard, and shows failed/Retry instead of dropping the message. |
| `lib/features/farmer/data/farmer_consultation_service.dart` | `sendChat(..., clientMessageId:)`. |
| `lib/core/network/realtime_chat_service.dart` | The (unused) socket `send` now requires a `clientMessageId`. |
| Tests | `backend/scripts/test_chat_message_state.py`, `test/chat_message_state_test.dart`. |

## API / schema / migration

* **Schema (additive):** `messages.client_message_id UUID NULL`, plus `UNIQUE (sender_id, client_message_id) WHERE client_message_id IS NOT NULL`. Existing rows stay NULL and are unaffected. As with every table here (`managed = False`) there is no Django migration: the DDL is idempotent in `postgres_backend_extension.sql`. It is already applied to the dev DB; ops must run `psql -d featherflow -f backend/postgres_backend_extension.sql` on other databases.
* **Send request:** optional `client_message_id` (UUID). Clients that omit it still work as before.
* **Send response:** `201` when created, `200` when the id was already used (the original message is returned), `409` when the id was used in a different conversation, and `400` for a malformed id.
* **Message payload** (lists, send response, socket event): adds `client_message_id`, `sender_id` and `type`. `sent_at` is now **always** ISO 8601 with an offset (`2026-10-30T10:48:20.203851+00:00`), and so is `last_message_at`. The doctor-only `from_doctor` and farmer-only `from_me` keys remain.
* **Notifications:** a single "New message" notification per created message, of type `message`, for every send path. The doctor path previously used `reminder`, and the socket path "New private message". A replay never notifies again.

## Deduplication and idempotency

1. Flutter generates a UUID v4 `client_message_id` **once** per outgoing message. The optimistic bubble's id is that client id.
2. The server stores it. A repeat with the same id returns the original row, and concurrent duplicates are settled by the unique index (the `IntegrityError` is caught and the winner returned).
3. Every list change in Flutter goes through `ChatTimeline.upsert`. An incoming server message replaces any entry with the same **server id or client id**, whichever arrives first (send response, socket echo or poll), so there is always one entry per message, even before the response arrives.
4. Refresh and reopen use `ChatTimeline.reconcile`: the server list wins, and only local messages still *sending* or *failed* (not yet stored) are kept.
5. Rendering uses `ValueKey(clientMessageId ?? id)`, which is stable across confirmation.
6. Send is disabled while a message is in flight, the text field is cleared synchronously (a double tap finds nothing to send), and an in-flight set keyed by client id blocks re-entry. Retry reuses the same client id.

## Timestamps and timezones

* **Authoritative time:** the server-persisted `messages.sent_at`, stored as UTC. The API emits it with an explicit `+00:00`; naive DB values are labelled UTC by `iso_utc`.
* **Flutter parsing:** `ChatTime.parseServer` turns an ISO value with an offset into that instant, and treats any legacy value without an offset as UTC (never local), then converts it to the **viewer's local zone**.
* **Provisional time:** the device time is shown only while the bubble is "Sending…". It is replaced by the server's `sent_at` on confirmation, and refresh, poll and echo carry the same server value thereafter.
* **Display:** today `4:52 PM`; yesterday `Yesterday, 4:52 PM`; within 7 days `Mon, 4:52 PM`; older `12 Oct 2026, 4:52 PM`. A server time slightly ahead of the device clock is shown as "now", never as a future time; the stored value is unchanged.
* **Ordering:** by `sent_at`, then id, on both server and client.

## Per-role summary

| | Doctor | Farmer |
|---|---|---|
| Chat entry point | Dashboard → Messages → conversation | My Consultations → Chat; Find Vet → Chats |
| Conversation type | Doctor ↔ farmer consultation conversation | Same conversation, other side |
| Send flow | REST `POST /api/doctor/conversations/<id>/` with `client_message_id` | REST `POST /api/consultations/chats/<id>/` with `client_message_id` |
| Optimistic message | Bubble with client id, "Sending…" plus provisional time | Same |
| Server confirmation | Upsert replaces the bubble (server id, server time) | Same |
| Polling | `DoctorSession.refresh` (dashboard 12s timer, notifications) → `reconcile` | Dialog poll every 4s → `reconcile` |
| Real-time | Socket.IO `message_created` → `upsert` | Same |
| Dedup key | Server id **or** `client_message_id` | Same |
| Timestamp source | Server `sent_at` (UTC) | Same |
| Timestamp parsing | `ChatTime.parseServer` | Same |
| Display timezone | Viewer's local zone | Viewer's local zone |
| Tests | Backend 43/43 (shared); Flutter: doctor widget + session tests pass | Backend 43/43 (shared); Flutter: farmer dialog widget tests pass |
| Manual verification | Pending, see the checklist below | Pending, see the checklist below |

No other role has person-to-person chat (`/api/consultations/chats/` is limited to farmer and doctor).

## Tests and results

**Backend:** `backend/scripts/test_chat_message_state.py` passes 43/43. It uses throwaway `chatstate+` accounts and cleans up after itself. It covers:

* **Idempotency:** one send creates one row; a replay returns 200 with the same id and the original timestamp, and no new row or notification; different ids create different rows; a send without an id still works; an id reused in another conversation gets 409; a malformed id gets 400.
* **Concurrency:** **5 concurrent identical submits produce exactly 1 row**, with exactly one 201 and four 200s.
* **Both roles' lists:** each message appears exactly once; every `sent_at` has an offset; the lists are time-ordered; sender, recipient and send response carry the identical timestamp; repeat fetches and mark-read leave timestamps unchanged; legacy naive rows come back labelled `+00:00`.
* **Socket.IO path:** creates the message, does not re-broadcast a replay, and refuses non-participants.

The **negative control** (old send/list code restored, column kept) fails 15 checks before crashing.

Existing backend suites:

| Suite | Result |
|---|---|
| chat_access | 13/13 |
| doctor_flow | 58/58 |
| transitions_and_receipts | 53/53 |
| booking_rules | 29/29 |
| doctor_consultation_queue | 43/43 |
| find_vet_discovery | 38/38 |
| notifications | 135/135 |
| admin_panel | 62/63 (known pre-existing "admin login 200" email-verification gate) |

`manage.py check`: clean. `migrate --check`: exit 0. `manage.py test doctor messaging consultations notifications`: 22 tests, 1 error, `test_discovery_row_exposes_farmer_facing_fields`, which is **pre-existing**: it fails identically with this change removed (`SimpleNamespace` has no `phone`).

**Flutter:** `test/chat_message_state_test.dart` passes 24/24. It covers:

* **Time parsing and display:** UTC and naive parsing, the exact screenshot message, all display formats, and the future-time clamp.
* **Client ids:** UUID v4 uniqueness.
* **Timeline logic:** echo-before-response, both mid-flight and final; response-then-echo-then-poll; provisional time replaced by server time; an older server without ids; overlapping pages; reconcile keeping unsent messages; refresh not changing the timestamp; stable ordering.
* **Doctor widgets:** one tap gives one API call and one bubble, with the echo racing the response; a double tap while in flight sends once; a failed send shows Retry, and the retry uses the same client id and produces one message; a later echo or refresh neither duplicates nor re-times the message.
* **Farmer widgets:** echo plus poll gives one bubble; server times are shown; a double tap sends once; failed → Retry with the same id; a real-time message delivered twice plus a poll shows once.

The **negative control** (match on server id only) fails the two race tests.

Full `flutter test`: 312 passed, 2 failed. Both failures are the known pre-existing navbar-photo tests in `doctor_dashboard_fixes_test.dart`. `flutter analyze lib test`: only the 6 known infos in `farmer_feed_marketplace_screen.dart`. `flutter build web --release`: built.

**Live data (read-only):** conversation `8f906e79-…` returns `hello` exactly once to each role, with `sent_at: 2026-10-30T10:48:20.203851+00:00`, which displays as 4:48 PM in Dhaka.

## Manual verification checklist (to be run by hand)

Run `.\run_backend.bat` (uvicorn, so Socket.IO is live) and `flutter run -d chrome`. Use two browser profiles: doctor `dr.samira.rahman@example.com`, farmer `farmer.rashed@example.com`.

1. Open the same conversation on both sides. Send one message once: one bubble on each side, and a time matching your clock.
2. Refresh or reopen both sides: still one bubble, same time.
3. Stop the backend, send: the bubble shows "Not sent · Tap to retry". Restart the backend and tap Retry: one bubble, and one row in the DB.
4. Double-tap Send quickly: one message.
5. Send across a minute boundary: correct order and times; nothing in the future.

## Limitations

* **Pagination:** the chat endpoints return whole conversations (no server-side paging). `mergePage` is ready for pages but is not yet exercised by a paged API.
* **Ops:** the new DDL must be applied on every non-dev database before deploying this backend. Without the column, inserts fail.
* **Older clients:** builds that don't send `client_message_id` still work but get no idempotency.
* **Data:** no mock chat data was added; tests use throwaway accounts or a fake HTTP server. Existing messages were not modified.
