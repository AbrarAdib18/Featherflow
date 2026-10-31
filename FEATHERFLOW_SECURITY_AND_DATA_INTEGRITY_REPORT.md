# FEATHERFLOW — Security & Data-Integrity Report

Scope: server-side authorization, object ownership, sensitive-data exposure, upload validation, injection/XSS, session/CSRF/CORS, rate limits, idempotency and races. Evidence = live HTTP against the :8000 server (`FEATHERFLOW_RUNTIME_TRUTH.md`), the 43 project test scripts (run against the live DB), and code reading. Fault IDs refer to `FEATHERFLOW_FAULT_REGISTER.md`.

## 1. Summary

| Area | Result |
|---|---|
| Unauthenticated access to protected APIs | **Denied** — 0 anonymous 2xx on any protected route (sweep of 151 param-free GET routes + 5 anonymous writes → 401). Anonymous 2xx only on health checks, `/api/`, `/api/auth/`, `/api/pharmacy/` root, `/api/articles/all|tags/` (published content, intentional) |
| Cross-role access (19 identities = 18 roles + anonymous × 151 GET routes = 2,869 requests) | **No violations**: every `/api/admin-panel/*` and `/api/admin/*` route returned 403 to all non-admin roles; each admin sub-role saw only its modules (matrix §3); Feed Owner got 403 on all admin routes; 0 × 5xx |
| IDOR / object ownership (76 checks) | **No leak**. Farmer expense/revenue/loan/feed order/pharmacy order/flock events+feed-chart, consultation receipt/clinical-results/video, doctor appointment video, pharmacy medicine GET/PATCH stock/price/DELETE, supplier, pharmacy order detail/confirm, rider order route/status, research paper PUT/DELETE/versions/submit → other users get 403/404. (3 flagged rows in the raw log were test artefacts: the owner themself, and per-pharmacy `ORD-003` copies) |
| JWT | tampered signature → 401; `alg=none` → 401; access lifetime short (tokens expired within the audit) |
| Registration privilege escalation | `role=admin_super` / `feed_admin` rejected (`Unsupported role. Choose one of: admin, delivery, doctor, farmer, pharmacy, researcher`); **`admin` is self-registerable but lands pending** (approval queue) |
| Upload validation | MIME + magic-byte + size enforced: PHP-as-PNG → 400 "does not look like a valid PNG", PNG bytes labelled JPG → 400, 8 MB image → 400 (limit 5 MB), HTML-as-PDF → 400, `.exe` → 400 |
| SQL injection | 4 payloads on search/filter params → 200, DB unaffected (ORM parameterisation) |
| XSS / content sanitisation | **Not sanitised** on write (F-010) |
| CORS | allow-all while `DJANGO_DEBUG=True` (F-019) |
| Rate limiting | login 20/min per IP verified (429 on 21st, also for valid credentials — F-026) |
| Idempotency / races | feed stock: 6 parallel over-stock orders → 1×201 + 5×409, no oversell, cancel restores stock (**safe**); subscription checkout/confirm idempotent (script); expense create **not** idempotent (F-039) |
| Sensitive exposure | see §4 (dashboard activity feed F-009, pharmacy contact data F-035, GET-created seed data F-004) |
| CSRF | n/a for the JSON API: auth is `Authorization: Bearer` (no cookies); Django admin at `/admin/` uses session+CSRF; `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: same-origin` present; no HSTS/CSP in dev responses |

## 2. Findings (security-relevant faults)

| ID | Sev | Finding |
|---|---|---|
| F-009 | Medium | Admin dashboard `activity` feed shows other users' login success/failure events (emails) to *every* admin role, bypassing per-module audit scoping |
| F-010 | Medium | Stored raw `<script>`/`onerror` payloads and `javascript:` media URLs accepted by `POST /api/community/`; unbounded category creation |
| F-019 | Medium | CORS wildcard with credentials under DEBUG; Maps keys committed in `web/index.html` and `backend/.env` |
| F-004 | High | Fabricated pharmacy medicines are auto-**Approved** by a GET handler (approval bypass for those rows) |
| F-007 | Medium | Missing client-side role guard (server still denies) |
| F-026 | Low | Per-IP login throttle locks out legitimate users behind one IP; no per-account lockout |
| F-035 | Low | Pharmacy e-mail/phone/licence and vet coordinates visible to every farmer; internal UUIDs (`owner_id`, `pharmacy_user_id`) exposed to every authenticated role |
| F-036 | Low | `proof_of_delivery_url` stored unvalidated on non-final transitions |
| F-037 | Low | 2FA fields without flow |
| F-025 | Low | 500 on malformed UUID in admin PATCH (request id returned; limited info leak) |

## 3. Authorization matrix (live) — status code per role

Columns: FRM farmer · DOC doctor · PHM pharmacy owner · PST legacy `pharmacist` · DLV rider · RSC researcher · FOW feed owner · FAD feed admin · SUP super admin · OPS operations · FIN finance · CNT content · RAD research admin · DAD delivery admin · PAD pharmacy admin · VAD doctor admin · SPT support · TEM team admin · ANO anonymous. Accounts used: `farmer.rashed`, `dr.mahfuz.kabir`, `pharmacy.agrocare`, `pharmacist.demo`, `rider.arif`, `research.fariha`, `feed.owner`, `feed.admin`, `admin.super`, `ops.nusrat`, `finance.tanvir`, `content.admin`, `research.admin`, `delivery.admin`, `pharmacy.admin@featherflow.local`, `doctor.admin`, `support.raisa`, `team.admin`. A 404 for an admin role on `my-shift/*` = the account does not track shifts (Feed Admin); 403 on the same for Super = not an hourly role.

Reading the matrix: farmer-only endpoints (`/api/farmers/*`) → 200 only in the FRM column; pharmacy endpoints → PHM + SUP; `/api/admin-panel/finance|cashouts/*` → SUP, FIN (+OPS for dashboards); `/api/admin-panel/pharmacy*` → SUP, OPS, PAD; feed catalogue → FAD, SUP; audit-logs → every admin role (scoped data, §1).

| Path | FRM | DOC | PHM | PST | DLV | RSC | FOW | FAD | SUP | OPS | FIN | CNT | RAD | DAD | PAD | VAD | SPT | TEM | ANO |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `/api/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/admin-panel/admin-payments/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/admins/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 401 |
| `/api/admin-panel/all-admins/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/approval-queue/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 401 |
| `/api/admin-panel/audit-logs/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/cashouts/approved/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/cashouts/pending/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/dashboard/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/escalations/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 401 |
| `/api/admin-panel/farmer-loans/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-catalogue/analytics/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-catalogue/companies/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-catalogue/orders/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-catalogue/products/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-catalogue/riders/available/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/feed-chats/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/finance/dashboard/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/finance/summary/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/me/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/my-payments/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 404 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/my-shift/earnings/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 404 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/my-shift/history/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 404 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/my-shift/hours/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 404 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/my-shift/status/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 404 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/offline-admins/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/online-admins/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/oversight/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy-chats/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy-deliveries/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy-riders/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/appeals/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/audit/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/dashboard/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/expiry-alerts/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/medicines/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/orders/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/pharmacy/settlements/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/profile/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/roles/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/admin-panel/shifts/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin-panel/subscription-plans/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/admin/pharmacies/commissions/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin/pharmacies/metrics/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/admin/pharmacies/sales/` | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 200 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 401 |
| `/api/articles/all/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/articles/tags/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/auth/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/auth/me/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/blocks/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/bookmarks/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/categories/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/following/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/follows/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/follows/suggestions/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/hashtags/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/latest/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/notifications/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/search/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/community/trending/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/consultations/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/consultations/chats/` | 200 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/consultations/disputes/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/consultations/vets/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/consultations/vets/nearby/` | 400 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/costs/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/attendance/` | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/dashboard/` | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/earnings/` | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/orders/` | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/requests/` | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/delivery/updates/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/doctor/appointments/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/availability/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/cases/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/conversations/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/dashboard/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/disputes/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/earnings/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/follow-ups/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/prescriptions/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctor/profile/` | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/doctors/updates/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/farmers/costs/batches/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/cashout/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/dashboard/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/expenses/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/inventory/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/loans/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/reports/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/costs/revenue/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/dashboard/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/feed-catalogue/orders/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/feed-catalogue/products/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/feed/consumption/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/feed/inventory/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/flocks/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/labor/attendance/history/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/labor/payments/history/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/labor/workers/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/medicines/search/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/orders/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/pharmacies/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/profile/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/sheds/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/tax/payment/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/tax/payments/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/tax/profile/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/farmers/tax/summary/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/feed-owner/chat/` | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/feed-owner/profile/` | 403 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/feed/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/health/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/health/ready/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/me/updates/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/ml/health/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/ml/scans/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/notifications/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/pharmacy/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/api/pharmacy/analytics/revenue/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/analytics/sales/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/analytics/top-products/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/appeals/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/dashboard/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/earnings/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/inventory/expiring-soon/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/inventory/low-stock/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/inventory/summary/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/marketplace/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/pharmacy/medicines/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/medicines/bulk-upload/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/orders/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/permissions/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/profile/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/suppliers/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/support-conversation/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/pharmacy/updates/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/pharmacy/verification-status/` | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/research/bookmarks/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/research/profile/` | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/research/profile/change-applications/` | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 404 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/research/tag-options/` | 403 | 403 | 403 | 403 | 403 | 200 | 403 | 403 | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/research/updates/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/subscriptions/current/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/subscriptions/plans/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/support/tickets/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 401 |
| `/api/vets/nearby/` | 400 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/api/workers/` | 200 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 403 | 401 |
| `/healthz/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/readyz/` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |

## 4. Data-integrity checks (live DB)

| Check | Result |
|---|---|
| Declared FK constraints | 197, all validated, **0 orphan rows** |
| `*_id` columns with no FK (soft references) | 29 (e.g. `billing_payment_intents.payment_id/plan_id/subscription_id`, `expenses.source_*_id`, `notifications.reference_id`, `payments.reference_id`, `delivery_orders.order_reference_id`, polymorphic `target_id`s) — orphans possible, cannot be detected by the DB |
| Duplicate user e-mails (case-insensitive) | 0 |
| Duplicate `user_roles` | 0; orphan `user_roles` 0 |
| Users with no role | 1 (`selftestfc6b19@x.com`, test leftover) |
| Farmers with >1 farm | 2 (`e25fb388-…`, `324fbf2e-…`) → breaks `seed_platform_demo` (F-015) |
| Test/demo pollution in live listings | `Playwright …`, `Smoke …`, `Repro 500 Medicine` visible to farmers (F-011); fabricated `ORD-00x` (F-004) |
| Stale operational state | admin shift open since 2026-09-16 (F-020) |
| Financial single-write | `test_delivery_proof_and_earnings`, `test_feed_order_delivery`, `test_pharmacy_flow`: 1 earning/expense per completed delivery (script-verified); order → `expenses`/`revenue` mirrors via `expenses/0003_source_order_mirrors` |
| Seed idempotency (3 runs) | rows stable from run 2; run 1 mutates 8 tables; one seed crashes (F-015) |
| Unbounded growth | notifications 11.5k, JWT outstanding 4.8k, activity logs 7.3k (F-030) |

## 5. Not tested (explicit)

Penetration-grade fuzzing; Socket.IO consultation-chat authorization beyond `test_consultation_chat_access.py` (13 script assertions); payment-gateway webhook signature handling with a real gateway (dev mode only); e-mail/SMS OTP delivery (dev codes); TLS/HSTS/CSP (dev HTTP only); signed registration-document token handling beyond `test_private_documents.py` (31 assertions); XSS execution in a browser DOM (Flutter canvas renders text only); production settings (DEBUG off).
