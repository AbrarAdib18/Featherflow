# Pharmacy Admin — Local Demo Credentials

**Local development only. Never use these values in a real deployment.**

```
Email:    pharmacy.admin@featherflow.local
Password: ChangeMe@2026!
Role:     admin_pharmacy (module-tier Pharmacy Admin — see backend/api/admin_rbac.py)
```

## How it's created

Created by a standalone, idempotent script,
`backend/scripts/_create_pharmacy_admin.py`, using the exact same
`User`/`Role`/`UserRole`/`AdminProfile` construction helpers as
`users/management/commands/seed_platform_demo.py`'s own admin-seeding block
(which now also lists this account — see that file's `admins` list, entry
`admin.pharmacy@example.com`... *see note below on why two different emails
exist*).

Run it directly against the local dev DB:

```bash
backend/venv/Scripts/python.exe backend/scripts/_create_pharmacy_admin.py
```

Safe to run repeatedly — matches on email, updates in place, never creates a
duplicate `User`, `UserRole`, or `AdminProfile` row. Verified by running it
three times in a row against the live dev DB (identical `id` every time, row
counts stay at 1).

**Note on the two email addresses:** `seed_platform_demo.py`'s `admins` list
now includes `admin.pharmacy@example.com` (matching that command's existing
`firstname.role@example.com` convention for every other seeded account), but
that full command currently fails before reaching the admin section, on a
**pre-existing, unrelated** data issue (`farmer.rashed@example.com` has two
duplicate `Farm` rows in this dev DB, likely from an earlier manual re-seed;
`Farm.objects.get_or_create` then raises `MultipleObjectsReturned`). That bug
predates this work and touches unrelated farmer/flock/expense data with many
foreign-key dependents — not something to silently "fix" as a side effect of
a pharmacy-admin request. Until it's resolved,
`_create_pharmacy_admin.py` is the reliable way to get this specific account
into a live dev DB; `pharmacy.admin@featherflow.local` (the address the
original request specified) is what it actually creates. Once the Farm
duplication is cleaned up, `seed_platform_demo` will also create
`admin.pharmacy@example.com` as a *second*, equivalent account — harmless,
but worth deduping at that point (drop one of the two from the `admins` list).

## Verified (live, against the running backend)

- `POST /api/auth/login/` with these credentials → `200`, real access+refresh
  tokens, `roles: ["admin_pharmacy"]`, `account_status: "active"`.
- `GET /api/admin-panel/pharmacy/dashboard/`, `/pharmacy/medicines/`,
  `/pharmacies/` → `200` (pharmacy module access works).
- `GET /api/admin-panel/finance/summary/`, `/admins/`,
  `PATCH /admin-panel/doctors/<id>/` → `403` (correctly denied outside the
  pharmacy module — this account has no wildcard/other-module access, unlike
  `admin_super`).
- `GET /api/admin-panel/audit-logs/` → `200` (every admin role can read the
  audit trail read-only — a pre-existing, unrelated platform convention, not
  specific to this account).
- Logging in as a **pharmacy owner** (`pharmacy.greenvet@example.com`) and
  hitting `/admin-panel/pharmacy/medicines/` → `403` (owning a pharmacy does
  not grant Pharmacy Admin — confirms the two roles are not conflated).
- Wrong password → `401`.
- `POST /api/auth/logout/` (with the access token) → `205`, refresh token
  blacklisted.

## Update (2026-09-26)

These credentials are unchanged. Since this file was written, the panel this
account opens gained an Add Medicine form, a Reports & Audit tab (14 CSV
report types + a dedicated audit-log view), an inventory stock-adjustment
action, and an explicit pre-confirmation dialog before assigning a delivery
to an offline rider — see `PHARMACY_ADMIN_IMPLEMENTATION_REPORT.md` §29–§38
for full detail, live-verification evidence, and two platform-wide bugs
(a CSV-export 406, a dead `is_online` field check) found and fixed along the
way.

## Update (2026-09-26, verification pass)

Credentials unchanged. A third work pass logged in as this exact account
(not `admin_super`) and found that the delivery-assignment rider picker
returned a 403 for it, because the Flutter picker called an endpoint gated to
the `delivery` module, which `admin_pharmacy` does not have. Fixed with a new
pharmacy-scoped `GET /api/admin-panel/pharmacy-riders/` endpoint; verified
live that this account can now list riders and successfully assign a
delivery to a genuinely offline rider (receiving the expected offline
warning). See `PHARMACY_ADMIN_END_TO_END_REPORT.md` for full detail. Login,
logout, and module scoping for this account were re-verified live and are
unchanged from the original verification below.

## Other demo accounts (unchanged, for reference)

See the conversation history / `users/management/commands/seed_platform_demo.py`
for the full role roster (farmer, doctor, pharmacy owner, delivery rider,
researcher, and the pre-existing `admin_super`/`admin_operations`/
`admin_finance`/`admin_support` admins) — all share the password
`FeatherflowDemo@2026`. This document only covers the new Pharmacy Admin
account, which uses a different, explicitly-requested password
(`ChangeMe@2026!`) to make it visually distinct in this file.
