# Feed Marketplace Admin + Feed Inventory Owner — Audit

Scope note up front: a full, real **Feed Marketplace Admin** system (catalogue,
inventory, orders, rider assignment, delivery sync, proof-of-delivery,
analytics) **already existed** in this codebase before this work started —
see §1. The actual gaps this session closed are: the **Feed Inventory Owner**
role/profile, a private **Feed Admin ↔ Feed Inventory Owner chat**, **feed
order → Cost Management** finance mirroring, and **Community** access for
both roles. This document records what was found, what was missing, and the
exact plan that was implemented.

## 1. Existing Feed Marketplace Admin (pre-existing, verified working)

App `backend/feed_catalogue/` — a real relational catalogue + order queue:

- `FeedCompany` / `FeedProduct` (real tables, `feed_marketplace_extension.sql`) —
  admin-approved catalogue with an approval workflow (`draft → pending_review
  → approved/rejected/suspended`), image upload, gallery, stock, min order qty.
- `admin_views.py` — Feed Admin CRUD (companies, products, image/gallery
  upload, approve/reject/suspend).
- `order_admin_views.py` — order queue, rider assignment (reuses
  `delivery.services` capacity/reassignment logic and `delivery.DeliveryOrder`,
  `order_type='marketplace'`), analytics.
- `farmer_views.py` — farmer-facing browse/order/cancel, server-side
  price/stock/min-qty revalidation (`services.order_items_from_cart`).
- `delivery/views.py::_sync_feed_order` — delivery status sync back onto the
  order, proof-of-delivery requirement (generic `delivery.views.proof_upload`
  + `update_status`), restock-on-failure, farmer/admin notifications.
- Flutter: `admin_feed_screen.dart`, `admin_feed_clients_screen.dart`,
  `admin_feed_client_detail_screen.dart`, `admin_feed_product_form_screen.dart`
  — dashboard, catalogue, orders, rider assignment, proof review UI already
  wired into the admin shell/sidebar/router.
- Role `feed_admin` (`panel_type='admin'`, tier 3), permissions scoped to
  `feed-catalogue` / `feed-orders` / `feed-delivery`.

**Confirmed by this session's regression run**: `test_feed_catalogue.py`,
`test_feed_marketplace_ux.py`, `test_feed_order_delivery.py`,
`test_feed_stock_integrity.py` all pass (26–66 assertions each).

## 2. Gaps found (what did not exist)

1. No **Feed Inventory Owner** role, profile model, or account.
2. No **owner ↔ admin private chat** (public Community is not an acceptable
   substitute — the spec is explicit about this).
3. No **feed order → Cost Management (`expenses`) mirroring** — a delivered
   feed order never became a farmer expense record (the pharmacy equivalent,
   `mirror_pharmacy_expense`, had no feed counterpart).
4. Community had no explicit accommodation for `feed_owner`/`feed_admin`
   badges (functionally already open to any authenticated user/role — see §3
   — but no verified-supplier badge for the new role).

## 3. Community — no gating exists to begin with

`backend/community/permissions.py` gates only *moderation* actions via RBAC
(`is_moderator` → `can_perform_action(user, 'community', action)`). Posting,
commenting, reacting is open to **any authenticated user of any role** —
confirmed by reading `community/urls.py` (no role-based decorators) and by
live browser verification (§ implementation report). This means:

- Feed Marketplace Admin already got a "Team Featherflow" badge automatically
  (any `panel_type='admin'` role does, via `is_admin(user)`).
- Feed Inventory Owner needed a badge entry added (cosmetic only — access was
  never gated).

No backend permission change was required for Community access itself; only
`_BADGE_ROLES` gained a `feed_owner` entry.

## 4. Implementation plan (what was built)

| Area | File(s) |
|---|---|
| `feed_owner` role + widened `roles.panel_type` CHECK | `backend/feed_owner_extension.sql` |
| `feed_owner_profiles` table | same file |
| `FeedOwnerProfile` Django model | `backend/profiles/models.py` + migration `0007_feed_owner_profile.py` |
| `Expense.source_feed_order_id` (+ unique index) | `backend/feed_owner_extension.sql`, `backend/expenses/models.py` + migration `0003_source_order_mirrors.py` |
| Owner permission class | `backend/feed_catalogue/owner_permissions.py` (`IsFeedOwnerAccount`, mirrors `pharmacy.permissions.IsPharmacyAccount`) |
| Owner profile API | `backend/feed_catalogue/owner_views.py` |
| Owner chat (owner side) | `backend/feed_catalogue/owner_chat_views.py` — reuses `doctor.Conversation`/`Message` + the existing `pharmacy_chat_status`/`assigned_admin` columns, filtered by `roles__name='feed_owner'` |
| Admin chat inbox (admin side) | `backend/api/admin_feed_chat.py` — mirrors `api/admin_pharmacy_chat.py`, gated by `can_perform_action(user, 'feed-orders', action)` |
| URL wiring | `backend/feed_catalogue/owner_urls.py`, `backend/api/urls.py` (`/api/feed-owner/...`, `/api/admin-panel/feed-chats/...`) |
| Finance mirror | `backend/feed_catalogue/services.py::mirror_feed_expense`, wired into `backend/delivery/views.py::_sync_feed_order` on `delivered` |
| Fixed demo accounts (idempotent) | `backend/feed_catalogue/management/commands/seed_feed_marketplace_demo.py::_seed_fixed_accounts` |
| Community badge | `backend/community/permissions.py::_BADGE_ROLES` |
| Flutter — Feed Owner panel | `lib/features/feed_owner/data/services/feed_owner_service.dart`, `.../presentation/screens/feed_owner_home_screen.dart`, `feed_owner_chat_screen.dart` |
| Flutter — Admin chat inbox | `lib/features/admin/presentation/screens/admin_feed_chats_screen.dart`, `admin_api_service.dart` (4 new methods), `admin_sidebar.dart` ("Feed Owner Chat" nav item) |
| Routing | `lib/core/router/app_router.dart` (`/feed-owner`, `/admin/feed-chats`), `lib/core/network/auth_service.dart` (`feed_owner` → `/feed-owner` role destination) |
| Backend tests | `backend/scripts/test_feed_owner_flow.py` (32 assertions) |
| Flutter tests | `test/feed_owner_smoke_test.dart` |

## 5. Role/permission design decision

`feed_owner` is modeled as a **plain business-account role** (like `pharmacy`),
**not** an admin-panel role: `panel_type='feed_owner'`, no RBAC `permissions`
JSON. This means every "must not access Pharmacy Admin / Super Admin / other
admin panels" restriction in the spec is satisfied **by construction** — a
`feed_owner` user never passes `api.admin_rbac.IsAdminUser` on any
`/api/admin-panel/...` endpoint, full stop. This was verified directly (not
just asserted) in `test_feed_owner_flow.py` and live in the browser (feed
owner's sidebar/shell shows no admin controls at all — it isn't the admin
shell).

## 6. Known assumptions / limitations

- Feed Inventory Owner has no suspend/appeal lifecycle (unlike Pharmacy) —
  the spec didn't ask for one, and `IsFeedOwnerAccount` doesn't need an
  "always-on" authenticator equivalent to `PharmacyAlwaysOnAuthentication`
  because there's no inactive/pending state to punch through.
- The chat reuses `pharmacy_chat_status`/`assigned_admin` columns (named for
  pharmacy but structurally generic) rather than adding new feed-specific
  columns — chosen because it exactly parallels how the existing pharmacy
  admin chat already works and avoids a redundant schema addition.
- Realtime push (Socket.IO) requires an ASGI server (Daphne/Uvicorn); this
  session verified over Django's WSGI `runserver`, so the live browser check
  saw the expected `ws://...` 404 and fell back to the REST path — this is a
  pre-existing platform characteristic (see doctor-panel chat architecture),
  not a defect introduced here.
