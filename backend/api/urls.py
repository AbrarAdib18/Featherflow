from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView

from api.views import api_root
from api.health import liveness, readiness
from api.admin_views import (
    admin_article_revision_history, admin_collection, admin_dashboard, admin_profile, admin_record,
)
from api.admin_extra import (
    admin_admin_action, admin_admin_detail, admin_admins, admin_approval_decide,
    admin_approval_queue, admin_audit_logs, admin_audit_override, admin_escalation_resolve,
    admin_escalations, admin_finance_summary, admin_me, admin_module_export,
    admin_oversight, admin_roles_view, me_updates, module_updates,
)
from api.admin_support import my_tickets
from api.admin_delivery_proofs import proof_approve, proof_detail, proof_reject, proofs_list
from api.admin_cashouts import cashout_approved_list, cashout_pending_list, cashout_review_action
from api.admin_finance import admin_finance_dashboard
from api.admin_subscriptions import subscription_plan_update, subscription_plans_list
from consultations.views import vets_nearby
from api.admin_farmer_loans import admin_farmer_loans, admin_farmer_loan_decide
from api.admin_pharmacy import (
    admin_pharmacy_account_detail, admin_pharmacy_analytics, admin_pharmacy_appeal_decide,
    admin_pharmacy_appeals, admin_pharmacy_approve, admin_pharmacy_dashboard,
    admin_pharmacy_delivery_assign, admin_pharmacy_delivery_queue, admin_pharmacy_available_riders,
    admin_pharmacy_employee_detail, admin_pharmacy_employees,
    admin_pharmacy_expiry_alerts, admin_pharmacy_medicine_approve,
    admin_pharmacy_medicine_archive, admin_pharmacy_medicine_create,
    admin_pharmacy_medicine_reject, admin_pharmacy_medicine_restore,
    admin_pharmacy_medicine_price, admin_pharmacy_medicine_stock,
    admin_pharmacy_medicine_update, admin_pharmacy_medicine_upload_image,
    admin_pharmacy_medicines, admin_pharmacy_order_refund,
    admin_pharmacy_orders, admin_pharmacy_reinstate, admin_pharmacy_reject,
    admin_pharmacy_request_info, admin_pharmacy_suspend,
    admin_pharmacy_audit, admin_pharmacy_export,
)
from api.admin_pharmacy_metrics import (
    admin_pharmacy_commissions, admin_pharmacy_metrics, admin_pharmacy_sales,
    admin_pharmacy_settlement_generate, admin_pharmacy_settlement_update,
    admin_pharmacy_settlements,
)
from api.admin_pharmacy_chat import (
    admin_pharmacy_chat_assign, admin_pharmacy_chat_detail, admin_pharmacy_chat_reply,
    admin_pharmacy_chat_status, admin_pharmacy_chats,
)
from api.admin_feed_chat import (
    admin_feed_chat_assign, admin_feed_chat_detail, admin_feed_chat_reply,
    admin_feed_chat_status, admin_feed_chats,
)
from feed_catalogue import admin_urls as feed_catalogue_admin_urls
from feed_catalogue import owner_urls as feed_catalogue_owner_urls
from billing.urls import (payment_urlpatterns as billing_payment_urls,
                          subscription_urlpatterns as billing_subscription_urls)
from api.admin_shifts import (
    admin_hourly_rate, admin_max_hours, admin_payment_update, admin_payments_export,
    admin_payments_list, admin_shift_detail, admin_shift_force_end, admin_shifts_list,
    all_admins, my_break_end, my_break_start, my_payments, my_shift_earnings, my_shift_end,
    my_shift_history, my_shift_hours, my_shift_start, my_shift_status, offline_admins,
    online_admins,
)

urlpatterns = [
    path('', api_root, name='api-root'),
    path('health/', liveness, name='api-health'),
    path('health/ready/', readiness, name='api-health-ready'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # User-facing polling (declared before the app includes so the explicit
    # "<module>/updates/" paths win over the module routers).
    path('me/updates/', me_updates),
    path('research/updates/', module_updates, {'module': 'research'}),
    path('delivery/updates/', module_updates, {'module': 'delivery'}),
    path('pharmacy/updates/', module_updates, {'module': 'pharmacy'}),
    path('doctors/updates/', module_updates, {'module': 'doctors'}),
    path('support/tickets/', my_tickets),

    # Farmer "find nearby vets" map — GET /api/vets/nearby/?lat=&lng=&radius=50
    path('vets/nearby/', vets_nearby),

    path('auth/', include('users.urls')),
    path('farmers/', include('pharmacy.farmer_urls')),
    path('farmers/tax/', include('tax.urls')),
    path('farmers/', include('farmers.urls')),
    path('workers/', include('workers.urls')),
    path('feed/', include('feed.urls')),
    path('costs/', include('expenses.urls')),
    path('community/', include('community.urls')),
    path('notifications/', include('notifications.urls')),
    path('consultations/', include('consultations.urls')),
    path('doctor/', include('doctor.urls')),
    path('pharmacy/', include('pharmacy.urls')),
    path('delivery/', include('delivery.urls')),
    path('feed-owner/', include(feed_catalogue_owner_urls)),
    # Billing / subscription checkout.
    # NOTE: the legacy `subscriptions.urls` (bare POST/GET /api/subscriptions/,
    # creating a Subscription row that never activates — no Payment, no amount
    # validation beyond the plan lookup, no idempotency) used to be mounted
    # here too, after this include. Because it matched the same "subscriptions/"
    # prefix with an empty sub-path, it was still reachable (Django falls
    # through to it whenever a request doesn't match plans/current/checkout)
    # even though the Flutter client only ever calls the paths below. Removed —
    # `billing` is the sole subscription/checkout implementation now.
    path('subscriptions/', include((billing_subscription_urls, 'billing'), namespace='billing-sub')),
    path('payments/', include((billing_payment_urls, 'billing'), namespace='billing-pay')),
    path('research/', include('research.urls')),
    path('articles/', include('articles.urls')),
    path('ml/', include('ml.urls')),
    path('chatbot/', include('chatbot.urls')),

    # ── Admin panel ────────────────────────────────────────────────────────
    path('admin-panel/delivery-proofs/', proofs_list),
    path('admin-panel/delivery-proofs/<uuid:proof_id>/', proof_detail),
    path('admin-panel/delivery-proofs/<uuid:proof_id>/approve/', proof_approve),
    path('admin-panel/delivery-proofs/<uuid:proof_id>/reject/', proof_reject),
    path('admin-panel/dashboard/', admin_dashboard),
    path('admin-panel/profile/', admin_profile),
    path('admin-panel/me/', admin_me),
    path('admin-panel/roles/', admin_roles_view),
    path('admin-panel/admins/', admin_admins),
    path('admin-panel/admins/<uuid:admin_id>/', admin_admin_detail),
    path('admin-panel/admins/<uuid:admin_id>/action/', admin_admin_action),
    path('admin-panel/audit-logs/', admin_audit_logs),
    path('admin-panel/audit-logs/<uuid:log_id>/override/', admin_audit_override),
    path('admin-panel/approval-queue/', admin_approval_queue),
    path('admin-panel/approval-queue/<uuid:queue_id>/decide/', admin_approval_decide),
    path('admin-panel/oversight/', admin_oversight),
    path('admin-panel/escalations/', admin_escalations),
    path('admin-panel/escalations/<uuid:escalation_id>/resolve/', admin_escalation_resolve),
    path('admin-panel/finance/summary/', admin_finance_summary),

    # ── Shift timer (own) ─────────────────────────────────────────────────
    path('admin-panel/my-shift/status/', my_shift_status),
    path('admin-panel/my-shift/start/', my_shift_start),
    path('admin-panel/my-shift/end/', my_shift_end),
    path('admin-panel/my-shift/break-start/', my_break_start),
    path('admin-panel/my-shift/break-end/', my_break_end),
    path('admin-panel/my-shift/hours/', my_shift_hours),
    path('admin-panel/my-shift/history/', my_shift_history),
    path('admin-panel/my-shift/earnings/', my_shift_earnings),
    path('admin-panel/my-payments/', my_payments),

    # ── Super Admin: team & payroll ──────────────────────────────────────
    path('admin-panel/all-admins/', all_admins),
    path('admin-panel/online-admins/', online_admins),
    path('admin-panel/offline-admins/', offline_admins),
    path('admin-panel/shifts/', admin_shifts_list),
    path('admin-panel/shifts/force-end/', admin_shift_force_end),
    path('admin-panel/shifts/<uuid:shift_id>/', admin_shift_detail),
    path('admin-panel/admins/<uuid:admin_id>/hourly-rate/', admin_hourly_rate),
    path('admin-panel/admins/<uuid:admin_id>/max-hours/', admin_max_hours),
    path('admin-panel/admin-payments/', admin_payments_list),
    path('admin-panel/admin-payments/export/', admin_payments_export),
    path('admin-panel/admin-payments/<uuid:payment_id>/', admin_payment_update),

    path('admin-panel/cashouts/pending/', cashout_pending_list),
    path('admin-panel/cashouts/approved/', cashout_approved_list),
    path('admin-panel/cashouts/<uuid:review_id>/review/', cashout_review_action),
    path('admin-panel/finance/dashboard/', admin_finance_dashboard),
    path('admin-panel/subscription-plans/', subscription_plans_list),
    path('admin-panel/subscription-plans/<int:plan_id>/', subscription_plan_update),

    # ── Admin panel: pharmacy oversight (before the generic module routes) ──
    path('admin-panel/pharmacy/dashboard/', admin_pharmacy_dashboard),
    path('admin-panel/pharmacy/medicines/', admin_pharmacy_medicines),
    path('admin-panel/pharmacy/medicines/create/', admin_pharmacy_medicine_create),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/approve/', admin_pharmacy_medicine_approve),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/reject/', admin_pharmacy_medicine_reject),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/update/', admin_pharmacy_medicine_update),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/archive/', admin_pharmacy_medicine_archive),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/restore/', admin_pharmacy_medicine_restore),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/upload-image/', admin_pharmacy_medicine_upload_image),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/stock/', admin_pharmacy_medicine_stock),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/price/', admin_pharmacy_medicine_price),
    path('admin-panel/pharmacy/expiry-alerts/', admin_pharmacy_expiry_alerts),
    path('admin-panel/pharmacy/orders/', admin_pharmacy_orders),
    path('admin-panel/pharmacy/orders/<uuid:order_id>/refund/', admin_pharmacy_order_refund),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/suspend/', admin_pharmacy_suspend),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/approve/', admin_pharmacy_approve),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/reject/', admin_pharmacy_reject),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/request-info/', admin_pharmacy_request_info),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/reinstate/', admin_pharmacy_reinstate),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/detail/', admin_pharmacy_account_detail),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/employees/', admin_pharmacy_employees),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/employees/<uuid:employee_id>/', admin_pharmacy_employee_detail),
    path('admin-panel/pharmacy/settlements/', admin_pharmacy_settlements),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/settlements/generate/', admin_pharmacy_settlement_generate),
    path('admin-panel/pharmacy/settlements/<uuid:settlement_id>/', admin_pharmacy_settlement_update),
    path('admin/pharmacies/metrics/', admin_pharmacy_metrics),
    path('admin/pharmacies/sales/', admin_pharmacy_sales),
    path('admin/pharmacies/commissions/', admin_pharmacy_commissions),
    path('admin-panel/pharmacy-chats/', admin_pharmacy_chats),
    path('admin-panel/pharmacy-chats/<uuid:conversation_id>/', admin_pharmacy_chat_detail),
    path('admin-panel/pharmacy-chats/<uuid:conversation_id>/messages/', admin_pharmacy_chat_reply),
    path('admin-panel/pharmacy-chats/<uuid:conversation_id>/status/', admin_pharmacy_chat_status),
    path('admin-panel/pharmacy-chats/<uuid:conversation_id>/assign/', admin_pharmacy_chat_assign),

    path('admin-panel/feed-chats/', admin_feed_chats),
    path('admin-panel/feed-chats/<uuid:conversation_id>/', admin_feed_chat_detail),
    path('admin-panel/feed-chats/<uuid:conversation_id>/messages/', admin_feed_chat_reply),
    path('admin-panel/feed-chats/<uuid:conversation_id>/status/', admin_feed_chat_status),
    path('admin-panel/feed-chats/<uuid:conversation_id>/assign/', admin_feed_chat_assign),
    path('admin-panel/pharmacy/appeals/', admin_pharmacy_appeals),
    path('admin-panel/pharmacy/appeals/<uuid:appeal_id>/decide/', admin_pharmacy_appeal_decide),
    path('admin-panel/pharmacy-deliveries/', admin_pharmacy_delivery_queue),
    path('admin-panel/pharmacy-riders/', admin_pharmacy_available_riders),
    path('admin-panel/pharmacy-orders/<str:queue_record_id>/assign-delivery/', admin_pharmacy_delivery_assign),
    path('admin-panel/pharmacy/export/<str:report_type>/', admin_pharmacy_export),
    path('admin-panel/pharmacy/audit/', admin_pharmacy_audit),
    path('admin-panel/feed-catalogue/', include(feed_catalogue_admin_urls)),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/analytics/', admin_pharmacy_analytics),

    # ── Admin panel: farmer loan applications ─────────────────────────────
    path('admin-panel/farmer-loans/', admin_farmer_loans),
    path('admin-panel/farmer-loans/<uuid:loan_id>/decide/', admin_farmer_loan_decide),

    path('admin-panel/articles/<uuid:article_id>/revision-history/', admin_article_revision_history),
    path('admin-panel/<str:module>/export/', admin_module_export),
    path('admin-panel/<str:module>/', admin_collection),
    path('admin-panel/<str:module>/<str:record_id>/', admin_record),
]
