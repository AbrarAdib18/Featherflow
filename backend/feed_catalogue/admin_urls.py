from django.urls import path

from . import admin_views as v
from . import order_admin_views as ov

urlpatterns = [
    path('companies/', v.companies),
    path('companies/<uuid:company_id>/', v.company_detail),
    path('companies/<uuid:company_id>/logo/', v.company_logo_upload),
    path('companies/<uuid:company_id>/cover/', v.company_cover_upload),
    path('products/', v.products),
    path('products/<uuid:product_id>/', v.product_detail),
    path('products/<uuid:product_id>/image/', v.product_image_upload),
    path('products/<uuid:product_id>/gallery/', v.product_gallery_image_delete),
    path('orders/', ov.orders),
    path('orders/<str:order_id>/', ov.order_detail),
    path('orders/<str:order_id>/assign/', ov.order_assign),
    path('riders/available/', ov.available_riders),
    path('analytics/', ov.analytics),
]
