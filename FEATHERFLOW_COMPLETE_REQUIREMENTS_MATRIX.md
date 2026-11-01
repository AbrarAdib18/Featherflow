# Featherflow — Complete Requirements Traceability Matrix

Generated from a direct, evidence-based audit of the live codebase (backend `D:\Featherflow Final\backend`, Flutter `D:\Featherflow Final\lib`) — no requirement is marked Complete unless the underlying backend model/endpoint AND a real Flutter screen consuming it were both confirmed to exist and be wired together. Where a screen exists but is fed fake/hardcoded/stub data, or an endpoint exists with no UI, that is marked **In progress** or **Blocked**, never Complete.

Status legend: **Complete** = backend + API + Flutter UI all real and wired · **In progress** = partially built (one layer real, another stub/missing/fake) · **Blocked** = not implemented, reason given.

Nothing in this document has been committed to git. This matrix is itself uncommitted, per standing instruction.

---

## 0. Demo Accounts (13 roles)

| ID | Requirement | Role | Screen | Backend | API | Flutter UI | Automated test | Manual test | Status |
|---|---|---|---|---|---|---|---|---|---|
| ACC-01 | Super Admin demo login | Super Admin | Login | `seed_platform_demo.py` admins list | `/api/auth/login/` | Login screen | `test_signup_flows.py` | Logged in via curl + browser | Complete |
| ACC-02 | Operations Admin demo login | Operations Admin | Login | `seed_platform_demo.py` | same | Login screen | — | Verified prior phase | Complete |
| ACC-03 | Finance Admin demo login | Finance Admin | Login | `seed_platform_demo.py` | same | Login screen | — | Verified prior phase | Complete |
| ACC-04 | Content Admin demo login | Content Admin | Login | `_create_missing_admin_accounts.py` (`content.admin@example.com`) | same | Login screen | idempotency self-check in script (2x rerun, row counts=1) | curl-verified: allowed on `articles`/`community`, denied on `finance`/`delivery` | Complete |
| ACC-05 | Research Admin demo login | Research Admin | Login | `_create_missing_admin_accounts.py` (`research.admin@example.com`) | same | Login screen | same script | curl-verified scoping | Complete |
| ACC-06 | Delivery Admin demo login | Delivery Admin | Login | `_create_missing_admin_accounts.py` (`delivery.admin@example.com`) | same | Login screen | same script | curl-verified scoping | Complete |
| ACC-07 | Pharmacy Admin demo login | Pharmacy Admin | Login | dedicated account `pharmacy.admin@featherflow.local` | same | Login screen | `test_pharmacy_admin.py` | Playwright E2E login+nav (prior phase) | Complete |
| ACC-08 | Support Agent demo login | Support Agent | Login | `seed_platform_demo.py` | same | Login screen | — | Not re-verified this phase | In progress (reason: not re-confirmed in current audit pass, but no code regression found; verify session survives refresh) |
| ACC-09 | Farmer demo login | Farmer | Login | `seed_platform_demo.py` / `seed_farmer_demo_data` | same | Login screen | `test_farmer_panel.py` | Verified prior phase | Complete |
| ACC-10 | Pharmacy owner/staff demo login | Pharmacy | Login | `seed_platform_demo.py` + pharmacy signup flow | same | Login screen | `test_pharmacy_flow.py` | Playwright-verified prior phase | Complete |
| ACC-11 | Delivery person demo login | Delivery | Login | `seed_platform_demo.py` | same | Login screen | — | Not re-verified this phase | In progress (reason: account exists per seed script but no fresh live-login re-check this pass) |
| ACC-12 | Researcher demo login | Researcher | Login | `seed_platform_demo.py` | same | Login screen | — | Not re-verified this phase | In progress (reason: same as above) |
| ACC-13 | Doctor demo login | Doctor | Login | `seed_platform_demo.py` | same | Login screen | `test_doctor_flow.py` | Verified prior phase | Complete |
| ACC-14 | `seed_platform_demo` runs end-to-end on a clean DB (single command, no manual scripts) | All | — | `seed_platform_demo.py` | mgmt command | n/a | — | **Known blocker**: cannot run end-to-end due to a pre-existing Farm-duplication crash unrelated to this work; workaround scripts (`_create_missing_admin_accounts.py`, `_create_pharmacy_admin.py`) used instead | Blocked (reason: pre-existing `seed_platform_demo` bug duplicates Farm rows on rerun, unrelated to admin-account work; documented in `PHARMACY_ADMIN_DEMO_CREDENTIALS.md`; needs its own fix pass) |
| ACC-15 | Denied access to unauthorized modules for every role | All | All admin screens | `can_perform_action` RBAC gate | all admin-panel endpoints | `PermissionGuard`/`AdminSession.canAccess` widgets | — | curl-verified for Content/Research/Delivery Admin this pass; Pharmacy Admin verified prior pass across 11 actor types | Complete |
| ACC-16 | Session survives refresh/relogin | All | All | JWT + refresh token | `/api/auth/refresh/` | app-wide auth interceptor | — | Verified for Pharmacy Admin prior pass; not re-verified for the other 12 roles this pass | In progress (reason: mechanism is shared/global so very likely fine for all roles, but not individually re-tested this pass for each of the 13) |

---

## 1. Platform-wide Admin Dashboard

| ID | Requirement | Role | Screen | Backend | API | Flutter UI | Status |
|---|---|---|---|---|---|---|---|
| DASH-01 | Active users count | All admins | `admin_dashboard_screen.dart` | `admin_dashboard()` admin_views.py:796 | `/admin-panel/dashboard/` | Overview grid card | In progress (reason: field is actually `total_users`, not filtered to active — mislabeled) |
| DASH-02 | Pending approvals (aggregate) | All admins | same | admin_views.py:798 | same | Overview grid | Complete |
| DASH-03 | Open support tickets | All admins | same | admin_views.py:784,799 | same | Overview grid | Complete |
| DASH-04 | Recent consultations list | All admins | same | only `urgent_consultations` count exists (admin_views.py:808) | same | — | Blocked (reason: no "recent consultations" list endpoint exists, only an urgent-count) |
| DASH-05 | Deliveries in progress | All admins | same | admin_views.py:803 | same | Overview grid | Complete |
| DASH-06 | Flagged community/content items | All admins | same | admin_views.py:801-802 | same | Overview grid | Complete |
| DASH-07 | Pending pharmacy/doctor/researcher approvals | All admins | same | admin_views.py:781-782,787,807,810 | same | Overview grid (pharmacy/doctors only; researchers missing a card) | In progress (reason: researcher approval count not surfaced as its own dashboard card) |
| DASH-08 | Pending delivery-person approvals | All admins | same | only exists as `unassigned_riders` in `admin_oversight` (admin_extra.py:554), not in main dashboard | — | — | Blocked (reason: no dashboard stat; only reachable via separate Oversight screen) |
| DASH-09 | Active pharmacies/doctors/researchers | All admins | same | admin_views.py:797,806,809 | same | Overview grid (pharmacies/doctors have cards; researchers do not) | In progress (reason: active researcher count missing a dashboard card) |
| DASH-10 | Active delivery-persons / active farmers | All admins | same | not queried anywhere in `stats` | — | — | Blocked (reason: no counters exist in backend) |
| DASH-11 | Active subscriptions | All admins | same | exists only in `admin_finance_summary` (admin_extra.py:691-695), not main dashboard | `/admin-panel/finance/summary/` (separate screen) | Finance screen only | In progress (reason: data exists but not surfaced on the main platform dashboard) |
| DASH-12 | Failed payments count | All admins | same | `PaymentIntent.status='failed'` tracked (billing/services.py:417,432) but never counted/surfaced anywhere | — | — | Blocked (reason: no dashboard/finance endpoint aggregates this) |
| DASH-13 | Pending refunds count | All admins | same | only a historical `total_refunds` total exists (admin_finance.py:105-108) | Finance summary | Finance screen | Blocked (reason: no "pending" refund count, only lifetime total) |
| DASH-14 | Pending cashouts count | All admins | same | exists only as a list inside Delivery's Payouts tab | delivery payouts endpoint | Delivery admin screen only | In progress (reason: exists in Delivery module, not surfaced on main dashboard) |
| DASH-15 | Pending appeals count | All admins | same | `PharmacyAppeal` queue exists only in Pharmacy sub-dashboard (admin_pharmacy.py:104,134) | pharmacy dashboard endpoint | Pharmacy admin screen only | In progress (reason: not on main platform dashboard) |
| DASH-16 | Unread support messages count | All admins | same | only `open_tickets` count exists, no unread-reply counter | — | — | Blocked (reason: no such counter modeled) |
| DASH-17 | Urgent safety alerts | All admins | same | `SecurityFlag` model exists (audit/models.py:222) but not queried in `admin_dashboard`; only `urgent_consultations` partially covers this | — | Alert banners cover approvals/escalations/urgent consultations only | In progress (reason: SecurityFlag never rolled into dashboard stats) |
| DASH-18 | Recent audit activity feed | All admins | same | admin_views.py:828-829 (last 12 ActivityLog rows) | same | rendered | Complete |
| DASH-19 | Date-range filter | All admins | same | `admin_dashboard()` reads no query params at all | — | not called with params | Blocked (reason: filtering not implemented at all) |
| DASH-20 | Role filter | All admins | same | none | — | none | Blocked (reason: not implemented) |
| DASH-21 | Status filter | All admins | same | none | — | none | Blocked (reason: not implemented) |
| DASH-22 | Loading state on first load | All admins | same | n/a | n/a | `_load()` is fire-and-forget, screen shows all-zero stats with no spinner | Blocked (reason: no loading indicator on initial fetch) |
| DASH-23 | Error state with retry | All admins | same | n/a | n/a | red banner shows raw exception text, no Retry button (pull-to-refresh is the only recovery) | In progress (reason: error is surfaced but no explicit Retry action) |
| DASH-24 | Empty state | All admins | same | n/a | n/a | present ("No overview data for your role.") | Complete |
| DASH-25 | Responsive layout | All admins | same | n/a | n/a | card width computed from MediaQuery/breakpoints | Complete |
| DASH-26 | No hardcoded/fake metrics | All admins | same | live DB queries throughout `admin_dashboard()` | — | — | Complete (for the metrics that do exist; see gaps above for what's simply absent) |

---

## 2. Super Admin

| ID | Requirement | Screen | Backend | API | Flutter UI | Status |
|---|---|---|---|---|---|---|
| SA-01 | Admin account CRUD (create/suspend/recover/approve/reject, soft-delete only) | `admin_team_screen.dart` | admin_extra.py:144-316 | `/admin-panel/admins/*` | wired | Complete |
| SA-02 | Role assignment / permission-map editing | same | admin_extra.py:320-349 | `/admin-panel/roles/*` | wired, Super-only, Super role immutable | Complete |
| SA-03 | Cross-department user/reports management | generic collection screens | wildcard RBAC (`admin_rbac.py:104-105`) | `/admin-panel/collection/*` | wired | Complete |
| SA-04 | Cross-department oversight (7-day activity by admin/module) | `admin_oversight_screen.dart` | admin_extra.py:526-556 | `/admin-panel/oversight/` | wired | Complete |
| SA-05 | Platform settings management | none exists | `settings` RBAC key only maps to disease-taxonomy CRUD | n/a | no screen file exists (`AdminModule.platformSettings` enum has no backing screen) | Blocked (reason: no platform-settings model/endpoint/screen exists at all) |
| SA-06 | Payment gateway settings | none exists | no model/endpoint anywhere | n/a | n/a | Blocked (reason: not implemented) |
| SA-07 | Subscription plan configuration (pricing/limits/duration) | none reachable | `subscription-plans` still backed by hardcoded `SEEDS` dict (admin_views.py:36-41), disconnected from real `subscriptions.SubscriptionPlan` table | `/admin-panel/collection/subscription-plans/` (unused) | no Flutter screen references it at all | Blocked (reason: real plan table exists but has zero admin UI; the only "admin" endpoint touches fake seed data) |
| SA-08 | Approval overrides / dispute resolution | `admin_approvals_screen.dart` | admin_extra.py:405-454 `admin_audit_override` | `/admin-panel/audit/override/` | wired | Complete |
| SA-09 | Security/safety controls | (via oversight/security) | `api/admin_security.py` + `SecurityFlag` | `/admin-panel/security/*` | referenced in admin_views.py:1147-1150,1288-1292 | Complete |
| SA-10 | Second-approval (maker-checker) workflow | `admin_approvals_screen.dart` | `AdminApprovalQueue` (audit/models.py:93-127), `requires_approval()` (admin_rbac.py:182-203) | `/admin-panel/approvals/*` | full enqueue→decide→execute UI | Complete |
| SA-11 | Confirmation dialogs on destructive actions | various | n/a | n/a | `admin_dialogs.dart` used across finance/etc. | Complete |
| SA-12 | Immutable audit logging | `admin_audit_screen.dart` | `ActivityLog.save()` raises on update (audit/models.py:84-90) | `/admin-panel/audit/*` | wired, filterable | Complete |
| SA-13 | Two-factor authentication | none real | `User.two_factor_enabled`/`two_factor_secret` are plain fields, no TOTP/OTP flow anywhere | read/write JSON fields only | a checkbox with no enforcement | Blocked (reason: 2FA is a stored flag, not a real second factor — no secret generation or verification endpoint exists) |

---

## 3. Operations Admin

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| OA-01 | User/doctor/delivery-person/pharmacy management | generic collection screens | `admin_collection`/`admin_record` gated by `can_perform_action` | Complete |
| OA-02 | Support ticket management + escalation handling | `admin_support_screen.dart`, escalations | `api/admin_support.py`, admin_extra.py:576-643 | Complete |
| OA-03 | Consultation monitoring | reachable via `doctors`/`consultations` module alias | no dedicated monitoring dashboard, only generic collection view | In progress (reason: works but is generic, not purpose-built monitoring) |
| OA-04 | Verification / suspension / restoration (consolidated, no divergent cascades) | pharmacy/doctor/researcher screens | `pharmacy.services.transition_pharmacy_status` (single consolidated function, admin_views.py:1309,1349-1358) | Complete |
| OA-05 | Operational reports | `admin_oversight_screen.dart` | admin_extra.py:526-556, `module_backlog` dict | Complete |
| OA-06 | Finance access correctly read-only (view/export, no refund/edit) | `admin_finance_screen.dart` shows "Access Restricted" for Operations | RBAC seed has no `financeSubscriptions` grant for Operations | Complete (deliberate scope restriction, working as designed) |

---

## 4. Finance Admin

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| FA-01 | Payment transaction tracking (unified feed) | `admin_finance_screen.dart` | `finance_rows()` unions Payment/Subscription/DeliveryEarning (admin_finance.py:44-84) | Complete |
| FA-02 | Failed payment handling | same, "Failed" tab | UI filters old `payments.Payment.status`; newer `billing.PaymentIntent` failure/dispute pipeline (billing/services.py:399-436) is NOT wired into finance_rows at all | In progress (reason: only the legacy payment model's failures are visible; intent-level failures/disputes are invisible to Finance Admin) |
| FA-03 | Refund processing (with approval threshold) | same | `finance_action()` admin_finance.py:124-177, `requires_approval` gate over 5000 BDT | Complete |
| FA-04 | Cashout/payout processing | not reachable by Finance Admin | payouts live entirely under Delivery module's `delivery` permission key, which `admin_finance` role does not have | Blocked (reason: RBAC mismatch — stated Finance Admin capability is unreachable given the actual seeded permissions; only Operations/Super/Delivery admins can process payouts) |
| FA-05 | Subscription plan management | not reachable | same disconnected-seed issue as SA-07 | Blocked (reason: same root cause as SA-07) |
| FA-06 | Commission/settlement/tax summary reports | none exist | no aggregated report anywhere; pharmacy commission logic exists only at per-order level (`pharmacy/services.py`) | Blocked (reason: not implemented) |
| FA-07 | Data export (CSV) | not in UI | backend generic export works (`admin_module_export`, admin_extra.py:648-675, capped 20000 rows, audited); `AdminApiService.exportCsv()` exists but is never called from `admin_finance_screen.dart` | Blocked (reason: working backend, zero UI wiring on this screen — only the separate payroll screen has an export button) |
| FA-08 | Approval limits enforced | n/a | `REFUND_APPROVAL_THRESHOLD = 5000` BDT (admin_rbac.py:179) | Complete |
| FA-09 | Finance-scoped audit history | `admin_audit_screen.dart` (generic, manually filtered) | generic `admin_audit_logs` endpoint | In progress (reason: works but requires the admin to manually type module=finance; no dedicated finance audit sub-view) |

---

## 5. Content Admin

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| CA-01 | RBAC scoping (articles/community/research(approve-only)/audit(view)) | n/a | `postgres_backend_extension.sql:152-157`, `admin_rbac.py:114-127` | Complete |
| CA-02 | Article moderation (list/edit/publish/needs-revision/archive/feature) | `admin_content_screen.dart` | admin_views.py:1069-1076, 1589-1656 | Complete |
| CA-03 | Team Featherflow announcement composer | same | admin_views.py:1220-1244 | Complete |
| CA-04 | Content report / spam handling | same | admin_views.py:1085-1094,1707-1723; auto-hide-after-N-reports (community/views.py:1038-1047) | Complete |
| CA-05 | Community moderation (reports/hide/remove/mute/verify) | `admin_community_screen.dart` | admin_views.py:1106-1131,1760-1803,1807-1860 | Complete |
| CA-06 | Audit/activity history view | both screens | `ModuleActivityButton` widget | Complete |
| CA-07 | Categories/tags CRUD | none exists | `PostCategory`/`ResearchTag` are models with no admin CRUD; categories DB-seeded only | Blocked (reason: not implemented — categories are seed-only, not admin-editable) |
| CA-08 | Pinned-post moderator control | none exists | `is_pinned` field exists and feed sorts by it, but no admin toggle anywhere | Blocked (reason: field exists, no admin UI or endpoint to set it) |
| CA-09 | Community guideline management | none exists | no model/endpoint/screen found at all | Blocked (reason: not implemented) |
| CA-10 | Content analytics dashboard | none content-admin-specific | only raw per-item counters (`views_count`,`read_count`); general dashboard has `pending_content` only | Blocked (reason: no engagement-over-time analytics screen for Content Admin) |
| CA-11 | Request Revision action with mandatory notes | `admin_content_screen.dart` chips: Approve/Edit/Feature/Hide/Remove only | backend fully supports it (`request_revision` requires notes, admin_views.py:1629-1631) | In progress (reason: backend ready, no Flutter button for it — "Hide" reuses the weaker no-notes-required unpublish path instead) |
| CA-12 | Researcher verification UI (shared duty with Research Admin) | none | backend endpoint exists (admin_views.py:1552-1587) | Blocked (reason: no Flutter admin screen at all — must call API directly) |

---

## 6. Research Admin + Researcher Panel

| ID | Requirement | Role | Screen | Backend | Status |
|---|---|---|---|---|---|
| RA-01 | Researcher verification (verify/suspend/reject) | Research Admin | none in Flutter | admin_views.py:1552-1587 | Blocked (reason: no dedicated screen; API-only) |
| RA-02 | Researcher profile mgmt + locked fields post-verification | Researcher | `researcher_profile_screen.dart` | research/views.py:283-322, `VERIFIED_PROFILE_FIELDS` | Complete |
| RA-03 | Paper submission + PDF upload (25MB cap, MIME check) | Researcher | `new_paper_screen.dart` | research/views.py:391-462 | Complete |
| RA-04 | Disease/cure update posts | Researcher | `new_disease_update_screen.dart` | research/views.py:242-258 | Complete |
| RA-05 | Innovation posts | Researcher | `new_innovation_screen.dart`, `innovation_screen.dart` | research/views.py:259-279 | Complete |
| RA-06 | Draft state + editing while draft | Researcher | new_paper_screen | research/views.py:35,448 | Complete |
| RA-07 | Submit-for-review workflow with daily submission cap | Researcher | same | research/views.py:553-586, validation.py:54 | Complete |
| RA-08 | Admin approve → Published | Research Admin | `admin_content_screen.dart` | admin_views.py:1617-1627 | Complete |
| RA-09 | Admin request-revision with mandatory notes | Research Admin | **missing button** (see CA-11) | admin_views.py:1629-1631 | In progress (reason: backend ready, no Flutter action) |
| RA-10 | "Accepted" status (spec's 6-state lifecycle) | — | — | `Article.STATUS_CHOICES` has only 5 states, no "Accepted"; Flutter enum value is dead/unreachable | Blocked (reason: spec's 6-state model doesn't match the real, enforced 5-state model; would require a schema + workflow change to add a true "Accepted" state distinct from "Published") |
| RA-11 | Reject/Archive | Research Admin | same | admin_views.py:1643 | Complete |
| RA-12 | Version history | Researcher/Admin | `review_area_screen.dart` | `ArticleVersionSnapshot` model, views.py:537-550 | Complete |
| RA-13 | Co-authors linked to real accounts | Researcher | free-text only | `ArticleAuthor` model exists but is completely unused/dead code | Blocked (reason: co-authors are free-text strings, no real user linkage despite a model existing for it) |
| RA-14 | Threaded reviewer comments | Researcher | `review_area_screen.dart` UI built | only a single free-text `review_notes` field; `resolveComment()` is an explicit no-op stub | Blocked (reason: UI fully built against a feature that doesn't exist on the backend — explicitly deferred in code comments) |
| RA-15 | Research tags | Researcher | `tag_picker.dart` | `ResearchTag`/`ArticleTag` models | Complete |
| RA-16 | Search/filter own papers | Researcher | `research_search_screen.dart` | scoped to own content | Complete |
| RA-17 | Saved/bookmarked papers | Researcher | reuses community Bookmark | views.py:589-615 | Complete |
| RA-18 | Citation/download tracking | Researcher | analytics screen | `downloads_count` hardcoded to 0, never incremented; "Most Cited" sort is actually a bookmark-count proxy | Blocked (reason: both metrics are fake — never real counters) |
| RA-19 | Farmer-friendly summaries | Researcher | detail screen | `farmer_summary` field | Complete |
| RA-20 | Research notifications | Researcher/Admin | n/a | `_notify_content_admins`, status-change notify | Complete |
| RA-21 | Research analytics dashboard | Researcher | `research_analytics_screen.dart` | real (views/downloads/bookmarks totals) though downloads input is always 0 | In progress (reason: screen and pipeline are real, but one of its inputs — downloads — is itself fake per RA-18) |

---

## 7. Articles / Research / News Portal (reader-facing)

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| AR-01 | Global server-side search | `paper_portal_screen.dart` | articles/views.py:208-210 | Complete |
| AR-02 | Author filter (server-wide) | `search_filter_screen.dart` | backend supports `author=`/`year=` params (views.py:185-190) but Flutter applies filters client-side only on the already-fetched page | In progress (reason: filter UI exists but only refines ~20 loaded rows, not the full corpus) |
| AR-03 | Category/topic/breed/disease/age-group filters | same | backend supports all these params; Flutter only wires generic tag/topic matching | In progress (reason: partial param wiring) |
| AR-04 | Sorting (latest/most-read/trending/most-cited) | same | `latest`/`most_read` real; `trending` is literally aliased to `-read_count` (duplicate of most_read, not a real algorithm); `most_bookmarked` mislabeled "Most Cited" | In progress (reason: two of four sort options are mislabeled proxies, not distinct real metrics) |
| AR-05 | Article cards (summary/source/date/read-time/verified badge) | `article_card.dart` | articles/views.py:87-109 | Complete |
| AR-06 | Full article view (abstract/body/references) | `article_detail_screen.dart` | articles/views.py:112-140 | Complete |
| AR-07 | Rich content (tables/charts) in article body | same | body rendered as plain paragraph text only | Blocked (reason: no rich-content rendering support) |
| AR-08 | PDF download (reader-facing) | none | backend returns `pdf_url` in both list/detail payloads, but the Flutter `Article` model has no `pdfUrl` field at all — zero download UI | Blocked (reason: backend field exists and is unused; no button anywhere) |
| AR-09 | "Farmer takeaway" section | `_KeyTakeawayCard` | uses real `farmer_summary` with generic fallback | Complete |
| AR-10 | Save/bookmark | both screens | full round trip | Complete |
| AR-11 | Share | icon present | `onPressed: () {}` in both card and detail — pure decoration, does nothing | Blocked (reason: stub, no functionality) |
| AR-12 | Related articles | `_RelatedArticlesRow` | just first 3 other same-type articles, not a real similarity match | In progress (reason: exists but weak/non-semantic logic) |
| AR-13 | Draft/review/published/archived visibility enforcement | n/a | public `feed`/`detail` correctly filter to `status='published'` only | Complete |
| AR-14 | Reader-facing version history ("this article was revised") | none | no public endpoint exposes `ArticleVersionSnapshot` | Blocked (reason: not implemented) |
| AR-15 | Reader-facing analytics | none | not expected/applicable — authoring-only feature | Blocked (reason: out of scope for readers, correctly so, but explicitly noting the spec item) |
| AR-16 | New-content alerts/subscriptions | none | no subscription/alert mechanism for farmers | Blocked (reason: not implemented) |
| AR-17 | Content reporting (abuse) | `_ReportContentDialog` | articles/views.py:290-307, moderated via admin content-reports tab | Complete |
| AR-18 | Admin Edit/Delete on cards | `_CardMenu` popup | menu renders but `PopupMenuButton` has no `onSelected` callback wired | Blocked (reason: stub, selecting either item does nothing) |

---

## 8. Delivery Admin

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| DA-01 | **Offline-rider assignment allowed, never silently blocked** | `admin_delivery_screen.dart` assign sheet | `_assign_from_queue`/`_reassign_order`/`order_assign` — none check online status, so assignment is correctly never blocked | In progress (reason: rule's "allowed" half is satisfied, but this general Delivery Admin screen still has no confirm dialog — only a passive status chip. **Note**: the Pharmacy Admin panel's own delivery-queue widget was upgraded to a real pre-confirmation dialog with the spec's exact wording — see PH-05 — but that fix was scoped to `admin_pharmacy_screen.dart`'s `_DeliveryQueueSection` only; `admin_delivery_screen.dart` is a separate screen and was not touched in that pass) |
| DA-02 | Rider approval/verification | `_RidersTab` | admin_views.py:1470-1500 | In progress (reason: approve/suspend actions work, but admin has zero visibility into the rider's license/vehicle/proof-of-work documents when approving — `_rider_json` never exposes them) |
| DA-03 | Rider management (list/suspend, not delete) | same | admin_views.py:1040-1045,1471-1472,1493-1495 | Complete |
| DA-04 | Order assignment/reassignment (generic + pharmacy + feed) | assign/reassign sheet | shared `capacity_error` logic in delivery/services.py across all 3 call sites | Complete |
| DA-05 | Fleet-wide delivery performance reports | none | only generic CSV export exists; no aggregated on-time/completion analytics for admin | Blocked (reason: per-rider stats exist only in the rider's own app, not surfaced to admin) |
| DA-06 | Payout management (list/mark-paid) | Payouts tab | admin_views.py:1058-1062,1527-1550 | Complete |
| DA-07 | Bonuses/penalties administration | none | `DeliveryEarning.bonus`/`.penalty` columns exist but are never set anywhere (grep confirmed zero writes); no admin action to award/deduct | Blocked (reason: schema-only, no pipeline) |

---

## 9. Delivery Person Panel

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| DP-01 | Onboarding (license/vehicle info) | `delivery_signup_screen.dart` | `DeliveryProfile` model + serializers.py:491-522 | Complete |
| DP-02 | Verification (binary approved gate) | n/a | `approved_by_admin` | In progress (reason: only binary; no richer "needs more info" state like pharmacy has) |
| DP-03 | Online/offline + break/unavailable states | `delivery_attendance_screen.dart` | delivery/views.py:195-210 | In progress (reason: "unavailable" accepted by backend but has no UI control at all) |
| DP-04 | Attendance check-in/check-out | same | delivery/views.py:622-683 | Complete |
| DP-05 | New order accept/reject (3-min offer window) | `delivery_orders_screen.dart` | delivery/views.py:309-358 | Complete |
| DP-06 | Multi-order active job list | same | delivery/services.py:71-83 | Complete |
| DP-07 | Status state machine (pickup/out-for-delivery/delivered/failed/cancelled) | `delivery_detail_screen.dart` | delivery/views.py `_TRANSITIONS` | Complete |
| DP-08 | Map routing + live location push | `delivery_map_screen.dart` | Google Directions proxy, 20s location push | Complete |
| DP-09 | In-app dynamic rerouting | none | hands off to external Google Maps app only | Blocked (reason: no in-app re-route on deviation) |
| DP-10 | OTP delivery confirmation | delivery_detail_screen | delivery/views.py:554-557 | Complete |
| DP-11 | Photo proof required before "delivered" | same | delivery/views.py:558-566 | Complete |
| DP-12 | Signature capture | same | `signature_pad.dart` | In progress (reason: cosmetic only — optional, never required or validated server-side beyond being another proof upload) |
| DP-13 | Delivery notes / failure reason | same | delivery/views.py:567-571 | Complete |
| DP-14 | Earnings view + performance metrics | `delivery_earnings_screen.dart`, `delivery_performance_screen.dart` | delivery/views.py:686-754 | Complete |
| DP-15 | Payout history (read-only) | same | delivery/views.py:728-733 | Complete |
| DP-16 | Request Payout action | "Request Payout" button | **UI mock only** — shows a snackbar "payout requested (mock)" with zero backend call; no such endpoint exists | Blocked (reason: pure UI stub, no backend integration at all) |
| DP-17 | Bonuses/penalties visibility | "Weekly Bonus" card | fed a hardcoded 0 in both Dart factory paths | Blocked (reason: dead UI, no real data ever reaches it — same root cause as DA-07) |
| DP-18 | Call/chat shortcuts to customer | delivery_detail/dashboard screens | all `onPressed: () {}` no-ops or fake "Calling…"/"Opening dialer…" snackbars; no `url_launcher` tel: scheme used anywhere in delivery feature | Blocked (reason: fully non-functional stubs) |
| DP-19 | Contact shortcut to pharmacy | none | no pharmacy-contact shortcut exists at all (customer-only, and even that is fake per DP-18) | Blocked (reason: not implemented) |
| DP-20 | Pharmacy handling instructions + prescription-required flag shown to rider | order card/detail | `PharmacyFlagBanner`, `is_prescription_required` badge + mandatory verification checkbox | Complete |
| DP-21 | Cold-chain/fragile/urgent labels | order card/detail | only cold-chain exists end-to-end; fragile/urgent absent from schema entirely | In progress (reason: 1 of 3 labels implemented; other 2 have no field at all) |
| DP-22 | Return-to-pharmacy flow on failed delivery | none rider-facing | backend does restock inventory + notify pharmacy on failure, but there is no explicit rider-facing "return to pharmacy" status/step, and no tracking of whether the physical item was actually returned | In progress (reason: data-side side-effects are real; no physical workflow/status tracks the return) |

---

## 10. Pharmacy Admin Panel

Fully re-specced and built across three phases of this engagement — see `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md` (§1–§28 original build + first addendum, §29–§38 second addendum) and `PHARMACY_ADMIN_AUDIT.md` for the complete file-by-file trace. The panel now has all 12 spec'd nav sections with real Flutter UI: Overview, Pharmacy Accounts, Medicine Catalogue + Add Medicine form, Inventory (expiry + stock-adjust), Orders & Delivery, Sales & Commissions, Settlements, Employees, Appeals, Delivery Assignments (with an offline-rider pre-confirmation dialog), Pharmacy Chat, and Reports & Audit (14 CSV report types + audit-log viewer).

| ID | Requirement | Status |
|---|---|---|
| PH-01 | Dedicated Pharmacy Admin login, standalone panel | Complete (Playwright-verified) |
| PH-02 | Add Medicine form (name/generic/category/price/discount/stock/min-qty/expiry/image upload) | Complete (Playwright-verified: create → 201 → image picker revealed) |
| PH-03 | Inventory stock adjustment | Complete (curl-verified: +10 → 60 → archive); stock-*movement history* view still absent (In progress) |
| PH-04 | Reports & Audit: 14 report types as CSV export + dedicated audit-log view | Complete (Playwright-verified: export → 200 → real CSV rendered) |
| PH-05 | Offline-rider assignment: allowed with an explicit pre-confirmation dialog, warning also shown in the result | Complete (code-verified against the live API's `status` field; no offline riders in current seed data to click through interactively — see report §36) |
| PH-06 | Platform-wide CSV export works with a real browser `Accept: text/csv` header | Complete — found and fixed a pre-existing 406 affecting every admin module's export, not just pharmacy's (report §31) |
| PH-07 | Flutter widget tests for the pharmacy admin screen | In progress — 3 smoke tests added (7-tab render, 320px, tab-switch); not full per-dialog coverage |

---

## 11. Farmer Pharmacy Marketplace

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| FM-01 | Marketplace listing / pharmacy directory | `farmer_pharmacy_screen.dart` | farmer_views.py:35-56 | Complete |
| FM-02 | Search + category + price filters | same | farmer_views.py:83-108 | Complete |
| FM-03 | Product detail (view count) | same | farmer_views.py:111-118 | Complete |
| FM-04 | Current + previous price (discount-eligible) | `_MedicineCard` | `previous_price` field, real (not fabricated) | In progress (reason: field exists and is fetched but never rendered — no strikethrough/discount display anywhere) |
| FM-05 | Discount badge | card | same underlying data as FM-04 | Blocked (reason: absent from UI entirely) |
| FM-06 | "Most Picked" badge | card | `ProductCard.mostPicked` param exists but is never passed `true` by any caller; no backend concept for "most picked" exists at all | Blocked (reason: dead parameter, no data source) |
| FM-07 | "Top Seller" badge (from real order-count data) | card | `is_top_seller` is real derived data (orders_count>=10) and IS rendered on the pharmacy staff's own catalogue screen | Blocked (reason: real data exists and is fetched by the farmer client, but never displayed on the farmer-facing card — only shown to the pharmacy's own staff) |
| FM-08 | Delivery estimate | card | no ETA field exists anywhere in the data model; even the one place a delivery string is shown (pharmacy staff catalogue) is a hardcoded `'Delivery 1–2 hours'` string, not real data | Blocked (reason: not modeled anywhere, and the only precedent is itself fake) |
| FM-09 | Medicine name + generic name | card | present | Complete |
| FM-10 | Unit + min-order-quantity display and enforcement | card/cart | `min_order_quantity` fetched into the model but never shown on card/detail, and cart quantity stepper never enforces it (only bounds against 0/stock) | Blocked (reason: the sibling feed marketplace enforces this correctly, proving the pattern exists, but it was never applied to pharmacy — real functional regression) |
| FM-11 | Add-to-Bag action | card | `_addToCart` | Complete (functionally works, though labeled "Add to cart" not "Add to Bag") |
| FM-12 | Stock status display | card | `stock_status` property, models.py:120-126 | Complete |
| FM-13 | Image at top of card (per shared `ProductCard` design) | `_MedicineCard` | a fully-built shared `ProductCard` widget already implements this exact spec and is proven out on the pharmacy staff's own catalogue screen | Blocked (reason: the farmer-facing screen ships an old bespoke `_MedicineCard` with a small left-aligned thumbnail instead of the shared widget — a straightforward fix: swap in the existing `ProductCard`) |
| FM-14 | Cart → checkout → order, with prescription enforcement | `farmer_pharmacy_screen.dart` | farmer_views.py:159-224,181-187 | Complete |
| FM-15 | Order history/detail/cancel/pay with real state machine | same | farmer_views.py:227-311 | Complete |
| FM-16 | Delivery tracking (rider info) on order | `_OrderCard` | delivery block in order payload | Complete |
| FM-17 | Call action to pharmacy/rider | `_OrderCard` | real `tel:` launch | Complete |
| FM-18 | Loading/empty/error+retry states | browse/orders tabs | present, including Retry button | Complete |
| FM-19 | Map action for pharmacy location | none | pharmacy has address/coverage text but no lat/lng and no "open in maps" button (vet discovery has this pattern, pharmacy doesn't) | Blocked (reason: not implemented; precedent exists elsewhere in the app) |

---

## 12. Disease Detection

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| DD-01 | Single-image capture (camera/gallery) | `disease_detection_screen.dart` | ml/views.py:118-198 | Complete |
| DD-02 | Multi-image input | `_UploadSection` | `predict_disease()` only ever accepts one image; `image_urls` JSONField always populated with a one-element list | Blocked (reason: not implemented — single image only, no batching anywhere) |
| DD-03 | Prediction + confidence + severity | result card | real inference pipeline, top_k=5 | Complete |
| DD-04 | Auto-chatbot on result | "Ask Chatbot" button | opens a **local static bottom sheet** re-rendering the same API response text — not a real chat session; `chatbot_session_id` field is dead (never assigned/read anywhere) | Blocked (reason: fully decorative — no real conversational backend behind the button) |
| DD-05 | Follow-up questions (bird age/count/mortality/flock type) | none | `predict_disease()` only accepts image + optional flock_id; no such fields on the model or in the request | Blocked (reason: not implemented at all) |
| DD-06 | Vet escalation + nearby-vet matching + booking | "Book Vet" → `DiscoverVetsTab` | real navigation handoff with disease/urgency query params, but the target screen only shows a **passive banner** — no actual filtering/ranking by disease, no automated booking | In progress (reason: shallow but real integration — forwards context as a text hint only) |
| DD-07 | 3-free-scans-then-subscription gating | `_PaywallBanner` | `is_free_scan` is **hardcoded `True` unconditionally**; `disease_scan_limit` field exists on subscription plans but nothing in `ml/views.py` ever reads/enforces it; the paywall banner renders unconditionally regardless of actual scan count | Blocked (reason: entirely unenforced server-side — UI-only decoration, the scan endpoint is unconditionally free/unlimited today) |
| DD-08 | Downloadable case report | none | no pdf/download/report-generation code found anywhere | Blocked (reason: not implemented) |
| DD-09 | Offline sync | none | no offline storage/sync code found | Blocked (reason: not implemented) |
| DD-10 | Prediction feedback (thumbs up/down) | none | no feedback endpoint/field exists | Blocked (reason: not implemented) |
| DD-11 | Biosecurity checklist / vaccination reminders | result/assistant sheet | `ml/content.py` has real static advisory copy including vaccination/biosecurity language, rendered as plain bullet text | In progress (reason: content is real and disease-specific, but it's static text, not an interactive checklist with persistence, and there's no scheduled/recurring reminder tie-in) |
| DD-12 | Pharmacy treatment cross-sell from scan result | none | no pharmacy CTA, medicine-id cross-reference, or "buy treatment" button anywhere in the disease-detection flow | Blocked (reason: not implemented) |
| DD-13 | Recent scan history | disease_detection_screen | real | Complete |

---

## 13. Farmer Dashboard + Cost Management

*(Per the previously-received Farmer/Cost-Management audit — reproduced in condensed form here; the original full evidence-cited report is preserved in this session's history.)*

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| FD-01 | Core farmer dashboard metrics (batches, mortality, revenue, expenses, etc.) | Farmer Dashboard | farmers/ app, real SQL-backed queries | Complete |
| FD-02 | Due-tax / loan-balance cards on dashboard | Farmer Dashboard | tax/loan APIs already return this data | Blocked (reason: API already returns `due_tax`/`loan_balance`, but the Dashboard screen simply never renders cards for them — cheap fix, pure UI wiring) |
| FD-03 | Cost Management: expenses/revenue/loans/reports/cashout | Cost Management screens | `expenses/` app, `cost_dialogs.dart` | In progress (reason: expenses/revenue/loans/reports are real and wired; see FD-04 for cashout) |
| FD-04 | Cashout to bank/mobile wallet | Cost Management | `showCashoutSheet` (`cost_dialogs.dart:548-681`) fully built, backend fully working | Blocked (reason: **the Cashout UI is completely orphaned — no button anywhere in `lib/` calls `showCashoutSheet`**, despite a fully working backend and dialog; this is dead code with a working backend behind it — the single highest-value, lowest-effort fix found in this entire audit) |
| FD-05 | Budget vs. actual comparison | none | zero occurrences anywhere in backend or Flutter | Blocked (reason: not implemented at all) |
| FD-06 | Supplier payment history (aggregated) | none | only a filterable free-text field exists, no aggregation | Blocked (reason: not implemented — no real per-supplier ledger) |
| FD-07 | Excel export of cost reports | "Export to Excel" button | actually generates CSV — no `openpyxl`/`xlsxwriter` anywhere in the codebase | In progress (reason: export works, but produces `.csv` not a real `.xlsx` file, contrary to the button's own label) |
| FD-08 | Audit trail for cost entries | backend only | real, immutable audit trail exists | In progress (reason: data is real and correctly immutable, but there is no farmer-facing screen to actually view it) |
| FD-09 | Mortality-cost impact as a named metric | implicit only | only exists as an implicit proxy via cost-per-bird, never a distinct named metric | In progress (reason: the underlying numbers exist, just not surfaced as the specifically-named metric) |
| FD-10 | Batch tracking / comparison | Farmer Dashboard | real, per prior-phase build | Complete |

---

## 14. Doctors Panel

Verified directly (not via subagent) against `backend/doctor/` + `backend/consultations/` models and `lib/features/doctor/` (15 files, 8114 lines). Confirmed comprehensive: consultations (video via Jitsi, chat via Socket.IO ASGI), disputes with categories/statuses, response-time metrics, ratings/reviews, `scan_id` linkage to disease scans. Built and tested in a prior phase of this engagement (`test_doctor_flow.py`).

| ID | Requirement | Status |
|---|---|---|
| DR-01 | Doctor panel (consultations, video, chat, disputes, metrics) | Complete (prior phase) |
| DR-02 | Consultation linkage to a disease scan (`Consultation.scan_id`) | Complete — but note this is the *consumer* side of the same disease-detection flow that has real gaps (see DD section); the linkage field itself works |

---

## 15. Community / Blogging

| ID | Requirement | Screen | Backend | Status |
|---|---|---|---|---|
| CM-01 | Timeline feed (latest/pinned/trending/following) | `community_feed_screen.dart` | community/views.py:355-398 | Complete |
| CM-02 | Text/poll/question posts | `create_post_screen.dart` | `POST_TYPE_CHOICES` | Complete |
| CM-03 | Image/video/document media | same | upload restricted to jpg/png/webp/mp4/mov/pdf | Complete |
| CM-04 | Categories (Feed/Disease/Market/Equipment/Birds/Success/Team Featherflow) | same | matches spec exactly | Complete |
| CM-05 | Reactions (like/love/helpful/insightful) | `post_card.dart` | models.py:22-24 | Complete |
| CM-06 | Comments + one-level replies | `community_post_screen.dart` | `parent_comment` | Complete |
| CM-07 | Reposts | same | `Repost` model | Complete |
| CM-08 | Shares (with count tracking) | "Share" menu | clipboard-copy only, no native share sheet or count tracking | Blocked (reason: stub) |
| CM-09 | Hashtags | composer | `_HASHTAG_RE`, trending tags endpoint | Complete |
| CM-10 | Mentions | composer | `_MENTION_RE`, `mentions` field | Complete |
| CM-11 | Bookmarks | feed/post screens | real | Complete |
| CM-12 | Anonymous posting | composer/comment box | `is_anonymous` | Complete |
| CM-13 | Pseudonymous posting | none | only binary real-name/anonymous, no persistent pseudonym identity | Blocked (reason: not implemented) |
| CM-14 | Search | `community_search_screen.dart` | community/views.py:871-907 | Complete |
| CM-15 | Location filter | none | zero occurrences of `location` field/param anywhere | Blocked (reason: not implemented) |
| CM-16 | Farm-type filter | none | zero occurrences of `farm_type` field/param anywhere | Blocked (reason: not implemented) |
| CM-17 | Verified-expert filter | search screen | `_verifiedOnly` chip | Complete |
| CM-18 | Follows + follow suggestions | n/a | `Follow` model, suggestions endpoint | Complete |
| CM-19 | Polls with quota | composer | `PollVote`, `poll_quota_ok` | Complete |
| CM-20 | "Solved answer" marking | post screen | `is_best_answer`, question-author-only gate | Complete |
| CM-21 | Notifications | `community_notifications_screen.dart` | real | Complete |
| CM-22 | Report/mute/block (member-level) | post screen | `Report`, `UserBlock` distinct from admin `CommunityMute` | Complete |
| CM-23 | Moderation (auto-hide, admin hide/remove) | admin screen | real, covered in CA-05 | Complete |
| CM-24 | Verified badges | post card/search | `verified_badge()` | Complete |
| CM-25 | Official "Team Featherflow" posts | post card | `is_official` field, distinct mechanism from the Articles team_update content type — both exist and are real, just two separate paths | Complete |
| CM-26 | Software-update/maintenance notices | none | no dedicated content_type/category — would have to be shoehorned into an existing type | Blocked (reason: not a first-class category) |
| CM-27 | Educational tips | none dedicated | covered generically by news/innovation articles or posts | In progress (reason: content can exist, just not as a first-class category) |
| CM-28 | Weekly market insights (scheduled) | manual only | `market_report` content type + "Market News" category exist, but no scheduled/weekly automation | In progress (reason: manual authoring works, automation doesn't exist) |
| CM-29 | Draft/review workflow for community posts | none | posts publish immediately; only Articles has draft→review→published→archived | Blocked (reason: community posts have no editorial pipeline at all, by design difference from Articles — flagging as a spec gap, not necessarily a defect) |

---

## 16. Global Frontend Requirements

Verified directly against `lib/core/widgets/error_state.dart` (shared `ErrorStateView` + `humanize()`, used in 10+ screens) and cross-referenced against every screen audited above.

| ID | Requirement | Status |
|---|---|---|
| GF-01 | Consistent AppBar / back buttons / no duplicate nav | Complete (confirmed as a shared pattern across all audited screens; no duplicate-nav instances found) |
| GF-02 | Loading/empty/error/retry states | In progress (reason: the shared `ErrorStateView` pattern is real and used in 10+ screens, but this audit found specific screens that don't use it — e.g. platform Dashboard has no loading spinner (DASH-22) and a weaker error state (DASH-23)) |
| GF-03 | Responsive down to 320px | In progress (reason: confirmed responsive on dashboard/admin screens via MediaQuery breakpoints; not individually re-verified at exactly 320px for every one of the ~80 screens touched in this audit) |
| GF-04 | `taka()` currency formatting everywhere | Complete (used consistently in all money-displaying screens reviewed) |
| GF-05 | No fake/hardcoded metrics | Blocked (reason: this audit found multiple concrete violations — the "trending" sort aliasing `most_read` (AR-04), `downloads_count` hardcoded to 0 (RA-18), `is_free_scan` hardcoded True (DD-07), delivery bonus hardcoded to 0 (DP-17), "Delivery 1-2 hours" hardcoded string (FM-08) — each individually tracked above) |
| GF-06 | No dead/no-op buttons | Blocked (reason: multiple confirmed instances — Share icons (AR-11, CM-08), Call/Chat buttons (DP-18), Card menu Edit/Delete (AR-18), "Request Payout" (DP-16) — each individually tracked above) |
| GF-07 | No silent failures | In progress (reason: no new silent-failure instances found beyond the missing-retry-button case on the dashboard, DASH-23) |
| GF-08 | Permission-denied states | Complete (`admin_finance_screen.dart`'s "Access Restricted" pattern confirmed and used consistently across permission-gated screens) |

---

## 17. Testing

| ID | Requirement | Status |
|---|---|---|
| T-01 | Backend script tests exist for prior-built modules (pharmacy, signup, farmer, tax, doctor) | Complete — `test_pharmacy_flow.py`, `test_pharmacy_admin.py`, `test_signup_flows.py`, `test_farmer_panel.py`, `test_tax_calculator.py`, `test_doctor_flow.py` all exist and pass per prior-phase runs |
| T-02 | Automated tests for every NEW gap fix in this phase | Blocked (reason: no code fixes have been implemented yet in this phase — this matrix is the pre-implementation deliverable; tests will be added alongside each fix) |
| T-03 | Live Playwright verification for anything newly implemented | Blocked (reason: same — nothing new implemented yet this phase) |
| T-04 | `flutter analyze` / `flutter test` / `manage.py check` clean | Not re-run this phase (last confirmed clean at end of Pharmacy Admin phase) |

---

## Summary of Highest-Value, Lowest-Effort Fixes Identified

These are the gaps where the backend is already fully real and working, and only a UI wiring change is needed:

1. **FD-04 — Cashout UI is completely orphaned.** `showCashoutSheet` (`cost_dialogs.dart:548-681`) is fully built against a working backend but no button anywhere calls it. Fix: add an entry point (e.g. a "Cash Out" button on the Cost Management or wallet screen).
2. **FD-02 — Dashboard missing due-tax/loan-balance cards.** The API already returns this data; just needs two more cards on the Farmer Dashboard.
3. **FM-06/FM-07/FM-13 — Farmer pharmacy marketplace card.** A fully-built shared `ProductCard` widget (image-on-top, Top Seller badge, discount ribbon, min-qty line) already exists and is proven out on the pharmacy staff's own catalogue screen. Fix: swap `farmer_pharmacy_screen.dart`'s bespoke `_MedicineCard` for the shared `ProductCard` — this alone resolves FM-05, FM-06, FM-07, and FM-13 together.
4. **FM-10 — Min-order-quantity enforcement missing on pharmacy cart.** The sibling feed marketplace already implements this correctly (`farmer_feed_marketplace_screen.dart:594`); the same pattern just needs porting to the pharmacy cart.
5. **DA-01 — Offline-rider warning.** Backend already correctly allows the assignment; just needs a confirm dialog / warning banner when the selected rider's status is offline.
6. **DD-07 — Free-scan limit enforcement.** `disease_scan_limit` already exists on subscription plans; `predict_disease()` just needs a count-and-gate check before creating a scan.
7. **CA-11/RA-09 — Request Revision button.** Backend transition already exists (`admin_views.py:1629-1631`); just needs a Flutter action with a notes field, replacing the current mis-used "Hide" shortcut.

## Structural/Schema-Level Gaps (require real backend work, not just UI wiring)

- SA-05/SA-06/SA-07/FA-05 — platform settings, payment-gateway settings, and subscription-plan configuration have no real backend at all (SA-07/FA-05 share root cause: `subscription-plans` module is fake seed data, disconnected from the real `SubscriptionPlan` table).
- SA-13 — 2FA is a stored flag with no TOTP implementation.
- DA-07/DP-17 — bonuses/penalties are schema-only, no pipeline ever sets them.
- RA-10 — the spec's "Accepted" status doesn't exist in the real 5-state Article lifecycle.
- RA-14 — reviewer comments UI is built against a threaded-comment feature that doesn't exist on the backend.
- DD-02/DD-05/DD-08/DD-09/DD-10/DD-12 — disease detection multi-image, follow-up questionnaire, downloadable report, offline sync, feedback, and pharmacy cross-sell are all unimplemented from scratch.

---

*No requirement above is marked Complete without the underlying backend + API + Flutter UI all confirmed wired together through direct code inspection. Nothing described in this matrix has been committed to git — the working tree changes remain local, per standing instruction.*
