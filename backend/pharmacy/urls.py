from django.urls import path

from pharmacy import catalogue_views as cat
from pharmacy.views import collection, dashboard, marketplace, pharmacy_root, place_order, record

urlpatterns = [
    path('', pharmacy_root),
    path('dashboard/', dashboard),
    path('marketplace/', marketplace),
    path('place-order/', place_order),

    # ── Real relational catalogue (pharmacy_catalogue_medicines) ──
    path('medicines/', cat.medicines),
    path('medicines/bulk-upload/', cat.medicines_bulk_upload),
    path('medicines/<uuid:medicine_id>/', cat.medicine_detail),
    path('medicines/<uuid:medicine_id>/upload-image/', cat.medicine_upload_image),
    path('medicines/<uuid:medicine_id>/stock/', cat.medicine_stock),
    path('medicines/<uuid:medicine_id>/price/', cat.medicine_price),

    # ── Inventory & expiry monitoring ──
    path('inventory/summary/', cat.inventory_summary_view),
    path('inventory/expiring-soon/', cat.inventory_expiring_soon),
    path('inventory/low-stock/', cat.inventory_low_stock),
    path('inventory/alerts/acknowledge/', cat.inventory_alerts_acknowledge),

    # ── Suppliers ──
    path('suppliers/', cat.suppliers),
    path('suppliers/<uuid:supplier_id>/', cat.supplier_detail),
    path('suppliers/<uuid:supplier_id>/orders/', cat.supplier_orders),

    # ── Analytics ──
    path('analytics/sales/', cat.analytics_sales),
    path('analytics/top-products/', cat.analytics_top_products),
    path('analytics/revenue/', cat.analytics_revenue),

    # ── Orders (JSON bridge + delivery hand-off) ──
    path('orders/', cat.orders_list),
    path('orders/<str:order_id>/detail/', cat.order_detail),
    path('orders/<str:order_id>/status/', cat.order_status),
    path('orders/<str:order_id>/confirm/', cat.order_confirm),
    path('orders/<str:order_id>/cancel/', cat.order_cancel),
    path('orders/<str:order_id>/ready-for-delivery/', cat.order_ready_for_delivery),

    # ── Legacy JSON collection/record (kept for the current app during transition) ──
    path('<str:kind>/', collection),
    path('<str:kind>/<str:record_id>/', record),
]
