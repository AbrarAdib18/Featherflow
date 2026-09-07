from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView

from api.views import api_root
from api.admin_views import admin_collection, admin_dashboard, admin_profile, admin_record
from api.admin_extra import (
    admin_admin_action, admin_admin_detail, admin_admins, admin_approval_decide,
    admin_approval_queue, admin_audit_logs, admin_audit_override, admin_escalation_resolve,
    admin_escalations, admin_finance_summary, admin_me, admin_module_export,
    admin_oversight, admin_roles_view, me_updates, module_updates,
)
from api.admin_support import my_tickets
from api.admin_farmer_loans import admin_farmer_loans, admin_farmer_loan_decide
from api.admin_pharmacy import (
    admin_pharmacy_analytics, admin_pharmacy_expiry_alerts, admin_pharmacy_medicine_approve,
    admin_pharmacy_medicine_reject, admin_pharmacy_medicines, admin_pharmacy_orders,
    admin_pharmacy_suspend,
)
from api.admin_shifts import (
    admin_hourly_rate, admin_max_hours, admin_payment_update, admin_payments_export,
    admin_payments_list, admin_shift_detail, admin_shift_force_end, admin_shifts_list,
    all_admins, my_break_end, my_break_start, my_payments, my_shift_end,
    my_shift_history, my_shift_hours, my_shift_start, my_shift_status, offline_admins,
    online_admins,
)

urlpatterns = [
    path('', api_root, name='api-root'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # User-facing polling (declared before the app includes so the explicit
    # "<module>/updates/" paths win over the module routers).
    path('me/updates/', me_updates),
    path('research/updates/', module_updates, {'module': 'research'}),
    path('delivery/updates/', module_updates, {'module': 'delivery'}),
    path('pharmacy/updates/', module_updates, {'module': 'pharmacy'}),
    path('doctors/updates/', module_updates, {'module': 'doctors'}),
    path('support/tickets/', my_tickets),

    path('auth/', include('users.urls')),
    path('farmers/', include('pharmacy.farmer_urls')),
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
    path('subscriptions/', include('subscriptions.urls')),
    path('research/', include('research.urls')),
    path('articles/', include('articles.urls')),
    path('ml/', include('ml.urls')),

    # ── Admin panel ────────────────────────────────────────────────────────
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

    # ── Admin panel: pharmacy oversight (before the generic module routes) ──
    path('admin-panel/pharmacy/medicines/', admin_pharmacy_medicines),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/approve/', admin_pharmacy_medicine_approve),
    path('admin-panel/pharmacy/medicines/<uuid:medicine_id>/reject/', admin_pharmacy_medicine_reject),
    path('admin-panel/pharmacy/expiry-alerts/', admin_pharmacy_expiry_alerts),
    path('admin-panel/pharmacy/orders/', admin_pharmacy_orders),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/suspend/', admin_pharmacy_suspend),
    path('admin-panel/pharmacy/<uuid:pharmacy_id>/analytics/', admin_pharmacy_analytics),

    # ── Admin panel: farmer loan applications ─────────────────────────────
    path('admin-panel/farmer-loans/', admin_farmer_loans),
    path('admin-panel/farmer-loans/<uuid:loan_id>/decide/', admin_farmer_loan_decide),

    path('admin-panel/<str:module>/export/', admin_module_export),
    path('admin-panel/<str:module>/', admin_collection),
    path('admin-panel/<str:module>/<str:record_id>/', admin_record),
]
