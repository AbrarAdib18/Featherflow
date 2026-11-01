# FEATHERFLOW — Feature Matrix

One row per feature/action intended or visible for each role. **Status vocabulary** (strict; "Complete" is deliberately not used):

* **Working (live UI + script)** — driven end-to-end in the real browser *and* covered by an automated script/test.
* **Working (live UI, read/render)** — screen rendered in Chrome with real API 2xx data; the mutating action was *not* driven (destructive/state-changing controls were excluded from the crawl).
* **Working (script/HTTP only)** — verified only by backend scripts or ad-hoc HTTP calls; the UI path was not exercised in a browser.
* **Partial** — some of the feature exists, or works only in part. **Broken** — observed failing. **Missing** — no implementation found. **Not verified** — could not be verified either way.

Automated-test counts are assertions from `backend/scripts/test_*.py` run on 2026-10-01 against the live DB (1,481 assertions pass in 42 of 43 scripts; `test_admin_pagination_performance.py` crashes — F-001) and Flutter widget tests (226 pass). "Live test" is the audit's own browser/HTTP evidence (see `FEATHERFLOW_LIVE_BROWSER_VERIFICATION.md`). Fault IDs → `FEATHERFLOW_FAULT_REGISTER.md`.

## Part A — Feature checklist by role

**Status totals (165 feature rows):** Working (live UI, read/render): 62, Working (script/HTTP only): 52, Working (live UI + script): 26, Partial: 9, Missing: 7, Not verified: 5, Broken: 4


### Farmer

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Farmer | Signup (2-step wizard + role data) | /signup/farmer, /signup | POST /api/auth/register/, /api/auth/registration-upload/ | users, user_roles, farmer_profiles, signup_documents | public | Submit wizard | Working (script/HTTP only) | test_signup_flows (107), signup_flow_test.dart | not driven |
| Farmer | Email/phone verification | /verify | POST /api/auth/verify/request/confirm/ | users.email_verified_at/phone_verified_at | public | Enter OTP | Working (script/HTTP only) | test_verification_flows (36), verification_flow_test.dart | not driven |
| Farmer | Login | /login | POST /api/auth/login/ | users | public | Log In | Working (live UI + script) | test_signup_flows | PASS (24 accounts) |
| Farmer | Logout / relogin / reload persistence | /farmer/profile → Sign out | POST /api/auth/logout/ (client clears session) | token_blacklist_* | farmer | Sign out → confirm | Working (live UI, read/render) | — | PASS (reload, logout, protected route redirect, relogin) |
| Farmer | Password reset | /reset-password | POST /api/auth/password-reset/request/confirm/ | users | public | Send code | Working (script/HTTP only) | test_verification_flows | request sent from UI once (200) |
| Farmer | View profile | /farmer/profile | GET /api/farmers/profile/ | farmer_profiles, users | farmer | open tab | Working (live UI, read/render) | test_farmer_panel (39) | PASS |
| Farmer | Edit profile / farm setup / farm location | /farmer/profile | PUT/PATCH /api/farmers/profile/ | farmer_profiles, farms | farmer | Edit | Working (script/HTTP only) | test_farmer_panel | not driven |
| Farmer | Profile photo upload (validation) | /farmer/profile (Change profile photo) | POST/DELETE /api/auth/profile-photo/ | users.profile_photo_url | farmer | Change profile photo | Working (script/HTTP only) | test_profile_photo (58), profile_photo_test.dart; live HTTP: PHP-as-PNG, JPG/PNG mismatch, 8 MB → 400 | button opened; file picker not driven |
| Farmer | Farm photos | profile | POST /api/farmers/profile/upload-photo/ | farmer_profiles.farm_photos | farmer | upload | Working (script/HTTP only) | test_farmer_panel | not driven |
| Farmer | Flock / batch / shed setup | /farmer/feed-management/flocks(/:id) | /api/farmers/flocks/, /sheds/, /flocks/<id>/events/ | flocks, sheds, flock_events | farmer | Add flock | Working (script/HTTP only) | test_flock_feed_management (17) | route renders; form not driven |
| Farmer | Mortality / vaccine history / biosecurity notes | — | — | flock_events only | — | — | Missing | — | no dedicated feature |
| Farmer | Notifications | AppBar bell | GET/PATCH /api/notifications/ | notifications | any auth | open bell | Working (live UI, read/render) | — | PASS (GET 200, PATCH read 200) |
| Farmer | Dashboard: revenue/expense/profit/cash/alerts/nav cards | /farmer | GET /api/farmers/dashboard/ | expenses, revenues, flocks, loans, tax_* | farmer | view | Working (live UI, read/render) | test_dashboard_integrity_and_seed_idempotency (13), farmer_dashboard_*_test.dart | PASS — UI numbers equal API |
| Farmer | Due tax / loan balance / labour cost / feed cost / medicine cost on dashboard | /farmer, /farmer/cost-management | GET /api/farmers/dashboard/, /costs/dashboard/, /tax/summary/ | expenses.category, loans, tax_payments | farmer | view | Working (live UI, read/render) | test_cost_dashboard_charts (20) | PASS (cost sections render) |
| Farmer | Cost Management: add expense (feed, medicine, labour, utilities, chicks, vaccines, litter, transport, repairs) | /farmer/cost-management/expenses | POST /api/farmers/costs/expenses/ | expenses, expense_categories (12) | farmer | Add expense dialog | Working (live UI + script) | test_farmer_panel | PASS — UI-driven: POST 201, row verified via API, then deleted |
| Farmer | Edit / delete / pay expense; receipt upload | expenses list | PUT/DELETE /costs/expenses/<id>/, POST /<id>/pay/, /upload-receipt/ | expenses | farmer | Edit, Pay | Working (script/HTTP only) | test_farmer_panel, test_labour_payment (27) | Edit/Pay buttons opened |
| Farmer | Revenue entry (bird/egg sales, other) | /farmer/cost-management/revenue | POST /api/farmers/costs/revenue/ | revenues (36), revenue_sources | farmer | Add revenue | Working (script/HTTP only) | test_farmer_panel | route opened |
| Farmer | Loans (create, installments) | /farmer/cost-management/loans | GET/POST /api/farmers/costs/loans/ | loans, loan_installments | farmer | Add loan | Working (script/HTTP only) | test_farmer_panel | route opened |
| Farmer | Inventory / batches linkage | /farmer/cost-management/inventory | GET /costs/inventory/, /costs/batches/ | feed_stock, flocks | farmer | view | Working (live UI, read/render) | test_flock_feed_management | route opened |
| Farmer | Reports: profit-loss, CSV and PDF export | /farmer/cost-management/reports | GET /api/farmers/costs/reports/?type=…&export=csv/pdf | expenses, revenues | farmer | CSV / PDF buttons | Working (live UI, read/render) | cost_charts_test.dart | PASS — both exports returned 200 in browser |
| Farmer | Period ranges lifetime / monthly / yearly / custom | /farmer/cost-management | GET /costs/dashboard/?period= | — | farmer | segment buttons | Not verified | test_cost_dashboard_charts | buttons clickable; only `period=lifetime` requests observed in capture |
| Farmer | Charts | /farmer/cost-management | — | — | farmer | view | Not verified | cost_charts_test.dart (widget) | rendered text totals; chart pixels not asserted |
| Farmer | Cashout request | cost mgmt | POST /api/farmers/costs/cashout/ | payments, cashout_reviews | farmer | Cash out | Working (script/HTTP only) | test_finance_admin (35) | not driven |
| Farmer | Tax: summary, calculator, profile, payments | /farmer/tax, /tax/calculator, /tax/profile, /tax/payments | /api/farmers/tax/* | tax_profiles, tax_payments, tax_records (0) | farmer | tabs | Working (live UI, read/render) | test_tax_calculator (64), tax_flow_test.dart | PASS — "Estimated tax for 2026 … ৳4,000, paid ৳67,000" rendered |
| Farmer | Labour management (workers, attendance, payments) | /farmer/labor (+pay-review/method/checkout/result) | /api/farmers/labor/* | workers, worker_attendance, worker_payments | farmer | Home / Workforce | Working (live UI, read/render) | test_labour_payment (27) | PASS render; payment flow not driven |
| Farmer | Feed management (stock, consumption, schedules, notifications) | /farmer/feed-management | /api/farmers/feed/* | feed_stock, feed_consumption, feed_schedules (0) | farmer | Home | Working (live UI, read/render) | test_flock_feed_management, test_feed_stock_integrity (29) | PASS render |
| Farmer | Feed marketplace: browse, search, filter, detail, images, qty ≥ MOQ, stock validation | /farmer/feed-management/marketplace | GET /api/farmers/feed-catalogue/products/(<id>/) | feed_products (26), feed_companies | farmer | Filters, Add to cart | Working (live UI, read/render) | test_feed_catalogue (22), test_feed_marketplace_ux (20), feed_*_fixes_test.dart | PASS render (15 products) |
| Farmer | Feed order checkout / confirmation / history | marketplace → cart | POST/GET /api/farmers/feed-catalogue/orders/, POST /<id>/cancel/ | JSON order records + delivery_orders, feed_stock | farmer | Checkout | Working (script/HTTP only) | test_feed_order_delivery (26), test_feed_stock_integrity; live HTTP race: 6 parallel over-stock orders → 1×201, 5×409, stock restored on cancel | checkout not driven |
| Farmer | Feed order delivery tracking | orders screen | GET /api/farmers/feed-catalogue/orders/<id>/ | delivery_orders | farmer | view | Not verified | test_feed_order_delivery (status mirror) | not driven |
| Farmer | Pharmacy marketplace: browse, search, filter, detail | /farmer/pharmacy | GET /api/farmers/medicines/search/, /pharmacies/ | pharmacy_catalogue_medicines, backend_admin_records | farmer | search, Add to cart | Working (live UI, read/render) | test_pharmacy_flow (22), test_pharmacy_marketplace_card_fields (13) | PASS render — **includes test products (F-011)** |
| Farmer | Pharmacy order checkout / history / cancel | pharmacy cart | POST/GET /api/farmers/orders/, /<id>/cancel/pay/ | JSON order records | farmer | Checkout | Working (script/HTTP only) | test_pharmacy_flow | not driven |
| Farmer | Prescription upload for Rx items | pharmacy | POST /api/farmers/prescriptions/upload/ | — | farmer | Upload | Working (script/HTTP only) | test_pharmacy_flow | not driven |
| Farmer | Disease detection: upload, prediction, confidence, severity, case history | /farmer/disease-detection | POST /api/ml/predict-disease/, GET /api/ml/scans/(<id>/) | disease_scans (89), diseases (16) | farmer (+ throttle 30/h) | Choose File | Working (live UI, read/render) | test_disease_detection (25), disease_detection screen tests | history of 5 scans rendered with confidence; upload/camera not driven (headless) |
| Farmer | Disease: image quality validation / multi-image | — | — | — | — | — | Partial | test_disease_detection | single image only; quality gate = "uncertain / needs closer look" state |
| Farmer | Disease: chatbot, follow-up questions, isolation advice, emergency warning | assistant sheet | — (client-side from scan result) | chatbot_* (0, proxies) | farmer | Ask chatbot | Partial | — | static advice sheet (what to do / avoid / prevention); **no chatbot API or follow-ups (F-016)** |
| Farmer | Disease: vet escalation | result → Book Vet | → /farmer/find-vet/discover | — | farmer | Book Vet | Working (live UI, read/render) | — | button present |
| Farmer | Disease: free limit / subscription / payment | /subscription (+review/pay/checkout/result) | GET /api/subscriptions/plans/current/, POST /checkout/, /api/payments/* | subscription_plans, subscriptions, billing_payment_intents, payments | farmer | Become a Pro Farmer | Working (live UI + script) | test_subscription_payment (65), subscription_flow_test.dart | PASS — plans screen reached from dashboard banner; payment steps script-only |
| Farmer | Disease: report download / feedback | — | — | — | — | — | Missing | — | not implemented |
| Farmer | Disease: disclaimer | result screen | — | — | farmer | view | Working (live UI, read/render) | — | "AI estimate … not a diagnosis" rendered |
| Farmer | Find Vet: list, filters (fee/rating/distance), profile, map | /farmer/find-vet(/discover) | GET /api/consultations/vets/(<id>/), /vets/nearby/ | doctor_profiles (9) | farmer | Discover tab | Working (live UI, read/render) | test_find_vet_discovery (38), test_vets_nearby (12), find_vet_screen_test.dart | PASS render; location-permission-denied state ("Open settings") shown in headless Chrome; map tiles not asserted |
| Farmer | Book consultation (online/in-person, slot, flock details, case) | vet booking dialog | GET /vets/<id>/booking-options/, POST /api/consultations/ | consultations, consultation_case_details | farmer | Book | Working (script/HTTP only) | test_consultation_booking_rules (29), vet_booking_dialog_overflow_test.dart | not driven |
| Farmer | Consultation payment, receipt | My Consultations | POST /consultations/<id>/mark-paid/, GET /receipt/ | payments, consultations | farmer | Pay | Working (script/HTTP only) | test_consultation_transitions_and_receipts (53) | not driven; IDOR checked (receipt 403/404 for others) |
| Farmer | Consultation chat (REST + Socket.IO) | /farmer/find-vet/chats | /api/consultations/chats/(<id>/), Socket.IO | conversations, messages | farmer | Chats tab | Working (live UI, read/render) | test_consultation_chat_access (13), test_doctor_flow | tab opened (list loads); realtime not driven |
| Farmer | Video call | consultation | GET /consultations/<id>/video/ | consultations.video_room | farmer | Join | Partial | test_doctor_flow | Jitsi URL issued (participants only); call itself not verified; `video_calls` table unused (F-021) |
| Farmer | Follow-up, rating/review, dispute | My Consultations | POST /consultations/<id>/action/, /disputes/ | follow_ups (0), consultation_disputes (0) | farmer | actions | Working (script/HTTP only) | test_consultation_transitions_and_receipts | not driven; no live rows |
| Farmer | Community feed (latest/trending/following), categories, search | /community, /community/search | GET /api/community/(latest/trending/following/search/categories/hashtags)/ | posts (31), post_categories | any auth | tabs | Working (live UI, read/render) | test_community (56), test_community_feed_performance (20) | PASS render (feed with posts + images) |
| Farmer | Create post (text/poll/question), media, hashtags, mentions | /community/create | POST /api/community/, /community/upload/ | posts | any auth (mute check) | Create | Working (script/HTTP only) | test_community | not driven; **raw HTML stored (F-010)** |
| Farmer | Comments, replies, reactions, reposts, bookmarks, polls/votes, best-answer | /community/post/:id | POST /community/(comment/react/repost/bookmark/vote)/, PATCH /comments/<id>/best-answer/ | comments, reactions, bookmarks, posts | any auth | buttons | Working (script/HTTP only) | test_community | not driven |
| Farmer | Reports, mute, block, follow, official updates | community | POST /community/report/follow/, /blocks/ | reports, follows, user_blocks (0) | any auth | — | Working (script/HTTP only) | test_community; admin side test_admin_panel | not driven |
| Farmer | Research/news: browse, search, read, bookmark, farmer summary | /paper-portal | GET /api/articles/all/tags/, /articles/<type>/<id>/, POST /research/bookmark/ | articles (22), bookmarks | public read; bookmark auth | — | Working (script/HTTP only) | test_articles_feed (28); live HTTP workflow (steps 14–19 PASS) | farmer UI for articles not driven in browser |
| Farmer | Research PDF download / share / notifications of new research | — | articles.pdf_url | articles | — | — | Not verified | — | pdf_url field exists; no download counter; share not verified |
| Farmer | Support tickets | — | GET/POST /api/support/tickets/ | support_tickets | any auth | — | Working (script/HTTP only) | test_admin_panel | no Flutter screen found for farmer ticketing (route table) |

### Doctor

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Doctor | Signup + credentials upload + verification | /signup/doctor | POST /api/auth/register/ (+uploads) | users, doctor_profiles, signup_documents | public | wizard | Working (script/HTTP only) | test_signup_flows, test_signup_documents (46), test_verification_flows | not driven |
| Doctor | Login / logout / relogin / reload | /login, /doctor | POST /api/auth/login/ | users | doctor | — | Working (live UI, read/render) | — | PASS ("Log Out" in profile) |
| Doctor | Dashboard (clients, today appts, cases, unread, schedule) | /doctor | GET /api/doctor/dashboard/ | consultations | doctor | view | Working (live UI, read/render) | test_doctor_flow (58), doctor_dashboard_*_test.dart | PASS real data ("Dr. Mahfuz Kabir, 3 clients"); **non-doctors see hard-coded demo data (F-008)** |
| Doctor | Availability toggle & slots | /doctor (toggle), profile | POST/DELETE/GET /api/doctor/availability/ | doctor_availability_slots (12) | doctor | Available switch | Working (script/HTTP only) | test_doctor_flow | toggle not clicked (excluded as state-changing) |
| Doctor | Appointments calendar / filter (All/Pending/Accepted/Completed/Rejected/No-show) | /doctor/appointments | GET /api/doctor/appointments/ | consultations | doctor | tabs | Working (live UI, read/render) | test_doctor_flow | PASS |
| Doctor | Accept / reject / reschedule / complete / no-show | appointments | POST /api/doctor/appointments/<id>/action/ | consultations, consultation_status_history | doctor | action buttons | Working (live UI + script) | test_consultation_transitions_and_receipts (53) | Endpoint exercised from the UI by the crawler (`accepted→no_show`, 200; side effect S-4) |
| Doctor | Online / offline / in-person modes | booking | consultations.mode | consultations | doctor/farmer | — | Working (script/HTTP only) | test_consultation_booking_rules | not driven |
| Doctor | Client chat (messenger), images/files | /doctor/messenger | /api/doctor/conversations/(<id>/), Socket.IO | conversations, messages | doctor | — | Working (live UI, read/render) | test_consultation_chat_access | render PASS; attachments not verified |
| Doctor | Video consultation | /doctor/video | POST/GET /api/doctor/appointments/<id>/video/ | consultations.video_room | doctor | Start | Partial | test_doctor_flow | Jitsi room URL only (F-021) |
| Doctor | Case notes (symptoms, diagnosis, treatment, poultry/flock fields) | /doctor/case-notes | POST/PATCH/GET /api/doctor/cases/(<id>/) | consultation_case_details, consultation_notes | doctor | Case Detail | Working (live UI, read/render) | test_doctor_flow | render PASS; edit not driven |
| Doctor | Prescriptions, PDF, resend e-mail | /doctor/prescriptions | POST/GET /api/doctor/prescriptions/, GET /consultations/prescriptions/<id>/pdf/, POST /resend-email/ | clinical_prescriptions (0), clinical_prescription_items (0) | doctor | Issue prescription | Working (script/HTTP only) | test_doctor_flow | render PASS; no live rows |
| Doctor | Follow-ups | /doctor/followups | POST/PATCH/GET /api/doctor/follow-ups/ | follow_ups (0) | doctor | — | Working (script/HTTP only) | test_doctor_flow | render PASS; no live rows |
| Doctor | Referrals | — | — | — | — | — | Missing | — | not implemented |
| Doctor | Earnings / payout request / ratings | /doctor/earnings | GET/POST /api/doctor/earnings/ | doctor_earnings (2), doctor_payout_requests (0) | doctor | Request Payout | Working (live UI, read/render) | test_doctor_flow, doctor_rating_label_test.dart | PASS render (৳0 values) |
| Doctor | Disputes | — | /api/doctor/disputes/ | consultation_disputes (0) | doctor | — | Working (script/HTTP only) | test_consultation_transitions_and_receipts | not driven |
| Doctor | Profile edit (+photo) | /doctor/profile | PATCH /api/doctor/profile/ | doctor_profiles | doctor | Edit | Working (script/HTTP only) | doctor_dashboard_profile_test.dart | route opened |
| Doctor | Cross-doctor / cross-farmer denial | — | — | — | doctor | — | Working (live UI + script) | test_consultation_chat_access | PASS (video, receipt, clinical results IDOR checks) |

### Pharmacy owner

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Pharmacy owner | Signup, business profile, documents | /signup/pharmacy | POST /api/auth/register/, GET/PATCH /api/pharmacy/profile/ | users, pharmacy_organizations, signup_documents | public / pharmacy | wizard | Working (script/HTTP only) | test_signup_flows, test_signup_documents, test_pharmacy_profile (32) | not driven |
| Pharmacy owner | Pending / locked state, locked features, review state | panel banner | GET /api/pharmacy/permissions/, /verification-status/ | pharmacy_organizations.review_state | pharmacy | banner | Working (script/HTTP only) | test_pharmacy_admin (132) | demo "pending" accounts are actually approved+active, so the lock banner could not be shown live (F-029) |
| Pharmacy owner | Login (active) / logout / relogin / reload | /pharmacy | POST /api/auth/login/ | — | pharmacy | — | Working (live UI, read/render) | — | PASS (Sign out in AppBar) |
| Pharmacy owner | Login while suspended | /login | login + /api/me/updates/ | users.account_status | pharmacy | — | Broken | test_pharmacy_admin (API only) | **BROKEN in UI — silently returned to /login (F-002)** |
| Pharmacy owner | Earnings summary | /pharmacy (card) | GET /api/pharmacy/earnings/ | pharmacy_sales (0) | pharmacy | view | Working (live UI, read/render) | test_pharmacy_admin | PASS ("Lifetime earnings ৳0.00") |
| Pharmacy owner | Pharmacy-Admin chat | support chat screen (from locked banner) | /api/pharmacy/support-conversation/(<id>/) | conversations, messages | pharmacy | Contact admin | Working (script/HTTP only) | test_pharmacy_admin | not reachable without lock banner; not driven |
| Pharmacy owner | Appeal / revision | PharmacyAppealScreen | GET/POST /api/pharmacy/appeals/ | pharmacy_appeals (0) | pharmacy | Appeal | Working (script/HTTP only) | test_pharmacy_admin | not reachable for a suspended owner (F-002) |
| Pharmacy owner | Medicines catalogue: add/edit/delete, categories, image upload, bulk upload | /pharmacy (Catalogue tab) | /api/pharmacy/medicines/(<id>//upload-image/bulk-upload) | pharmacy_catalogue_medicines, backend_admin_records | pharmacy | Add | Working (live UI, read/render) | test_pharmacy_medicine_edit (7), test_pharmacy_medicine_images (20), card_fields (13) | PASS render ("No medicines yet" for AgroCare); create not driven |
| Pharmacy owner | Inventory: stock, price, low-stock, expiring-soon, alerts | Inventory tab | PATCH /medicines/<id>/stock/price, GET /inventory/* | pharmacy_expiry_alerts (0) | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_flow | PASS render |
| Pharmacy owner | Orders: incoming/preparing/delivery/completed/cancel; confirm; ready-for-delivery | Orders tab | GET /api/pharmacy/orders/, POST /orders/<id>/confirm/cancel/ready-for-delivery | JSON order records (+ medicine_orders 0) | pharmacy | tabs; Cancel order dialog opened and declined | Working (live UI, read/render) | test_pharmacy_flow (22), test_pharmacy_admin | PASS render of 1 pending order; status changes script-only |
| Pharmacy owner | Delivery of pharmacy orders (rider, OTP) | — | delivery_orders (order_type medicine) | delivery_orders | pharmacy/rider | — | Working (script/HTTP only) | test_delivery_multi_active (34), test_delivery_proof_and_earnings (24) | not driven |
| Pharmacy owner | Suppliers | Suppliers tab | /api/pharmacy/suppliers/(<id>/) | pharmacy_suppliers (8) | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_flow | PASS render |
| Pharmacy owner | Analytics (sales/top products/revenue) | Analytics tab | GET /api/pharmacy/analytics/* | pharmacy_sales (0) | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_flow | PASS render (zeros) |
| Pharmacy owner | Employees roster | — | — | pharmacy_employees (0) | admin-managed | — | Partial | test_pharmacy_admin | roster only; no employee login (F-032) |
| Pharmacy owner | Sales, 20/80 commission, settlements | — | /api/admin/pharmacies/(sales/commissions)/ | pharmacy_sales/commissions/settlements (0) | pharmacy admin | — | Working (script/HTTP only) | test_pharmacy_admin (132) | no live rows (F-024) |
| Pharmacy owner | Profile edit | Profile tab | PATCH /api/pharmacy/profile/ | pharmacy_organizations | pharmacy | Edit | Working (live UI, read/render) | test_pharmacy_profile (32) | PASS render |
| Pharmacy owner | Cross-pharmacy denial | — | — | — | pharmacy | — | Working (live UI + script) | test_pharmacy_admin | PASS (IDOR checks: medicine/supplier/order) |

### Pharmacy Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Pharmacy Admin | Role routing / shell / sidebar | /admin | GET /api/admin-panel/me/ | roles | admin_pharmacy | login | Working (live UI + script) | test_pharmacy_admin | PASS (sidebar: Dashboard, Earnings, Pharmacy, Audit Trail) |
| Pharmacy Admin | Dashboard (active pharmacies count, recent activity) | /admin | GET /api/admin-panel/dashboard/ | — | admin_pharmacy | view | Working (live UI, read/render) | test_admin_dashboard_metrics (12) | PASS |
| Pharmacy Admin | Overview: account holders / pending / employees / medicines / categories / brands / low / out of stock / sales / commission / deliveries | /admin/pharmacy (Overview) | GET /api/admin/pharmacies/metrics/ | pharmacy_organizations, medicines | pharmacy.view | tab | Working (live UI, read/render) | test_pharmacy_admin | PASS — 5 holders, 0 pending, 13 medicines, ৳0 sales |
| Pharmacy Admin | Pharmacies list; approve / reject / suspend / reactivate; Request Revision | /admin/pharmacy (Pharmacies) | PATCH /api/admin-panel/pharmacies/<id>/, /pharmacy/… | users, pharmacy_organizations | pharmacy.approve/reject/suspend | buttons | Working (script/HTTP only) | test_pharmacy_admin (132) | tabs rendered; state changes not driven (destructive) |
| Pharmacy Admin | Medicine approvals / catalogue | Medicine Approvals | GET /api/admin-panel/pharmacy/medicines/ | pharmacy_catalogue_medicines | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_admin | PASS render |
| Pharmacy Admin | Expiry monitoring | Expiry Monitoring | GET /api/admin-panel/pharmacy/expiry-alerts/ | pharmacy_expiry_alerts | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_admin | PASS render |
| Pharmacy Admin | Orders & delivery assignment; offline-rider warning | Orders & Delivery | GET /api/admin-panel/pharmacy/orders/, /pharmacy-deliveries/, /pharmacy-riders/ | delivery_orders | pharmacy.assign | tab | Working (live UI, read/render) | test_pharmacy_admin | render PASS; **N+1 321 queries (F-012)**; assignment not driven |
| Pharmacy Admin | Chat & appeals | Chat & Appeals | /api/admin-panel/pharmacy-chats/, /pharmacy/appeals/ | conversations, pharmacy_appeals (0) | pharmacy | tab | Working (live UI, read/render) | test_pharmacy_admin | render PASS; no live data |
| Pharmacy Admin | Sales & settlements; 20/80 commission; refunds | Sales & Settlements | GET /api/admin-panel/pharmacy/settlements/, /api/admin/pharmacies/sales/commissions/ | pharmacy_sales/settlements/commissions (0) | pharmacy.refund | tab | Working (live UI, read/render) | test_pharmacy_admin | render PASS with zeros (F-024) |
| Pharmacy Admin | Reports, CSV export, audit viewer | Reports & Audit; /admin/audit | GET /api/admin-panel/pharmacy/audit/, /pharmacy/…export | activity_logs | pharmacy.export, audit.view | tab | Working (live UI, read/render) | test_pharmacy_admin | PASS render; export not downloaded |
| Pharmacy Admin | Back buttons / navigation | all | — | — | — | Back | Working (live UI, read/render) | admin_navigation_test.dart | PASS |
| Pharmacy Admin | Permission restrictions | — | — | — | admin_pharmacy | — | Working (live UI + script) | test_pharmacy_admin; live matrix | PASS (403 on users/finance/feed/etc.) |

### Feed Marketplace Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Feed Marketplace Admin | Role routing / shell / sidebar | /admin | GET /api/admin-panel/me/ | roles | feed_admin | login | Working (live UI + script) | test_feed_owner_flow (32) | PASS (Dashboard, Feed, Clients, Feed Owner Chat, Audit Trail) |
| Feed Marketplace Admin | Dashboard | /admin | GET /api/admin-panel/dashboard/ | — | feed_admin | view | Partial | — | "No overview data for your role" (F-027); activity feed leaks logins (F-009) |
| Feed Marketplace Admin | Feed catalogue: products create/edit, images, approve/reject/suspend | /admin/feed | /api/admin-panel/feed-catalogue/products/ | feed_products | feed-catalogue.* | screen | Working (live UI, read/render) | test_feed_catalogue (22) | PASS render; forms not driven |
| Feed Marketplace Admin | Inventory / stock adjustment | /admin/feed | feed stock endpoints | feed_stock, feed_stock_movements | feed-catalogue.edit | — | Working (script/HTTP only) | test_feed_stock_integrity (29) | not driven |
| Feed Marketplace Admin | Suppliers / companies (Clients) | /admin/feed-clients | /api/admin-panel/feed-catalogue/companies/ | feed_companies (4) | feed-catalogue | screen | Working (live UI, read/render) | test_feed_catalogue | PASS render |
| Feed Marketplace Admin | Orders queue, farmer location, map preview | /admin/feed | GET /feed-catalogue/orders/(<id>/) | delivery_orders | feed-orders.view | screen | Working (script/HTTP only) | test_feed_order_delivery (26) | lat/lng in payload verified by script; map not asserted |
| Feed Marketplace Admin | Assign rider; offline-rider warning | /admin/feed | POST /feed-catalogue/orders/<id>/assign/, GET /riders/available/ | delivery_orders | feed-delivery.assign | — | Working (script/HTTP only) | test_feed_order_delivery, test_delivery_multi_active | not driven |
| Feed Marketplace Admin | Rider route (Google Directions) | rider app | GET /api/delivery/orders/<id>/route/ | — | rider | — | Broken | — | REQUEST_DENIED → 404 (F-003) |
| Feed Marketplace Admin | Arrival, proof review, rejection, resubmission, approval | — | — | — | — | — | Missing | — | not implemented (F-005) |
| Feed Marketplace Admin | Final completion, revenue appears once, Cost Management mirror | — | _sync_feed_order, expenses mirror | expenses, revenues | system | — | Working (script/HTTP only) | test_feed_order_delivery, test_delivery_proof_and_earnings (24) | script-verified only |
| Feed Marketplace Admin | Feed-owner chat inbox (read/unread/resolve/reopen) | /admin/feed-chats | /api/admin-panel/feed-chats/ | conversations, messages | feed_admin | Feed Owner Chat | Working (live UI, read/render) | test_feed_owner_flow | PASS render |
| Feed Marketplace Admin | Reports / audit | /admin/audit | GET /api/admin-panel/audit-logs/ | activity_logs | audit.view | Audit Trail | Working (live UI, read/render) | test_feed_owner_flow | PASS (returns none for feed admin: scoped) |
| Feed Marketplace Admin | Community access | — | — | — | — | — | Missing | — | Feed Admin sidebar has no Community entry (Feed Owner does) |

### Feed Inventory Owner

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Feed Inventory Owner | Login, limited home, inventory context, assigned categories | /feed-owner | GET /api/feed-owner/profile/ | feed_owner_profiles | feed_owner | view | Working (live UI + script) | test_feed_owner_flow (32), feed_owner_smoke_test.dart | PASS |
| Feed Inventory Owner | Chat with Feed Admin (send, read/unread) | /feed-owner → chat | POST/GET/PATCH /api/feed-owner/chat/(<id>/) | conversations, messages | feed_owner | Chat button | Working (live UI + script) | test_feed_owner_flow | PASS — conversation POST 200 + read PATCH 200 in browser |
| Feed Inventory Owner | Resolve / reopen; attachments | admin side /admin/feed-chats | PATCH …/chat/<id>/ | conversations | feed_admin/feed_owner | — | Working (script/HTTP only) | test_feed_owner_flow | attachments not supported/verified |
| Feed Inventory Owner | Community access / feed-related posts | Community button | GET /api/community/ | posts | any auth | Community | Working (live UI, read/render) | test_community | PASS — community feed opened, Feed Admin announcement visible |
| Feed Inventory Owner | No unrelated admin access (server-side) | — | /api/admin-panel/* | — | feed_owner | — | Working (live UI + script) | test_feed_owner_flow; live matrix | PASS (all admin routes 403; `#/admin` shows 403 shell — F-007) |
| Feed Inventory Owner | Refresh / relogin persistence | — | — | — | — | — | Working (live UI, read/render) | — | PASS |

### Delivery rider

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Delivery rider | Signup + license + vehicle + verification | /signup/delivery | POST /api/auth/register/ | users, delivery_profiles, delivery_vehicle_details (0), signup_documents | public | wizard | Working (script/HTTP only) | test_signup_flows, test_signup_documents, test_verification_flows | not driven |
| Delivery rider | Login / reload / logout / relogin | /delivery | — | — | delivery | Profile tab → Log Out | Working (live UI, read/render) | — | PASS |
| Delivery rider | Online/offline toggle & availability | dashboard chip | PATCH /api/delivery/availability/ | delivery_profiles.is_online | delivery | Offline/Online | Working (live UI + script) | test_delivery_multi_active (34) | PASS — toggled by crawler (PATCH 200); later restored (S-2) |
| Delivery rider | Attendance check-in/out, calendar | /delivery/attendance | PATCH /attendance/checkin/checkout, GET /attendance/ | delivery_attendance (6) | delivery | Check In | Working (live UI, read/render) | test_delivery_multi_active | PASS render |
| Delivery rider | Order queue / requests; accept / reject | dashboard, /delivery/orders | GET /requests/, PATCH /requests/<id>/respond/ | delivery_orders (36) | delivery | Accept/Reject | Working (script/HTTP only) | test_feed_order_delivery, test_delivery_multi_active | active order card rendered; accept/reject not driven |
| Delivery rider | Pickup → on-the-way → delivered / failed (reason) | order detail | PATCH /orders/<id>/status/ | delivery_orders | delivery | status buttons | Working (script/HTTP only) | test_delivery_proof_and_earnings (24) | not driven; state machine 409s verified |
| Delivery rider | Route / map | /delivery/map | GET /orders/<id>/route/ | — | delivery | Map tab | Broken | — | 404 (F-003); `PATCH /location/` capture works (script) |
| Delivery rider | Arrival marker | — | — | — | — | — | Missing | — | no arrival state (F-005) |
| Delivery rider | Proof photo upload (mandatory) with signed token | order detail | POST /api/delivery/proof-upload/ | delivery_orders.proof_of_delivery_url | delivery | Upload | Working (script/HTTP only) | test_delivery_proof_and_earnings | verified: delivered without proof → 400; invalid token → 400 |
| Delivery rider | OTP (pharmacy orders) / signature | order detail, SignaturePadScreen | otp_code in status PATCH | delivery_orders.otp_code | delivery | OTP field | Working (script/HTTP only) | test_delivery_proof_and_earnings | feed orders have no OTP; signature has no storage |
| Delivery rider | Contact actions (call customer) | dashboard Call button | tel: | — | delivery | Call | Working (live UI, read/render) | — | button present |
| Delivery rider | Earnings, payouts, performance | /delivery/earnings; Performance screen | GET /api/delivery/earnings/ | delivery_earnings (9) | delivery | Earnings tab | Working (live UI, read/render) | test_delivery_proof_and_earnings | PASS render; bonuses/penalties columns exist (0), no UI |
| Delivery rider | Pharmacy vs feed handling | — | _sync_pharmacy_order / _sync_feed_order | — | system | — | Working (script/HTTP only) | test_feed_order_delivery, test_pharmacy_flow | script-verified |
| Delivery rider | Permission restrictions | — | — | — | delivery | — | Working (live UI + script) | live IDOR (route/status of others → 404) | PASS |

### Researcher

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Researcher | Signup + credentials + verification | /signup/researcher | POST /api/auth/register/ | users, researcher_profiles | public | wizard | Working (script/HTTP only) | test_signup_flows, test_verification_flows | not driven |
| Researcher | Login / reload / logout / relogin | /research | — | — | researcher | Sign Out | Working (live UI, read/render) | — | PASS |
| Researcher | Dashboard, workspace, sidebar (10 routes) | /research, /papers, /diseases, /innovations, /search, /collaboration, /analytics, /review, /profile | GET /api/research/(papers/disease-updates/innovations/profile/bookmarks)/ | articles, researcher_profiles | researcher | sidebar | Working (live UI, read/render) | — | PASS — 146 controls clicked, 0 errors (but 615 API calls, F-013) |
| Researcher | Create/edit draft paper, co-authors, tags, farmer summary | /research/new-paper | POST/PUT /api/research/papers/(<id>/) | articles (co_authors JSON), article_tags | researcher (verified+premium) | New paper | Working (script/HTTP only) | **no test script (F-017)**; ad-hoc HTTP workflow steps 1–3, 10 PASS | forms not driven in browser |
| Researcher | PDF upload | /research/new-paper | POST /api/research/upload-pdf/ | media | researcher | Upload PDF | Not verified | — | not tested (≤25 MB, PDF-only per code) |
| Researcher | Submit for review / revision / resubmit / publish | /research/review | POST …/submit-review/, admin PATCH research-papers/<id>/ (approve/request_revision) | articles, article_version_snapshots (7) | researcher; research/content admin | — | Working (script/HTTP only) | HTTP workflow steps 5–13 PASS | review area screen rendered |
| Researcher | Version history | paper detail | GET /api/research/papers/<id>/versions/ | article_version_snapshots | researcher (owner) | — | Working (script/HTTP only) | HTTP step 12 PASS (2 versions) | — |
| Researcher | Disease/cure updates & innovation posts | /research/diseases, /innovations | kind=disease-updates/innovations | articles | researcher | — | Working (live UI, read/render) | — | render PASS |
| Researcher | Comments on papers | — | — | — | — | — | Missing | — | no comment endpoints on research content |
| Researcher | Notifications (revision, publish) | bell | GET /api/notifications/ | notifications | researcher | — | Working (script/HTTP only) | HTTP workflow (3 notifications received) | wording: needs_revision shown as "hidden" (F-034) |
| Researcher | Search & discovery / saved papers | /research/search | GET /api/articles/all/?search=, /research/bookmarks/ | bookmarks | any | Search | Working (live UI, read/render) | test_articles_feed (28) | render PASS; search HTTP PASS |
| Researcher | Analytics | /research/analytics | profile stats (counts, views) | articles.views_count | researcher | — | Working (live UI, read/render) | — | render PASS; downloads not tracked |
| Researcher | Collaboration | /research/collaboration | — | — | researcher | — | Partial | — | screen present, no dedicated backend |
| Researcher | Permission restrictions (other researcher, unverified, non-premium) | — | — | — | researcher | — | Working (live UI + script) | live IDOR + HTTP step 4/20 | PASS |

### Super Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Super Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | wildcard `*` — every module (Users, Doctors, Delivery, Pharmacy, Feed, Clients, Feed Owner Chat, Team, Research & Articles, Community, Finance, Subscriptions, Cashouts pending/approved, Support, Approvals, Audit, Admins, Oversight, Earnings…) | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Operations Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Operations Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | users, doctors, finance (view/export), support, articles, delivery, pharmacy (full), research, community, settings, approvals, oversight, escalations, subscriptions (view/export), team (view), audit (view/export) | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Finance Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Finance Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | finance (view/edit/refund/export/approve), cashouts (view/review/approve/reject), subscriptions (view/edit/approve/refund/export/manage), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Content Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Content Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | articles (view/create/edit/approve/reject/delete), research (view/approve/reject), community (view/edit/reject/suspend/delete), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Research Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Research Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | articles (view/create/edit/approve/reject — **no delete**), research (view/create/edit/approve/reject/suspend), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Delivery Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Delivery Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | delivery (view/edit/approve/reject/assign/suspend/export/refund), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Doctor Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Doctor Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | doctors (view/edit/approve/reject/suspend/export), support view, escalations view, audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Team Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Team Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | team (view/create/edit/assign/suspend), approvals view, audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Support Agent

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Support Agent | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | users view, doctors view, community view, support (view/create/edit/assign), escalations (create/view), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Pharmacy Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Pharmacy Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | pharmacy (full incl. refund/delete), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### Feed Marketplace Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Feed Marketplace Admin | Permitted modules (server `roles.permissions`) | /admin/* | GET /api/admin-panel/me/ | roles.permissions JSON | tier-based | feed-catalogue (view/create/edit/approve/reject/suspend/delete/export), feed-orders (view/edit/assign/export), feed-delivery (view/assign), audit view | Working (live UI + script) | test_admin_panel (66), test_finance_admin (35) | PASS — live login + sidebar + 403 matrix |

### All admin roles

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| All admin roles | Hidden modules → server denial | /admin/<module> | 403 from /api/admin-panel/<module>/ | — | ModulePermission | open URL directly | Partial | live matrix (0 violations) | server denies (PASS); UI still paints the shell first (F-007/F-038) |

### All hourly admin roles

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| All hourly admin roles | Shift start/end/break, my earnings/payments | Dashboard shift card, /admin/earnings | /api/admin-panel/my-shift/* | admin_shifts, admin_payments (129) | hourly admins | Start Shift | Working (live UI, read/render) | test_admin_earnings (29) | Start Shift worked (201) — ended afterwards via API; stale shift for Ops since 2026-09-16 (F-020) |

### Super Admin / Ops

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Super Admin / Ops | Oversight, escalations, approvals queue, admins, payroll | /admin/oversight, /approvals, /admins, /payroll | /api/admin-panel/(oversight/escalations/approval-queue/admins/all-admins/admin-payments)/ | admin_escalations (88), admin_approval_queue (90) | tier ≤2 | sidebar | Working (live UI, read/render) | test_admin_panel | render PASS |

### Doctor Admin / Super / Ops / Support

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Doctor Admin / Super / Ops / Support | Doctors & Patients (list, pending, consultations, disputes) | /admin/doctors | /api/admin-panel/(doctors/consultations/consultation-disputes)/ | doctor_profiles, consultations | doctors.* | tabs | Broken | test_admin_pagination_performance (FAILS) | **500 → "No doctors found" (F-001)** |

### Finance Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Finance Admin | Finance dashboard, payments, subscriptions, cashouts (pending/approved) | /admin/finance, /subscriptions, /cashouts/* | /api/admin-panel/finance/*, /cashouts/*, /subscription-plans/ | payments, subscriptions, cashout_reviews | finance/cashouts/subscriptions | sidebar | Working (live UI, read/render) | test_finance_admin (35), admin_finance_test.dart | PASS — 85 controls, 0 errors |

### Content / Research Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Content / Research Admin | Articles/research moderation, community reports | /admin/content, /community | /api/admin-panel/(articles/research-papers/community-reports/…)/ | articles, reports | articles/community | sidebar | Working (live UI, read/render) | test_admin_panel, test_community | PASS (70 / 51 controls, 0 errors); crawler dismissed 1 content report (S-3) |

### Delivery Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Delivery Admin | Riders, delivery orders, payouts | /admin/delivery | /api/admin-panel/(riders/delivery-orders/payouts)/ | delivery_profiles, delivery_orders | delivery.* | sidebar | Working (live UI, read/render) | test_admin_panel, test_delivery_* | PASS (68 controls, 0 errors); crawler cancelled 4 queued orders via Super Admin (S-3) |

### Team Admin

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Team Admin | Team / admins management | /admin/team, /admins | /api/admin-panel/(team/admins)/ | admin_profiles | team.* | sidebar | Working (live UI, read/render) | test_admin_panel | PASS (62 controls, 0 errors) |

### Support Agent

| Role | Feature | Screen/route | API endpoint | Model/table | Permission | UI action | Status | Automated test | Live test |
|---|---|---|---|---|---|---|---|---|---|
| Support Agent | Support & Safety tickets / escalations | /admin/support | /api/admin-panel/(support-tickets/escalations)/ | support_tickets, admin_escalations | support.* | sidebar | Partial | test_admin_panel | PASS render but shares the F-001 500 on Doctors page |


## Part B — Individual UI actions observed in the browser (per-role control inventory)

Counts of distinct on-screen controls clicked per role (depth 0 + depth 1) with result classification. The full per-control table (route, API request, response code, screenshot, notes) is in `FEATHERFLOW_LIVE_BROWSER_VERIFICATION.md` §2.

| Role session | Controls exercised | PASS | NO-EFFECT | WARN | FAIL | Skipped (destructive/state-changing) |
|---|---:|---:|---:|---:|---:|---:|
| admin_content (`content.admin@featherflow.dev`) | 70 | 46 | 20 | 0 | 0 | 4 |
| admin_delivery (`delivery.admin@featherflow.dev`) | 68 | 42 | 22 | 0 | 0 | 4 |
| admin_doctor (`doctor.admin@featherflow.dev`) | 79 | 44 | 23 | 0 | 8 | 4 |
| admin_finance (`finance.tanvir@example.com`) | 85 | 77 | 7 | 0 | 0 | 1 |
| admin_operations (`ops.nusrat@example.com`) | 188 | 122 | 52 | 0 | 8 | 6 |
| admin_pharmacy (`pharmacy.admin@featherflow.local`) | 60 | 35 | 21 | 0 | 0 | 4 |
| admin_research (`research.admin@featherflow.dev`) | 51 | 27 | 20 | 0 | 0 | 4 |
| admin_super (`admin.super@example.com`) | 222 | 130 | 78 | 0 | 13 | 1 |
| admin_support (`support.raisa@example.com`) | 138 | 85 | 46 | 0 | 6 | 1 |
| admin_team (`team.admin@featherflow.dev`) | 62 | 43 | 14 | 0 | 0 | 5 |
| delivery (`rider.arif@example.com`) | 12 | 7 | 5 | 0 | 0 | 0 |
| delivery_pending (`rider.pending.belal@example.com`) | 10 | 6 | 4 | 0 | 0 | 0 |
| doctor (`dr.mahfuz.kabir@example.com`) | 23 | 7 | 16 | 0 | 0 | 0 |
| doctor_pending (`dr.pending.kabir@example.com`) | 17 | 5 | 12 | 0 | 0 | 0 |
| farmer (`farmer.rashed@example.com`) | 57 | 39 | 17 | 1 | 0 | 0 |
| feed_admin (`feed.admin@featherflow.local`) | 53 | 35 | 15 | 0 | 0 | 3 |
| feed_owner (`feed.owner@featherflow.local`) | 3 | 1 | 1 | 0 | 0 | 1 |
| pharmacist (`pharmacist.demo@example.com`) | 42 | 2 | 12 | 28 | 0 | 0 |
| pharmacy_owner (`pharmacy.agrocare@example.com`) | 12 | 6 | 5 | 0 | 0 | 1 |
| pharmacy_pending (`pharmacy.pending.agrocare@example.com`) | 12 | 6 | 5 | 0 | 0 | 1 |
| pharmacy_suspended (`smoke.pharmacy@featherflow.dev`) | 5 | 2 | 3 | 0 | 0 | 0 |
| researcher (`research.fariha@example.com`) | 146 | 130 | 15 | 0 | 0 | 1 |
| researcher_pending (`research.pending.mahmud@example.com`) | 119 | 97 | 21 | 0 | 0 | 1 |
| researcher_suspended (`research.sabiha@example.com`) | 119 | 97 | 21 | 0 | 0 | 1 |