# F-003 — Rider route / ETA: fix report

**Status: fixed in the working tree. Nothing was committed** (HEAD is still `6a036eb`). No secrets appear in this report or in `audit_logs/f003/`.

## 1. Inspection (before the fix)

| Question | Finding |
|---|---|
| Provider | Google Maps Platform. |
| Endpoint | `delivery/views.py::route` called the **legacy Directions API** (`maps.googleapis.com/maps/api/directions/json`) with `urllib.urlopen(timeout=8)` on the request thread. |
| Enabled APIs | The project key has the **Routes API** enabled and the legacy Directions API **not** enabled. Checked against the live key: legacy → `REQUEST_DENIED … legacy API … not enabled for your project`; `routes.googleapis.com/directions/v2:computeRoutes` → 200 with polyline, distance and duration. |
| Key restrictions / billing | Key is read from `backend/.env` (`GOOGLE_MAPS_API_KEY`, 39 chars). It is accepted by Routes API from the server, i.e. billing is enabled and the key is not blocked for that API. The same key string is also hard-coded in `web/index.html` for the browser Maps JS loader (**F-019, still open**) — a browser-exposed key must never be the server routing key. |
| Backend error mapping | Any non-`OK` Google status (including `REQUEST_DENIED`) → **404 "No route found."**; network errors → 502; missing key → 503. A configuration problem was therefore reported as "not found". |
| Flutter handling | `delivery_map_screen.dart` swallowed every error (`catch (_) {}`): the rider saw no route, no reason, no retry. Distance/ETA fell back silently to a straight-line guess. |
| Legacy or Routes? | Legacy Directions — the root cause. |

## 2. Solution: Google Routes API behind a provider-agnostic module

* **`backend/delivery/routing.py`** (new): `get_route(...) -> {polyline, distance_km, duration_min, provider}` or `RoutingError(code, detail, status)`. Only `_fetch_google` knows Google's request/response shapes — another provider replaces that one function.
* Request: `POST https://routes.googleapis.com/directions/v2:computeRoutes`, `X-Goog-Api-Key` header (key never in a URL), `X-Goog-FieldMask: routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline`, `travelMode DRIVE`, 6 s timeout, lat/lng waypoints or `address` waypoints.
* **Key configuration:** new optional `GOOGLE_ROUTES_API_KEY` (falls back to `GOOGLE_MAPS_API_KEY`); documented in `.env.example`. It is used only on the server — Flutter never receives it (a test asserts the response body never contains the key). Recommended: a separate key restricted to the Routes API and the server's IPs.
* **Cache:** 5-minute cache on (origin, destination) so repeated map opens do not spend quota.
* **Origin fallback:** feed deliveries have a warehouse *text* but no pickup coordinates; the route is then computed from the rider's last reported position (if < 30 min old), else by address. The response says which (`origin_source`).

### Error mapping (no provider problem is a 404 any more)

| Situation | HTTP | `code` |
|---|---|---|
| Success | 200 | – (`provider`, `cached`, `origin_source` included) |
| Order has no coordinates and no address | 422 | `location_missing` |
| Provider found no drivable route / unroutable points | 422 | `no_route` |
| No server key configured | 503 | `routing_not_configured` |
| Key invalid / Routes API disabled / key restricted | 503 | `routing_configuration_error` |
| Quota / rate limit (429) | 503 | `routing_quota_exceeded` |
| Network failure, provider 5xx, unreadable answer | 502 | `routing_unreachable` |
| Timeout | 504 | `routing_timeout` |
| Not this rider's order / unknown id | 404 (genuine) | – |
| Farmer / anonymous | 403 / 401 | – |

## 3. Flutter

* `DeliveryApiException` now carries `statusCode` + `code`; `data/models/route_info.dart` maps codes to `RouteFailure` (`locationMissing, noRoute, configuration, quota, unreachable, timeout, unknown`) and `loadRouteInfo()`.
* New `RouteSummaryCard` (used by the map screen's bottom panel) renders every required state: **loading**, **route available** (distance + "ETA ~N min"), **route unavailable** / **no route** / **busy** / **timed out**, **API configuration error** (red, tells the rider to alert an admin), **location missing**, **Retry** (hidden when retrying cannot help), and the **manual fallback** — "Navigate by address" (opens Google Maps with the addresses), both addresses printed, and a clearly labelled straight-line estimate ("Est. ~N min", never shown as "ETA").
* The map shows whenever the drop has coordinates (pickup marker optional) and fits the camera to the route.
* **Bug found and fixed during the live test (pre-existing, latent):** `decodePolyline` used `~x`, which on the **web** (dart2js) yields an *unsigned* 32-bit value, so any route heading south/west decoded to garbage (the first live render drew world-spanning lines). Replaced with `-(x) - 1`, with a regression test and a comment.

## 4. Tests

### Backend — `backend/scripts/test_delivery_route.py` → **29 passed, 0 failed** (provider mocked; `ROUTE_LIVE=1` adds one real call, which also passed)
Successful route (polyline/distance/duration, Routes endpoint, POST + key/field-mask headers, key not in URL, lat/lng + `DRIVE` body, key never echoed, cache hit makes no provider call) · invalid key, Routes API disabled, restricted key → 503 `routing_configuration_error` · quota → 503 · provider 500 / network / garbage / malformed → 502 · timeout (both forms) → 504 · empty routes / unroutable → 422 · every provider failure asserted `!= 404` · no key → 503 and provider not called · `GOOGLE_ROUTES_API_KEY` precedence · missing coordinates → routed by address · no coordinates + no address → 422 `location_missing`, provider not called · fresh rider position used as origin, stale ignored · other rider 404 (genuine), farmer 403, anonymous 401, unknown id 404.

### Flutter — `test/delivery_route_test.dart` (16) + `test/delivery_polyline_test.dart` (1) → **17 passed**
Route display + route handed to map · ETA · loading state · unavailable error + labelled estimate + Retry → recovers · configuration error distinct · no route · addresses-only is routed, not "missing" · truly missing location (no provider call, no Retry) · fallback addresses + "Navigate by address" · every API `code` → state mapping (7) · polyline decode against a real Routes API sample.

### Full suites
| Command | Result |
|---|---|
| `manage.py check` / `migrate --check` | no issues / exit 0 |
| `manage.py test` | unchanged known F-014 |
| all 48 `backend/scripts/test_*.py` | **all pass, 0 failures** |
| `flutter analyze` | 6 pre-existing `prefer_const` infos, 0 errors/warnings |
| `flutter test` | **279 passed**, 0 failed |
| `flutter build web --release` | `√ Built build\web` |

## 5. Live browser verification (Chrome + Playwright, release build, backend on scratch DB `featherflow_clean`, real key, real feed-order assignment)
Order `#FD-87F21E` assigned by a Feed Admin through the real endpoint to a real rider; log: `audit_logs/f003/e2e_log.txt`.

| # | Scenario | Result | Screenshot |
|---|---|---|---|
| 1 | Rider sees the assignment and accepts it | pending → accepted | `01_rider_assigned.png` |
| 2 | **Route + ETA (live Google Routes, valid key)** | `GET …/route/` **200**; polyline drawn through Dhaka to the drop marker; **10.2 km · ETA ~27 min** (rider position → drop) | `02_route_and_eta.png`, `api_route_ok.json` |
| 3 | **API configuration error** (server restarted with an *invalid* routing key — the provider answered `API_KEY_INVALID`) | `GET …/route/` **503** (not 404); UI "Route service configuration error — tell an admin", **Retry**, **Navigate by address**, both addresses listed | `03_config_error_fallback.png` |
| 4 | **Retry** after the key is fixed (server restarted with the valid key) | tapping Retry → **200**, error cleared, ETA shown again, no page reload | `04_retry_recovered.png` |

Location-missing and the other failure modes are covered by the backend and widget tests (a real order without any location cannot be created through the product). The unrelated live-path observation: the feed order has **no pickup coordinates**, which is why the origin-from-rider-position fallback exists.

## 6. Notes
* `web/index.html` still embeds a Maps JavaScript key (F-019). It is a browser key by design but must be referrer-restricted; the server routing key should be a different one (`GOOGLE_ROUTES_API_KEY`).
* The dev server's `.env` key currently serves both purposes; split them in production.
* Servers stopped after testing; scratch DB `featherflow_clean` left in place.

## 7. Confirmation
Verified with backend contract tests, Flutter tests, the full existing suites, a release build and a real Chrome run against the live Google Routes API — not by code review alone. **Nothing was committed.**
