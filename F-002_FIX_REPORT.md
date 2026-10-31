# F-002 Fix Report — suspended pharmacy ejected to the login screen

Date: 2026-10-01. **Nothing was committed** (HEAD `6a036eb`; `git stash list` empty). Fix is in the working tree only. Evidence: `audit_logs/f002/` (logs, 24 screenshots, browser log); tooling `audit_logs/tools/{f002*.js,mkphstatus.py,lockedresp.py}`; captured API shapes `audit_logs/data/f002_suspended_pharmacy_responses.json`.

## 1. Trace (login → locked shell) and where it broke

| Step | Value / component | Before | After |
|---|---|---|---|
| Login request | `POST /api/auth/login/` | — | — |
| Login response | `users/views.py` `resume_response` → `_gets_session_while_non_active` (role `pharmacy`) | **already** returned **200 + `access`/`refresh`**, `next:"pending_approval"`, `account_status` | unchanged |
| Account role / status | `roles.name = "pharmacy"`; `users.account_status ∈ {active, pending, suspended}` (DB CHECK) + `pharmacy_organizations.review_state ∈ {pending_review, needs_more_information, rejected, approved, …}` | — | unchanged |
| Token / session | `PharmacyAlwaysOnAuthentication` accepts the non-active pharmacy token on always-on endpoints | worked | unchanged |
| **Poll** | `GET /api/me/updates/` (`api/admin_extra.py`) | returned `access_revoked: true` for **any** suspended user | `access_revoked: false` for a pharmacy (still `true` for every other role) |
| **Flutter auth state** | `UserUpdatesService.poll()` (`lib/core/network/user_updates_service.dart`) | `data['access_revoked'] == true \|\| _accountStatus == 'suspended'` → `_setAccessRevoked(true)` → router `_redirect` → `clearSession()` → `/login?revoked=1` | the **client-side** `suspended` rule exempts role `pharmacy`; the server flag is authoritative |
| Post-login route | `AuthService.getRoleDestination('pharmacy')` → **`/pharmacy`** | (never reached — ejected) | `/pharmacy` |
| Shell widget | `PharmacyDashboardScreen` (`lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart`) | — | same widget, now with locked operational tabs |

**Root cause:** two generic "suspended ⇒ revoke access" rules (server flag `access_revoked`, client `_accountStatus == 'suspended'`) ignored the deliberate pharmacy exception that the rest of the stack (login, auth class, permission snapshot) implements. After "Login Successful!" the first `/api/me/updates/` poll revoked the session and the router bounced to `/login` (the login page, already mounted, never showed the "access changed" snackbar). Pending and rejected pharmacies were **not** affected (their `account_status` is `pending`, not `suspended`).

## 2. Role / status values (exact)

Stored values and what the API/UI do now (verified by the backend script and the browser; `rejected` is stored as `account_status='pending'` + `review_state='rejected'` — a raw `account_status='rejected'` violates the DB CHECK constraint `users_account_status_check`):

| Case | `users.account_status` | `review_state` | Login API | `next` | `/api/me/updates` `access_revoked` | `GET /api/pharmacy/permissions/` `status` | `can{catalogue,orders,suppliers,analytics,employees}` | `can{chat,profile}` | `can.appeal` | Route → shell |
|---|---|---|---|---|---|---|---|---|---|---|
| Pending | `pending` | `pending_review` | 200 + tokens | `pending_approval` | false | `PENDING_REVIEW` | all false | true | false | `/pharmacy` → locked `PharmacyDashboardScreen` ("Verification pending") |
| Rejected | `pending` | `rejected` | 200 + tokens | `pending_approval` | false | `REJECTED` | all false | true | false | `/pharmacy` → locked ("Application rejected") |
| **Suspended** | `suspended` | `approved` | 200 + tokens | `pending_approval` | **false (was true)** | `SUSPENDED` → `APPEAL_PENDING` after an appeal | all false | true | **true** | `/pharmacy` → locked ("Account suspended" / "Appeal under review") |
| Active | `active` | `approved` | 200 + tokens | `dashboard` | false | `ACTIVE` | all true | true | false | `/pharmacy` → full panel |
| Restored (suspended → reinstate) | `active` | `approved` | 200 + tokens | `dashboard` | false | `ACTIVE` | all true | true | false | same session unlocks on the next permissions poll (no reload) |
| Other roles (farmer, doctor, delivery, researcher, admins) pending/suspended | `pending`/`suspended` | n/a | **403, no tokens** | `pending_approval` | token rejected (401) / still `true` for suspended | — | — | — | — | stay on `/login` (unchanged) |

## 3. Files changed

| File | Change |
|---|---|
| `backend/api/admin_extra.py` (`me_updates`) | `access_revoked` = suspended **and not** a pharmacy owner. |
| `lib/core/network/user_updates_service.dart` | the local `_accountStatus == 'suspended'` revoke rule exempts role `pharmacy`; explicit server `access_revoked: true` still revokes anyone. |
| `lib/features/pharmacy/presentation/widgets/pharmacy_lock_gate.dart` (**new**) | `PharmacyLockGate`: while permissions are not ACTIVE it replaces an operational section by a locked panel (status, reason, "Contact Pharmacy Admin", "Submit/View appeal", refresh); while the first permissions call is in flight it shows a spinner instead of building the screen (no 401 data calls / empty-list flash). |
| `lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart` | Catalogue, Inventory, Orders, Suppliers, Analytics tabs wrapped in `PharmacyLockGate`. Home (banner + earnings) and Profile tabs untouched. |
| `lib/core/router/app_router.dart` | the five standalone `/pharmacy/<section>` routes wrapped in the same gate. |
| `backend/scripts/test_pharmacy_locked_session.py` (**new**), `test/pharmacy_locked_panel_test.dart` (**new**) | regression tests (§4). |

Backend permission enforcement needed no change — it was already correct (always-on endpoints use `PharmacyAlwaysOnAuthentication` + `IsPharmacyAccount`; operational endpoints use the default auth + `IsPharmacyUser` and return **401/403** to a non-active pharmacy). The test suite now pins that behaviour.

## 4. Tests

### 4.1 Backend — `backend/scripts/test_pharmacy_locked_session.py` → **104 passed, 0 failed** (live DB, `lockedsess+` accounts, real `POST /api/auth/login/`)
* **Session creation** while pending, rejected, suspended: login 200 with `access`+`refresh`, `next=pending_approval`, correct `account_status`, role `["pharmacy"]`; active → `next=dashboard`.
* `/api/me/updates/` for pending/rejected/suspended pharmacy → 200, **`access_revoked == false`**.
* **Allowed** (2xx) while locked: `profile`, `permissions`, `earnings` (real zeros), `verification-status`, `appeals` (GET), `support-conversation` (create + send message).
* **Denied** (401/403) while locked: `medicines` (GET/POST), `orders`, `suppliers`, `inventory/summary`, `inventory/low-stock`, `analytics/sales|revenue`; permission flags: operational false, chat/profile true.
* **Appeal** while suspended: `POST /appeals/` 201 → status `APPEAL_PENDING`, still locked. **Restored** (`transition_pharmacy_status('reinstate')`): login `next=dashboard`, `ACTIVE`, operational endpoints 200, `access_revoked false`.
* **Other roles unchanged**: farmer, doctor, delivery, researcher, admin_content × {pending, suspended}: login **403, no tokens, `next=pending_approval`**; a token minted for the inactive account → **401** on `/api/me/updates/`; active → 200 with session; a farmer is still 403 on pharmacy endpoints; wrong password 401.
* **Mutation check**: with the old `access_revoked` line restored the suite fails (`suspended: /api/me/updates/ … access_revoked == false`); with the fix 104/0.

### 4.2 Flutter — `test/pharmacy_locked_panel_test.dart` → **15 passed** (real widgets/services, mock HTTP client returning the captured backend JSON)
* **Routing:** `getRoleDestination` — pharmacy → `/pharmacy`; farmer/doctor/delivery/researcher/feed_owner/admin unchanged.
* **Poll rule** (5): suspended pharmacy and pending pharmacy **not** revoked; suspended farmer still revoked; suspended doctor revoked even without the flag (client rule unchanged); pharmacy revoked when the server explicitly says so. *(Fails on the old `user_updates_service.dart`.)*
* **Locked shell:** suspended — locked Home shows "Account suspended", the reason, "Contact Pharmacy Admin", "Submit appeal", **earnings card**, sign-out, no login/farmer screen; pending ("Verification pending", no appeal) and rejected ("Application rejected", no appeal — backend grants appeals to suspended accounts only); **Catalogue/Inventory/Orders/Suppliers/Analytics** show "<Section> is locked", no "Add", no empty-state text, and **zero** operational API calls; **Profile** tab loads `/api/pharmacy/profile/`; **chat** opens and the conversation is created; **appeal** screen opens and a submitted appeal reaches the backend; **logout** clears the session → login; **refresh/relogin** — rebuilt shell shows the same state, and a restored account (`ACTIVE`) unlocks without reload.

### 4.3 Requested suite runs
| Command | Result |
|---|---|
| `python manage.py check` / `migrate --check` | no issues / exit 0 |
| `python manage.py test` | still cannot run (F-014: `relation "users" does not exist`; unchanged) |
| all backend scripts (46 incl. the 2 new ones from earlier fixes + this one) | **46/46 exit 0, 1,743 assertions, 0 failed** |
| `flutter analyze` | 6 `info` (same pre-existing `prefer_const` hints; 0 new) |
| `flutter test` | **250 passed**, 0 failed (235 + 15) |
| `flutter build web --release` | `√ Built build\web` |

## 5. Live browser test (Chrome 154 + Playwright, release build of the fixed tree, :8080; backend :8000 on the scratch DB `featherflow_clean` with dedicated accounts so the appeal does not pollute the dev DB; plus a read-only check on the real suspended dev account)
Log: `audit_logs/f002/browser_log.txt`.

**Suspended pharmacy `ph.suspended@example.com` (role `pharmacy`, `account_status=suspended`, `review_state=approved`):**

| # | Step | Result | Screenshot |
|---|---|---|---|
| 1 | Log in | route **`/pharmacy`** (not `/login`, not `/farmer`); API `200`, tokens, `next=pending_approval`; `/api/me/updates/` 200 | `suspended_01_locked_home.png` |
| 2 | Locked panel | red banner "**Account suspended** — Your pharmacy account is suspended." with **Contact Pharmacy Admin** and **Submit appeal** | same |
| 3 | Profile | Profile tab opens, `GET /api/pharmacy/profile/` 200, "Edit profile" | `suspended_02_profile.png` |
| 4 | Earnings | Home shows "Lifetime earnings ৳ 0.00 · 0 orders" (`/api/pharmacy/earnings/` 200) | `suspended_01…` |
| 5 | Pharmacy Admin chat | "Contact Pharmacy Admin" screen; message sent; **stored server-side**: `["Please review my suspension - licence renewed."]` | `suspended_08_chat.png`, `suspended_09_chat_sent.png` |
| 6 | Appeal | "Suspension Appeal" form, submitted; **stored** (`status: submitted`), `permissions.status` → **`APPEAL_PENDING`**; banner becomes "**Appeal under review** — … your appeal is under review" with **View appeal** | `suspended_10_appeal_form.png`, `suspended_10b_appeal_filled.png`, `suspended_12_after_appeal.png` |
| 7 | Medicines / Inventory / Orders / Suppliers / Analytics | each shows "**<Section> is locked**" + the same status/actions; no Add button; no empty-state text | `suspended_03…07_*_locked.png` |
| 8 | Refresh, sign out, relogin | after reload still `/pharmacy`; Sign out → `/login`; relogin → `/pharmacy` with **"Appeal under review"** — same state persisted | `suspended_13_after_refresh.png`, `suspended_14_signed_out.png`, `suspended_15_relogin.png` |
| — | 5xx during the journey | 0 | |

(Harness note: the typed appeal text lost its first character — a Playwright focus timing artefact; the explanation stored is "ur licence was renewed on time; please lift the suspension.")

Other statuses: **pending** (`ph.pending`: `account_status=pending`, `review_state=pending_review`) → `/pharmacy`, banner "Verification pending", chat only, Orders locked; **rejected** (`ph.rejected`: `account_status=pending`, `review_state=rejected`) → `/pharmacy`, banner "Application rejected… contact Pharmacy Admin", chat only, Orders locked (`pending_locked_home.png`, `rejected_locked_home.png`); **active** (`ph.active`) → full panel, Catalogue open ("No medicines yet", not locked) (`active_catalogue.png`); **restored** (`ph.restore`): suspended panel → Pharmacy Admin reinstates (`PATCH /api/admin-panel/pharmacies/<id>/ {status:"Verified"}` 200) → **without reload** the banner disappears, stat cards appear and Catalogue unlocks (`restore_before.png`, `restore_after.png`); **other roles unchanged**: suspended farmer and suspended doctor → login API 403 without tokens, browser stays on `/login` (`susp_farmer_login.png`).

**Real dev account (read-only):** `smoke.pharmacy@featherflow.dev` (suspended, the original F-002 reproduction) → now lands on `/pharmacy` with "Contact Pharmacy Admin / Submit appeal / Lifetime earnings ৳ 0.00" and stays there after refresh (`live_smoke_pharmacy_locked.png`). No appeal was submitted on the dev DB.

## 6. Notes
* The locked-state UI/permissions for pending/rejected already existed (banner, permission snapshot); this fix removes the suspension-only ejection and adds the missing lock on the operational tabs (previously they showed empty lists with working "Add" buttons for a locked account).
* A non-active pharmacy calling an operational endpoint gets **401** (default authentication rejects the inactive token) rather than 403 — still denied, and the client no longer calls those endpoints while locked.
* Scratch database `featherflow_clean` is left in place (disposable); servers stopped.

## 7. Confirmation
Verified with backend and Flutter regression tests, the full existing suites, a release build, and a running Chrome against the real backend — not by code review alone. **Nothing was committed.**
