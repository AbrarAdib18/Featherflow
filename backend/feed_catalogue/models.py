"""Admin-approved feed catalogue (Priorities 5-6).

Mirrors ``pharmacy.models.PharmacyMedicine``'s shape/approval workflow — real
relational tables (``feed_companies`` / ``feed_products``, created by
``../feed_marketplace_extension.sql``), not JSON. Farmers may only ever
browse/order ``approval_status='approved'`` rows — enforced server-side in
``order_views.py``, never trusted from client-supplied product data.
"""
import uuid

from django.db import models

from farms.constants import BIRD_TYPE_CHOICES


class FeedCompany(models.Model):
    # "Client" in the Feed Admin UI is this model — a feed company/brand
    # working with FeatherFlow, not a farmer. Farmers are order customers,
    # never rows in this table; the UI standardizes on "Client(s)" for this
    # model and "Company/Brand" as the same concept when shown to farmers on
    # a product card, to stop "company"/"supplier"/"client" being used
    # interchangeably (see FEED_MARKETPLACE_UX_AUDIT.md).
    STATUS_CHOICES = [
        ('pending', 'Pending'), ('active', 'Active'),
        ('suspended', 'Suspended'), ('rejected', 'Rejected'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    contact_person = models.CharField(max_length=150, blank=True, default='')
    contact_phone = models.CharField(max_length=20, blank=True, default='')
    contact_email = models.EmailField(max_length=255, blank=True, default='')
    address = models.TextField(blank=True, default='')
    district = models.CharField(max_length=100, blank=True, default='')
    upazila = models.CharField(max_length=100, blank=True, default='')
    description = models.TextField(blank=True, null=True)
    logo_url = models.TextField(blank=True, null=True)
    cover_url = models.TextField(blank=True, null=True)
    license_number = models.CharField(max_length=100, blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    admin_notes = models.TextField(blank=True, null=True)
    created_by = models.ForeignKey('users.User', models.SET_NULL, blank=True, null=True,
                                   db_column='created_by', related_name='feed_companies_created')
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'feed_companies'
        ordering = ['name']

    def __str__(self):
        return self.name


class FeedProduct(models.Model):
    FEED_TYPES = [(v, v.title()) for v in (
        'starter', 'grower', 'finisher', 'layer', 'breeder', 'supplement', 'other')]
    BIRD_TYPES = BIRD_TYPE_CHOICES
    UNIT_CHOICES = [(v, v.replace('_', ' ').title()) for v in (
        'kg', 'bag_25kg', 'bag_50kg', 'ton', 'piece')]
    APPROVAL_STATUS = [
        ('draft', 'Draft'), ('pending_review', 'Pending review'), ('approved', 'Approved'),
        ('rejected', 'Rejected'), ('suspended', 'Suspended'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    company = models.ForeignKey(FeedCompany, models.CASCADE, related_name='products')
    product_name = models.CharField(max_length=200)
    brand = models.CharField(max_length=150, blank=True, default='')
    feed_type = models.CharField(max_length=30, choices=FEED_TYPES, default='other')
    bird_type = models.CharField(max_length=20, choices=BIRD_TYPES, default='other')
    description = models.TextField(blank=True, null=True)
    ingredients = models.TextField(blank=True, null=True)
    nutritional_info = models.JSONField(default=dict, blank=True)
    unit = models.CharField(max_length=20, choices=UNIT_CHOICES, default='kg')
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    stock_quantity = models.IntegerField(default=0)
    min_order_quantity = models.IntegerField(default=1)
    image_url = models.TextField(blank=True, null=True)
    gallery_urls = models.JSONField(default=list, blank=True)
    approval_status = models.CharField(max_length=20, choices=APPROVAL_STATUS, default='draft')
    rejection_reason = models.TextField(blank=True, null=True)
    created_by = models.ForeignKey('users.User', models.SET_NULL, blank=True, null=True,
                                   db_column='created_by', related_name='feed_products_created')
    approved_by = models.ForeignKey('users.User', models.SET_NULL, blank=True, null=True,
                                    db_column='approved_by', related_name='feed_products_approved')
    orders_count = models.IntegerField(default=0)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'feed_products'
        ordering = ['-created_at']

    def __str__(self):
        return self.product_name

    @property
    def is_orderable(self):
        return self.approval_status == 'approved' and self.stock_quantity > 0
