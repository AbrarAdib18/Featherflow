# Targeted regression rerun after the NF-3..NF-7, F-014 and F-015 fixes

Written for: the engineer deciding whether to rerun the full eight-role matrix. HEAD is still `6a036eb`; **nothing was committed**. **The project remains in repair status.**

## 1. Result in one table

| Gate / workflow | Result |
|---|---|
| `manage.py check` / `migrate --check` | no issues / nothing to apply (exit 0) |
| `manage.py test` | `COLLECTED 39 | RAN 39 | PASSED 39 | FAILURES 0 | ERRORS 0 | SKIPPED 0 | EXPECTED-FAILURES 0 | UNEXPECTED-SUCCESSES 0` |
| `scripts/run_all_tests.py` -> `audit_logs/gate/run_all_tests_after_gate.log` | **52 suites, 2075 assertions, 0 failures**, 0 errors (a crashed script would show as FAIL / no summary: none), skips: the scripts have no skip mechanism (0), runtime **251 s**, no flaky test (nothing needed a rerun) |
| `flutter analyze` / `flutter test` | no issues / **316 passed** (one test added for the persisted map selection) |
| Chrome workflows (this run) | **105 of 107 recorded steps pass**; the 2 that do not pass are explained in section 4 (one wrong expected literal in my script, one count that assumed a clean database) - in both the application state is correct |

Order followed: NF-3 -> NF-4 -> NF-7 -> NF-5 -> NF-6 -> script suite -> suspended pharmacy -> delivery proof lifecycle -> Doctors & Patients. The full eight-role matrix was **not** run (section 6).

## 2. Code changes made while doing this (all uncommitted)

Running the workflows exactly as specified exposed three gaps; each was fixed and then re-verified:

* **Refresh must preserve the selected delivery (NF-4).** The selection used to live only in memory, so a page refresh dropped it. It is now stored per rider (`SharedPreferences`, key `delivery_selected_order_<user id>`), restored only if that delivery is still active, removed by "Change delivery", and forgotten when the delivery completes. Nothing is ever selected implicitly.
* **Pickup shown to admin and rider (NF-7).** On assignment the order stores `pickup {name, address, latitude, longitude}` (the supplier of the first item); the admin order card shows `Pickup: <supplier, address> (lat, lng)` and the rider detail shows `Pickup pin: lat, lng` next to `Drop pin`.
* **Short offer window for testing (NF-7).** `DELIVERY_OFFER_WINDOW_SECONDS` (default 180) overrides the offer expiry; this run used 45 s. The default behaviour is unchanged.

## 3. Environment

Isolated database `featherflow_nf` (clone of `featherflow_retest`), API on `127.0.0.1:8000`, release web build on `:8080`, Chrome via Playwright. **Set-up (not verification) through the ORM:** a fresh farmer `regr.farmer@example.com` (with a farm), and two fresh approved riders (`regr.rider`, `regr.rider2`) - `audit_logs/tools/regr_setup.py`. Everything else - supplier coordinates, the fresh product, checkout, orders, assignments, acceptances, proofs, approvals - was done through the UI. The retest and development databases were not touched. API-level calls made by the harness are listed in section 5 and labelled; the network stubs in Doctors & Patients (HTTP 500 / empty list) are browser-level fault injection and labelled in the step.

## 4. Workflow results

### P1-a  Feed admin set-up: distinct supplier pickup coordinates + a fresh product (NF-7 set-up, UI)

| Step | Result | Note |
|---|---|---|
| `FeedAdmin-1` Login | PASS |  |
| `FeedAdmin-2` Supplier pickup coordinates: Demo Nourish Feeds Ltd | PASS |  |
| `FeedAdmin-3` Supplier pickup coordinates: Demo Golden Grain Feeds | PASS |  |
| `FeedAdmin-4` Supplier pickup coordinates: Demo Premium Poultry Nutrition | PASS |  |
| `FeedAdmin-5` Fresh product created through the form | PASS |  |
| `FeedAdmin-6` Fresh product approved via the row menu | PASS |  |

### P1-b  NF-3 fresh farmer: location required / invalid / valid, three+ orders with distinct coordinates

| Step | Result | Note |
|---|---|---|
| `Farmer-2` NF-3: location is required (Place order blocked with no location) | PASS |  |
| `Farmer-3` NF-3: invalid locations are rejected, no order is created | PASS | {"range":true,"outside":true,"letters":true} |
| `Farmer-4` NF-3: place order A with a valid location | PASS |  |
| `Farmer-5` NF-3: place order B with a valid location | PASS |  |
| `Farmer-6` NF-3: place order C with a valid location | PASS |  |
| `Farmer-7` NF-3: farmer order details show each order with its own pin | PASS |  |
| `Farmer-8r` NF-3: place order D with a valid location | PASS |  |
| `Farmer-9r` NF-3: place order E with a valid location | PASS |  |
| `Farmer-9r` Login | PASS |  |
| `Farmer-10r` NF-3: place order F with a valid location | PASS |  |

### P1-c  NF-3 / NF-7 feed admin: order details show the location; assignment stores the supplier pickup

| Step | Result | Note |
|---|---|---|
| `FeedAdmin-1` Login | PASS |  |
| `FeedAdmin-2` NF-3: admin order details show each order's address and map location | PASS |  |
| `FeedAdmin-3` NF-7: assign order A to the fresh rider | PASS |  |
| `FeedAdmin-4` NF-7: assign order B to the fresh rider | PASS |  |
| `FeedAdmin-5` NF-7: assign order C to the fresh rider | PASS |  |
| `FeedAdmin-6` NF-7: admin order details now show the pickup name, address and coordinates | PASS |  |

### P1-d  NF-3 / NF-4 rider: accept three offers; each detail shows its own pickup and drop-off pins

| Step | Result | Note |
|---|---|---|
| `Deliveryperson-1` Login | PASS |  |
| `Deliveryperson-2` NF-4: accept offer 1 of 3 | PASS |  |
| `Deliveryperson-3` NF-4: accept offer 2 of 3 | PASS |  |
| `Deliveryperson-4` NF-4: accept offer 3 of 3 | PASS |  |
| `Deliveryperson-5` NF-3/NF-7: rider sees all three active deliveries, each detail shows its own pickup and drop-off pins | PASS | {"A":{"pickup":"23.84200,90.25700","drop":"23.78050,90.40100","addr":true},"B":{"pickup":"24.00230,90.42030","drop":"23.86100,90.35500","addr":true},"C":{"pickup":"23.623 |

### P1-e  NF-4 rider Map with several active deliveries

| Step | Result | Note |
|---|---|---|
| `Deliveryperson-1` Login | PASS |  |
| `Deliveryperson-2` NF-4: three active deliveries and nothing chosen -> a chooser, no implicit map | PASS |  |
| `Deliveryperson-3` NF-4: select delivery A -> A's route and ETA | PASS |  |
| `Deliveryperson-4` NF-4: Change delivery -> select B -> the map becomes B's | PASS |  |
| `Deliveryperson-5` NF-4: refreshing the page preserves B | PASS |  |
| `Deliveryperson-6` NF-4: after Change delivery and a refresh nothing is selected implicitly | PASS |  |
| `Deliveryperson-7` NF-4: opening delivery C from the Active list passes C's id to the Map | PASS |  |
| `Deliveryperson-8` Login | PASS |  |
| `Deliveryperson-9` NF-4: the completed delivery C leaves no cached map; A and B are offered again | PASS |  |

### P1-f  NF-4 stale-ID regression: the open Map while delivery A is completed elsewhere

| Step | Result | Note |
|---|---|---|
| `Deliveryperson-1` Login | PASS |  |
| `Deliveryperson-2` NF-4: rider selects delivery A on the Map and leaves the page open | PASS |  |
| `Deliveryperson-3` Delivery A is taken through pickup, delivery, arrival and proof by the rider (second session) | PASS |  |
| `Deliveryperson-4` Admin approves A's proof (completion) while the rider's Map still shows A | PASS |  |
| `Deliveryperson-5` NF-4: with NO reload the open Map drops A (completed) - no cached route for A | PASS |  |
| `Deliveryperson-6` NF-4: after a reload A is still gone and nothing stale is restored | PASS |  |

### P1-g  NF-7 expired assignment offer (45 s window), idempotency, reassignment

| Step | Result | Note |
|---|---|---|
| `Expiry-1` Login (admin) | PASS |  |
| `Expiry-2` NF-7: assign order D (offer window 45 s) | PASS |  |
| `Expiry-3` NF-7: the rider sees the live offer in the New tab | PASS |  |
| `Expiry-4` NF-7: the FARMER is the first reader after expiry and sees the order as available (Pending), not Assigned | PASS |  |
| `Expiry-5` NF-7: the rider no longer sees the expired offer (New tab) | PASS |  |
| `Expiry-6` NF-7: repeating the supported expiry command and page loads changes nothing (idempotent) | PASS | released 0 stale offer(s) / released 0 stale offer(s) |
| `Expiry-7` NF-7: the admin sees an actionable order (Reassign rider is offered) and reassigns it | PASS |  |
| `Expiry-8` NF-7: the rider accepts the reassigned offer | PASS |  |

### P2-a  NF-5 Research Admin Request Revision

| Step | Result | Note |
|---|---|---|
| `ResearchAdmin-1` Login | PASS |  |
| `ResearchAdmin-2` NF-5: the action is offered only for submissions pending review | PASS |  |
| `ResearchAdmin-3` NF-5: Request revision requires a reason (empty / too short / blank rejected, nothing sent) | PASS | short-reason message shown=true |
| `ResearchAdmin-4` NF-5: request revision with a reason | PASS |  |
| `ResearchAdmin-5` NF-5: the card now shows the status and the open request; the action is gone | PASS |  |
| `ResearchAdmin-6` NF-5: History shows the current status and the revision entry | PASS |  |
| `ResearchAdmin-7` NF-5: the author is told (notification) and sees the reason on the paper | PASS |  |
| `ResearchAdmin-8` NF-5: a non-admin (farmer) cannot reach the research moderation screen | PASS |  |
| `ResearchAdmin-9` NF-5: a non-admin (researcher (the author)) cannot reach the research moderation screen | PASS |  |

### P2-b  NF-6 Doctor case-note editing

| Step | Result | Note |
|---|---|---|
| `Doctor-2` NF-6: a closed case cannot be edited ("reopen to edit notes") | PASS |  |
| `Doctor-3` NF-6: reopen the case (status only - no notes are resent) | PASS |  |
| `Doctor-4` NF-6: editor opens with existing values; Save is disabled until something changes | PASS |  |
| `Doctor-5` NF-6: record diagnosis and treatment (first save) | PASS |  |
| `Doctor-6` NF-6: a recorded diagnosis cannot be blanked (validation, nothing sent) | PASS |  |
| `Doctor-7` NF-6: partial edit sends only the changed field; other notes are preserved | PASS |  |
| `Doctor-8` NF-6: a concurrent edit from another device is not overwritten (conflict) | PASS |  |
| `Doctor-9` NF-6: reload the latest notes, re-apply the edit, save | PASS |  |
| `Doctor-10` NF-6: audit history shows revision, author, timestamp, previous and new value | PASS |  |
| `Doctor-11` NF-6: refresh preserves the saved notes | PASS |  |
| `Doctor-13` NF-6: the patient (farmer) cannot reach the doctor case notes | PASS |  |
| `Doctor-14` NF-6: another doctor does not see this patient case | PASS |  |
| `Doctor-13r` Login | PASS |  |
| `Doctor-14r` NF-6: saving identical content again adds no history entry (Save stays disabled) | PASS |  |

### P3-a  Suspended pharmacy

| Step | Result | Note |
|---|---|---|
| `Suspendedpharmacy-1` Login (suspended) | PASS |  |
| `Suspendedpharmacy-2` Locked panel + earnings visible | PASS |  |
| `Suspendedpharmacy-3` Profile tab | PASS |  |
| `Suspendedpharmacy-4` Earnings (API) | PASS | earnings API 200 {"total_orders":0,"gross_sales":"0.00","featherflow_commission":"0.00","pharmacy_earnings":"0.00"} |
| `Suspendedpharmacy-5` Locked operational tab: Catalogue | PASS |  |
| `Suspendedpharmacy-6` Locked operational tab: Inventory | PASS |  |
| `Suspendedpharmacy-7` Locked operational tab: Orders | PASS |  |
| `Suspendedpharmacy-8` Locked operational tab: Suppliers | PASS |  |
| `Suspendedpharmacy-9` Locked operational tab: Analytics | PASS |  |
| `Suspendedpharmacy-10` Locked operational actions refused by API | PASS | POST /api/pharmacy/medicines/ -> 401; GET /api/pharmacy/orders/ -> 401; GET /api/pharmacy/suppliers/ -> 401; GET /api/pharmacy/inventory/summary/ -> 401; GET /api/pharmac |
| `Suspendedpharmacy-11` Chat with Pharmacy Admin | PASS |  |
| `Suspendedpharmacy-12` Appeal | PASS |  |
| `Suspendedpharmacy-13` After appeal: still locked, appeal under review | FAIL | RT Suspended Pharmacy Dhaka Sign out Refresh status Contact Pharmacy Admin View appeal Lifetime earnings ৳ 0.00 0 orders / 2 / submitted |
| `Suspendedpharmacy-14` Relogin in a fresh browser: still locked, appeal still under review | PASS |  |

### P3-b  Delivery proof lifecycle (part 1 rider -> arrived -> proof)

| Step | Result | Note |
|---|---|---|
| `Deliveryperson-1` Login | PASS |  |
| `Deliveryperson-2` Proof lifecycle: assigned -> picked up | PASS |  |
| `Deliveryperson-3` Proof lifecycle: picked up -> out for delivery | PASS |  |
| `Deliveryperson-4` Proof lifecycle: out for delivery -> arrived | PASS |  |
| `Deliveryperson-5` Proof lifecycle: arrived -> proof submitted (photo) | FAIL | {"status":"proof_submitted","proofs":"submitted#1","earnings":"0","expenses":"0","source":"proof_under_review","events":"4"} |

### P3-b  Delivery proof lifecycle (part 2 admin rejects with a reason)

| Step | Result | Note |
|---|---|---|
| `FeedAdmin-1` Login | PASS |  |
| `FeedAdmin-2` Proof review: reject with a reason (order must NOT complete) | PASS |  |

### P3-b  Delivery proof lifecycle (part 3 rider resubmits)

| Step | Result | Note |
|---|---|---|
| `Deliveryperson-1` Login | PASS |  |
| `Deliveryperson-2` Proof lifecycle: rider sees the rejection and resubmits | PASS |  |

### P3-b  Delivery proof lifecycle (part 4 admin approves; duplicate approval)

| Step | Result | Note |
|---|---|---|
| `FeedAdmin-1` Login | PASS |  |
| `FeedAdmin-2` Proof review: approve -> completed | PASS |  |
| `FeedAdmin-3` Completion: duplicate approval refused (API-labelled check), financial rows exactly once | PASS | HTTP 409 |

### P3-c  Doctors & Patients with a consultation that has no appointment time

| Step | Result | Note |
|---|---|---|
| `DoctorsPatients-1` Login (farmer) | PASS |  |
| `DoctorsPatients-2` Farmer requests a consultation with "Request any available time" (no appointment time) | PASS |  |
| `DoctorsPatients-3` Login (doctor admin) | PASS |  |
| `DoctorsPatients-4` Admin Doctors & Patients: the panel loads and lists doctors | PASS |  |
| `DoctorsPatients-5` Admin Consultations: the no-time consultation appears and the missing time is rendered meaningfully | PASS |  |
| `DoctorsPatients-6` An API error is an error state with Retry - not "No consultations yet" (network stub: HTTP 500) | PASS |  |
| `DoctorsPatients-7` Genuinely empty data shows the empty state (network stub: empty list), different from the error | PASS |  |
| `DoctorsPatients-8` Doctor panel shows the real request and no fabricated demo clients | PASS |  |

**The two non-passing steps (state verified correct):**

* `Deliveryperson-5` in the proof lifecycle part 1: I expected the new proof row to read `pending#1`; the application (correctly) stores `submitted#1`. Recorded state after the step: delivery `proof_submitted`, proof `submitted#1`, no earning, no expense, source order `proof_under_review`. The literal was corrected for parts 3 and 4, which pass.
* `Suspendedpharmacy-13`: expected exactly one appeal; the cloned database already held one from the earlier retest, so there are two (`2 / submitted`). The screen shows the locked shell with **View appeal** and the account stays `suspended`.

Earlier attempts that failed for harness reasons (a wrong product picked in the two-column grid, a card-click on the list container, an address hard-coded in an assertion, a rider at his 3-delivery capacity) are preserved in `audit_logs/regr/aborted_runs/`; every final run started from a freshly cloned database or a new order.

### Key evidence (API, database before/after, screenshot)

#### `Farmer-4` NF-3: place order A with a valid location - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** Regr Fresh Feed 816112 / drop 23.7805,90.4010 / Regr Address A, Savar Bazar
* **UI action:** Add to cart -> Proceed to checkout -> type address -> Enter coordinates manually -> type lat/lng -> Place order
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/farmers/feed-catalogue/orders/ body={"items":[{"product_id":"f417ec45-6aa0-49db-86cc-fa168faa83ca","quantity":1}],"delivery_address":"Regr Address A, Savar Bazar","latitude":23.7805,"longitude":90.401,"payment_method":"c` -> `201 {"id":"FEED-DEA425C0CB","order_number":"#FD-25C0CB","farmer_id":"69a95e37-eba2-4b0a-b710-b5051cb3d0cd","farmer_name":"Regr Farmer","farmer_phone":"+8801900770001","delivery_address":"Regr Address A, Savar Bazar","latitud`
* **Database before -> after:**
  * `orders`: `0` -> `1`
  * `last`: `-` -> `#FD-25C0CB | 23.7805,90.401 | Regr Address A, Savar Bazar | Regr Fresh Feed 816112 | created`
  * `stock`: `3961` -> `3960`
* **Screenshot:** [Farmer-4.png](audit_logs/regr/shots/Farmer-4.png)

#### `Farmer-5` NF-3: place order B with a valid location - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** Broiler Starter Economy / drop 23.8610,90.3550 / Regr Address B, Ashulia
* **UI action:** Add to cart -> Proceed to checkout -> type address -> Enter coordinates manually -> type lat/lng -> Place order
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/farmers/feed-catalogue/orders/ body={"items":[{"product_id":"09372ff5-44a7-4c02-a36f-bef6148de42f","quantity":1}],"delivery_address":"Regr Address B, Ashulia","latitude":23.861,"longitude":90.355,"payment_method":"cod","` -> `201 {"id":"FEED-1858C519F0","order_number":"#FD-C519F0","farmer_id":"69a95e37-eba2-4b0a-b710-b5051cb3d0cd","farmer_name":"Regr Farmer","farmer_phone":"+8801900770001","delivery_address":"Regr Address B, Ashulia","latitude":2`
* **Database before -> after:**
  * `orders`: `1` -> `2`
  * `last`: `#FD-25C0CB | 23.7805,90.401 | Regr Address A, Savar Bazar | Regr Fresh Feed 816112 | created` -> `#FD-C519F0 | 23.861,90.355 | Regr Address B, Ashulia | Broiler Starter Economy | created`
  * `stock`: `3960` -> `3959`
* **Screenshot:** [Farmer-5.png](audit_logs/regr/shots/Farmer-5.png)

#### `FeedAdmin-3` NF-7: assign order A to the fresh rider - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-25C0CB -> Regr Rider; supplier Demo Nourish Feeds Ltd
* **UI action:** Assign rider -> choose Regr Rider -> Assign
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/feed-catalogue/orders/FEED-DEA425C0CB/assign/ body={"rider_id":"915b8bfe-a353-4aef-9870-ad7435e0915f","notes":""}` -> `201 {"id":"FEED-DEA425C0CB","items":[{"unit":"bag_50kg","quantity":1,"line_total":777.0,"product_id":"f417ec45-6aa0-49db-86cc-fa168faa83ca","unit_price":777.0,"company_name":"Demo Nourish Feeds Ltd","product_name":"Regr Fres`
* **Database before -> after:**
  * `order`: `created / ds=- / rider=- / pickup=-,-` -> `assigned / ds=pending / rider=915b8bfe-a353-4aef-9870-ad7435e0915f / pickup=23.842,90.257`
  * `delivery`: `none` -> `pending pickup=23.842000,90.257000 [Demo Nourish Feeds Ltd, Savar, Dhaka, Savar, Dhaka] drop=23.780500,90.401000 [Regr Address A, Savar Bazar]`
* **Screenshot:** [FeedAdmin-3.png](audit_logs/regr/shots/FeedAdmin-3.png)

#### `Deliveryperson-5` NF-3/NF-7: rider sees all three active deliveries, each detail shows its own pickup and drop-off pins - **PASS**

* **Role / route:** Delivery person / `/delivery (Orders -> Active -> Details)`
* **Test data:** {"A":"b9f8e068-f942-4478-bb57-e7aaf5d2da86","B":"8c498ad9-abf9-4ec3-a59c-02b01112ce6c","C":"b4b9bbc5-b914-4b51-b29a-eaab9602fb87"}
* **UI action:** Active tab -> Details on each card
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `GET /api/delivery/orders/b9f8e068-f942-4478-bb57-e7aaf5d2da86/route/` -> `200 {"polyline":"qsopCui{ePl@EfEy@bYcGjEs@`BMzCO`E?`FNvFJhAFtEn@fOz@j[hCzEZbLJx`@\\tD?hCQ`Ci@jAe@vUaLfJyDdMeFzE_BnCk@`JwAtFaAdAWfAa@rAw@vAeArBgBbAw@jCoCpBmCnBmDb@eArAeFh@mCVyBNqCBwCIeCa@kEwDq[[yASkA[{CS{CYiDYmFEyCKaCUeOEcE@}`
  * `GET /api/delivery/orders/8c498ad9-abf9-4ec3-a59c-02b01112ce6c/route/` -> `200 {"polyline":"m}nqCod{fPZFFFVELDv@BfALhAHjA@fAHXCJEVSXJr@AjBJz@NdBl@j@Zn@r@v@vCpDjKz@fCtAbDf@hAV`AP~@bAfHJ~@h@rD~Gl^f@hCTjCN\\RpBBj@j@hH\\`D@`@ZhCf@tG`@tEfA`RJx@DpBCTx@tMd@bGl@dGDn@|BjSRpBVdBb@zDG`@FnC?dAHf@V\\lAx@^Ht@Cd@`
  * `GET /api/delivery/orders/b4b9bbc5-b914-4b51-b29a-eaab9602fb87/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
* **Database before -> after:**
  * `deliveries`: `accepted,accepted,accepted` -> `accepted,accepted,accepted`
* **Screenshot:** [Deliveryperson-5.png](audit_logs/regr/shots/Deliveryperson-5.png)
* **Note:** {"A":{"pickup":"23.84200,90.25700","drop":"23.78050,90.40100","addr":true},"B":{"pickup":"24.00230,90.42030","drop":"23.86100,90.35500","addr":true},"C":{"pickup":"23.62380,90.50000","drop":"23.70100,90.45200","addr":true}}

#### `Deliveryperson-4` NF-4: Change delivery -> select B -> the map becomes B's - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** B = 8c498ad9-abf9-4ec3-a59c-02b01112ce6c
* **UI action:** Change delivery -> tap the card for B
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `GET /api/delivery/orders/8c498ad9-abf9-4ec3-a59c-02b01112ce6c/route/` -> `200 {"polyline":"m}nqCod{fPZFFFVELDv@BfALhAHjA@fAHXCJEVSXJr@AjBJz@NdBl@j@Zn@r@v@vCpDjKz@fCtAbDf@hAV`AP~@bAfHJ~@h@rD~Gl^f@hCTjCN\\RpBBj@j@hH\\`D@`@ZhCf@tG`@tEfA`RJx@DpBCTx@tMd@bGl@dGDn@|BjSRpBVdBb@zDG`@FnC?dAHf@V\\lAx@^Ht@Cd@`
* **Screenshot:** [Deliveryperson-4.png](audit_logs/regr/shots/Deliveryperson-4.png)

#### `Deliveryperson-5` NF-4: refreshing the page preserves B - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** reload /delivery/map
* **UI action:** reload the page on the Map tab
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `GET /api/delivery/orders/8c498ad9-abf9-4ec3-a59c-02b01112ce6c/route/` -> `200 {"polyline":"m}nqCod{fPZFFFVELDv@BfALhAHjA@fAHXCJEVSXJr@AjBJz@NdBl@j@Zn@r@v@vCpDjKz@fCtAbDf@hAV`AP~@bAfHJ~@h@rD~Gl^f@hCTjCN\\RpBBj@j@hH\\`D@`@ZhCf@tG`@tEfA`RJx@DpBCTx@tMd@bGl@dGDn@|BjSRpBVdBb@zDG`@FnC?dAHf@V\\lAx@^Ht@Cd@`
  * `GET /api/delivery/orders/8c498ad9-abf9-4ec3-a59c-02b01112ce6c/route/` -> `200 {"polyline":"m}nqCod{fPZFFFVELDv@BfALhAHjA@fAHXCJEVSXJr@AjBJz@NdBl@j@Zn@r@v@vCpDjKz@fCtAbDf@hAV`AP~@bAfHJ~@h@rD~Gl^f@hCTjCN\\RpBBj@j@hH\\`D@`@ZhCf@tG`@tEfA`RJx@DpBCTx@tMd@bGl@dGDn@|BjSRpBVdBb@zDG`@FnC?dAHf@V\\lAx@^Ht@Cd@`
* **Screenshot:** [Deliveryperson-5.png](audit_logs/regr/shots/Deliveryperson-5.png)

#### `Deliveryperson-5` NF-4: with NO reload the open Map drops A (completed) - no cached route for A - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** wait for the 4-second refresh
* **UI action:** wait on the open Map page (no reload)
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `status`: `delivered` -> `delivered`
  * `statuses`: `delivered,delivered,accepted` -> `delivered,delivered,accepted`
* **Screenshot:** [Deliveryperson-5.png](audit_logs/regr/shots/Deliveryperson-5.png)

#### `Expiry-4` NF-7: the FARMER is the first reader after expiry and sees the order as available (Pending), not Assigned - **PASS**

* **Role / route:** Expiry / `/farmer/feed-management/marketplace (My Orders)`
* **Test data:** #FD-08D792
* **UI action:** open My Orders after the offer window
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `order`: `created / ds=offer_expired / rider=-` -> `created / ds=offer_expired / rider=-`
  * `deliveries`: `rejected:Offer expired` -> `rejected:Offer expired`
  * `events`: `0` -> `0`
  * `notes`: `16` -> `16`
  * `history`: `1` -> `1`
* **Screenshot:** [Expiry-4.png](audit_logs/regr/shots/Expiry-4.png)

#### `Expiry-6` NF-7: repeating the supported expiry command and page loads changes nothing (idempotent) - **PASS**

* **Role / route:** Expiry / `(command) + /admin/feed`
* **Test data:** manage.py expire_stale_offers x2 + two admin reloads
* **UI action:** run the command twice, reload the admin order list twice
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `order`: `created / ds=offer_expired / rider=-` -> `created / ds=offer_expired / rider=-`
  * `deliveries`: `rejected:Offer expired` -> `rejected:Offer expired`
  * `events`: `0` -> `0`
  * `notes`: `16` -> `16`
  * `history`: `1` -> `1`
* **Screenshot:** [Expiry-6.png](audit_logs/regr/shots/Expiry-6.png)
* **Note:** released 0 stale offer(s) | released 0 stale offer(s)

#### `FeedAdmin-2` Proof review: reject with a reason (order must NOT complete) - **PASS**

* **Role / route:** Feed Admin / `/admin/delivery-proofs`
* **Test data:** Photo is blurry - please retake it at the farm gate.
* **UI action:** Delivery Proofs -> Reject -> type reason -> confirm
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/delivery-proofs/3a7de126-b2c3-4290-8ed3-4dc078022e4b/reject/ body={"reason":"Photo is blurry - please retake it at the farm gate."}` -> `200 {"id":"3a7de126-b2c3-4290-8ed3-4dc078022e4b","attempt":1,"status":"rejected","url":"http://127.0.0.1:8000/api/auth/registration-documents/eyJwIjoicmVnaXN0cmF0aW9uL2RlbGl2ZXJ5X3Byb29mLzM5ODcxZDlhZjNhZjQxODBiMTg0MzJkOWE1YT`
* **Database before -> after:**
  * `status`: `proof_submitted` -> `proof_rejected`
  * `proofs`: `submitted#1` -> `rejected#1`
  * `earnings`: `0` -> `0`
  * `expenses`: `0` -> `0`
  * `source`: `proof_under_review` -> `proof_under_review`
  * `events`: `4` -> `5`
* **Screenshot:** [FeedAdmin-2.png](audit_logs/regr/shots/FeedAdmin-2.png)

#### `FeedAdmin-2` Proof review: approve -> completed - **PASS**

* **Role / route:** Feed Admin / `/admin/delivery-proofs`
* **Test data:** attempt 2
* **UI action:** Delivery Proofs -> Approve -> "Approve & complete"
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/delivery-proofs/161965de-b65a-4098-983b-570665fe2f5c/approve/ body={}` -> `200 {"id":"161965de-b65a-4098-983b-570665fe2f5c","attempt":2,"status":"approved","url":"http://127.0.0.1:8000/api/auth/registration-documents/eyJwIjoicmVnaXN0cmF0aW9uL2RlbGl2ZXJ5X3Byb29mLzU2M2M2MzZmYWVhNzQ4OGE4NmM4OWQxOTMyMj`
* **Database before -> after:**
  * `status`: `proof_submitted` -> `delivered`
  * `proofs`: `rejected#1,submitted#2` -> `rejected#1,approved#2`
  * `earnings`: `0` -> `1`
  * `expenses`: `0` -> `1`
  * `source`: `proof_under_review` -> `delivered`
  * `events`: `6` -> `7`
* **Screenshot:** [FeedAdmin-2.png](audit_logs/regr/shots/FeedAdmin-2.png)

#### `FeedAdmin-3` Completion: duplicate approval refused (API-labelled check), financial rows exactly once - **PASS**

* **Role / route:** Feed Admin / `(API)`
* **Test data:** POST approve again
* **UI action:** repeat approve with the admin token
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/delivery-proofs/161965de-b65a-4098-983b-570665fe2f5c/approve/ body={}` -> `409 {"detail":"This proof was already reviewed (approved); the order is delivered."}`
* **Database before -> after:**
  * `status`: `delivered` -> `delivered`
  * `proofs`: `rejected#1,approved#2` -> `rejected#1,approved#2`
  * `earnings`: `1` -> `1`
  * `expenses`: `1` -> `1`
  * `source`: `delivered` -> `delivered`
  * `events`: `7` -> `7`
* **Screenshot:** [FeedAdmin-3.png](audit_logs/regr/shots/FeedAdmin-3.png)
* **Note:** HTTP 409

## 5. API-level evidence (labelled; not UI steps)

`audit_logs/tools/regr_evidence.py` -> `audit_logs/regr/api_evidence.json`.

**Stored locations - each order has its own, tied to its own product and supplier:**

| Order | Drop-off stored | Delivery address | Product | Supplier | Pickup stored |
|---|---|---|---|---|---|
| A `#FD-25C0CB` | 23.7805, 90.401 | Regr Address A, Savar Bazar | Regr Fresh Feed 816112 | Demo Nourish Feeds Ltd | Demo Nourish Feeds Ltd, Savar, Dhaka, Savar, Dhaka (23.842, 90.257) |
| B `#FD-C519F0` | 23.861, 90.355 | Regr Address B, Ashulia | Broiler Starter Economy | Demo Golden Grain Feeds | Demo Golden Grain Feeds, Gazipur, Gazipur Sadar, Gazipur (24.0023, 90.4203) |
| C `#FD-252176` | 23.701, 90.452 | Regr Address C, Keraniganj | Layer Starter Mash | Demo Premium Poultry Nutrition | Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sad (23.6238, 90.5) |
| F `#FD-08D792` | 23.73, 90.33 | Regr Address F, Mirpur Section | Broiler Finisher Premium | Demo Golden Grain Feeds | Demo Golden Grain Feeds, Gazipur, Gazipur Sadar, Gazipur (24.0023, 90.4203) |
| E `#FD-ADB480` | 23.95, 90.28 | Regr Address E, Savar Union | Breeder Rearing Feed | Demo Golden Grain Feeds | Demo Golden Grain Feeds, Gazipur, Gazipur Sadar, Gazipur (24.0023, 90.4203) |
| D `#FD-269AEF` | 23.91, 90.3 | Regr Address D, Dhamrai | Chick Grower Feed | Demo Nourish Feeds Ltd | Demo Nourish Feeds Ltd, Savar, Dhaka, Savar, Dhaka (23.842, 90.257) |

**Routing - the pickup is routable and the route belongs to its delivery** (`GET /api/delivery/orders/<id>/route/`, Google Routes; `start->pickup` / `end->drop` = distance between the first / last polyline point and the stored coordinate):

| Delivery | HTTP | origin | distance / ETA | pickup (stored) | drop-off (stored) | first point | last point | start->pickup | end->drop |
|---|---|---|---|---|---|---|---|---|---|
| A `b9f8e068` | 200 | pickup | 23.06 km / 49 min | [23.842, 90.257] | [23.7805, 90.401] | [23.84201, 90.25707] | [23.78052, 90.401] | 0.007 km | 0.002 km |
| B `8c498ad9` | 200 | pickup | 25.29 km / 60 min | [24.0023, 90.4203] | [23.861, 90.355] | [24.00231, 90.42008] | [23.86097, 90.3552] | 0.022 km | 0.021 km |
| C `b4b9bbc5` | 200 | pickup | 11.26 km / 20 min | [23.6238, 90.5] | [23.701, 90.452] | [23.62379, 90.49998] | [23.70101, 90.45217] | 0.002 km | 0.017 km |
| F `bb0dafb8` | 200 | pickup | 41.06 km / 85 min | [24.0023, 90.4203] | [23.73, 90.33] | [24.00231, 90.42008] | [23.72995, 90.32998] | 0.022 km | 0.006 km |

Four deliveries, four different routes (distinct coordinates), every route starts at its supplier and ends at its farmer drop-off within 25 m.

**Negative checks (must be rejected):**

| Check | Request | Status | Expected |
|---|---|---|---|
| anonymous cannot place a feed order | `POST /api/farmers/feed-catalogue/orders/` | 401 | 401 ok |
| a rider cannot place a feed order | `POST /api/farmers/feed-catalogue/orders/` | 403 | 403 ok |
| no location -> 400 delivery_location_required | `POST /api/farmers/feed-catalogue/orders/` | 400 delivery_location_required | 400 ok |
| outside Bangladesh -> 400 | `POST /api/farmers/feed-catalogue/orders/` | 400 delivery_location_outside_service_area | 400 ok |
| a farmer cannot assign a rider | `POST /api/admin-panel/feed-catalogue/orders/FEED-DEA425C0CB/assign/` | 403 | 403 ok |
| a rider cannot read another rider's route (rider2 -> delivery A) | `GET /api/delivery/orders/b9f8e068-f942-4478-bb57-e7aaf5d2da86/route/` | 404 | 404 ok |
| a rider cannot answer another rider's offer | `PATCH /api/delivery/requests/8c498ad9-abf9-4ec3-a59c-02b01112ce6c/respond/` | 404 | 404 ok |

The fresh farmer ended with 6 orders - exactly the ones placed through valid checkouts (A, B, C, D, E, F); the failed attempts (no location, 95/90, 51.5/10.1, abc/xyz, wrong-product guard) created none (see `Farmer-2`/`-3`: orders `0` before and after).

## 6. What was NOT verified and the decision on the full matrix

* **No notification deep-link exists for deliveries** in the rider app, so "open a delivery from a notification" could not be tested; the list -> Details -> Map path (which passes the id) was.
* The NF-4 part-2 step in `rider_map` (`Deliveryperson-9`) ran in a fresh browser profile and therefore does not by itself prove the cache is cleared; that proof is the **stale** workflow (`wf_stale`), where the Map stays open on A while A is completed by another session.
* Suspended pharmacy: the locked-operations API calls returned 401 (not 403) for the suspended token; the UI refuses them either way. This matches the earlier retest.
* The Doctors & Patients 500 / empty states use browser-level request stubbing (the real backend never fails on demand).
* The script suite ran while Chrome workflows were using the machine; it passed, nothing was flaky.

**Decision.** The targeted workflows (NF-3, NF-4, NF-7, NF-5, NF-6), the high-risk regressions (suspended pharmacy, proof lifecycle, null-time Doctors & Patients) and the 52-suite script run all pass. The full eight-role matrix **is now warranted but was not run in this pass**; the branches it must cover are the ones listed in the request (checkout with/without location, one vs several deliveries, expired vs accepted offers, revision request, doctor note create/edit, suspended pharmacy, proof reject/resubmit/approve, null-time consultation) plus the new persisted-selection and pickup-display behaviour. Until it runs, the project stays in repair status.

## 7. Screenshots

* [Admin-assign-A.png](audit_logs/regr/shots/Admin-assign-A.png)
* [Admin-assign-B.png](audit_logs/regr/shots/Admin-assign-B.png)
* [Admin-assign-C.png](audit_logs/regr/shots/Admin-assign-C.png)
* [Admin-new-product-filled.png](audit_logs/regr/shots/Admin-new-product-filled.png)
* [Admin-orders-assigned.png](audit_logs/regr/shots/Admin-orders-assigned.png)
* [Admin-orders.png](audit_logs/regr/shots/Admin-orders.png)
* [Deliveryperson-1.png](audit_logs/regr/shots/Deliveryperson-1.png)
* [Deliveryperson-2.png](audit_logs/regr/shots/Deliveryperson-2.png)
* [Deliveryperson-3.png](audit_logs/regr/shots/Deliveryperson-3.png)
* [Deliveryperson-4.png](audit_logs/regr/shots/Deliveryperson-4.png)
* [Deliveryperson-5.png](audit_logs/regr/shots/Deliveryperson-5.png)
* [Deliveryperson-6.png](audit_logs/regr/shots/Deliveryperson-6.png)
* [Deliveryperson-7.png](audit_logs/regr/shots/Deliveryperson-7.png)
* [Deliveryperson-8.png](audit_logs/regr/shots/Deliveryperson-8.png)
* [Deliveryperson-9.png](audit_logs/regr/shots/Deliveryperson-9.png)
* [Doctor-1.png](audit_logs/regr/shots/Doctor-1.png)
* [Doctor-10.png](audit_logs/regr/shots/Doctor-10.png)
* [Doctor-11.png](audit_logs/regr/shots/Doctor-11.png)
* [Doctor-12.png](audit_logs/regr/shots/Doctor-12.png)
* [Doctor-13.png](audit_logs/regr/shots/Doctor-13.png)
* [Doctor-13r.png](audit_logs/regr/shots/Doctor-13r.png)
* [Doctor-14.png](audit_logs/regr/shots/Doctor-14.png)
* [Doctor-14r.png](audit_logs/regr/shots/Doctor-14r.png)
* [Doctor-2.png](audit_logs/regr/shots/Doctor-2.png)
* [Doctor-3.png](audit_logs/regr/shots/Doctor-3.png)
* [Doctor-4.png](audit_logs/regr/shots/Doctor-4.png)
* [Doctor-5.png](audit_logs/regr/shots/Doctor-5.png)
* [Doctor-6.png](audit_logs/regr/shots/Doctor-6.png)
* [Doctor-7.png](audit_logs/regr/shots/Doctor-7.png)
* [Doctor-8.png](audit_logs/regr/shots/Doctor-8.png)
* [Doctor-9.png](audit_logs/regr/shots/Doctor-9.png)
* [Doctor-after-refresh.png](audit_logs/regr/shots/Doctor-after-refresh.png)
* [Doctor-after-reload.png](audit_logs/regr/shots/Doctor-after-reload.png)
* [Doctor-closed-case.png](audit_logs/regr/shots/Doctor-closed-case.png)
* [Doctor-conflict.png](audit_logs/regr/shots/Doctor-conflict.png)
* [Doctor-editor-filled.png](audit_logs/regr/shots/Doctor-editor-filled.png)
* [Doctor-editor-open.png](audit_logs/regr/shots/Doctor-editor-open.png)
* [Doctor-history.png](audit_logs/regr/shots/Doctor-history.png)
* [Doctor-identical-save.png](audit_logs/regr/shots/Doctor-identical-save.png)
* [Doctor-saved.png](audit_logs/regr/shots/Doctor-saved.png)
* [Doctor-status-menu.png](audit_logs/regr/shots/Doctor-status-menu.png)
* [Doctor-validation.png](audit_logs/regr/shots/Doctor-validation.png)
* [Doctors-admin-500.png](audit_logs/regr/shots/Doctors-admin-500.png)
* [Doctors-admin-consultations.png](audit_logs/regr/shots/Doctors-admin-consultations.png)
* [Doctors-admin-doctors.png](audit_logs/regr/shots/Doctors-admin-doctors.png)
* [Doctors-admin-empty.png](audit_logs/regr/shots/Doctors-admin-empty.png)
* [Doctors-admin-regr-farmer.png](audit_logs/regr/shots/Doctors-admin-regr-farmer.png)
* [Doctors-doctor-appointments.png](audit_logs/regr/shots/Doctors-doctor-appointments.png)
* [Doctors-farmer-filled.png](audit_logs/regr/shots/Doctors-farmer-filled.png)
* [DoctorsPatients-1.png](audit_logs/regr/shots/DoctorsPatients-1.png)
* [DoctorsPatients-2.png](audit_logs/regr/shots/DoctorsPatients-2.png)
* [DoctorsPatients-3.png](audit_logs/regr/shots/DoctorsPatients-3.png)
* [DoctorsPatients-4.png](audit_logs/regr/shots/DoctorsPatients-4.png)
* [DoctorsPatients-5.png](audit_logs/regr/shots/DoctorsPatients-5.png)
* [DoctorsPatients-6.png](audit_logs/regr/shots/DoctorsPatients-6.png)
* [DoctorsPatients-7.png](audit_logs/regr/shots/DoctorsPatients-7.png)
* [DoctorsPatients-8.png](audit_logs/regr/shots/DoctorsPatients-8.png)
* [Expiry-1.png](audit_logs/regr/shots/Expiry-1.png)
* [Expiry-2.png](audit_logs/regr/shots/Expiry-2.png)
* [Expiry-3.png](audit_logs/regr/shots/Expiry-3.png)
* [Expiry-4.png](audit_logs/regr/shots/Expiry-4.png)
* [Expiry-5.png](audit_logs/regr/shots/Expiry-5.png)
* [Expiry-6.png](audit_logs/regr/shots/Expiry-6.png)
* [Expiry-7.png](audit_logs/regr/shots/Expiry-7.png)
* [Expiry-8.png](audit_logs/regr/shots/Expiry-8.png)
* [Expiry-admin.png](audit_logs/regr/shots/Expiry-admin.png)
* [Expiry-assign-first.png](audit_logs/regr/shots/Expiry-assign-first.png)
* [Expiry-assign-second.png](audit_logs/regr/shots/Expiry-assign-second.png)
* [Expiry-farmer.png](audit_logs/regr/shots/Expiry-farmer.png)
* [Expiry-rider-after.png](audit_logs/regr/shots/Expiry-rider-after.png)
* [Expiry-rider-offer.png](audit_logs/regr/shots/Expiry-rider-offer.png)
* [Farmer-1.png](audit_logs/regr/shots/Farmer-1.png)
* [Farmer-10r.png](audit_logs/regr/shots/Farmer-10r.png)
* [Farmer-1r.png](audit_logs/regr/shots/Farmer-1r.png)
* [Farmer-2.png](audit_logs/regr/shots/Farmer-2.png)
* [Farmer-2r.png](audit_logs/regr/shots/Farmer-2r.png)
* [Farmer-3.png](audit_logs/regr/shots/Farmer-3.png)
* [Farmer-4.png](audit_logs/regr/shots/Farmer-4.png)
* [Farmer-5.png](audit_logs/regr/shots/Farmer-5.png)
* [Farmer-6.png](audit_logs/regr/shots/Farmer-6.png)
* [Farmer-6r.png](audit_logs/regr/shots/Farmer-6r.png)
* [Farmer-7.png](audit_logs/regr/shots/Farmer-7.png)
* [Farmer-7r.png](audit_logs/regr/shots/Farmer-7r.png)
* [Farmer-8r.png](audit_logs/regr/shots/Farmer-8r.png)
* [Farmer-9r.png](audit_logs/regr/shots/Farmer-9r.png)
* [Farmer-checkout-A.png](audit_logs/regr/shots/Farmer-checkout-A.png)
* [Farmer-checkout-B.png](audit_logs/regr/shots/Farmer-checkout-B.png)
* [Farmer-checkout-C.png](audit_logs/regr/shots/Farmer-checkout-C.png)
* [Farmer-checkout-D.png](audit_logs/regr/shots/Farmer-checkout-D.png)
* [Farmer-checkout-E.png](audit_logs/regr/shots/Farmer-checkout-E.png)
* [Farmer-checkout-F.png](audit_logs/regr/shots/Farmer-checkout-F.png)
* [Farmer-invalid-letters.png](audit_logs/regr/shots/Farmer-invalid-letters.png)
* [Farmer-invalid-outside.png](audit_logs/regr/shots/Farmer-invalid-outside.png)
* [Farmer-invalid-range.png](audit_logs/regr/shots/Farmer-invalid-range.png)
* [Farmer-my-orders.png](audit_logs/regr/shots/Farmer-my-orders.png)
* [Farmer-no-location.png](audit_logs/regr/shots/Farmer-no-location.png)
* [FeedAdmin-1.png](audit_logs/regr/shots/FeedAdmin-1.png)
* [FeedAdmin-2.png](audit_logs/regr/shots/FeedAdmin-2.png)
* [FeedAdmin-3.png](audit_logs/regr/shots/FeedAdmin-3.png)
* [FeedAdmin-4.png](audit_logs/regr/shots/FeedAdmin-4.png)
* [FeedAdmin-5.png](audit_logs/regr/shots/FeedAdmin-5.png)
* [FeedAdmin-6.png](audit_logs/regr/shots/FeedAdmin-6.png)
* [NonAdmin-farmer.png](audit_logs/regr/shots/NonAdmin-farmer.png)
* [NonAdmin-researcher.png](audit_logs/regr/shots/NonAdmin-researcher.png)
* [OtherDoctor-case-notes.png](audit_logs/regr/shots/OtherDoctor-case-notes.png)
* [Patient-doctor-notes.png](audit_logs/regr/shots/Patient-doctor-notes.png)
* [Proof-approve-confirm.png](audit_logs/regr/shots/Proof-approve-confirm.png)
* [Proof-arrived.png](audit_logs/regr/shots/Proof-arrived.png)
* [Proof-on_the_way.png](audit_logs/regr/shots/Proof-on_the_way.png)
* [Proof-picked_up.png](audit_logs/regr/shots/Proof-picked_up.png)
* [Proof-reject-dialog.png](audit_logs/regr/shots/Proof-reject-dialog.png)
* [Proof-resubmitted.png](audit_logs/regr/shots/Proof-resubmitted.png)
* [Proof-rider-sees-rejection.png](audit_logs/regr/shots/Proof-rider-sees-rejection.png)
* [Proof-submitted.png](audit_logs/regr/shots/Proof-submitted.png)
* [ResearchAdmin-1.png](audit_logs/regr/shots/ResearchAdmin-1.png)
* [ResearchAdmin-2.png](audit_logs/regr/shots/ResearchAdmin-2.png)
* [ResearchAdmin-3.png](audit_logs/regr/shots/ResearchAdmin-3.png)
* [ResearchAdmin-4.png](audit_logs/regr/shots/ResearchAdmin-4.png)
* [ResearchAdmin-5.png](audit_logs/regr/shots/ResearchAdmin-5.png)
* [ResearchAdmin-6.png](audit_logs/regr/shots/ResearchAdmin-6.png)
* [ResearchAdmin-7.png](audit_logs/regr/shots/ResearchAdmin-7.png)
* [ResearchAdmin-8.png](audit_logs/regr/shots/ResearchAdmin-8.png)
* [ResearchAdmin-9.png](audit_logs/regr/shots/ResearchAdmin-9.png)
* [ResearchAdmin-after-request.png](audit_logs/regr/shots/ResearchAdmin-after-request.png)
* [ResearchAdmin-all-content.png](audit_logs/regr/shots/ResearchAdmin-all-content.png)
* [ResearchAdmin-card-needs-revision.png](audit_logs/regr/shots/ResearchAdmin-card-needs-revision.png)
* [ResearchAdmin-dialog-empty.png](audit_logs/regr/shots/ResearchAdmin-dialog-empty.png)
* [ResearchAdmin-dialog-filled.png](audit_logs/regr/shots/ResearchAdmin-dialog-filled.png)
* [ResearchAdmin-dialog-short.png](audit_logs/regr/shots/ResearchAdmin-dialog-short.png)
* [ResearchAdmin-history.png](audit_logs/regr/shots/ResearchAdmin-history.png)
* [Researcher-sees-revision.png](audit_logs/regr/shots/Researcher-sees-revision.png)
* [Rider-active-3.png](audit_logs/regr/shots/Rider-active-3.png)
* [Rider-detail-A.png](audit_logs/regr/shots/Rider-detail-A.png)
* [Rider-detail-B.png](audit_logs/regr/shots/Rider-detail-B.png)
* [Rider-detail-C.png](audit_logs/regr/shots/Rider-detail-C.png)
* [Rider-offers.png](audit_logs/regr/shots/Rider-offers.png)
* [RiderMap-A.png](audit_logs/regr/shots/RiderMap-A.png)
* [RiderMap-B-after-reload.png](audit_logs/regr/shots/RiderMap-B-after-reload.png)
* [RiderMap-B.png](audit_logs/regr/shots/RiderMap-B.png)
* [RiderMap-C-from-list.png](audit_logs/regr/shots/RiderMap-C-from-list.png)
* [RiderMap-after-C-completed.png](audit_logs/regr/shots/RiderMap-after-C-completed.png)
* [RiderMap-chooser.png](audit_logs/regr/shots/RiderMap-chooser.png)
* [RiderMap-chooser2.png](audit_logs/regr/shots/RiderMap-chooser2.png)
* [RiderMap-none-after-reload.png](audit_logs/regr/shots/RiderMap-none-after-reload.png)
* [Stale-A-selected.png](audit_logs/regr/shots/Stale-A-selected.png)
* [Stale-after-A-completed-no-reload.png](audit_logs/regr/shots/Stale-after-A-completed-no-reload.png)
* [Stale-after-reload.png](audit_logs/regr/shots/Stale-after-reload.png)
* [Suspendedpharmacy-1.png](audit_logs/regr/shots/Suspendedpharmacy-1.png)
* [Suspendedpharmacy-10.png](audit_logs/regr/shots/Suspendedpharmacy-10.png)
* [Suspendedpharmacy-11.png](audit_logs/regr/shots/Suspendedpharmacy-11.png)
* [Suspendedpharmacy-12.png](audit_logs/regr/shots/Suspendedpharmacy-12.png)
* [Suspendedpharmacy-13.png](audit_logs/regr/shots/Suspendedpharmacy-13.png)
* [Suspendedpharmacy-14.png](audit_logs/regr/shots/Suspendedpharmacy-14.png)
* [Suspendedpharmacy-2.png](audit_logs/regr/shots/Suspendedpharmacy-2.png)
* [Suspendedpharmacy-3.png](audit_logs/regr/shots/Suspendedpharmacy-3.png)
* [Suspendedpharmacy-4.png](audit_logs/regr/shots/Suspendedpharmacy-4.png)
* [Suspendedpharmacy-5.png](audit_logs/regr/shots/Suspendedpharmacy-5.png)
* [Suspendedpharmacy-6.png](audit_logs/regr/shots/Suspendedpharmacy-6.png)
* [Suspendedpharmacy-7.png](audit_logs/regr/shots/Suspendedpharmacy-7.png)
* [Suspendedpharmacy-8.png](audit_logs/regr/shots/Suspendedpharmacy-8.png)
* [Suspendedpharmacy-9.png](audit_logs/regr/shots/Suspendedpharmacy-9.png)
* [Suspendedpharmacy-appeal-filled.png](audit_logs/regr/shots/Suspendedpharmacy-appeal-filled.png)
* [Suspendedpharmacy-chat-typed.png](audit_logs/regr/shots/Suspendedpharmacy-chat-typed.png)
* [Suspendedpharmacy-locked-home.png](audit_logs/regr/shots/Suspendedpharmacy-locked-home.png)
* [Suspendedpharmacy-relogin.png](audit_logs/regr/shots/Suspendedpharmacy-relogin.png)
