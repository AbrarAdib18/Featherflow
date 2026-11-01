# NF-3 / NF-4 / NF-7 fix report

Baseline: `FEATHERFLOW_POST_REPAIR_VERIFICATION_REPORT.md` (99/119 workflow records, findings NF-1..NF-7). HEAD is still `6a036eb`; **nothing was committed**.

**Status: the project remains in repair status. This report covers NF-3, NF-4 and NF-7 only. It does not claim the project is complete.**

## 1. Result

| Item | Result |
|---|---|
| NF-3 delivery location at feed checkout | Fixed and verified in the browser (UI only, 7/7 farmer steps + admin/rider display) |
| NF-4 rider Map bound to the selected delivery | Fixed and verified in the browser; one rider-side display check was first wrong in my harness (see section 6) |
| NF-7 routable pickup + expired offers | Fixed and verified in the browser for farmer and admin views; **rider-side view of an expired offer is verified by backend tests only** (the available second rider cannot log in to the app: it is redirected to `/verify`) |
| Backend | `manage.py test`: Ran 31 tests in 13.127s OK; 50 script files, **1986 assertions, 0 failed** (`test_nf_repairs.py`: 85) |
| Flutter | `flutter analyze`: no issues; `flutter test`: **302 tests passed** (new: `nf3_feed_checkout_location_test.dart` 5, `nf4_map_selection_test.dart` 8, `repairs_logic_test.dart` 5, +1 in `delivery_multi_active_test.dart`) |
| Release build | `flutter build web --release` succeeded (`audit_logs/nf/flutter_build.log`) |

## 2. What was wrong and what changed

### NF-3 - delivery location at checkout
* **Cause:** the farmer checkout never sent coordinates; orders had none, so the admin card had no "Map:" line and the rider Map fell back to addresses.
* **Backend** (`delivery/geo.py`, `feed_catalogue/farmer_views.py`): `parse_location()` requires latitude+longitude, rejects partial / non-numeric / NaN / out-of-range / outside-Bangladesh values with HTTP 400 and a `code` (`delivery_location_required|incomplete|invalid|outside_service_area`) **before** stock is reduced or an order is created. The submitted address and the coordinates are stored on the order and copied to the delivery record (`delivery_lat/lng`, `delivery_address`). No default or fake location is ever substituted.
* **Flutter** (`core/location/delivery_location.dart`, `core/widgets/delivery_location_picker.dart`, `farmer_feed_marketplace_screen.dart`): "Use my current location" (GPS) or manual latitude/longitude with the same rules; Place order is disabled until a valid location exists; validation errors are shown; the checkout summary shows `Delivery location: lat, lng`; My Orders shows `Delivery pin`; the admin order card shows `Map: lat, lng`; the rider detail screen shows `Drop pin: lat, lng`.

### NF-4 - rider Map
* **Cause:** the Map tab used `activeOrders.first`.
* **Fix** (`delivery_session.dart`, `delivery_map_screen.dart`, `delivery_orders_screen.dart`): `DeliverySession.selectedOrderId`; the detail screen selects its order; the Map tab uses the explicit order passed through navigation, else the selected one, else (exactly one active delivery) that one, else **a chooser** listing pickup and drop-off per delivery. A selection that is no longer active after a refresh is dropped. "Change delivery" returns to the chooser. The polyline is bound to its order id (never shown for another order) and the map view is keyed by order id. The Active tab got a **Details** button so a delivery can be opened (and selected) from the list. The route request is `GET /api/delivery/orders/<id>/route/` for the displayed order only.

### NF-7 - pickup location and expired offers
* **Pickup:** feed suppliers (`feed_companies`) now have validated `latitude/longitude` (`repairs_nf_extension.sql`, admin client create/edit UI). On assignment the delivery pickup is the **supplier of the first order item**: its name, address, upazila, district and coordinates; the placeholder "Feed warehouse (see order items for supplier)" is gone. A supplier without coordinates is routed by address and the admin sees "Pickup location: Not set".
* **Expiry** (`delivery/offers.py`): `release_offer()` is idempotent (only a `pending` delivery is released): the delivery becomes `rejected` ("Offer expired"), the source order returns to its pre-assignment status, `delivery_status` becomes `offer_expired` (or `offer_rejected`), `assigned_rider_id` is cleared, one history entry and one admin notification are written. `sweep_stale_offers()` runs **lazily** from the admin order list/detail, the pharmacy delivery queue, the rider dashboard and request list, and **(added in this pass) the farmer feed and pharmacy order list/detail**, plus the `expire_stale_offers` command for cron. The browser run exposed that before this addition a farmer could still see the stale "assigned" state until someone else loaded a page.

## 3. Browser verification (isolated DB `featherflow_nf`, cloned from `featherflow_retest`)

API on `127.0.0.1:8000` (`POSTGRES_DB=featherflow_nf`), release web build on `:8080`, Chrome via Playwright semantics. Every functional step below is a UI action; API traffic is only observed. The only API calls made by the harness itself are the labelled read-only/negative checks in section 5.

Orders: #FD-06B4E4, #FD-960126, #FD-6E96FD. Rider: Arif Mahmud (accepts #FD-06B4E4 and #FD-960126, also has one older medicine delivery in `arrived`). The unanswered offer went to Karim Uddin.

### 3.1 Farmer - checkout location (NF-3)

#### `Farmer-1` Login - **PASS**

* **Role / route:** Farmer / `/login -> /farmer`
* **Test data:** farmer.rashed@example.com
* **UI action:** type credentials, press Log In
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"farmer.rashed@example.com","password":"***"}` -> `200 {"user":{"id":"05eebb17-4f3a-499f-bf29-0d90ba715ced","email":"farmer.rashed@example.com","phone":"+8801700001101","full_name":"Md. Rashed Karim","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/`
* **Screenshot:** [Farmer-1.png](audit_logs/nf/shots/Farmer-1.png)

#### `Farmer-2` NF-3: checkout without a location is blocked - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (Cart -> checkout)`
* **Test data:** 1 x first catalogue item, no location entered
* **UI action:** Add to cart -> Proceed to checkout -> press Place order with no location
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `orders`: `9` -> `9`
* **Screenshot:** [Farmer-checkout-empty.png](audit_logs/nf/shots/Farmer-checkout-empty.png)

#### `Farmer-3` NF-3: invalid coordinates show validation errors - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** lat 95/lng 90, then outside Bangladesh 51.5/10.1, then letters
* **UI action:** Enter coordinates manually -> type values
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `orders`: `9` -> `9`
* **Screenshot:** [Farmer-3.png](audit_logs/nf/shots/Farmer-3.png)
* **Note:** range-error=true outside-error=true letters-error=true

#### `Farmer-4` NF-3: place feed order #1 with the browser location (GPS button) - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** address "RT Village Road 5, Savar, Dhaka", GPS 23.75,90.39 (browser geolocation), COD
* **UI action:** type address -> Use my current location -> Place order
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/farmers/feed-catalogue/orders/ body={"items":[{"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","quantity":1}],"delivery_address":"DhaRT Village Road 5, Savar, Dhaka","latitude":23.75,"longitude":90.39,"payment_method` -> `201 {"id":"FEED-F24806B4E4","order_number":"#FD-06B4E4","farmer_id":"05eebb17-4f3a-499f-bf29-0d90ba715ced","farmer_name":"Md. Rashed Karim","farmer_phone":"+8801700001101","delivery_address":"DhaRT Village Road 5, Savar, Dha`
* **Database before -> after:**
  * `orders`: `9` -> `10`
  * `last`: `FEED-B78D2642FD | 23.81,90.41 | RT Village Road 5, Savar | delivered` -> `FEED-F24806B4E4 | 23.75,90.39 | DhaRT Village Road 5, Savar, Dhaka | created`
* **Screenshot:** [Farmer-4.png](audit_logs/nf/shots/Farmer-4.png)
* **Note:** location-set=true summary-row=true

#### `Farmer-5` NF-3: order shows the delivery pin in My Orders - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (My Orders)`
* **Test data:** order #1
* **UI action:** open My Orders
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Screenshot:** [Farmer-5.png](audit_logs/nf/shots/Farmer-5.png)

#### `Farmer-6` NF-3: place feed order #2 with the browser location (GPS button) - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** address "RT Farm Gate 2, Savar, Dhaka", GPS 23.75,90.39 (browser geolocation), COD
* **UI action:** type address -> Use my current location -> Place order
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/farmers/feed-catalogue/orders/ body={"items":[{"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","quantity":1}],"delivery_address":"DhaRT Farm Gate 2, Savar, Dhaka","latitude":23.75,"longitude":90.39,"payment_method":"` -> `201 {"id":"FEED-B12B960126","order_number":"#FD-960126","farmer_id":"05eebb17-4f3a-499f-bf29-0d90ba715ced","farmer_name":"Md. Rashed Karim","farmer_phone":"+8801700001101","delivery_address":"DhaRT Farm Gate 2, Savar, Dhaka"`
* **Database before -> after:**
  * `orders`: `10` -> `11`
  * `last`: `FEED-F24806B4E4 | 23.75,90.39 | DhaRT Village Road 5, Savar, Dhaka | created` -> `FEED-B12B960126 | 23.75,90.39 | DhaRT Farm Gate 2, Savar, Dhaka | created`
* **Screenshot:** [Farmer-6.png](audit_logs/nf/shots/Farmer-6.png)
* **Note:** location-set=true summary-row=true

#### `Farmer-7` NF-3: place feed order #3 with the browser location (GPS button) - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (checkout)`
* **Test data:** address "RT Farm Gate 3, Savar, Dhaka", GPS 23.75,90.39 (browser geolocation), COD
* **UI action:** type address -> Use my current location -> Place order
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/farmers/feed-catalogue/orders/ body={"items":[{"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","quantity":1}],"delivery_address":"DhaRT Farm Gate 3, Savar, Dhaka","latitude":23.75,"longitude":90.39,"payment_method":"` -> `201 {"id":"FEED-50FD6E96FD","order_number":"#FD-6E96FD","farmer_id":"05eebb17-4f3a-499f-bf29-0d90ba715ced","farmer_name":"Md. Rashed Karim","farmer_phone":"+8801700001101","delivery_address":"DhaRT Farm Gate 3, Savar, Dhaka"`
* **Database before -> after:**
  * `orders`: `11` -> `12`
  * `last`: `FEED-B12B960126 | 23.75,90.39 | DhaRT Farm Gate 2, Savar, Dhaka | created` -> `FEED-50FD6E96FD | 23.75,90.39 | DhaRT Farm Gate 3, Savar, Dhaka | created`
* **Screenshot:** [Farmer-7.png](audit_logs/nf/shots/Farmer-7.png)
* **Note:** location-set=true summary-row=true

### 3.2 Feed Admin - supplier pickup, assignment, expiry (NF-3/NF-7)

#### `FeedAdmin-1` Login - **PASS**

* **Role / route:** Feed Admin / `/login -> /admin`
* **Test data:** feed.admin@featherflow.local
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"feed.admin@featherflow.local","password":"***"}` -> `200 {"user":{"id":"94404fe9-1e28-4cb1-8381-92ee920804d9","email":"feed.admin@featherflow.local","phone":"+8801700000900","full_name":"Feed Marketplace Admin","profile_photo_url":null,"date_of_birth":"1990-01-01","present_add`
* **Screenshot:** [FeedAdmin-1.png](audit_logs/nf/shots/FeedAdmin-1.png)

#### `FeedAdmin-2` NF-7: invalid supplier pickup coordinates are rejected - **PASS**

* **Role / route:** Feed Admin / `/admin/feed-clients -> client -> edit`
* **Test data:** Demo Premium Poultry Nutrition, lat 10 / lng 10 (outside Bangladesh)
* **UI action:** edit client -> type coordinates -> Save changes
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/admin-panel/feed-catalogue/companies/9b087a34-ad47-49cf-bd19-878f32d54489/ body={"name":"Demo Premium Poultry Nutrition","contact_person":"Rafiqul Islam","contact_phone":"+8801700000703","contact_email":"premiumpoultry@` -> `400 {"detail":"This location is outside the Bangladesh delivery area.","code":"delivery_location_outside_service_area"}`
* **Database before -> after:**
  * `coords`: `23.623800,90.500000` -> `23.623800,90.500000`
* **Screenshot:** [FeedAdmin-2.png](audit_logs/nf/shots/FeedAdmin-2.png)

#### `FeedAdmin-3` NF-7: valid supplier pickup coordinates are saved - **PASS**

* **Role / route:** Feed Admin / `/admin/feed-clients -> client -> edit`
* **Test data:** Demo Premium Poultry Nutrition, 23.6238 / 90.5000 (Narayanganj)
* **UI action:** edit client -> type coordinates -> Save changes
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/admin-panel/feed-catalogue/companies/9b087a34-ad47-49cf-bd19-878f32d54489/ body={"name":"Demo Premium Poultry Nutrition","contact_person":"Rafiqul Islam","contact_phone":"+8801700000703","contact_email":"premiumpoultry@` -> `200 {"id":"9b087a34-ad47-49cf-bd19-878f32d54489","name":"Demo Premium Poultry Nutrition","contact_person":"Rafiqul Islam","contact_phone":"+8801700000703","contact_email":"premiumpoultry@example.com","address":"Narayanganj",`
* **Database before -> after:**
  * `coords`: `23.623800,90.500000` -> `23.623800,90.500000`
* **Screenshot:** [FeedAdmin-3.png](audit_logs/nf/shots/FeedAdmin-3.png)

#### `FeedAdmin-4` NF-3: admin order cards show the farmer delivery location - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-06B4E4, #FD-960126, #FD-6E96FD
* **UI action:** open Orders & Delivery
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Screenshot:** [FeedAdmin-4.png](audit_logs/nf/shots/FeedAdmin-4.png)

#### `FeedAdmin-5` NF-7: assign order #FD-6E96FD to a rider who will not answer - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-6E96FD -> Karim Uddin
* **UI action:** Assign rider -> choose Karim Uddin -> Assign
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/feed-catalogue/orders/FEED-50FD6E96FD/assign/ body={"rider_id":"364d70b9-7898-4660-96ba-d0d148e9cb2e","notes":""}` -> `201 {"id":"FEED-50FD6E96FD","items":[{"unit":"bag_50kg","quantity":1,"line_total":2900.0,"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","unit_price":2900.0,"company_name":"Demo Premium Poultry Nutrition","product_name":`
* **Database before -> after:**
  * `order`: `created / ds=- / rider=-` -> `assigned / ds=pending / rider=364d70b9-7898-4660-96ba-d0d148e9cb2e`
  * `delivery`: `none` -> `pending pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
* **Screenshot:** [FeedAdmin-5.png](audit_logs/nf/shots/FeedAdmin-5.png)

#### `FeedAdmin-6` NF-7: assign order #FD-06B4E4 (pickup from supplier) - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-06B4E4 -> Arif Mahmud
* **UI action:** Assign rider -> Arif Mahmud (default) -> Assign
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/feed-catalogue/orders/FEED-F24806B4E4/assign/ body={"rider_id":"884c7649-a4e3-436f-8d0a-65a88b6a4d13","notes":""}` -> `201 {"id":"FEED-F24806B4E4","items":[{"unit":"bag_50kg","quantity":1,"line_total":2900.0,"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","unit_price":2900.0,"company_name":"Demo Premium Poultry Nutrition","product_name":`
* **Database before -> after:**
  * `order`: `created / ds=- / rider=-` -> `assigned / ds=pending / rider=884c7649-a4e3-436f-8d0a-65a88b6a4d13`
  * `delivery`: `none` -> `pending pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
* **Screenshot:** [FeedAdmin-6.png](audit_logs/nf/shots/FeedAdmin-6.png)

#### `FeedAdmin-7` NF-7: assign order #FD-960126 (pickup from supplier) - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-960126 -> Arif Mahmud
* **UI action:** Assign rider -> Arif Mahmud (default) -> Assign
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/feed-catalogue/orders/FEED-B12B960126/assign/ body={"rider_id":"884c7649-a4e3-436f-8d0a-65a88b6a4d13","notes":""}` -> `201 {"id":"FEED-B12B960126","items":[{"unit":"bag_50kg","quantity":1,"line_total":2900.0,"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","unit_price":2900.0,"company_name":"Demo Premium Poultry Nutrition","product_name":`
* **Database before -> after:**
  * `order`: `created / ds=- / rider=-` -> `assigned / ds=pending / rider=884c7649-a4e3-436f-8d0a-65a88b6a4d13`
  * `delivery`: `none` -> `pending pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
* **Screenshot:** [FeedAdmin-7.png](audit_logs/nf/shots/FeedAdmin-7.png)

#### `FeedAdmin-8` Login - **PASS**

* **Role / route:** Feed Admin / `/login -> /admin`
* **Test data:** feed.admin@featherflow.local
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"feed.admin@featherflow.local","password":"***"}` -> `200 {"user":{"id":"94404fe9-1e28-4cb1-8381-92ee920804d9","email":"feed.admin@featherflow.local","phone":"+8801700000900","full_name":"Feed Marketplace Admin","profile_photo_url":null,"date_of_birth":"1990-01-01","present_add`
* **Screenshot:** [FeedAdmin-8.png](audit_logs/nf/shots/FeedAdmin-8.png)

#### `FeedAdmin-9` NF-7: the unanswered offer is released and the admin sees an actionable order - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-6E96FD
* **UI action:** open Orders & Delivery after the 3-minute offer window
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `order`: `assigned / ds=pending / rider=364d70b9-7898-4660-96ba-d0d148e9cb2e` -> `created / ds=offer_expired / rider=-`
  * `delivery`: `pending pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000` -> `rejected pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
* **Screenshot:** [FeedAdmin-9.png](audit_logs/nf/shots/FeedAdmin-9.png)

#### `FeedAdmin-10` NF-7: repeated page loads do not change the released order (idempotent) - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-6E96FD
* **UI action:** reload Orders & Delivery twice
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `order`: `created / ds=offer_expired / rider=-` -> `created / ds=offer_expired / rider=-`
  * `delivery`: `rejected pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000` -> `rejected pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
  * `notes`: `0` -> `0`
* **Screenshot:** [FeedAdmin-10.png](audit_logs/nf/shots/FeedAdmin-10.png)

#### `FeedAdmin-11` NF-7: the released order can be reassigned - **PASS**

* **Role / route:** Feed Admin / `/admin/feed (Orders & Delivery)`
* **Test data:** #FD-6E96FD -> Test Delivery Rider
* **UI action:** Reassign rider -> choose -> Assign
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/admin-panel/feed-catalogue/orders/FEED-50FD6E96FD/assign/ body={"rider_id":"ac6e9535-1a13-48b0-9bcf-82e095f8bc34","notes":""}` -> `201 {"id":"FEED-50FD6E96FD","items":[{"unit":"bag_50kg","quantity":1,"line_total":2900.0,"product_id":"0decbb43-eb9d-4b57-9b29-238337fa8187","unit_price":2900.0,"company_name":"Demo Premium Poultry Nutrition","product_name":`
* **Database before -> after:**
  * `order`: `created / ds=offer_expired / rider=-` -> `assigned / ds=pending / rider=ac6e9535-1a13-48b0-9bcf-82e095f8bc34`
  * `delivery`: `rejected pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000` -> `rejected pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000 ; pending pickup=23.623800,90.500000 addr=Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj drop=23.750000,90.390000`
* **Screenshot:** [FeedAdmin-11.png](audit_logs/nf/shots/FeedAdmin-11.png)

### 3.3 Rider - Map tab (NF-4)

#### `Deliveryperson-1` Login - **PASS**

* **Role / route:** Delivery person / `/login -> /delivery`
* **Test data:** rider.arif@example.com
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"rider.arif@example.com","password":"***"}` -> `200 {"user":{"id":"43d69a78-8d98-4eb1-8b33-15dfd9222640","email":"rider.arif@example.com","phone":"+8801711000401","full_name":"Arif Mahmud","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/eyJwIjoi`
  * `GET /api/delivery/orders/b0710a25-0a32-401c-ad49-cc34b2f4baa5/route/` -> `422 {"detail":"No route could be found between these locations.","code":"no_route"}`
* **Screenshot:** [Deliveryperson-1.png](audit_logs/nf/shots/Deliveryperson-1.png)

#### `Deliveryperson-3` NF-4: accept the offer for #FD-960126 - **PASS**

* **Role / route:** Delivery person / `/delivery/orders (New)`
* **Test data:** #FD-960126
* **UI action:** Orders tab -> request card -> Accept
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/delivery/requests/ec31a58c-05c5-4252-aa96-3d9bf75a8c17/respond/ body={"action":"accept"}` -> `200 {"id":"ec31a58c-05c5-4252-aa96-3d9bf75a8c17","order_number":"#FD-06B4E4","pickup_address":"Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj","delivery_address":"DhaRT Village Road 5, Savar, Dha`
  * `GET /api/delivery/orders/ec31a58c-05c5-4252-aa96-3d9bf75a8c17/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
* **Database before -> after:**
  * `delivery`: `accepted 9a794a86-41b9-432e-86f5-c6d267aa5bb2` -> `accepted 9a794a86-41b9-432e-86f5-c6d267aa5bb2`
* **Screenshot:** [Deliveryperson-3.png](audit_logs/nf/shots/Deliveryperson-3.png)

#### `Deliveryperson-5` Login - **PASS**

* **Role / route:** Delivery person / `/login -> /delivery`
* **Test data:** rider.arif@example.com
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"rider.arif@example.com","password":"***"}` -> `200 {"user":{"id":"43d69a78-8d98-4eb1-8b33-15dfd9222640","email":"rider.arif@example.com","phone":"+8801711000401","full_name":"Arif Mahmud","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/eyJwIjoi`
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-5.png](audit_logs/nf/shots/Deliveryperson-5.png)

#### `Deliveryperson-6` NF-4: Map tab with several active deliveries shows a chooser, not an arbitrary map - **PASS**

* **Role / route:** Delivery person / `/delivery (bottom nav: Map)`
* **Test data:** Arif has 3 active deliveries (2 feed + 1 older medicine)
* **UI action:** press the Map tab
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-6.png](audit_logs/nf/shots/Deliveryperson-6.png)

#### `Deliveryperson-7` NF-4: choosing the second delivery routes THAT delivery (pickup, drop-off, ETA) - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** delivery 9a794a86-41b9-432e-86f5-c6d267aa5bb2 (drop "Farm Gate 2")
* **UI action:** tap the card for Farm Gate 2
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `GET /api/delivery/orders/9a794a86-41b9-432e-86f5-c6d267aa5bb2/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-7.png](audit_logs/nf/shots/Deliveryperson-7.png)

#### `Deliveryperson-8` NF-4: Change delivery -> the other delivery is routed, never the previous one - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** delivery ec31a58c-05c5-4252-aa96-3d9bf75a8c17 (drop "Village Road 5")
* **UI action:** Change delivery -> tap the card for Village Road 5
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `GET /api/delivery/orders/ec31a58c-05c5-4252-aa96-3d9bf75a8c17/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
* **Screenshot:** [Deliveryperson-8.png](audit_logs/nf/shots/Deliveryperson-8.png)

#### `Deliveryperson-9` NF-4: a page reload does not restore an implicit/cached delivery - **PASS**

* **Role / route:** Delivery person / `/delivery/map`
* **Test data:** 
* **UI action:** reload /delivery/map
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-9.png](audit_logs/nf/shots/Deliveryperson-9.png)

#### `Deliveryperson-22r` NF-4: opening a delivery then the Map tab keeps that delivery - **PASS**

* **Role / route:** Delivery person / `/delivery/orders (Active) -> detail -> Map`
* **Test data:** delivery 9a794a86-41b9-432e-86f5-c6d267aa5bb2
* **UI action:** Active tab -> Details of Farm Gate 2 -> Back -> Map tab
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
  * `GET /api/delivery/orders/b0710a25-0a32-401c-ad49-cc34b2f4baa5/route/` -> `422 {"detail":"No route could be found between these locations.","code":"no_route"}`
  * `GET /api/delivery/orders/ec31a58c-05c5-4252-aa96-3d9bf75a8c17/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
  * `GET /api/delivery/orders/9a794a86-41b9-432e-86f5-c6d267aa5bb2/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-22r.png](audit_logs/nf/shots/Deliveryperson-22r.png)

#### `Deliveryperson-23` Login - **PASS**

* **Role / route:** Delivery person / `/login -> /delivery`
* **Test data:** rider.arif@example.com
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"rider.arif@example.com","password":"***"}` -> `200 {"user":{"id":"43d69a78-8d98-4eb1-8b33-15dfd9222640","email":"rider.arif@example.com","phone":"+8801711000401","full_name":"Arif Mahmud","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/eyJwIjoi`
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-23.png](audit_logs/nf/shots/Deliveryperson-23.png)

#### `Deliveryperson-24` NF-3: rider delivery detail shows the farmer drop pin (address + coordinates) - **PASS**

* **Role / route:** Delivery person / `/delivery (Orders -> Active -> Details)`
* **Test data:** delivery 9a794a86-41b9-432e-86f5-c6d267aa5bb2
* **UI action:** Orders -> Active -> Details of the Farm Gate 2 delivery
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
  * `GET /api/delivery/orders/b0710a25-0a32-401c-ad49-cc34b2f4baa5/route/` -> `422 {"detail":"No route could be found between these locations.","code":"no_route"}`
  * `GET /api/delivery/orders/ec31a58c-05c5-4252-aa96-3d9bf75a8c17/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
  * `GET /api/delivery/orders/9a794a86-41b9-432e-86f5-c6d267aa5bb2/route/` -> `200 {"polyline":"u_eoC{wjgPFNCPODA?Mj@IfAm@Pc@ReI`FqBzAqA|@qCvAqAXqAJyIb@u@BeBP_B^uGp@sCZmB\\cBPoDh@}D`@iE^ePdBiEf@}I~@}Df@aDf@mGxAqOzCaGzAaZbKeDbAsMtC{Bp@oYjGiBd@oB`@eCh@mFfA_B\\]BsFtAw@JaDx@mE`A}G`BwEz@sFrAkEnAkBf@uC|@mDz@`
  * `PATCH /api/delivery/location/ body={"lat":23.75,"lng":90.39}` -> `200 {"current_lat":23.75,"current_lng":90.39}`
* **Screenshot:** [Deliveryperson-24.png](audit_logs/nf/shots/Deliveryperson-24.png)

### 3.4 Farmer - first reader of an expired offer (NF-7)

#### `Farmer-1` Login - **PASS**

* **Role / route:** Farmer / `/login -> /farmer`
* **Test data:** farmer.rashed@example.com
* **UI action:** log in
* **API requests/responses (state-changing + route calls; read-only GETs omitted):**
  * `POST /api/auth/login/ body={"email":"farmer.rashed@example.com","password":"***"}` -> `200 {"user":{"id":"05eebb17-4f3a-499f-bf29-0d90ba715ced","email":"farmer.rashed@example.com","phone":"+8801700001101","full_name":"Md. Rashed Karim","profile_photo_url":"http://127.0.0.1:8000/api/auth/registration-documents/`
* **Screenshot:** [Farmer-1.png](audit_logs/nf/shots/Farmer-1.png)

#### `Farmer-2` NF-7: farmer is the first reader of an expired offer and sees "Pending", not "Assigned" - **PASS**

* **Role / route:** Farmer / `/farmer/feed-management/marketplace (My Orders)`
* **Test data:** #FD-6E96FD (second offer, rider never answered)
* **UI action:** open My Orders
* **API requests/responses:** no state-changing or route call (read-only GETs omitted); this step proves that nothing was sent.
* **Database before -> after:**
  * `order`: `assigned / ds=pending / rider=ac6e9535-1a13-48b0-9bcf-82e095f8bc34` -> `created / ds=offer_expired / rider=-`
  * `delivery`: `rejected:Offer expired ; pending:-` -> `rejected:Offer expired ; rejected:Offer expired`
* **Screenshot:** [Farmer-expired-offer.png](audit_logs/nf/shots/Farmer-expired-offer.png)

### 3.5 Superseded / failed rider attempts (kept for honesty)

`audit_logs/nf/nfwf_delivery_person.json` also contains these records, which are **not** counted as evidence:

* `Deliveryperson-2` NF-4: accept the offer for #FD-06B4E4 - FAIL: delivery pending ec31a58c-05c5-4252-aa96-3d9bf75a8c17
* `Deliveryperson-4` NF-4: delivery detail shows the drop pin - FAIL: text button|Back group| tablist| tab|New tab|Active tab|Completed tab|History tabpanel|Submit Delivery ProofMark as Picked UpMark as Picked 
* `Deliveryperson-10` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids  text button|Back group| tablist| tab|New tab|Active tab|Completed tab|History tabpanel|Submit Delivery ProofMark as Picked UpMark as Pi
* `Deliveryperson-11r` Login - PASS: 
* `Deliveryperson-12r` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids ec31a58c-05c5-4252-aa96-3d9bf75a8c17 text null|#ec31a58c-05c5-4252-aa96-3d9bf75a8c17AcceptedDelivery StatusAcceptedPicked UpOut for deli
* `Deliveryperson-13r` Login - PASS: 
* `Deliveryperson-14r` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids b0710a25-0a32-401c-ad49-cc34b2f4baa5,ec31a58c-05c5-4252-aa96-3d9bf75a8c17,9a794a86-41b9-432e-86f5-c6d267aa5bb2 text null|#9a794a86-41b9-
* `Deliveryperson-15r` Login - PASS: 
* `Deliveryperson-16r` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids  text null|#9a794a86-41b9-432e-86f5-c6d267aa5bb2AcceptedDelivery StatusAcceptedPicked UpOut for deliveryArrivedProof reviewCompletedCust
* `Deliveryperson-17r` Login - PASS: 
* `Deliveryperson-18r` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids  text button|Back group| tablist| tab|New tab|Active tab|Completed tab|History tabpanel|DetailsSubmit Delivery ProofDetailsMark as Picke
* `Deliveryperson-19r` Login - PASS: 
* `Deliveryperson-20r` NF-4: opening a delivery then the Map tab keeps that delivery - FAIL: ids  text button|Change delivery button|Open in Google Maps button|Dashboard Tab 1 of 5 button|Orders Tab 2 of 5 button|Map Tab 3 of 5 butto
* `Deliveryperson-21r` Login - PASS: 

Reasons: (a) `Deliveryperson-2` expected the first Accept to belong to #FD-06B4E4 but accepted the other offer first (the end state - both offers accepted - is what `Deliveryperson-3` and the DB show); (b) `-4` opened the wrong card; (c) `-10..-21r` were harness iterations: wrong start route, the Map bottom-nav is not present on the pushed detail page, route requests of intermediate wrong clicks were counted, and the chooser used to truncate the drop address (this was a real UI defect that I fixed: pickup and drop-off are now separate lines). `-22r` is the final passing run of that scenario. Earlier whole-run attempts are in `audit_logs/nf/aborted_runs/`.

## 4. Route coordinates (Google Routes through `GET /api/delivery/orders/<id>/route/`)

| Delivery | Pickup (DB) | Drop-off (DB) | First / last decoded polyline point | Distance / ETA |
|---|---|---|---|---|
| `ec31a58c-05c5-4252-aa96-3d9bf75a8c17` (#FD-06B4E4) | `23.623800,90.500000 | Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj` | `23.750000,90.390000 | DhaRT Village Road 5, Savar, Dhaka` | [23.62379, 90.49998] -> [23.74989, 90.39039] (222 points) | 20.78 km / 46 min (google_routes, origin `pickup`) |
| `9a794a86-41b9-432e-86f5-c6d267aa5bb2` (#FD-960126) | `23.623800,90.500000 | Demo Premium Poultry Nutrition, Narayanganj, Narayanganj Sadar, Narayanganj` | `23.750000,90.390000 | DhaRT Farm Gate 2, Savar, Dhaka` | [23.62379, 90.49998] -> [23.74989, 90.39039] (222 points) | 20.78 km / 46 min (google_routes, origin `pickup`) |

Screenshots: [Rider-map-d2.png](audit_logs/nf/shots/Rider-map-d2.png) and [Rider-map-d1.png](audit_logs/nf/shots/Rider-map-d1.png) show the pickup marker in Narayanganj (23.6238, 90.5000), the drop-off marker in Savar/Dhaka (23.75, 90.39), the green route line, distance and ETA.

**Limitation:** in the browser run all three orders used the same GPS point (23.75, 90.39), so the two accepted deliveries have identical coordinates and only differ by delivery id and drop-address text. The browser steps therefore prove the *request URL* and displayed addresses follow the selected id; that different orders use *different* coordinates is proven by the backend test (`test_nf_repairs.py`, mocked routing: each route call receives its own drop-off) and the Flutter `nf4_map_selection_test.dart`.

## 5. API checks made by the harness (not UI steps)

`audit_logs/tools/nf_evidence.py` -> `audit_logs/nf/api_evidence.json`.

| Check | Request | Status | Expected |
|---|---|---|---|
| anonymous cannot place a feed order | `POST /api/farmers/feed-catalogue/orders/` | 401 | 401 ok |
| a rider cannot place a feed order | `POST /api/farmers/feed-catalogue/orders/` | 403 | 403 ok |
| a farmer cannot assign a rider | `POST /api/admin-panel/feed-catalogue/orders/FEED-F24806B4E4/assign/` | 403 | 403 ok |
| a rider cannot read another rider's delivery route | `GET /api/delivery/orders/abcfd724-87ea-4563-84be-e89ca6aec8f8/route/` | 404 | 404 ok |
| a rider cannot answer another rider's offer | `PATCH /api/delivery/requests/abcfd724-87ea-4563-84be-e89ca6aec8f8/respond/` | 404 | 404 ok |
| checkout with no location is rejected (400 delivery_location_required) | `POST /api/farmers/feed-catalogue/orders/` | 400 | 400 ok |
| checkout with coordinates outside Bangladesh is rejected | `POST /api/farmers/feed-catalogue/orders/` | 400 | 400 ok |

Final state of the three orders and four delivery rows:

```
#FD-06B4E4 status=assigned ds=pending lat/lng=23.75,90.39 addr=DhaRT Village Road 5, Savar, Dhaka
#FD-960126 status=assigned ds=pending lat/lng=23.75,90.39 addr=DhaRT Farm Gate 2, Savar, Dhaka
#FD-6E96FD status=created ds=offer_expired lat/lng=23.75,90.39 addr=DhaRT Farm Gate 3, Savar, Dhaka

58c3a865 rejected reason=Offer expired pickup=23.623800,90.500000 drop=23.750000,90.390000
ec31a58c accepted reason=- pickup=23.623800,90.500000 drop=23.750000,90.390000
9a794a86 accepted reason=- pickup=23.623800,90.500000 drop=23.750000,90.390000
abcfd724 rejected reason=Offer expired pickup=23.623800,90.500000 drop=23.750000,90.390000
```

The first row of deliveries (`58c3a865`, offer to Karim Uddin) and the last (`abcfd724`, the reassignment to Test Delivery Rider) were both released as `Offer expired`; the order is `created` / `offer_expired` and can be assigned again. Before the sweep fix, the DB snapshot of `FeedAdmin-9` shows the order was still `assigned` / `pending` after 18 minutes with nobody reading it (lazy sweep); the farmer step `Farmer-2` (farmer expiry file) shows the farmer as the first reader now releases it.

## 6. Tests (exact results)

Backend, isolated clones only (`python scripts/run_all_tests.py`, see `TESTING.md`):

```
manage.py test: Ran 31 tests in 13.127s OK
test_admin_consultations_null_time.py                27 passed, 0 failed
test_admin_dashboard_metrics.py                      12 passed, 0 failed
test_admin_earnings.py                               29 passed, 0 failed
test_admin_pagination_performance.py                 99 passed, 0 failed
test_admin_panel.py                                  66 passed, 0 failed
test_admin_row_builder_performance.py                35 passed, 0 failed
test_articles_feed.py                                28 passed, 0 failed
test_community.py                                    56 passed, 0 failed
test_community_feed_performance.py                   20 passed, 0 failed
test_consultation_booking_rules.py                   29 passed, 0 failed
test_consultation_chat_access.py                     13 passed, 0 failed
test_consultation_transitions_and_receipts.py        53 passed, 0 failed
test_cost_dashboard_charts.py                        20 passed, 0 failed
test_dashboard_integrity_and_seed_idempotency.py     13 passed, 0 failed
test_data_integrity.py                               11 passed, 0 failed
test_delivery_multi_active.py                        34 passed, 0 failed
test_delivery_proof_and_earnings.py                  27 passed, 0 failed
test_delivery_proof_review.py                        75 passed, 0 failed
test_delivery_route.py                               29 passed, 0 failed
test_disease_detection.py                            25 passed, 0 failed
test_doctor_flow.py                                  58 passed, 0 failed
test_farmer_panel.py                                 39 passed, 0 failed
test_feed_catalogue.py                               22 passed, 0 failed
test_feed_marketplace_ux.py                          20 passed, 0 failed
test_feed_order_delivery.py                          28 passed, 0 failed
test_feed_owner_flow.py                              32 passed, 0 failed
test_feed_stock_integrity.py                         29 passed, 0 failed
test_finance_admin.py                                35 passed, 0 failed
test_find_vet_discovery.py                           38 passed, 0 failed
test_flock_feed_management.py                        17 passed, 0 failed
test_labour_payment.py                               27 passed, 0 failed
test_nf_repairs.py                                   85 passed, 0 failed
test_pharmacy_admin.py                               132 passed, 0 failed
test_pharmacy_flow.py                                25 passed, 0 failed
test_pharmacy_locked_session.py                      104 passed, 0 failed
test_pharmacy_marketplace_card_fields.py             13 passed, 0 failed
test_pharmacy_medicine_edit.py                       7 passed, 0 failed
test_pharmacy_medicine_images.py                     20 passed, 0 failed
test_pharmacy_no_fabricated_data.py                  32 passed, 0 failed
test_pharmacy_profile.py                             32 passed, 0 failed
test_private_documents.py                            31 passed, 0 failed
test_profile_photo.py                                58 passed, 0 failed
test_seed_platform_demo.py                           46 passed, 0 failed
test_signup_documents.py                             46 passed, 0 failed
test_signup_flows.py                                 107 passed, 0 failed
test_subscription_payment.py                         65 passed, 0 failed
test_tax_calculator.py                               64 passed, 0 failed
test_verification_flows.py                           36 passed, 0 failed
test_verification_status.py                          25 passed, 0 failed
test_vets_nearby.py                                  12 passed, 0 failed
TOTAL 50 script files, 1986 assertions, 0 failed
```

`test_nf_repairs.py` (85) covers: valid location; missing / partial / non-numeric / NaN / out-of-range / outside-Bangladesh locations (no stock change, no order); supplier coordinates validation; pickup from supplier coordinates and address; expiry by sweep, by rider reject and by command; **repeated expiry** (second `release_offer` is a no-op, no second notification or history entry); **unauthorized access** (anonymous 401, rider/farmer on admin or farmer endpoints 403, other rider 404 on respond/route, other farmer 404); **no stale assignment** in farmer detail/list, admin view, rider list and rider dashboard; **multiple active rider deliveries** with a per-order route call; farmer as first reader of a stale offer.

Flutter: `flutter analyze` - No issues found; `flutter test` - 302 passed, 0 failed. New: `nf3_feed_checkout_location_test.dart` (disabled button until a location, invalid manual coordinates, GPS denied fallback, valid location in summary and request body, server rejection shown), `nf4_map_selection_test.dart` (chooser with no selection and no route request, second delivery routed by its own id, change delivery, selection dropped after refresh, selection kept when still active, single active delivery, explicit order beats selection, no active delivery), `repairs_logic_test.dart` (validation, role guard), `delivery_multi_active_test.dart` (Details opens and selects the second delivery).

## 7. Known limits / disclosures

* The farmer workflow and the farmer-expiry workflow both use the ids `Farmer-1`/`Farmer-2`; the second run overwrote those two PNGs, so the report points at `Farmer-checkout-empty.png` and `Farmer-expired-offer.png` instead.
* The two admin client-coordinate steps (`FeedAdmin-2/-3`) ran after an earlier partial run had already saved 23.6238/90.5, so their DB before/after are equal; the null -> value transition was observed in that earlier partial run, whose record I overwrote by re-running the script. The PATCH 400 / 200 responses and screenshots are from the final run.
* My typing helper left the first three characters ("Dha") of the prefilled address in front of the typed address on the three orders (`DhaRT Village Road 5...`). The submitted address *is* stored exactly as typed in the field; this is a harness artefact, not an application defect. An earlier mis-indexed run typed into the Upazila field; it is archived in `audit_logs/nf/aborted_runs/` (and its data lived only in the discarded clone).
* Typing a minus sign into the manual longitude field was dropped by the browser text field; irrelevant for Bangladesh coordinates (all positive) but noted. The outside-Bangladesh check therefore used 51.5 / 10.1 in the browser and -0.12 in the API check.
* **Rider-side expired-offer view is not browser-verified** (see section 1). It is verified by `test_nf_repairs.py`.
* The retest database `featherflow_retest` was not modified; all browser work ran on `featherflow_nf`, a clone of it. The dev database `featherflow` was not touched by this pass.
* No commit was made. Remaining open work outside this report: NF-5, NF-6 browser verification, the full 8-workflow rerun, and the remaining medium/low faults.

## 8. Screenshots

* [Deliveryperson-1.png](audit_logs/nf/shots/Deliveryperson-1.png)
* [Deliveryperson-10.png](audit_logs/nf/shots/Deliveryperson-10.png)
* [Deliveryperson-11.png](audit_logs/nf/shots/Deliveryperson-11.png)
* [Deliveryperson-11r.png](audit_logs/nf/shots/Deliveryperson-11r.png)
* [Deliveryperson-12.png](audit_logs/nf/shots/Deliveryperson-12.png)
* [Deliveryperson-12r.png](audit_logs/nf/shots/Deliveryperson-12r.png)
* [Deliveryperson-13.png](audit_logs/nf/shots/Deliveryperson-13.png)
* [Deliveryperson-13r.png](audit_logs/nf/shots/Deliveryperson-13r.png)
* [Deliveryperson-14.png](audit_logs/nf/shots/Deliveryperson-14.png)
* [Deliveryperson-14r.png](audit_logs/nf/shots/Deliveryperson-14r.png)
* [Deliveryperson-15.png](audit_logs/nf/shots/Deliveryperson-15.png)
* [Deliveryperson-15r.png](audit_logs/nf/shots/Deliveryperson-15r.png)
* [Deliveryperson-16.png](audit_logs/nf/shots/Deliveryperson-16.png)
* [Deliveryperson-16r.png](audit_logs/nf/shots/Deliveryperson-16r.png)
* [Deliveryperson-17r.png](audit_logs/nf/shots/Deliveryperson-17r.png)
* [Deliveryperson-18r.png](audit_logs/nf/shots/Deliveryperson-18r.png)
* [Deliveryperson-19r.png](audit_logs/nf/shots/Deliveryperson-19r.png)
* [Deliveryperson-2.png](audit_logs/nf/shots/Deliveryperson-2.png)
* [Deliveryperson-20r.png](audit_logs/nf/shots/Deliveryperson-20r.png)
* [Deliveryperson-21r.png](audit_logs/nf/shots/Deliveryperson-21r.png)
* [Deliveryperson-22r.png](audit_logs/nf/shots/Deliveryperson-22r.png)
* [Deliveryperson-23.png](audit_logs/nf/shots/Deliveryperson-23.png)
* [Deliveryperson-24.png](audit_logs/nf/shots/Deliveryperson-24.png)
* [Deliveryperson-3.png](audit_logs/nf/shots/Deliveryperson-3.png)
* [Deliveryperson-4.png](audit_logs/nf/shots/Deliveryperson-4.png)
* [Deliveryperson-5.png](audit_logs/nf/shots/Deliveryperson-5.png)
* [Deliveryperson-6.png](audit_logs/nf/shots/Deliveryperson-6.png)
* [Deliveryperson-7.png](audit_logs/nf/shots/Deliveryperson-7.png)
* [Deliveryperson-8.png](audit_logs/nf/shots/Deliveryperson-8.png)
* [Deliveryperson-9.png](audit_logs/nf/shots/Deliveryperson-9.png)
* [Deliverypersonexpiredoffer-1.png](audit_logs/nf/shots/Deliverypersonexpiredoffer-1.png)
* [Deliverypersonexpiredoffer-2.png](audit_logs/nf/shots/Deliverypersonexpiredoffer-2.png)
* [Farmer-1.png](audit_logs/nf/shots/Farmer-1.png)
* [Farmer-2.png](audit_logs/nf/shots/Farmer-2.png)
* [Farmer-3.png](audit_logs/nf/shots/Farmer-3.png)
* [Farmer-4.png](audit_logs/nf/shots/Farmer-4.png)
* [Farmer-5.png](audit_logs/nf/shots/Farmer-5.png)
* [Farmer-6.png](audit_logs/nf/shots/Farmer-6.png)
* [Farmer-7.png](audit_logs/nf/shots/Farmer-7.png)
* [Farmer-checkout-empty.png](audit_logs/nf/shots/Farmer-checkout-empty.png)
* [Farmer-expired-offer.png](audit_logs/nf/shots/Farmer-expired-offer.png)
* [Farmer-invalid-range.png](audit_logs/nf/shots/Farmer-invalid-range.png)
* [Farmer-letters.png](audit_logs/nf/shots/Farmer-letters.png)
* [Farmer-location-set-1.png](audit_logs/nf/shots/Farmer-location-set-1.png)
* [Farmer-location-set-2.png](audit_logs/nf/shots/Farmer-location-set-2.png)
* [Farmer-location-set-3.png](audit_logs/nf/shots/Farmer-location-set-3.png)
* [Farmer-outside-bd.png](audit_logs/nf/shots/Farmer-outside-bd.png)
* [FeedAdmin-1.png](audit_logs/nf/shots/FeedAdmin-1.png)
* [FeedAdmin-10.png](audit_logs/nf/shots/FeedAdmin-10.png)
* [FeedAdmin-11.png](audit_logs/nf/shots/FeedAdmin-11.png)
* [FeedAdmin-2.png](audit_logs/nf/shots/FeedAdmin-2.png)
* [FeedAdmin-3.png](audit_logs/nf/shots/FeedAdmin-3.png)
* [FeedAdmin-4.png](audit_logs/nf/shots/FeedAdmin-4.png)
* [FeedAdmin-5.png](audit_logs/nf/shots/FeedAdmin-5.png)
* [FeedAdmin-6.png](audit_logs/nf/shots/FeedAdmin-6.png)
* [FeedAdmin-7.png](audit_logs/nf/shots/FeedAdmin-7.png)
* [FeedAdmin-8.png](audit_logs/nf/shots/FeedAdmin-8.png)
* [FeedAdmin-9.png](audit_logs/nf/shots/FeedAdmin-9.png)
* [FeedAdmin-assign-FD-06B4E4.png](audit_logs/nf/shots/FeedAdmin-assign-FD-06B4E4.png)
* [FeedAdmin-assign-FD-6E96FD.png](audit_logs/nf/shots/FeedAdmin-assign-FD-6E96FD.png)
* [FeedAdmin-assign-FD-960126.png](audit_logs/nf/shots/FeedAdmin-assign-FD-960126.png)
* [FeedAdmin-client-bad.png](audit_logs/nf/shots/FeedAdmin-client-bad.png)
* [FeedAdmin-client-saved.png](audit_logs/nf/shots/FeedAdmin-client-saved.png)
* [FeedAdmin-expired.png](audit_logs/nf/shots/FeedAdmin-expired.png)
* [Rider-detail-d2.png](audit_logs/nf/shots/Rider-detail-d2.png)
* [Rider-detail-drop-pin.png](audit_logs/nf/shots/Rider-detail-drop-pin.png)
* [Rider-detail.png](audit_logs/nf/shots/Rider-detail.png)
* [Rider-expired-new-tab.png](audit_logs/nf/shots/Rider-expired-new-tab.png)
* [Rider-map-chooser.png](audit_logs/nf/shots/Rider-map-chooser.png)
* [Rider-map-chooser2.png](audit_logs/nf/shots/Rider-map-chooser2.png)
* [Rider-map-d1.png](audit_logs/nf/shots/Rider-map-d1.png)
* [Rider-map-d2.png](audit_logs/nf/shots/Rider-map-d2.png)
* [Rider-map-from-detail.png](audit_logs/nf/shots/Rider-map-from-detail.png)
* [Rider-map-reload.png](audit_logs/nf/shots/Rider-map-reload.png)
* [Rider-offers-FD-06B4E4.png](audit_logs/nf/shots/Rider-offers-FD-06B4E4.png)
* [Rider-offers-FD-960126.png](audit_logs/nf/shots/Rider-offers-FD-960126.png)
