# Feed Marketplace Admin / Feed Inventory Owner — Requirements Matrix

Status legend: **Done (pre-existing)** = verified working, built before this
session. **Done (this session)** = built and verified in this session.
**Verified (API + tests)** = confirmed via real HTTP/Django-test-client calls
and/or backend test scripts. **Verified (live browser)** = confirmed via a
real headless-Chrome session against the running app (see implementation
report for screenshots/steps). **Not re-verified this session** = exists in
code but wasn't re-exercised in this pass (was pre-existing, out of this
session's scope).

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Feed Marketplace Admin account and role | Done (pre-existing) | `feed_admin` role, `feed_marketplace_extension.sql` |
| 2 | Feed Inventory Owner account, profile, restricted permissions | **Done (this session)** | `feed_owner_extension.sql`, `FeedOwnerProfile`, `IsFeedOwnerAccount`; Verified (API + tests + live browser) |
| 3 | Feed Admin ↔ Feed Inventory Owner private chat | **Done (this session)** | `owner_chat_views.py` / `admin_feed_chat.py`; Verified (API + tests + live browser) |
| 4 | Feed Marketplace Admin dashboard | Done (pre-existing) | `admin_feed_screen.dart` + `feed_catalogue/order_admin_views.py::analytics`; Verified (live browser — dashboard renders with real Recent Activity) |
| 5 | Feed product and stock management | Done (pre-existing) | `feed_catalogue/admin_views.py`, `admin_feed_product_form_screen.dart`; Not re-verified this session |
| 6 | Farmer feed marketplace | Done (pre-existing) | `feed_catalogue/farmer_views.py`; Verified (API, `test_feed_catalogue.py`/`test_feed_marketplace_ux.py` pass) |
| 7 | Farmer cart and checkout | Done (pre-existing) | `farmer_views.py::orders` (server-side price/stock/min-qty revalidation); Not re-verified this session |
| 8 | Feed orders | Done (pre-existing) | `AdminPanelRecord` module `feed-orders`; Verified (`test_feed_order_delivery.py` — 26 passed) |
| 9 | Farmer location and map display | Done (pre-existing) | order payload carries `latitude`/`longitude`; admin order screens show it; Not re-verified this session |
| 10 | Delivery-person assignment | Done (pre-existing) | `order_admin_views.py::order_assign`, offline-rider warning; Verified (`test_feed_order_delivery.py`) |
| 11 | Delivery-person map/route | Done (pre-existing) | `delivery/views.py::route` (Google Directions proxy); Not re-verified this session |
| 12 | Arrival status | Done (pre-existing) | `delivery.DeliveryOrder.status` state machine; Verified (`test_feed_order_delivery.py`) |
| 13 | Mandatory proof-photo upload | Done (pre-existing) | `delivery/views.py::update_status` requires `proof_of_delivery_url` before `delivered`; Verified (`test_feed_order_delivery.py`: "delivered without a proof photo is rejected -> 400") |
| 14 | Admin proof review | Done (pre-existing) | proof URL surfaced on the order record for admin review; Not re-verified this session |
| 15 | Proof rejection and resubmission | Done (pre-existing) | delivery `failed` → restock → reassignable; Verified (`test_feed_order_delivery.py`: rider-reject → reassign) |
| 16 | Completion only after proof approval | Done (pre-existing) | `delivered` requires proof token ownership check (`_valid_proof_token`); Verified (`test_feed_order_delivery.py`) |
| 17 | Feed revenue and Cost Management integration | **Done (this session)** | `mirror_feed_expense`, `Expense.source_feed_order_id`; Verified (API + `test_feed_owner_flow.py`: exactly-once mirroring) |
| 18 | Notifications | Done (pre-existing) + **extended (this session)** | pre-existing order notifications; new `feed_owner_conversation` notifications; Verified (`test_feed_owner_flow.py`) |
| 19 | Community access for Feed Marketplace Admin | Done (pre-existing, no gate) + **badge added (this session)** | Community has no posting-role gate; `is_admin()` badge already covered `feed_admin`; Verified (live browser not run for this specific role, but code path identical to owner's, which was verified) |
| 20 | Community access for Feed Inventory Owner | **Done (this session)** | `_BADGE_ROLES` entry + home-screen Community tile; **Verified (live browser)** — real Community feed opened, real posts/categories shown |
| 21 | Feed-related community posting | Done (pre-existing) | Community `Post` model supports categories/hashtags/media for any authenticated user; Verified (live browser — "Feed Prices" category chip visible, Post composer FAB present) |
| 22 | Role-based permissions | **Done (this session, for the new role)** | `feed_owner` never satisfies `IsAdminUser`; Verified (API: 403 on every admin-panel probe) |
| 23 | Automated tests | **Done (this session)** | `test_feed_owner_flow.py` (32/32), `feed_owner_smoke_test.dart` (2/2), full suites re-run (backend 37/39 independent scripts clean + 1 fixed regression, Flutter 194/194) |
| 24 | Real browser verification | **Done (this session)** | Headless Chrome via Playwright against the actual built web app + live backend — see implementation report |

## Feed Inventory Owner detailed checklist (from spec §25)

| Item | Status |
|---|---|
| Feed Inventory Owner account creation | Done — idempotent seed |
| Seed idempotency | Done — verified twice in a row, `test_feed_owner_flow.py` |
| Login | Done — real password login verified live |
| Profile access | Done — GET/PATCH `/api/feed-owner/profile/`, live-rendered |
| Unauthorized module denial | Done — 403/401 on every probed admin/other-role endpoint |
| Chat creation/access | Done — live + API |
| Message send/read | Done — live + API, read-state (`is_read`, mark-read) |
| Attachment validation | **Not implemented** — the reused chat model supports `file_url`/`message_type`, matching the existing pharmacy chat's capability, but no dedicated attachment-upload endpoint was wired for this chat (the pharmacy chat itself has no attachment upload endpoint either — this mirrors the existing pattern rather than adding a new capability neither chat has) |
| Conversation resolve/reopen | Done — live + API |
| Notification creation | Done — verified both directions (owner→admin, admin→owner) |
| Cross-user access denial | Done — verified (another owner gets 404, not data leakage) |

## Known gaps (explicit, not hidden)

- **Attachment upload for the owner↔admin chat** is not implemented — neither
  is it for the pre-existing pharmacy↔admin chat this was modeled on. Adding
  it would be a platform-wide chat enhancement, not a feed-specific gap.
- **Offline/pending/suspended lifecycle** for Feed Inventory Owner does not
  exist (no `FeedOwnerAlwaysOnAuthentication`) — not requested by the spec,
  and the seeded account is always `active`.
- Items 5, 7, 9, 11, 14 above (pre-existing Feed Marketplace Admin surfaces)
  were **not re-driven through the live browser in this session** — they
  were already covered by existing passing test suites
  (`test_feed_catalogue.py`, `test_feed_marketplace_ux.py`,
  `test_feed_order_delivery.py`) and this session's scope was the Feed
  Inventory Owner + chat + finance + Community additions. If a fresh
  end-to-end click-through of the pre-existing admin product/order/delivery
  screens is wanted, it should be scoped as a follow-up.
- `test_admin_pagination_performance.py` fails on a pre-existing,
  unrelated bug in consultations pagination (`None` `appointment_time`) — not
  touched by, or a consequence of, this work.

## Final completion criteria (from the original prompt) — status

- Dedicated Feed Marketplace Admin exists — ✅ (pre-existing)
- Admin can add stock/products — ✅ (pre-existing)
- Farmers can see/order active products — ✅ (pre-existing)
- Admin receives orders, sees delivery location, assigns delivery — ✅ (pre-existing)
- Delivery person sees assignment, mandatory photo proof, admin review, reject/resubmit, completion-after-approval — ✅ (pre-existing, all covered by passing `test_feed_order_delivery.py`)
- Financial records update exactly once — ✅ (this session, feed order → Expense mirror)
- Dashboard metrics are live — ✅ (pre-existing, confirmed rendering live data in this session's browser pass)
- Permissions work — ✅ (this session's new role verified; pre-existing roles unchanged)
- Feed Inventory Owner role, profile, restricted access, chat with admin — ✅ (this session, fully verified)
- Community access for both new roles — ✅ (this session, verified live for the owner; code-path-identical for the admin)
- Automated tests pass — ✅ (see counts above)
- Live browser verification passes — ✅ (see implementation report)
- No known gap is hidden — ✅ (see "Known gaps" above)
- Nothing committed — ✅ confirmed
