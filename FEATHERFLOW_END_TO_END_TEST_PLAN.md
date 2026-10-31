# FEATHERFLOW — End-to-End Test Plan (with execution status)

Each workflow lists its steps, the evidence available **today**, and a gap list. Evidence tags (strongest first):

* **[UI]** driven in Chrome through the real Flutter UI against the real backend (Playwright).
* **[UI-read]** screen opened in Chrome with real data; the step's mutation not driven.
* **[HTTP]** driven through the live HTTP API by this audit (not through the UI).
* **[SCRIPT]** covered by a project script (`backend/scripts/test_*.py`, Django test client against the live DB; counts = assertions, run 2026-10-01) or Flutter widget test.
* **[GAP]** no evidence (not implemented, not testable here, or not run).
* **[BROKEN]** executed and failing (fault ID given).

"Verified" in the final column means **[UI] or [HTTP]+[SCRIPT]**; a workflow is called *end-to-end verified* only if every step has at least [HTTP]/[UI]. **No workflow below is fully verified through the UI.**

## 1. Farmer (20 steps)

| # | Step | Evidence |
|---|---|---|
| 1 | Signup | [SCRIPT] test_signup_flows (107), signup_flow_test.dart — wizard not driven in browser |
| 2 | Login | [UI] |
| 3 | Complete profile / farm | [UI-read] profile; edit [SCRIPT] test_farmer_panel (39) |
| 4 | Add flock/batch | [UI-read] flocks route; [SCRIPT] test_flock_feed_management (17) |
| 5 | Add expense | **[UI]** POST 201 → row confirmed → deleted |
| 6 | Add revenue | [SCRIPT] test_farmer_panel; [UI-read] revenue page |
| 7 | View dashboard | [UI] numbers equal API (৳198,550 expense / −৳35,893 net / ৳148,167 cash) |
| 8 | View Cost Management | [UI] incl. CSV and PDF export (200) |
| 9 | Buy feed | [HTTP] 6 parallel over-stock orders (1 success, no oversell, cancel restores stock); [SCRIPT] test_feed_order_delivery (26); UI checkout not driven |
| 10 | Buy medicine | [SCRIPT] test_pharmacy_flow (22); UI checkout not driven |
| 11 | Track delivery | [SCRIPT] status mirror; rider route [BROKEN] F-003; UI tracking [GAP] |
| 12 | Run disease detection | [UI-read] scan history; [SCRIPT] test_disease_detection (25); upload [GAP] (headless camera/file) |
| 13 | Use chatbot | [BROKEN/PARTIAL] static advice sheet only (F-016) |
| 14 | Find vet | [UI-read] list + filters + permission-denied state; [SCRIPT] 38 + 12 |
| 15 | Book consultation | [SCRIPT] test_consultation_booking_rules (29); UI [GAP] |
| 16 | Chat with doctor | [SCRIPT] test_consultation_chat_access (13); chats tab [UI-read]; realtime [GAP] |
| 17 | Read research | **[HTTP]** publish → farmer feed → detail → bookmark → search; farmer UI [GAP] |
| 18 | Create community post | [SCRIPT] test_community (56); [HTTP] create (also reveals raw-HTML storage F-010); UI [GAP] |
| 19 | Receive notification | [UI-read] bell (GET/PATCH 200); [HTTP] researcher received 3 admin notifications |
| 20 | Logout / relogin / persistence | **[UI]** reload, logout, protected-route redirect, relogin — PASS |

## 2. Pharmacy owner (19 steps)

| # | Step | Evidence |
|---|---|---|
| 1 | Signup | [SCRIPT] test_signup_flows, test_signup_documents |
| 2 | Pending login | [SCRIPT] test_pharmacy_admin; demo "pending" account is actually active → [GAP] live |
| 3 | Locked panel | [SCRIPT] permissions API (`can{…}` false while suspended); UI [GAP] |
| 4 | Profile | [UI-read] + [SCRIPT] test_pharmacy_profile (32) |
| 5 | Earnings | [UI-read] "Lifetime earnings ৳0.00" |
| 6 | Pharmacy Admin chat | [SCRIPT] only |
| 7 | Appeal | [SCRIPT] only; **[BROKEN] in UI for suspended owner (F-002)** |
| 8 | Admin activation | [SCRIPT] test_pharmacy_admin (132) |
| 9 | Feature unlock | [SCRIPT] |
| 10 | Add medicine | [SCRIPT] test_pharmacy_medicine_edit; UI add [GAP] |
| 11 | Upload image | [SCRIPT] test_pharmacy_medicine_images (20) |
| 12 | Manage inventory | [UI-read] + [SCRIPT] |
| 13 | Receive/process order | [UI-read] order card; [SCRIPT] confirm/cancel/ready |
| 14 | Delivery | [SCRIPT] test_delivery_multi_active (34) |
| 15 | Sales | [SCRIPT]; no live rows (F-024) |
| 16 | Settlement | [SCRIPT]; no live rows |
| 17 | Suspension | [SCRIPT]; admin UI [GAP] (destructive action excluded) |
| 18 | Appeal / revision | [SCRIPT]; owner UI [BROKEN] F-002 |
| 19 | Restoration | [SCRIPT] |

## 3. Feed workflows (20 steps)

| # | Step | Evidence |
|---|---|---|
| 1 | Feed Admin login | [UI] |
| 2 | Add feed product | [SCRIPT] test_feed_catalogue (22); UI form [GAP] |
| 3 | Add stock | [SCRIPT] test_feed_stock_integrity (29) |
| 4 | Farmer sees product | [UI-read] 15 products; [HTTP] |
| 5 | Farmer orders | [HTTP] + [SCRIPT] |
| 6 | Admin receives order | [SCRIPT] |
| 7 | Admin sees location | [SCRIPT] (lat/lng in payload) |
| 8 | Admin assigns rider | [SCRIPT] (incl. reject → reassign) |
| 9 | Rider sees map | **[BROKEN] route polyline F-003** (map widget itself not asserted) |
| 10 | Rider marks arrival | **[GAP — not implemented] F-005** |
| 11 | Rider uploads proof | [SCRIPT] test_delivery_proof_and_earnings (mandatory, signed token) |
| 12 | Admin rejects proof | **[GAP — not implemented] F-005** |
| 13 | Rider resubmits | **[GAP — not implemented] F-005** |
| 14 | Admin approves | **[GAP — not implemented] F-005** |
| 15 | Order completes | [SCRIPT] (rider `delivered`) |
| 16 | Financial record once | [SCRIPT] (single earning/expense mirror) |
| 17 | Feed Owner login | [UI] |
| 18 | Chat | **[UI]** (POST/PATCH 200) |
| 19 | Resolve / reopen | [SCRIPT] test_feed_owner_flow (32); admin chat inbox [UI-read] |
| 20 | Community post | Feed Owner opens community [UI]; post creation [GAP]; Feed Admin announcement visible |

## 4. Doctor (13 steps)

| # | Step | Evidence |
|---|---|---|
| 1–2 | Signup, verification | [SCRIPT] test_signup_flows, test_verification_flows |
| 3 | Login | [UI] |
| 4 | Availability | [SCRIPT] test_doctor_flow (58); toggle not clicked |
| 5 | Consultation request | [SCRIPT] booking rules (29) |
| 6 | Accept | [SCRIPT] + the UI invoked `action` endpoint once (S-4: `accepted → no_show`, 200) |
| 7 | Chat | [SCRIPT]; messenger [UI-read] |
| 8 | Video (if supported) | Jitsi link only [PARTIAL] F-021 |
| 9 | Case notes | [SCRIPT] + [UI-read] |
| 10 | Prescription | [SCRIPT]; PDF endpoint; no live rows |
| 11 | Follow-up | [SCRIPT]; no live rows |
| 12 | Complete | [SCRIPT] test_consultation_transitions_and_receipts (53) |
| 13 | Payment / rating | [SCRIPT]; earnings screen [UI-read] |

## 5. Research (11 steps)

| # | Step | Evidence |
|---|---|---|
| 1–2 | Signup, verification | [SCRIPT] |
| 3 | Submit paper | **[HTTP]** (draft create/edit PASS) |
| 4 | Upload PDF | [GAP] |
| 5 | Draft | **[HTTP]** (draft invisible to farmers, not editable when pending) |
| 6 | Submit for review | **[HTTP]** (other researcher → 404) |
| 7 | Request revision | **[HTTP]** (notes mandatory; author notified) |
| 8 | Resubmit | **[HTTP]** (2 version snapshots) |
| 9 | Approve/publish | **[HTTP]** (Content/Research Admin); published → not editable |
| 10 | Farmer reads summary | **[HTTP]** (feed, detail, bookmark, search) |
| 11 | Search / save / download | search + save [HTTP]; download [GAP] |
| — | Automated regression test | **[GAP] none exists (F-017)**; the 22-step workflow lives in the audit scratch tooling |

## 6. Delivery (14 steps)

| # | Step | Evidence |
|---|---|---|
| 1–2 | Signup, verification | [SCRIPT] |
| 3 | Login | [UI] |
| 4 | Online/offline | [UI] (PATCH 200; restored afterwards) |
| 5 | Assignment | [SCRIPT] |
| 6 | Accept | [SCRIPT] |
| 7 | Pickup | [SCRIPT] |
| 8 | Route | [BROKEN] F-003 |
| 9 | Arrival | [GAP — not implemented] F-005 |
| 10 | Proof | [SCRIPT] |
| 11 | Completion | [SCRIPT] |
| 12 | Earnings | [UI-read] + [SCRIPT] |
| 13 | Payout | [SCRIPT] (admin payouts) |
| 14 | Attendance | [UI-read] + [SCRIPT]; check-in not clicked |

## 7. Admin roles — allowed vs denied

| Check | Evidence |
|---|---|
| Login → `/admin`, server-driven sidebar per role | **[UI]** all 11 admin roles (+ legacy) |
| Allowed modules open and load data | **[UI-read]** 51–222 controls per role |
| Denied modules → server 403 | **[HTTP]** 151 routes × 19 identities: 0 violations |
| Denied modules → UI | **[UI]** shell paints then shows 403 message (F-007, F-038) |
| Mutations (approve/suspend/refund/assign/export) | [SCRIPT] test_admin_panel (66), test_finance_admin (35), test_pharmacy_admin (132); UI mutations not driven (destructive controls excluded). Unintended UI side effects are listed in the fault register S-1…S-4 |
| Audit visibility per role | **[HTTP]** scoped (Super/Ops 7,523, Support 1,409, Pharmacy 1,156, Content 341, Feed Admin none) |

## 8. Gaps to close to call the product end-to-end verified

1. A browser-level (Playwright) suite that drives **form submissions** with disposable accounts and cleans up (this audit deliberately avoided destructive/mutating controls after accidental side effects S-1…S-4).
2. Fix F-001/F-002/F-003/F-004/F-005 first; they block steps above.
3. Add `test_research_flow.py`; add Socket.IO and Jitsi two-client tests; add an isolated test database (F-014).
