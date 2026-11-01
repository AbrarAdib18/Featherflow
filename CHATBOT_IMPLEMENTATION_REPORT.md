# Poultry & Featherflow Assistant: Implementation Report

Nothing was committed. All changes are in the working tree.

## Files changed

**Backend (new)**
- `backend/chatbot/knowledge.py`: system prompt (scope rules, vet-safety rules, disease format, Featherflow platform knowledge) and the fixed refusal text.
- `backend/chatbot/providers.py`: the only module that talks to Gemini (stdlib `urllib`, no new dependency). Reads `GEMINI_API_KEY` from the environment at call time and sends it in the `x-goog-api-key` header, never in the URL.
- `backend/chatbot/service.py`: payload validation, PII/secret scrubbing, history trimming, strict parsing of the model's JSON reply.
- `backend/chatbot/views.py`, `backend/chatbot/urls.py`: the endpoint, throttles, audit log.
- `backend/chatbot/tests.py`: 14 backend tests.

**Backend (edited)**
- `backend/api/urls.py`: `path('chatbot/', include('chatbot.urls'))`.
- `backend/featherflow_backend/settings.py`: throttle rates `chatbot_burst` (8/min) and `chatbot` (60/hour), both env-overridable; `chatbot` added to the configured loggers.
- `backend/.env.example`: `GEMINI_API_KEY=` (empty), optional `GEMINI_MODEL`, throttle settings.

**Flutter (new)**
- `lib/features/chatbot/data/chatbot_service.dart`: HTTP client for the backend endpoint, error mapping.
- `lib/features/chatbot/presentation/chatbot_overlay.dart`: draggable bubble and chat panel.
- `test/chatbot_overlay_test.dart`: 17 tests.

**Flutter (edited)**
- `lib/main.dart`: `MaterialApp.router`'s `builder` wraps every route in `ChatbotOverlay`.

No database migrations. The audit log goes through the Python logger, and the existing `chatbot` app only has proxy models.

## API

`POST /api/chatbot/chat/`. Requires `Authorization: Bearer <user JWT>`.

Request:
```json
{ "message": "string, 1-1000 chars",
  "history": [ { "role": "user|assistant", "text": "string" } ] }
```
`history` is optional. Only the last 6 turns are used. The server stores no conversation.

Success (200):
```json
{ "reply": "string", "in_scope": true, "error": null }
```
Refusal (200): `in_scope: false` and `reply` is a fixed server-side message, never model text.

Error:
```json
{ "reply": "", "in_scope": false,
  "error": { "code": "not_configured", "message": "…" } }
```

| Situation | Status | `error.code` |
|---|---|---|
| Invalid body | 400 | `invalid_request` |
| Not authenticated | 401/403 | (standard auth error) |
| Throttled | 429 | (standard throttle error) |
| `GEMINI_API_KEY` missing | 503 | `not_configured` |
| Provider busy (429) / 5xx / network | 503 | `provider_rate_limited` / `provider_unavailable` |
| Provider rejected request (400/401/403) | 502 | `provider_rejected` |
| Timeout (default 20 s) | 504 | `timeout` |
| Unparseable model output | 502 | `invalid_response` |
| Any other exception | 502 | `internal_error` |

## Scope rules

- The system prompt limits the assistant to poultry farming, poultry diseases and Featherflow usage. It refuses finance, legal, human-medical and unrelated requests, and ignores attempts to change its rules.
- The model must answer with `{"in_scope": bool, "reply": str}`. If `in_scope` is false, the user sees the fixed refusal text, so a prompt-injected "reply" cannot leak out.
- Disease answers follow the required section order: possible causes, symptoms, immediate precautions, what to do, what not to do, when to contact a vet, disclaimer. The prompt forbids claiming a diagnosis and drug doses.
- Platform questions (all roles, account statuses, support, appeals) are answered in numbered steps with the screen and role named. The model is told to say so, not invent, when unsure.
- Before leaving the server, emails, phone-like numbers and key-like tokens in user text are replaced with placeholders.

## Error handling

Missing key, timeouts, provider errors, rate limits and bad output all return a controlled JSON error; none crash the server. Provider response bodies and URLs are never included in errors or logs. In Flutter, each error shows a readable message. Retryable errors get a **Retry** button, which resends the failed message without duplicating it. Offline shows a distinct message. `not_configured` shows the configuration message with no Retry.

The audit log (`chatbot.audit`) records only user id, outcome, message character count and duration. It never records message or reply text.

## Tests

- **Backend, `manage.py test chatbot`: 14/14.** Covers authentication required, valid poultry question, off-topic refusal (including a model that tries to smuggle text), missing key, invalid bodies, history trimming and PII scrubbing, provider failures mapped to statuses, malformed model output, masked unexpected exceptions, rate limit (8 allowed, 9th gets 429), and no key in responses or logs. It also checks that a key pasted by a user is not forwarded, and that HTTP errors from the provider don't leak the key. All tests use a fake provider. The real Gemini API is never called.
- **Flutter, 17 tests:**
  - Bubble hidden when signed out and shown after sign-in.
  - Bubble on multiple pages, right-side default, no blocking of buttons or scrolling.
  - Drag, clamping to the viewport, persistence and restore.
  - Tap does not move the bubble; open/close via button, outside tap and Esc.
  - Send/receive with history, loading state with duplicate-request blocking.
  - Error with Retry, offline, not-configured (no Retry), off-topic refusal, empty input.
  - 360×640 phone layout, accessibility label.
  - HTTP layer: bearer token, no network when signed out, 429/503/HTML/offline mapping.

## Verification results

| Command | Result |
|---|---|
| `python manage.py check` | no issues |
| `python manage.py migrate --check` | exit 0 (no pending migrations) |
| `python manage.py test` | 54/54 passed |
| `flutter analyze` | no issues |
| `flutter test` | 333/333 passed |
| `flutter build web --release` | built successfully |

## Browser verification steps (manual)

I did not run a live browser or live Gemini session. Do this once yourself:

1. Make sure `GEMINI_API_KEY` is set in `backend/.env`, then start the backend and the web build.
2. Sign in. The green bubble appears at the right edge on the dashboard and on other pages. It does not appear on the login screen.
3. Drag it to another spot and refresh. It should stay there. Try dragging past the window edge. It should stop at the edge.
4. Click it to open the panel. Close it with the X, an outside click and Esc.
5. Ask "How warm should broiler chicks be?" and expect a poultry answer.
6. Ask "Who won the football match?" and expect the refusal text.
7. Ask a disease question such as "My chickens have green diarrhoea" and expect the sectioned format and disclaimer.
8. Ask "How do I order feed?" and expect numbered steps naming the Farmer role and Marketplace screen.
9. Stop the backend and send a message. Expect the offline message with Retry.
10. Blank `GEMINI_API_KEY`, restart the backend, and send a message. Expect the configuration error, with no crash.
11. Resize to about 360 px wide. The panel should dock at the bottom, leaving the top of the page usable.
12. In DevTools → Network, open the `/api/chatbot/chat/` request. Confirm it carries only your own JWT and the message, and no Gemini key.

## Confirmation: no key committed, logged or exposed

- Nothing was committed.
- The key is read only from the `GEMINI_API_KEY` environment variable. `.env.example` contains an empty `GEMINI_API_KEY=`.
- A search of the repo (excluding `venv`, `node_modules`, `.git`) finds the key only in `backend/.env`, which is git-ignored (`git check-ignore` confirms). `web/config.js` is also still git-ignored. The compiled `build/web` bundle contains neither the key nor any Gemini URL.
- Responses, errors and logs are tested to never contain the key, and the audit log has no message content.

## Notes

- **Rotate the key.** The key was pasted into this chat, so treat it as exposed and create a new one. Replace the value in `backend/.env` (it is the only place it lives).
- **Other uncommitted changes.** The working tree already had many uncommitted edits before this work (see `git status`). Only the files listed above belong to the chatbot. Review before committing so unrelated changes aren't bundled in.
- **Language.** The chat UI strings are English only and are not yet wired into the app's `l10n` system. The assistant itself replies in the user's language (English or Bangla).
- **Production.** With more than one server process, set `REDIS_URL`. Otherwise the per-process throttle counters aren't shared (this applies to all of Featherflow's throttles).
