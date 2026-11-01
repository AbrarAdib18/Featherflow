# Maps / Google API key security report (F-019)

No key value appears in this report. "Key A" is the single Google API key that was committed to the repository.

**Status: repository side fixed; the key itself is still exposed until you restrict and rotate it in the Google Cloud Console, which I cannot do from here (no console access).** Treat the release as blocked on that action.

## 1. What was found

| Location | Before | Now |
|---|---|---|
| `web/index.html` | Key A hard-coded in the Maps JavaScript `<script src>` (tracked since commit `083b78d`, 2026-09-06) | no key; loads `config.js` and injects the Maps script only if a browser key is configured |
| `android/app/src/main/AndroidManifest.xml` | Key A as `com.google.android.geo.API_KEY` | `${MAPS_API_KEY}` manifest placeholder, filled from `android/local.properties` or the `MAPS_API_KEY` environment variable by `app/build.gradle.kts` (not built in this pass - no Android toolchain run) |
| Backend (`GOOGLE_MAPS_API_KEY`, falling back into the Routes API calls in `delivery/routing.py`) | The **same Key A** was used server-side for Routes API route/ETA | The Maps fallback is removed. Routing needs its own `GOOGLE_ROUTES_API_KEY`; without it the endpoint returns `503 routing_not_configured` (test added: a Maps key is never used server-side) |
| `backend/.env` (ignored) | Key A | unchanged on this machine, plus a temporary copy as `GOOGLE_ROUTES_API_KEY` so local routing keeps working until rotation |

**Exposure.** `main` equals `origin/main` and `origin` is a GitHub repository, so Key A is in the published history; deleting it from the working tree does not remove it from history.

**Restriction test (read-only, one request each):** a Routes API call with Key A succeeded **with no Referer header and with a foreign Referer (`https://evil.example/`)** - so Key A has **no HTTP-referrer restriction**, and the Routes API is enabled on it. Anyone holding the key can make billable Routes calls. Because the same key was also used by the server (no referrer, fixed IP) it could never have been referrer-restricted for the browser at the same time: one key was doing three incompatible jobs.

## 2. Decision

* **Rotate: YES.** The key has been public in a repository history and is unrestricted. Restricting it alone is not enough; create new keys and delete (or at least disable) Key A after cut-over.
* A browser key is public by design (it is delivered to every visitor), so its protection is the restriction, not secrecy. The server key must remain secret and never reach Flutter/web assets.

## 3. Required Google Cloud Console actions (owner action, not done)

Create **three** keys in the Cloud project:

| Key | Used by | Application restriction | API restriction |
|---|---|---|---|
| Browser key | `web/config.js` (`mapsBrowserKey`) | HTTP referrers: the production origins (e.g. `https://<your-domain>/*`) and, for development only, `http://localhost:*/*` / `http://127.0.0.1:*/*` | Maps JavaScript API only (add only what the app calls - the flutter `google_maps_flutter` web plugin needs the Maps JavaScript API) |
| Android key | `MAPS_API_KEY` in `android/local.properties` / CI secret | Android apps: package `com.example.featherflow_app` (change to the real application id before release) + the release signing SHA-1 | Maps SDK for Android only |
| Server key | `GOOGLE_ROUTES_API_KEY` in the server environment / secret store | IP addresses: the API servers' egress IPs | Routes API only |

Then: set budget alerts and per-API quotas; review the Cloud billing report and API metrics for unexpected Routes/Maps traffic since 2026-09-06; **delete Key A once the new keys are live**; update `backend/.env`, the deployment secret store and `web/config.js` in the build pipeline.

## 4. Repository changes made (uncommitted)

* `web/index.html` (key removed, config loader), `web/config.example.js` (template, tracked), `web/config.js` (**git-ignored**, holds the local key), `.gitignore` (`web/config.js`, `audit_logs/`).
* `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`.
* `backend/delivery/routing.py`, `featherflow_backend/settings.py`, `.env.example`, `scripts/test_delivery_route.py` (29 assertions, 0 failed).

## 5. Verification

* **Local development (verified):** the rebuilt release web bundle loads the Maps script from `config.js`; in the full-matrix run the rider map rendered tiles, pickup/drop markers and the route polyline with distance and ETA (`audit_logs/matrix/shots/Stale-A-selected.png`, `RiderMap-*.png`), and every route call went through the dedicated `GOOGLE_ROUTES_API_KEY` (the Maps fallback is removed; before it was configured the endpoint correctly returned `503 routing_not_configured`, which the matrix also exercised).
* **Missing config degrades safely:** without `config.js` the page logs `Maps disabled: web/config.js has no mapsBrowserKey` and the app still loads (Maps widgets show no map; route/ETA text still comes from the backend).
* **No server secret in Flutter/web assets:** after the rebuild, `build/web` contains an API key only in `config.js` (the per-environment browser config); `lib/`, `web/` (except the ignored `config.js`), `pubspec.yaml`, `android/app/src` and `ios/Runner` contain none, and a scan for private-key blocks, `SECRET_KEY`, `client_secret` and live-key patterns found nothing.
* **Production behaviour: NOT verifiable here.** It depends on the new keys and the console restrictions above. After rotation, verify: (a) the site loads maps from an allowed origin; (b) the same browser key fails from a non-listed origin; (c) the server key fails from a non-listed IP; (d) the old key returns `REQUEST_DENIED`.
* **Residual:** Key A remains in git history. If the repository is public, rotation is the only effective remedy; rewriting history would not un-publish it.
