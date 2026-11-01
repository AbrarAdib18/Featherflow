# Featherflow full eight-role matrix (fresh isolated database)

Written for: the engineer deciding release readiness. HEAD is still `6a036eb`; nothing was committed or pushed.

**Environment.** Database `featherflow_matrix`: built from scratch by the F-014 bootstrap (SQL manifest + migrations + reference data) plus the create-only demo seeds - not a clone, not the development database. API (uvicorn) on `127.0.0.1:8000`, release web build on `:8080` (Maps key loaded from the git-ignored `web/config.js`), headless Chrome/Playwright against the Flutter semantics tree. Offer window set per phase (300 / 900 / 45 s). Evidence: `audit_logs/matrix/` (workflow JSON with request/response ledgers and DB before/after, screenshots, `aborted_runs/`).

**Set-up through the ORM (not verification steps, labelled):** fresh farmer `regr.farmer`, riders `regr.rider`/`regr.rider2`, the suspended pharmacy, the empty pharmacy, prescription authority for the doctor, verified contacts for three seeded research-demo users (the seed was fixed so new databases do not need this). **API-assisted checks (labelled):** duplicate proof approval (409), negative-permission calls, API repetition in the F-004 check. **Network stubs:** HTTP 500 / empty list in Doctors & Patients.

**Result: 166 of 184 recorded steps pass; every non-passing step is explained in section 3 and in each case the application state was verified correct (script assertion artefacts) - except where noted as a defect found and fixed during this run (section 2).**

## 1. Explicit checks you asked for

| Check | Result | Evidence |
|---|---|---|
| Empty pharmacy data does not fabricate records after repeated GETs | PASS | Pharmacyownerempty-2, -3, -4 |
| Suspended pharmacy remains suspended after seed runs | PASS | every demo seed run 3 times on the used database; `seedcheck.json`; Suspendedpharmacy-13/-14 |
| Multiple rider deliveries select the correct map order | PASS | Deliveryperson-2..7 (rider_map) and wf_stale |
| Feed checkout persists delivery location | PASS | Farmer-2..10 (farmer) |
| Expired assignments do not remain assigned | PASS | Expiry-4..8 |
| Research revision request is performed through the UI | PASS | ResearchAdmin-3..5 (both papers) |
| Doctor notes can be edited and audited | PASS | Doctor-6..13 (nf6) |
| Delivery proof approval is idempotent | PASS | Admin-3 (pharmacy) and FeedAdmin-3 (feed): 409, one earning, one expense |
| Null appointment time does not crash Doctors & Patients | PASS | DoctorsPatients-5r..8r |

Seed check (every demo seed command run three times on the *used* matrix database): rows before 1820, after 1820; tables that changed: []; suspended pharmacy afterwards: `[['rt.pharmacy.suspended@example.com', 'suspended', False, '20afbb51']]`; all user status/verification/password-hash rows identical: **True**.

## 2. Defects found by this matrix and fixed (all uncommitted, each with a regression test)

| Defect | Impact | Fix | Test |
|---|---|---|---|
| **Delivered pharmacy orders produced no sale and no commission** (the F-005 proof workflow replaced the old "delivered" transition that wrote them); Pharmacy Admin Sales & Settlements showed zero | **Financial records**; also the reason F-024 was open | `delivery/views.py::_sync_pharmacy_order` now calls the idempotent `create_pharmacy_sale_and_commission`; new `backfill_pharmacy_sales` command for already-delivered orders (dry-run supported) | `test_delivery_proof_review.py`: one sale, one 20% commission (100/400), repeated approval creates no second row |
| Prescription for a consultation without a case-detail row returned 500 **after** the transaction (seeded/legacy data) | Doctor saw an error; nothing saved | `doctor/views.py::_prescription_row` tolerates a missing case | `test_doctor_flow.py` (59 assertions) |
| `seed_farmer_demo_data` crashed on a re-run once another farmer existed (the fixed rng picked an already used consultation slot) | Seed not idempotent | slot collision avoided | seed re-run in the matrix; exercised by `mx_seedcheck` |
| `seed_research_demo` created users with unverified contacts (cannot sign in) and crashed on re-run after real revision snapshots (`MultipleObjectsReturned`) | Seed unusable on a used DB | verified contacts on creation; snapshot lookup via `exists()` | `test_seed_research_demo.py` (33 assertions) |
| Demo seeds (which create admin accounts with well-known passwords) could run against a production database | Credential exposure | `users/demo_guard.py`: refuse unless DEBUG or `ALLOW_DEMO_SEED=1` | `featherflow_backend/tests.py::DemoSeedGuardTests` |
| Maps key shared by browser, Android and server, committed to git | see `MAPS_KEY_SECURITY_REPORT.md` | per-environment config | `test_delivery_route.py` |

## 3. Roles, workflows and results

### 1. Farmer

* **Account / status:** farmer.rashed@example.com (active, seeded) and regr.farmer@example.com (fresh, set up through the ORM)
* **Database:** `featherflow_matrix`

**Cost management, feed order with GPS location, disease detection, vet request without an appointment time, community post** (`wf_farmer_legacy.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Farmer-1r` Login | /login -> /farmer | type credentials, press Log In | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Farmer-1r.png) | **PASS** |
| `Farmer-2r` Add expense | /farmer/cost-management/expenses | Add -> fill amount/supplier/notes -> Add | expected 1 RT expense, got 2 ["GET/api/farmers/costs/expenses/200","GET/api/farmers/costs/dashboard/?period=li | POST /api/farmers/costs/expenses/ -> 201 | expenses: 17 rows, sum=82204.00 -> 18 rows, sum=83438.00; rt_expense: 1 -> 2 | [img](audit_logs/matrix/shots/Farmer-2r.png) | **FAIL** |
| `Farmer-3r` Cost dashboard reflects the new expense | /farmer/cost-management | open dashboard | as named | - | expenses: 18 rows, sum=83438.00 -> 18 rows, sum=83438.00 | [img](audit_logs/matrix/shots/Farmer-3r.png) | **PASS** |
| `Farmer-4r` Feed order (cart -> checkout) | /farmer/feed-management/marketplace | Add to cart, Cart tab, Place order | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | feed_orders: 3 -> 4 | [img](audit_logs/matrix/shots/Farmer-4r.png) | **PASS** |
| `Farmer-5r` Disease detection (image upload) | /farmer/disease-detection | Choose File -> upload image | as named | POST /api/ml/predict-disease/ -> 201 | scans: 1 -> 2 | [img](audit_logs/matrix/shots/Farmer-5r.png) | **PASS** |
| `Farmer-6r` Vet request (book consultation) | /farmer/find-vet/discover | View & book -> submit request | as named | POST /api/consultations/ -> 201 | consults: 4 -> 5 | [img](audit_logs/matrix/shots/Farmer-6r.png) | **PASS** |
| `Farmer-7r` Community post | /community/create | type post, press Post | as named | POST /api/community/ -> 201 | posts: 5 -> 6 | [img](audit_logs/matrix/shots/Farmer-7r.png) | **PASS** |

**Fresh farmer: feed checkout without location / with invalid locations / with valid locations (six orders)** (`wf_farmer.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Farmer-5` NF-3: place order B with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 0 -> 1; last: - -> #FD-4C32F9 / 23.861,90.355 /; stock: 3799 -> 3798 | [img](audit_logs/matrix/shots/Farmer-5.png) | **PASS** |
| `Farmer-6` NF-3: place order C with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 1 -> 2; last: #FD-4C32F9 / 23.861,90.355 / -> #FD-D67939 / 23.701,90.452 /; stock: 3798 -> 3797 | [img](audit_logs/matrix/shots/Farmer-6.png) | **PASS** |
| `Farmer-7` NF-3: place order F with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 2 -> 3; last: #FD-D67939 / 23.701,90.452 / -> #FD-2CA777 / 23.73,90.33 / R; stock: 3797 -> 3796 | [img](audit_logs/matrix/shots/Farmer-7.png) | **PASS** |
| `Farmer-8` NF-3: place order E with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 3 -> 4; last: #FD-2CA777 / 23.73,90.33 / R -> #FD-3D16D6 / 23.95,90.28 / R; stock: 3796 -> 3795 | [img](audit_logs/matrix/shots/Farmer-8.png) | **PASS** |
| `Farmer-9` NF-3: place order D with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 4 -> 5; last: #FD-3D16D6 / 23.95,90.28 / R -> #FD-905D68 / 23.91,90.3 / Re; stock: 3795 -> 3794 | [img](audit_logs/matrix/shots/Farmer-9.png) | **PASS** |
| `Farmer-7r` NF-3: location is required (Place order blocked with no location) | /farmer/feed-management/marketplace (che | Add fresh product -> Cart -> Proceed to checkout -> type address -> pr | posts 0 orders 5 | - | orders: 5 -> 5; last: #FD-905D68 / 23.91,90.3 / Re -> #FD-905D68 / 23.91,90.3 / Re; stock: 3794 -> 3794 | [img](audit_logs/matrix/shots/Farmer-7r.png) | **FAIL** |
| `Farmer-8r` NF-3: invalid locations are rejected, no order is created | /farmer/feed-management/marketplace (che | Enter coordinates manually -> type each invalid pair -> press Place or | {"range":true,"outside":true,"letters":true} | - | orders: 5 -> 5; last: #FD-905D68 / 23.91,90.3 / Re -> #FD-905D68 / 23.91,90.3 / Re; stock: 3794 -> 3794 | [img](audit_logs/matrix/shots/Farmer-8r.png) | **FAIL** |
| `Farmer-9r` NF-3: place order A with a valid location | /farmer/feed-management/marketplace (che | Add to cart -> Proceed to checkout -> type address -> Enter coordinate | as named | POST /api/farmers/feed-catalogue/orders/ -> 201 | orders: 5 -> 6; last: #FD-905D68 / 23.91,90.3 / Re -> #FD-A5BAD3 / 23.7805,90.401 ; stock: 3794 -> 3793 | [img](audit_logs/matrix/shots/Farmer-9r.png) | **PASS** |
| `Farmer-10r` NF-3: farmer order details show each order with its own pin | /farmer/feed-management/marketplace (My  | open My Orders | as named | - | - | [img](audit_logs/matrix/shots/Farmer-10r.png) | **PASS** |
| `Farmer-10r` Login | /login -> /farmer | type credentials, press Log In | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Farmer-10r.png) | **PASS** |
| `Farmer-11r` Disease detection (image upload) | /farmer/disease-detection | Choose File -> upload image | as named | POST /api/ml/predict-disease/ -> 201 | scans: 0 -> 1 | [img](audit_logs/matrix/shots/Farmer-11r.png) | **PASS** |

**Pharmacy order for an over-the-counter medicine** (`wf_pharm_1.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Farmer-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Farmer-1.png) | **PASS** |
| `Farmer-2` Pharmacy order for an over-the-counter medicine | /farmer/pharmacy (Cart) | Add to cart (card of PoultryVit AD3E) -> Cart -> Place order | as named | POST /api/farmers/orders/ -> 201 | orders: 5 -> 6; last: ORD-39A20F0A6B / delivered / -> ORD-7BF15005BF / pending / P | [img](audit_logs/matrix/shots/Farmer-2.png) | **PASS** |

**Delivered pharmacy order tracked in the UI** (`wf_tracking.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Farmer-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Farmer-1.png) | **PASS** |
| `Farmer-2` Pharmacy order tracking: the delivered order is shown as Delivered | /farmer/pharmacy (My Orders) | Pharmacy -> My Orders | as named | - | - | [img](audit_logs/matrix/shots/Farmer-2.png) | **PASS** |

### 2. Suspended pharmacy

* **Account / status:** rt.pharmacy.suspended@example.com (account_status=suspended, set up through the ORM before any seed ran)
* **Database:** `featherflow_matrix`

**Locked shell, profile, earnings, blocked operations, support chat, appeal, refresh, relogin** (`wf_suspended_pharmacy.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Suspendedpharmacy-1` Login (suspended) | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | status: suspended -> suspended | [img](audit_logs/matrix/shots/Suspendedpharmacy-1.png) | **PASS** |
| `Suspendedpharmacy-2` Locked panel + earnings visible | /pharmacy | view locked home | as named | - | status: suspended -> suspended | [img](audit_logs/matrix/shots/Suspendedpharmacy-2.png) | **PASS** |
| `Suspendedpharmacy-3` Profile tab | /pharmacy (Profile tab) | open Profile tab | as named | - | - | [img](audit_logs/matrix/shots/Suspendedpharmacy-3.png) | **PASS** |
| `Suspendedpharmacy-4` Earnings (API) | /pharmacy | earnings card on home + API | earnings API 200 {"total_orders":0,"gross_sales":"0.00","featherflow_commission":"0.00","pharmacy_earnings":"0 | - | - | [img](audit_logs/matrix/shots/Suspendedpharmacy-4.png) | **PASS** |
| `Suspendedpharmacy-5` Locked operational tab: Catalogue | /pharmacy/catalogue | open Catalogue tab (no Add, no API calls) | as named | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-5.png) | **PASS** |
| `Suspendedpharmacy-6` Locked operational tab: Inventory | /pharmacy/inventory | open Inventory tab (no Add, no API calls) | as named | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-6.png) | **PASS** |
| `Suspendedpharmacy-7` Locked operational tab: Orders | /pharmacy/orders | open Orders tab (no Add, no API calls) | as named | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-7.png) | **PASS** |
| `Suspendedpharmacy-8` Locked operational tab: Suppliers | /pharmacy/suppliers | open Suppliers tab (no Add, no API calls) | as named | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-8.png) | **PASS** |
| `Suspendedpharmacy-9` Locked operational tab: Analytics | /pharmacy/analytics | open Analytics tab (no Add, no API calls) | as named | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-9.png) | **PASS** |
| `Suspendedpharmacy-10` Locked operational actions refused by API | (API) | direct API attempts | POST /api/pharmacy/medicines/ -> 401; GET /api/pharmacy/orders/ -> 401; GET /api/pharmacy/suppliers/ -> 401; G | - | meds: 0 -> 0 | [img](audit_logs/matrix/shots/Suspendedpharmacy-10.png) | **PASS** |
| `Suspendedpharmacy-11` Chat with Pharmacy Admin | /pharmacy (Contact Pharmacy Admin) | open chat, type, send | as named | PATCH /api/pharmacy/support-conversation/72bb8dbc-db33-49d0- -> 200; POST /api/pharmacy/support-conversation/ -> 201; POST /api/pharmacy/support-conve | messages: 0 -> 1 | [img](audit_logs/matrix/shots/Suspendedpharmacy-11.png) | **PASS** |
| `Suspendedpharmacy-12` Appeal | /pharmacy (Submit appeal) | Submit appeal form | as named | POST /api/pharmacy/appeals/ -> 201 | appeals: 0 / - -> 1 / submitted; status: suspended -> suspended | [img](audit_logs/matrix/shots/Suspendedpharmacy-12.png) | **PASS** |
| `Suspendedpharmacy-13` After appeal: still locked, appeal under review | /pharmacy | reload panel | as named | - | status: suspended -> suspended; appeals: 1 / submitted -> 1 / submitted | [img](audit_logs/matrix/shots/Suspendedpharmacy-13.png) | **PASS** |
| `Suspendedpharmacy-14r` Relogin in a fresh browser: still locked, appeal still under review | /login -> /pharmacy | log in again (new browser session) | button/ button/Sign out group/Refresh statusContact Pharmacy AdminSubmit appealLifetime earnings ৳ 0.00 0 orde | POST /api/auth/login/ -> 200 | status: suspended -> suspended; appeals: 1 / denied -> 1 / denied | [img](audit_logs/matrix/shots/Suspendedpharmacy-14r.png) | **FAIL** |

### 3. Pharmacy Admin (+ the active pharmacy owner)

* **Account / status:** admin.pharmacy@example.com (admin_pharmacy); pharmacy.greenvet@example.com (active owner); empty.pharmacy@example.com (active, no data)
* **Database:** `featherflow_matrix`

**Owner adds a prescription-only medicine in the UI** (`wf_owner_medicine.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Pharmacyowner-1` Login | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Pharmacyowner-1.png) | **PASS** |
| `Pharmacyowner-2` Owner adds a prescription-only medicine (needs admin approval) | /pharmacy (Catalogue -> Add) | Catalogue -> Add -> fill the form -> Prescription required -> Add Medi | as named | POST /api/pharmacy/medicines/ -> 201 | med: 0 / approved=- -> 1 / approved=false | [img](audit_logs/matrix/shots/Pharmacyowner-2.png) | **PASS** |

**Owner confirms the order** (`wf_pharm_2.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Pharmacyowner-1` Login | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Pharmacyowner-1.png) | **PASS** |
| `Pharmacyowner-2` Owner confirms the order | /pharmacy (Orders) | Orders -> open order -> Confirm order | as named | POST /api/pharmacy/orders/ORD-7BF15005BF/confirm/ -> 200 | status: pending -> processing | [img](audit_logs/matrix/shots/Pharmacyowner-2.png) | **PASS** |

**Owner requests delivery** (`wf_pharm_3.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Pharmacyowner-1` Login | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Pharmacyowner-1.png) | **PASS** |
| `Pharmacyowner-2` Owner advances the order: Ready/ship/deliver | /pharmacy (Orders) | Orders -> open order -> Ready/ship/deliver | as named | POST /api/pharmacy/orders/ORD-39A20F0A6B/ready-for-delivery/ -> 200 | status: processing -> shipped | [img](audit_logs/matrix/shots/Pharmacyowner-2.png) | **PASS** |
| `Pharmacyowner-3` Login | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Pharmacyowner-3.png) | **PASS** |
| `Pharmacyowner-4` Owner advances the order: Request | /pharmacy (Orders) | Orders -> open order -> Request | as named | POST /api/pharmacy/orders/ORD-7BF15005BF/ready-for-delivery/ -> 200 | status: processing -> shipped | [img](audit_logs/matrix/shots/Pharmacyowner-4.png) | **PASS** |

**Admin: pharmacies, appeal, medicine approval, rider assignment, reports** (`wf_pharmacy_admin.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `PharmacyAdmin-2` Account review: the suspended pharmacy is listed (status unchanged) | /admin/pharmacy (Pharmacies) | open Pharmacies tab | as named | - | susp: suspended -> suspended | [img](audit_logs/matrix/shots/PharmacyAdmin-2.png) | **PASS** |
| `PharmacyAdmin-3` Appeal: deny the suspension appeal (the account must stay suspended) | /admin/pharmacy (Chat & Appeals) | Deny -> reason -> confirm | as named | PATCH /api/admin-panel/pharmacy/appeals/cb68abd1-8b24-4140-8 -> 200 | appeal: submitted -> denied; susp: suspended -> suspended | [img](audit_logs/matrix/shots/PharmacyAdmin-3.png) | **PASS** |
| `PharmacyAdmin-4` Medicine: approve the pending prescription medicine created by the own | /admin/pharmacy (Medicine Approvals) | Medicines tab -> Approve | as named | PATCH /api/admin-panel/pharmacy/medicines/316771d1-7686-4ef3 -> 200 | med: pending -> approved | [img](audit_logs/matrix/shots/PharmacyAdmin-4.png) | **PASS** |
| `PharmacyAdmin-7` Reports: export "Orders" CSV and audit trail shows this session | /admin/pharmacy (Reports & Audit) | click Orders export | clicked export | - | - | [img](audit_logs/matrix/shots/PharmacyAdmin-7.png) | **FAIL** |
| `PharmacyAdmin-9` Reports: audit trail lists the admin actions of this retest | /admin/pharmacy (Reports & Audit) | read Audit trail section | P Pharmacy Admin Back Pharmacy Management 4 Pharmacies 0 Pending approvals Pharmacy Admin 1 Active deliveries  | - | audit: 1 -> 1 | [img](audit_logs/matrix/shots/PharmacyAdmin-9.png) | **FAIL** |
| `PharmacyAdmin-6r` Login | /login -> /admin | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/PharmacyAdmin-6r.png) | **PASS** |
| `PharmacyAdmin-7r` Delivery assignment: assign a rider to the pharmacy order | /admin/pharmacy (Orders & Delivery -> As | Orders -> Assign -> choose rider -> confirm | as named | POST /api/admin-panel/pharmacy-orders/DQ-ORD-7BF15005BF/assi -> 201 | deliveries: 0 / - -> 1 / pending; order: shipped -> shipped | [img](audit_logs/matrix/shots/PharmacyAdmin-7r.png) | **PASS** |

**Rider accepts the pharmacy delivery** (`wf_proof_pharmacy_0.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` Rider accepts the offer (pharmacy delivery) | /delivery/orders (New) | Orders tab -> Accept | as named | PATCH /api/delivery/requests/df7db8d8-3345-420f-8975-0f7205c -> 200 | status: pending -> accepted | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |

**Pharmacy delivery to proof submitted (OTP)** (`wf_proof_pharmacy_1.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` Proof lifecycle: assigned -> picked up | /delivery (detail of C) | press "Mark as Picked Up" | as named | PATCH /api/delivery/orders/df7db8d8-3345-420f-8975-0f7205c7c -> 200 | status: accepted -> picked_up; events: 0 -> 1 | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |
| `Deliveryperson-3` Proof lifecycle: picked up -> out for delivery | /delivery (detail of C) | press "On The Way" | as named | PATCH /api/delivery/orders/df7db8d8-3345-420f-8975-0f7205c7c -> 200 | status: picked_up -> on_the_way; events: 1 -> 2 | [img](audit_logs/matrix/shots/Deliveryperson-3.png) | **PASS** |
| `Deliveryperson-4` Proof lifecycle: out for delivery -> arrived | /delivery (detail of C) | press "Mark Arrived" | as named | PATCH /api/delivery/orders/df7db8d8-3345-420f-8975-0f7205c7c -> 200 | status: on_the_way -> arrived; events: 2 -> 3 | [img](audit_logs/matrix/shots/Deliveryperson-4.png) | **PASS** |
| `Deliveryperson-5` Proof lifecycle: arrived -> proof submitted (photo) | /delivery (detail of C) | Take/Upload Delivery Photo -> Submit Delivery Proof | as named | POST /api/delivery/orders/df7db8d8-3345-420f-8975-0f7205c7c2 -> 201 | status: arrived -> proof_submitted; proofs: - -> submitted#1; earnings: 0 -> 0 | [img](audit_logs/matrix/shots/Deliveryperson-5.png) | **PASS** |

**Admin approves; duplicate approval; sale + commission** (`wf_proof_pharmacy_4.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Admin-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Admin-1.png) | **PASS** |
| `Admin-2` Proof review: approve -> completed | /admin/delivery-proofs | Delivery Proofs -> Approve -> "Approve & complete" | as named | POST /api/admin-panel/delivery-proofs/89ddeb71-af6d-458c-8d7 -> 200 | status: proof_submitted -> delivered; proofs: submitted#1 -> approved#1; earnings: 0 -> 1 | [img](audit_logs/matrix/shots/Admin-2.png) | **PASS** |
| `Admin-3` Completion: duplicate approval refused (API-labelled check), financial | (API) | repeat approve with the admin token | HTTP 409 | POST /api/admin-panel/delivery-proofs/89ddeb71-af6d-458c-8d7 -> 409 | status: delivered -> delivered; proofs: approved#1 -> approved#1; earnings: 1 -> 1 | [img](audit_logs/matrix/shots/Admin-3.png) | **PASS** |

**Sales & Settlements show live figures** (`wf_money.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `PharmacyAdminFarmer-1` Login (pharmacy admin) | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/PharmacyAdminFarmer-1.png) | **PASS** |
| `PharmacyAdminFarmer-2` Sales tab shows live figures for delivered pharmacy orders | /admin/pharmacy (Sales) | open Sales | as named | - | earnings: 4 rows, total=570.70 -> 4 rows, total=570.70; expenses: 4 -> 4; sales: 5 -> 5 | [img](audit_logs/matrix/shots/PharmacyAdminFarmer-2.png) | **PASS** |

**F-004: empty pharmacy stays empty after repeated GETs** (`wf_f004.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Pharmacyownerempty-1` Login (empty pharmacy) | /login -> /pharmacy | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Pharmacyownerempty-1.png) | **PASS** |
| `Pharmacyownerempty-2` F-004: opening every tab three times creates no records and shows no d | /pharmacy (all tabs) | visit each tab, reload, repeat | as named | - | owned: x -> x | [img](audit_logs/matrix/shots/Pharmacyownerempty-2.png) | **PASS** |
| `Pharmacyownerempty-3` F-004 (API-labelled): 5 repeated GETs of every pharmacy list endpoint  | (API) | direct API reads | dashboard:200:{"profile":{"name":"Empty Pharmacy Owner","license_number":" / medicines:200:{"results":[]} / or | - | - | [img](audit_logs/matrix/shots/Pharmacyownerempty-3.png) | **PASS** |
| `Pharmacyownerempty-4` F-004: the empty pharmacy contributes nothing to the farmer marketplac | (API) | farmer search | results from the empty pharmacy: 0 | - | - | [img](audit_logs/matrix/shots/Pharmacyownerempty-4.png) | **PASS** |

### 4. Feed Admin

* **Account / status:** feed.admin@featherflow.local (feed_admin)
* **Database:** `featherflow_matrix`

**Supplier pickup coordinates, fresh product** (`wf_feed_admin_setup.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedAdmin-1` Login | /login -> /admin | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedAdmin-1.png) | **PASS** |
| `FeedAdmin-2` Supplier pickup coordinates: Demo Nourish Feeds Ltd | /admin/feed-clients -> client -> edit | edit client -> type latitude/longitude -> Save changes | as named | PATCH /api/admin-panel/feed-catalogue/companies/ac971cfa-2d1 -> 200 | coords: 23.842000,90.257000 -> 23.842000,90.257000 | [img](audit_logs/matrix/shots/FeedAdmin-2.png) | **PASS** |
| `FeedAdmin-3` Supplier pickup coordinates: Demo Golden Grain Feeds | /admin/feed-clients -> client -> edit | edit client -> type latitude/longitude -> Save changes | as named | PATCH /api/admin-panel/feed-catalogue/companies/4819f052-d13 -> 200 | coords: 24.002300,90.420300 -> 24.002300,90.420300 | [img](audit_logs/matrix/shots/FeedAdmin-3.png) | **PASS** |
| `FeedAdmin-4` Supplier pickup coordinates: Demo Premium Poultry Nutrition | /admin/feed-clients -> client -> edit | edit client -> type latitude/longitude -> Save changes | as named | PATCH /api/admin-panel/feed-catalogue/companies/38657827-03b -> 200 | coords: 23.623800,90.500000 -> 23.623800,90.500000 | [img](audit_logs/matrix/shots/FeedAdmin-4.png) | **PASS** |
| `FeedAdmin-5` Fresh product created through the form | /admin/feed (Products -> Add product) | Add product -> fill -> Save product | as named | POST /api/admin-panel/feed-catalogue/products/ -> 201 | product: 0 -> 1 | [img](audit_logs/matrix/shots/FeedAdmin-5.png) | **PASS** |
| `FeedAdmin-6` Fresh product approved via the row menu | /admin/feed (Products) | row menu -> Approve | as named | PATCH /api/admin-panel/feed-catalogue/products/8ea85630-8bd7 -> 200 | approval: pending_review -> approved | [img](audit_logs/matrix/shots/FeedAdmin-6.png) | **PASS** |

**Order details, assignment with supplier pickup** (`wf_feed_admin_orders.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedAdmin-1` Login | /login -> /admin | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedAdmin-1.png) | **PASS** |
| `FeedAdmin-2` NF-3: admin order details show each order's address and map location | /admin/feed (Orders & Delivery) | open Orders & Delivery | as named | - | - | [img](audit_logs/matrix/shots/FeedAdmin-2.png) | **PASS** |
| `FeedAdmin-3` NF-7: assign order A to the fresh rider | /admin/feed (Orders & Delivery) | Assign rider -> choose Regr Rider -> Assign | order assigned / ds=pending / rider=9043e550-d047-4375-972f-8bee5f96342c / pickup=23.842,90.257 delivery rejec | POST /api/admin-panel/feed-catalogue/orders/FEED-7657A5BAD3/ -> 201 | order: created / ds=offer_expired / -> assigned / ds=pending / ride; delivery: rejected pickup=23.842000,90 -> rejected pickup=23.842000,90 | [img](audit_logs/matrix/shots/FeedAdmin-3.png) | **FAIL** |
| `FeedAdmin-4` NF-7: assign order B to the fresh rider | /admin/feed (Orders & Delivery) | Assign rider -> choose Regr Rider -> Assign | as named | POST /api/admin-panel/feed-catalogue/orders/FEED-D0C24C32F9/ -> 201 | order: created / ds=- / rider=- / p -> assigned / ds=pending / ride; delivery: none -> pending pickup=24.002300,90. | [img](audit_logs/matrix/shots/FeedAdmin-4.png) | **PASS** |
| `FeedAdmin-5` NF-7: assign order C to the fresh rider | /admin/feed (Orders & Delivery) | Assign rider -> choose Regr Rider -> Assign | order assigned / ds=pending / rider=9043e550-d047-4375-972f-8bee5f96342c / pickup=23.6238,90.5 delivery reject | POST /api/admin-panel/feed-catalogue/orders/FEED-644DD67939/ -> 201 | order: created / ds=offer_expired / -> assigned / ds=pending / ride; delivery: rejected pickup=23.623800,90 -> rejected pickup=23.623800,90 | [img](audit_logs/matrix/shots/FeedAdmin-5.png) | **FAIL** |
| `FeedAdmin-6` NF-7: admin order details now show the pickup name, address and coordi | /admin/feed (Orders & Delivery) | reload Orders & Delivery | as named | - | - | [img](audit_logs/matrix/shots/FeedAdmin-6.png) | **PASS** |

**Third assignment** (`wf_third.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedAdminRider-1` Login (feed admin) | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedAdminRider-1.png) | **PASS** |
| `FeedAdminRider-2` Assign order E to the multi-delivery rider | /admin/feed | Assign rider -> Regr Rider -> Assign | as named | POST /api/admin-panel/feed-catalogue/orders/FEED-19653D16D6/ -> 201 | deliveries: delivered,delivered,accepted -> delivered,delivered,accepted | [img](audit_logs/matrix/shots/FeedAdminRider-2.png) | **PASS** |
| `FeedAdminRider-3` Rider accepts the third delivery | /delivery/orders (New) | Orders -> Accept | as named | PATCH /api/delivery/requests/93fe457d-2824-44d6-8d2c-ad73357 -> 200; POST /api/auth/login/ -> 200 | deliveries: delivered,delivered,accepted -> delivered,delivered,accepted | [img](audit_logs/matrix/shots/FeedAdminRider-3.png) | **PASS** |

**Reject a proof with a reason** (`wf_proof_2.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedAdmin-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedAdmin-1.png) | **PASS** |
| `FeedAdmin-2` Proof review: reject with a reason (order must NOT complete) | /admin/delivery-proofs | Delivery Proofs -> Reject -> type reason -> confirm | as named | POST /api/admin-panel/delivery-proofs/3a20854c-8c6c-45be-a9e -> 200 | status: proof_submitted -> proof_rejected; proofs: submitted#1 -> rejected#1; earnings: 0 -> 0 | [img](audit_logs/matrix/shots/FeedAdmin-2.png) | **PASS** |

**Approve the resubmitted proof; duplicate approval** (`wf_proof_4.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedAdmin-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedAdmin-1.png) | **PASS** |
| `FeedAdmin-2` Proof review: approve -> completed | /admin/delivery-proofs | Delivery Proofs -> Approve -> "Approve & complete" | as named | POST /api/admin-panel/delivery-proofs/72c95ccf-e598-4cd0-acb -> 200 | status: proof_submitted -> delivered; proofs: rejected#1,submitted#2 -> rejected#1,approved#2; earnings: 0 -> 1 | [img](audit_logs/matrix/shots/FeedAdmin-2.png) | **PASS** |
| `FeedAdmin-3` Completion: duplicate approval refused (API-labelled check), financial | (API) | repeat approve with the admin token | HTTP 409 | POST /api/admin-panel/delivery-proofs/72c95ccf-e598-4cd0-acb -> 409 | status: delivered -> delivered; proofs: rejected#1,approved#2 -> rejected#1,approved#2; earnings: 1 -> 1 | [img](audit_logs/matrix/shots/FeedAdmin-3.png) | **PASS** |

**Expired assignment, idempotent expiry, reassignment** (`wf_expiry.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Expiry-1` Login (admin) | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Expiry-1.png) | **PASS** |
| `Expiry-2` NF-7: assign order D (offer window 45 s) | /admin/feed | Assign rider -> Regr Rider -> Assign | as named | POST /api/admin-panel/feed-catalogue/orders/FEED-D6C42CA777/ -> 201 | order: created / ds=- / rider=- -> assigned / ds=pending / ride; deliveries: none -> pending:-; events: 0 -> 0 | [img](audit_logs/matrix/shots/Expiry-2.png) | **PASS** |
| `Expiry-3` NF-7: the rider sees the live offer in the New tab | /delivery/orders (New) | Orders tab -> New | as named | - | order: assigned / ds=pending / ride -> assigned / ds=pending / ride; deliveries: pending:- -> pending:-; events: 0 -> 0 | [img](audit_logs/matrix/shots/Expiry-3.png) | **PASS** |
| `Expiry-4` NF-7: the FARMER is the first reader after expiry and sees the order a | /farmer/feed-management/marketplace (My  | open My Orders after the offer window | as named | - | order: created / ds=offer_expired / -> created / ds=offer_expired /; deliveries: rejected:Offer expired -> rejected:Offer expired; events: 0 -> 0 | [img](audit_logs/matrix/shots/Expiry-4.png) | **PASS** |
| `Expiry-5` NF-7: the rider no longer sees the expired offer (New tab) | /delivery/orders (New) | reload Orders -> New | as named | - | order: created / ds=offer_expired / -> created / ds=offer_expired /; deliveries: rejected:Offer expired -> rejected:Offer expired; events: 0 -> 0 | [img](audit_logs/matrix/shots/Expiry-5.png) | **PASS** |
| `Expiry-6` NF-7: repeating the supported expiry command and page loads changes no | (command) + /admin/feed | run the command twice, reload the admin order list twice | released 0 stale offer(s) / released 0 stale offer(s) | - | order: created / ds=offer_expired / -> created / ds=offer_expired /; deliveries: rejected:Offer expired -> rejected:Offer expired; events: 0 -> 0 | [img](audit_logs/matrix/shots/Expiry-6.png) | **PASS** |
| `Expiry-7` NF-7: the admin sees an actionable order (Reassign rider is offered) a | /admin/feed | Orders & Delivery -> Reassign rider -> Assign | as named | POST /api/admin-panel/feed-catalogue/orders/FEED-D6C42CA777/ -> 201 | order: created / ds=offer_expired / -> assigned / ds=pending / ride; deliveries: rejected:Offer expired -> rejected:Offer expired ; pen; events: 0 ->  | [img](audit_logs/matrix/shots/Expiry-7.png) | **PASS** |
| `Expiry-8` NF-7: the rider accepts the reassigned offer | /delivery/orders (New) | Orders -> Accept | as named | PATCH /api/delivery/requests/338fe91a-37d5-4d57-b9eb-6acc73c -> 200 | order: assigned / ds=pending / ride -> assigned / ds=pending / ride; deliveries: rejected:Offer expired ; pen -> rejected:Offer expired ; acc; events: | [img](audit_logs/matrix/shots/Expiry-8.png) | **PASS** |

### 5. Feed Inventory Owner

* **Account / status:** feed.owner@featherflow.local (feed_owner)
* **Database:** `featherflow_matrix`

**Limited profile, chat with Feed Admin, community post** (`wf_feed_owner.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `FeedInventoryOwner-1` Login | /login -> /feed-owner | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/FeedInventoryOwner-1.png) | **PASS** |
| `FeedInventoryOwner-2` Limited profile: only inventory context, chat and community | /feed-owner | view home; probe forbidden APIs | /api/farmers/dashboard/ -> 403; /api/admin-panel/dashboard/ -> 403; /api/pharmacy/medicines/ -> 403; /api/deli | - | - | [img](audit_logs/matrix/shots/FeedInventoryOwner-2.png) | **PASS** |
| `FeedInventoryOwner-3` Feed Admin chat: send message | /feed-owner (chat) | open chat, type, send | as named | PATCH /api/feed-owner/chat/2a6a5c08-d136-4733-bcdb-7945b1096 -> 200; POST /api/feed-owner/chat/ -> 201; POST /api/feed-owner/chat/2a6a5c08-d136-4733-b | msgs: 0 -> 1 | [img](audit_logs/matrix/shots/FeedInventoryOwner-3.png) | **PASS** |
| `FeedInventoryOwner-4` Feed Admin chat: admin sees the message (API) | (API) /api/admin-panel/feed-chats/ | GET as Feed Admin | HTTP 200 | - | - | [img](audit_logs/matrix/shots/FeedInventoryOwner-4.png) | **PASS** |
| `FeedInventoryOwner-5` Community post | /community/create | Community tile -> new post -> Post | as named | POST /api/community/ -> 201 | posts: 0 -> 1 | [img](audit_logs/matrix/shots/FeedInventoryOwner-5.png) | **PASS** |

### 6. Doctor

* **Account / status:** dr.samira.rahman@example.com (doctor, prescription authority granted through the ORM); admin.super@example.com for Doctors & Patients
* **Database:** `featherflow_matrix`

**Availability, accept request, chat, prescription (legacy script, see notes)** (`wf_doctor.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Doctor-1` Login | /login -> /doctor | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Doctor-1.png) | **PASS** |
| `Doctor-2` Availability: set Busy then Available again | /doctor | Show menu -> Busy ; Show menu -> Available | as named | PATCH /api/doctor/profile/ -> 200 | avail: true -> true | [img](audit_logs/matrix/shots/Doctor-2.png) | **PASS** |
| `Doctor-3` Availability: publish a weekly consultation time | /doctor/appointments (Set consultation t | Set consultation times -> Publish time | no POST ["GET/api/doctor/earnings/200","GET/api/doctor/conversations/200","GET/api/doctor/cases/200","GET/api/ | POST /api/doctor/availability/ -> 409 | slots: 1 -> 1 | [img](audit_logs/matrix/shots/Doctor-3.png) | **FAIL** |
| `Doctor-4` Consultation: accept the farmer request | /doctor/appointments (Pending) | Pending filter -> Accept on the request card | as named | POST /api/doctor/appointments/58d5bb1c-0c4b-47d9-9e54-a3d4aa -> 200 | cstatus: requested -> accepted; convs: 0 -> 1 | [img](audit_logs/matrix/shots/Doctor-4.png) | **PASS** |
| `Doctor-5` Chat: reply to the farmer in the messenger | /doctor/messenger -> thread | open thread, type, send | as named | PATCH /api/doctor/conversations/6db5348d-e615-4759-b668-0318 -> 200; POST /api/doctor/conversations/6db5348d-e615-4759-b668-03186 -> 201 | msgs: 0 -> 1 | [img](audit_logs/matrix/shots/Doctor-5.png) | **PASS** |
| `Doctor-6` Case notes: issue prescription and case advice (also schedules the fol | /doctor/appointments (Completed) -> Issu | fill dialog, pick follow-up date, Save | notes 0->0 rx 0->0 ["POST/api/doctor/prescriptions/201"] | POST /api/doctor/prescriptions/ -> 201 | notes: 0 -> 0; followups: 0 -> 0; rx: 0 -> 0 | [img](audit_logs/matrix/shots/Doctor-6.png) | **FAIL** |
| `Doctor-7` Follow-up: follow-up exists for the consultation | /doctor/followups | open Follow-Ups screen | follow_ups 0 | - | followups: 0 -> 0; fu: - -> - | [img](audit_logs/matrix/shots/Doctor-7.png) | **FAIL** |
| `Doctor-8` Case: close the case | /doctor/case-notes -> case -> Close Case | Close Case | case_status open | - | cs: open -> open | [img](audit_logs/matrix/shots/Doctor-8.png) | **FAIL** |

**Case-note editing, audit history, conflicts, permissions** (`wf_nf6.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Doctor-2` Doctor closes the open case through the UI (Close Case) | /doctor/case-notes -> case | open the case -> Close Case | open -> open | - | notes: no note row -> no note row; status: open -> open; history: 0 -> 0 | [img](audit_logs/matrix/shots/Doctor-2.png) | **ERROR** |
| `Doctor-4` NF-6: reopen the case (status only - no notes are resent) | /doctor/case-notes -> case (menu) | three-dot menu -> Mark In Progress | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 200 | notes: no note row -> no note row; status: open -> in_progress; history: 0 -> 1 | [img](audit_logs/matrix/shots/Doctor-4.png) | **PASS** |
| `Doctor-5` NF-6: editor opens with existing values; Save is disabled until someth | /doctor/case-notes -> case -> Edit notes | press Edit notes | as named | - | notes: no note row -> no note row; status: in_progress -> in_progress; history: 1 -> 1 | [img](audit_logs/matrix/shots/Doctor-5.png) | **PASS** |
| `Doctor-6` NF-6: record diagnosis and treatment (first save) | /doctor/case-notes -> case -> Edit notes | type diagnosis + treatment -> Save 2 changes | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 200 | notes: no note row -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 1 -> 2 | [img](audit_logs/matrix/shots/Doctor-6.png) | **PASS** |
| `Doctor-7` NF-6: a recorded diagnosis cannot be blanked (validation, nothing sent | /doctor/case-notes -> case -> Edit notes | Edit notes -> clear Diagnosis | as named | - | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 2 -> 2 | [img](audit_logs/matrix/shots/Doctor-7.png) | **PASS** |
| `Doctor-8` NF-6: partial edit sends only the changed field; other notes are prese | /doctor/case-notes -> case -> Edit notes | restore diagnosis by cancelling -> Edit notes -> change only Next step | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 200 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 2 -> 3 | [img](audit_logs/matrix/shots/Doctor-8.png) | **PASS** |
| `Doctor-9` NF-6: a concurrent edit from another device is not overwritten (confli | /doctor/case-notes -> case -> Edit notes | A: open editor; B: edit + save Warnings; A: change Next steps -> Save | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 409 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 3 -> 4 | [img](audit_logs/matrix/shots/Doctor-9.png) | **PASS** |
| `Doctor-10` NF-6: reload the latest notes, re-apply the edit, save | /doctor/case-notes -> case -> Edit notes | Reload the latest notes -> change Next steps -> Save 1 change | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 200 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 4 -> 5 | [img](audit_logs/matrix/shots/Doctor-10.png) | **PASS** |
| `Doctor-11` NF-6: audit history shows revision, author, timestamp, previous and ne | /doctor/case-notes -> case -> Notes hist | press Notes history | as named | - | history: 5 -> 5 | [img](audit_logs/matrix/shots/Doctor-11.png) | **PASS** |
| `Doctor-12` NF-6: refresh preserves the saved notes | /doctor/case-notes -> case | reload -> Case Notes -> open the case | as named | - | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 5 -> 5 | [img](audit_logs/matrix/shots/Doctor-12.png) | **PASS** |
| `Doctor-13` NF-6: saving identical content again adds no history entry (Save stays | /doctor/case-notes -> case -> Edit notes | Edit notes -> retype the same text -> try Save -> Cancel | as named | - | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 5 -> 5 | [img](audit_logs/matrix/shots/Doctor-13.png) | **PASS** |
| `Doctor-14` NF-6: the patient (farmer) cannot reach the doctor case notes | /doctor/case-notes | log in as the farmer -> navigate to the doctor case notes | as named | POST /api/auth/login/ -> 200 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 5 -> 5 | [img](audit_logs/matrix/shots/Doctor-14.png) | **PASS** |
| `Doctor-15` NF-6: another doctor does not see this patient case | /doctor/case-notes | log in as another doctor -> Case Notes | as named | POST /api/auth/login/ -> 401 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> in_progress; history: 5 -> 5 | [img](audit_logs/matrix/shots/Doctor-15.png) | **PASS** |
| `Doctor-14r` Login | /login -> /doctor | type credentials, press Log In | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Doctor-14r.png) | **PASS** |
| `Doctor-15r` Doctor closes the case through the UI (menu -> Close Case) | /doctor/case-notes -> case | open the case -> Close Case | as named | PATCH /api/doctor/cases/fc541a40-db2e-4a3c-b43e-cc67cc3b7c10 -> 200 | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: in_progress -> closed; history: 5 -> 6 | [img](audit_logs/matrix/shots/Doctor-15r.png) | **PASS** |
| `Doctor-16r` NF-6: a closed case cannot be edited ("reopen to edit notes") | /doctor/case-notes -> case | open the closed case, try to press the edit button | as named | - | notes: dx=Infectious bronchitis (su -> dx=Infectious bronchitis (su; status: closed -> closed; history: 6 -> 6 | [img](audit_logs/matrix/shots/Doctor-16r.png) | **PASS** |

**Doctors & Patients with a null appointment time** (`wf_doctors.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `DoctorsPatients-1` Login (farmer) | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/DoctorsPatients-1.png) | **PASS** |
| `DoctorsPatients-2` Farmer requests a consultation with "Request any available time" (no a | /farmer/find-vet/discover | View & book -> Book consultation -> fill -> Request any available time | as named | POST /api/consultations/ -> 201 | consults: 0 -> 1; nulltime: 0 -> 1 | [img](audit_logs/matrix/shots/DoctorsPatients-2.png) | **PASS** |
| `DoctorsPatients-8` Doctor panel shows the real request and no fabricated demo clients | /doctor (appointments) | log in as the doctor -> Appointments | as named | POST /api/auth/login/ -> 200 | consults: 1 -> 1; nulltime: 1 -> 1 | [img](audit_logs/matrix/shots/DoctorsPatients-8.png) | **PASS** |
| `DoctorsPatients-4r` Login (doctor admin) | /login -> /admin | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/DoctorsPatients-4r.png) | **PASS** |
| `DoctorsPatients-5r` Admin Doctors & Patients: the panel loads and lists doctors | /admin/doctors | open Doctors & Patients | as named | - | - | [img](audit_logs/matrix/shots/DoctorsPatients-5r.png) | **PASS** |
| `DoctorsPatients-6r` Admin Consultations: the no-time consultation appears and the missing  | /admin/doctors (Consultations) | Consultations tab | as named | - | consults: 1 -> 1; nulltime: 1 -> 1 | [img](audit_logs/matrix/shots/DoctorsPatients-6r.png) | **PASS** |
| `DoctorsPatients-7r` An API error is an error state with Retry - not "No consultations yet" | /admin/doctors (Consultations) | reload with the consultations request failing -> Retry | as named | - | - | [img](audit_logs/matrix/shots/DoctorsPatients-7r.png) | **PASS** |
| `DoctorsPatients-8r` Genuinely empty data shows the empty state (network stub: empty list), | /admin/doctors (Consultations) | reload with an empty consultations list | as named | - | - | [img](audit_logs/matrix/shots/DoctorsPatients-8r.png) | **PASS** |

### 7. Researcher

* **Account / status:** research.fariha@example.com / research.mahmud@example.com (researcher), research.admin@example.com (admin_research)
* **Database:** `featherflow_matrix`

**Submit paper, revision, resubmit, publish** (`wf_researcher.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Researcher-1` Login | /login -> /research | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Researcher-1.png) | **PASS** |
| `Researcher-2` Paper submission: fill form and Submit for Review | /research/new-paper | type title/abstract/keywords/body, tag, PDF, Submit for Review | as named | POST /api/research/papers/ -> 201; POST /api/research/papers/beaaa84a-905c-4010-a3b3-4017ac5efd -> 200; POST /api/research/upload-pdf/ -> 201 | count: 0 -> 1; status: - -> pending_review | [img](audit_logs/matrix/shots/Researcher-2.png) | **PASS** |
| `Researcher-3` Login | /login -> /research | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Researcher-3.png) | **PASS** |
| `Researcher-4` Revision: researcher edits the paper and resubmits for review | /research/papers -> Edit Paper | Options -> Edit -> change abstract -> Submit for Review | as named | POST /api/research/papers/beaaa84a-905c-4010-a3b3-4017ac5efd -> 200; PUT /api/research/papers/beaaa84a-905c-4010-a3b3-4017ac5efda -> 200 | st: needs_revision / Please add  -> pending_review / Please add ; snaps: 2 -> 3; abs: RT-RETEST abstract: a contro -> RT-RETEST abstract: a contro | [img](audit_logs/matrix/shots/Researcher-4.png) | **PASS** |
| `Researcher-5` Login (Research Admin) | /login -> /admin | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Researcher-5.png) | **PASS** |
| `Researcher-6` Publish: Research Admin approves the resubmitted paper | /admin/content (Pending Review) | Pending Review tab -> Approve on the paper card | as named | PATCH /api/admin-panel/articles/beaaa84a-905c-4010-a3b3-4017 -> 200 | st: pending_review / - -> published / 2026-10-02 17:11; notes: 11 -> 12 | [img](audit_logs/matrix/shots/Researcher-6.png) | **PASS** |
| `Researcher-7` Publish: researcher sees the paper as Published | /research/papers | log in as researcher, Published filter | button/Open navigation menu ; button/Off shift ; checkbox/Research Admin · T3 ; button/R ; group/Off shift00:0 | - | st: published / 2026-10-02 17:11 -> published / 2026-10-02 17:11 | [img](audit_logs/matrix/shots/Researcher-7.png) | **FAIL** |
| `Researcher-8` Login | /login -> /research | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Researcher-8.png) | **PASS** |
| `Researcher-9` Publish (retry in a clean session): researcher sees the paper as Publi | /research/papers | Published filter on My Papers | as named | - | st: published -> published | [img](audit_logs/matrix/shots/Researcher-9.png) | **PASS** |

**Request Revision through the Research Admin UI (submitted paper)** (`wf_nf5_research_flow_fariha.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `ResearchAdmin-1` Login | /login -> /admin | type credentials, press Log In | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/ResearchAdmin-1.png) | **PASS** |
| `ResearchAdmin-2` NF-5: the action is offered only for submissions pending review | /admin/content | open Research & Articles -> All Content, inspect cards | violations [] pending 1 others 17 :: Pending [Approve,Request revision,History,Edit,Feature] / Needs Revision  | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-2.png) | **FAIL** |
| `ResearchAdmin-3` NF-5: Request revision requires a reason (empty / too short / blank re | /admin/content (Pending Review) | Pending Review tab -> Request revision -> type nothing, "ab", spaces | short-reason message shown=true | - | article: pending_review / notes= / v1 -> pending_review / notes= / v1; snapshots: 1 -> 1; notifications: 0 -> 0 | [img](audit_logs/matrix/shots/ResearchAdmin-3.png) | **PASS** |
| `ResearchAdmin-4` NF-5: request revision with a reason | /admin/content (Pending Review) | type the reason -> Request revision | as named | PATCH /api/admin-panel/articles/beaaa84a-905c-4010-a3b3-4017 -> 200 | article: pending_review / notes= / v1 -> needs_revision / notes=Pleas; snapshots: 1 -> 2; notifications: 0 -> 1 | [img](audit_logs/matrix/shots/ResearchAdmin-4.png) | **PASS** |
| `ResearchAdmin-5` NF-5: the card now shows the status and the open request; the action i | /admin/content (All Content) | reload -> All Content (the orange "Revision requested: <reason>" line  | as named | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-5.png) | **PASS** |
| `ResearchAdmin-6` NF-5: History shows the current status and the revision entry | /admin/content (History dialog) | History -> read dialog | text button/R button/Back checkbox/Off shift group/ tablist/ tab/All Content tab/Pending Review tab/Featured t | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-6.png) | **FAIL** |
| `ResearchAdmin-7` NF-5: the author is told (notification) and sees the reason on the pap | /research/papers | log in as the author (separate browser) -> My papers -> Needs Revision | as named | POST /api/auth/login/ -> 200 | notifications: 1 -> 1; article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-7.png) | **PASS** |
| `ResearchAdmin-8` NF-5: a non-admin (farmer) cannot reach the research moderation screen | /admin/content | log in as farmer -> navigate to /admin/content | as named | POST /api/auth/login/ -> 200 | article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-8.png) | **PASS** |
| `ResearchAdmin-9` NF-5: a non-admin (researcher (the author)) cannot reach the research  | /admin/content | log in as researcher (the author) -> navigate to /admin/content | as named | POST /api/auth/login/ -> 200 | article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-9.png) | **PASS** |

**Request Revision through the Research Admin UI (seeded pending paper)** (`wf_nf5_pending_paper_mahmud.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `ResearchAdmin-2` NF-5: the action is offered only for submissions pending review | /admin/content | open Research & Articles -> All Content, inspect cards | violations [] pending 1 others 16 :: Published [History,Edit,Unfeature,Hide] / Needs Revision [History,Edit,Fe | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-2.png) | **FAIL** |
| `ResearchAdmin-3` NF-5: Request revision requires a reason (empty / too short / blank re | /admin/content (Pending Review) | Pending Review tab -> Request revision -> type nothing, "ab", spaces | short-reason message shown=true | - | article: pending_review / notes= / v1 -> pending_review / notes= / v1; snapshots: 1 -> 1; notifications: 0 -> 0 | [img](audit_logs/matrix/shots/ResearchAdmin-3.png) | **PASS** |
| `ResearchAdmin-4` NF-5: request revision with a reason | /admin/content (Pending Review) | type the reason -> Request revision | as named | PATCH /api/admin-panel/articles/68d42cfb-1bf4-4158-9fda-7162 -> 200 | article: pending_review / notes= / v1 -> needs_revision / notes=Pleas; snapshots: 1 -> 2; notifications: 0 -> 1 | [img](audit_logs/matrix/shots/ResearchAdmin-4.png) | **PASS** |
| `ResearchAdmin-5` NF-5: the card now shows the status and the open request; the action i | /admin/content (All Content) | reload -> All Content (the orange "Revision requested: <reason>" line  | as named | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-5.png) | **PASS** |
| `ResearchAdmin-6` NF-5: History shows the current status and the revision entry | /admin/content (History dialog) | History -> read dialog | as named | - | - | [img](audit_logs/matrix/shots/ResearchAdmin-6.png) | **PASS** |
| `ResearchAdmin-8` NF-5: a non-admin (farmer) cannot reach the research moderation screen | /admin/content | log in as farmer -> navigate to /admin/content | as named | POST /api/auth/login/ -> 200 | article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-8.png) | **PASS** |
| `ResearchAdmin-9` NF-5: a non-admin (researcher (the author)) cannot reach the research  | /admin/content | log in as researcher (the author) -> navigate to /admin/content | as named | POST /api/auth/login/ -> 403 | article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-9.png) | **PASS** |
| `ResearchAdmin-8r` Login | /login -> /admin | type credentials, press Log In | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/ResearchAdmin-8r.png) | **PASS** |
| `ResearchAdmin-9r` NF-5: the author is told (notification) and sees the reason on the pap | /research/papers | log in as the author (separate browser) -> My papers -> Needs Revision | as named | POST /api/auth/login/ -> 200 | notifications: 1 -> 1; article: needs_revision / notes=Pleas -> needs_revision / notes=Pleas | [img](audit_logs/matrix/shots/ResearchAdmin-9r.png) | **PASS** |

### 8. Delivery person

* **Account / status:** regr.rider@example.com, regr.rider2@example.com (fresh, approved, set up through the ORM)
* **Database:** `featherflow_matrix`

**Accept three offers; each detail shows its pins** (`wf_rider.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login -> /delivery | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` NF-4: accept offer 1 of 3 | /delivery/orders (New) | Orders tab -> Accept | as named | PATCH /api/delivery/requests/ecef2999-d9f8-41ad-b1bd-3214d87 -> 200 | deliveries: delivered,pending,pending,pe -> delivered,pending,pending,ac | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |
| `Deliveryperson-3` NF-4: accept offer 2 of 3 | /delivery/orders (New) | Orders tab -> Accept | as named | PATCH /api/delivery/requests/fb27a44b-672c-4a08-b66a-ea2942c -> 200 | deliveries: delivered,pending,pending,ac -> delivered,pending,accepted,a | [img](audit_logs/matrix/shots/Deliveryperson-3.png) | **PASS** |
| `Deliveryperson-4` NF-4: accept offer 3 of 3 | /delivery/orders (New) | Orders tab -> Accept | as named | PATCH /api/delivery/requests/24eacb42-4d91-44d1-9bde-0c6a8fc -> 200 | deliveries: delivered,pending,accepted,a -> delivered,accepted,accepted, | [img](audit_logs/matrix/shots/Deliveryperson-4.png) | **PASS** |
| `Deliveryperson-5` NF-3/NF-7: rider sees all three active deliveries, each detail shows i | /delivery (Orders -> Active -> Details) | Active tab -> Details on each card | {"A":{"pickup":"23.84200,90.25700","drop":"23.78050,90.40100","addr":true},"B":{"pickup":"24.00230,90.42030"," | - | deliveries: delivered,accepted,accepted, -> delivered,accepted,accepted, | [img](audit_logs/matrix/shots/Deliveryperson-5.png) | **PASS** |

**Map with several active deliveries** (`wf_rider_map.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login -> /delivery | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` NF-4: three active deliveries and nothing chosen -> a chooser, no impl | /delivery (Map tab) | open the dashboard -> press the Map tab | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |
| `Deliveryperson-3` NF-4: select delivery A -> A's route and ETA | /delivery/map | tap the card for A | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-3.png) | **PASS** |
| `Deliveryperson-4` NF-4: Change delivery -> select B -> the map becomes B's | /delivery/map | Change delivery -> tap the card for B | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-4.png) | **PASS** |
| `Deliveryperson-5` NF-4: refreshing the page preserves B | /delivery/map | reload the page on the Map tab | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-5.png) | **PASS** |
| `Deliveryperson-6` NF-4: after Change delivery and a refresh nothing is selected implicit | /delivery/map | Change delivery -> reload the page | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-6.png) | **PASS** |
| `Deliveryperson-7` NF-4: opening delivery C from the Active list passes C's id to the Map | /delivery (Orders -> Active -> Details - | Orders -> Active -> Details of C -> Back -> Map tab | as named | - | - | [img](audit_logs/matrix/shots/Deliveryperson-7.png) | **PASS** |
| `Deliveryperson-8` Login | /login -> /delivery | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-8.png) | **PASS** |
| `Deliveryperson-9` NF-4: the completed delivery C leaves no cached map; A and B are offer | /delivery/map | open the Map tab after C was approved (page reload, and again without  | ids  statuses delivered,delivered,delivered,accepted,accepted text button/Back group/Which delivery do you wan | - | statuses: delivered,delivered,delivere -> delivered,delivered,delivere | [img](audit_logs/matrix/shots/Deliveryperson-9.png) | **FAIL** |

**Open Map while a delivery is completed elsewhere** (`wf_stale.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` NF-4: rider selects delivery A on the Map and leaves the page open | /delivery/map | Map tab -> tap A | as named | - | status: accepted -> accepted; statuses: delivered,delivered,accepted -> delivered,delivered,accepted | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |
| `Deliveryperson-3` Delivery A is taken through pickup, delivery, arrival and proof by the | /delivery (detail of A) | Mark as Picked Up -> On The Way -> Mark Arrived -> upload photo -> Sub | as named | PATCH /api/delivery/orders/24eacb42-4d91-44d1-9bde-0c6a8fc13 -> 200; POST /api/delivery/orders/24eacb42-4d91-44d1-9bde-0c6a8fc13b -> 201 | status: accepted -> proof_submitted; statuses: delivered,delivered,accepted -> delivered,proof_submitted,de | [img](audit_logs/matrix/shots/Deliveryperson-3.png) | **PASS** |
| `Deliveryperson-4` Admin approves A's proof (completion) while the rider's Map still show | /admin/delivery-proofs | Delivery Proofs -> Approve -> "Approve & complete" | as named | POST /api/admin-panel/delivery-proofs/7c4a346e-7442-4a15-bef -> 200 | status: proof_submitted -> delivered; statuses: delivered,proof_submitted,de -> delivered,delivered,delivere | [img](audit_logs/matrix/shots/Deliveryperson-4.png) | **PASS** |
| `Deliveryperson-5` NF-4: with NO reload the open Map drops A (completed) - no cached rout | /delivery/map | wait on the open Map page (no reload) | as named | - | status: delivered -> delivered; statuses: delivered,delivered,delivere -> delivered,delivered,delivere | [img](audit_logs/matrix/shots/Deliveryperson-5.png) | **PASS** |
| `Deliveryperson-6` NF-4: after a reload A is still gone and nothing stale is restored | /delivery/map | reload the Map page | as named | - | status: delivered -> delivered; statuses: delivered,delivered,delivere -> delivered,delivered,delivere | [img](audit_logs/matrix/shots/Deliveryperson-6.png) | **PASS** |

**Proof lifecycle: picked up -> arrived -> proof submitted** (`wf_proof_1.json`)

| Step | Route | UI action | Expected / actual | State-changing API calls | DB before -> after | Screenshot | Result |
|---|---|---|---|---|---|---|---|
| `Deliveryperson-1` Login | /login | log in | as named | POST /api/auth/login/ -> 200 | - | [img](audit_logs/matrix/shots/Deliveryperson-1.png) | **PASS** |
| `Deliveryperson-2` Proof lifecycle: assigned -> picked up | /delivery (detail of C) | press "Mark as Picked Up" | as named | PATCH /api/delivery/orders/ecef2999-d9f8-41ad-b1bd-3214d8767 -> 200 | status: accepted -> picked_up; events: 0 -> 1 | [img](audit_logs/matrix/shots/Deliveryperson-2.png) | **PASS** |
| `Deliveryperson-3` Proof lifecycle: picked up -> out for delivery | /delivery (detail of C) | press "On The Way" | as named | PATCH /api/delivery/orders/ecef2999-d9f8-41ad-b1bd-3214d8767 -> 200 | status: picked_up -> on_the_way; events: 1 -> 2 | [img](audit_logs/matrix/shots/Deliveryperson-3.png) | **PASS** |
| `Deliveryperson-4` Proof lifecycle: out for delivery -> arrived | /delivery (detail of C) | press "Mark Arrived" | as named | PATCH /api/delivery/orders/ecef2999-d9f8-41ad-b1bd-3214d8767 -> 200 | status: on_the_way -> arrived; events: 2 -> 3 | [img](audit_logs/matrix/shots/Deliveryperson-4.png) | **PASS** |
| `Deliveryperson-5` Proof lifecycle: arrived -> proof submitted (photo) | /delivery (detail of C) | Take/Upload Delivery Photo -> Submit Delivery Proof | as named | POST /api/delivery/orders/ecef2999-d9f8-41ad-b1bd-3214d8767f -> 201 | status: arrived -> proof_submitted; proofs: - -> submitted#1; earnings: 0 -> 0 | [img](audit_logs/matrix/shots/Deliveryperson-5.png) | **PASS** |

### Non-passing steps (all explained)

* **Script assertion literals tied to the previous retest data** (state verified correct): `Farmer-2r` (expense count compared with one earlier RT expense), `Farmer-7r/-8r` (expected zero existing orders; the count was unchanged by the failed attempts), `FeedAdmin-3/-5` (the delivery list now starts with an older rejected row because the offers had been released first), `ResearchAdmin-2` (expected at least three pending papers; the database has one, with zero violations), `ResearchAdmin-6` on the second paper (History button off-screen after scrolling; passes on the first), `Deliveryperson-9` (superseded by the stale-ID workflow), `PharmacyAdmin-7/-9` (audit-trail text expectations written for the old retest), `Suspendedpharmacy-14r` (after the admin denied the appeal the screen correctly offers "Submit appeal" again instead of "View appeal"), `Researcher-7` (same-session publish view; its clean-session retry `Researcher-9` passes).
* **Legacy doctor script** (`wf_doctor.json`): `Doctor-3` (the weekly slot already existed from an earlier run - nothing to publish); `Doctor-6/-7/-8` assert state of a hard-wired consultation while the script issues the prescription on the first completed card: the prescription POST returned **201** (it returned 500 before the fix in section 2), the follow-up and close-case assertions then looked at the wrong consultation. Case close/reopen and notes were verified by `wf_nf6.json`; follow-up scheduling by `test_doctor_flow.py`.
* **`Doctor-2` in `wf_nf6.json`:** the first close attempt used the wrong button; the menu-based `Close Case` step passed.

## 4. Gates run after the last code change

| Gate | Result |
|---|---|
| `manage.py check` / `migrate --check` | no issues / exit 0 |
| `manage.py test` | `COLLECTED 40 | RAN 40 | PASSED 40 | FAILURES 0 | ERRORS 0 | SKIPPED 0 | EXPECTED-FAILURES 0 | UNEXPECTED-SUCCESSES 0` |
| `scripts/run_all_tests.py` (`audit_logs/final/run_all_tests.log`) | **52 suites, 2082 assertions, 0 failures**, 0 errors, 0 skips, runtime 233 s, no flaky rerun |
| `flutter analyze` / `flutter test` / `flutter build web --release` | no issues / 316 passed / built |
