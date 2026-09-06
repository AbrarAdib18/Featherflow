from django.urls import path

from feed import views as feed_core
from workers import views as workers_core

from . import cost_views, dashboard_views, farm_views, feed_views, labor_views, profile_views

urlpatterns = [
    path('dashboard/', dashboard_views.dashboard),

    # ── profile ──────────────────────────────────────────────────────────
    path('profile/', profile_views.profile),
    path('profile/upload-photo/', profile_views.upload_photo),

    # ── sheds & flocks (batches) ─────────────────────────────────────────
    path('sheds/', farm_views.sheds),
    path('sheds/<uuid:shed_id>/', farm_views.shed_detail),
    path('flocks/', farm_views.flocks),
    path('flocks/<uuid:flock_id>/', farm_views.flock_detail),

    # ── cost management ─────────────────────────────────────────────────
    path('costs/dashboard/', cost_views.dashboard),
    path('costs/expenses/', cost_views.expenses),
    path('costs/expenses/upload-receipt/', cost_views.upload_receipt),
    path('costs/expenses/<uuid:expense_id>/', cost_views.expense_detail),
    path('costs/expenses/<uuid:expense_id>/pay/', cost_views.pay_expense),
    path('costs/revenue/', cost_views.revenue),
    path('costs/revenue/upload-receipt/', cost_views.upload_receipt),
    path('costs/revenue/<uuid:revenue_id>/', cost_views.revenue_detail),
    path('costs/loans/', cost_views.loans),
    path('costs/loans/<uuid:loan_id>/', cost_views.loan_detail),
    path('costs/inventory/', cost_views.inventory),
    path('costs/batches/', cost_views.batches),
    path('costs/reports/', cost_views.reports),
    path('costs/cashout/', cost_views.cashout),

    # ── labor ───────────────────────────────────────────────────────────
    path('labor/workers/', workers_core.workers),
    path('labor/workers/<uuid:worker_id>/', labor_views.worker_detail),
    path('labor/attendance/', workers_core.attendance),
    path('labor/attendance/history/', labor_views.attendance_history),
    path('labor/payments/', workers_core.payments),
    path('labor/payments/history/', labor_views.payment_history),

    # ── feed ────────────────────────────────────────────────────────────
    path('feed/inventory/', feed_core.feed),
    path('feed/inventory/<uuid:stock_id>/', feed_views.stock_detail),
    path('feed/schedules/', feed_core.schedules),
    path('feed/consumption/', feed_views.consumption),
    path('feed/consumption/<uuid:consumption_id>/', feed_views.consumption_detail),
]
