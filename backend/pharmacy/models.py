import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone

from audit.models import AdminPanelRecord

# Low-stock and expiry thresholds are fixed platform-wide (industry decision §E).
LOW_STOCK_THRESHOLD = 10
EXPIRY_CRITICAL_DAYS = 7
EXPIRY_WARNING_DAYS = 30
EXPIRY_INFO_DAYS = 60


class PharmacyOrganization(AdminPanelRecord):
    class Meta:
        proxy = True
        verbose_name_plural = 'Pharmacy organizations'


class PharmacyMedicineRecord(AdminPanelRecord):
    """Legacy JSON approval mirror (module='medicines'). Kept as the bridge to
    the admin approval workflow until that side is migrated too."""

    class Meta:
        proxy = True
        verbose_name_plural = 'Pharmacy medicine approvals'


class PharmacyMedicine(models.Model):
    """Real relational catalogue entry. Replaces the JSON `pharmacy-products`
    module in backend_admin_records (see migrate_pharmacy_catalogue)."""

    CATEGORY_CHOICES = [
        ('antibiotic', 'Antibiotic'), ('vaccine', 'Vaccine'), ('vitamin', 'Vitamin'),
        ('antiparasitic', 'Antiparasitic'), ('disinfectant', 'Disinfectant'),
        ('feed_supplement', 'Feed supplement'), ('equipment', 'Equipment'),
        ('other', 'Other'),
    ]
    UNIT_CHOICES = [
        ('tablet', 'Tablet'), ('capsule', 'Capsule'), ('ml', 'ml'), ('gram', 'Gram'),
        ('kg', 'Kg'), ('piece', 'Piece'), ('pack', 'Pack'), ('bottle', 'Bottle'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pharmacy_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='pharmacy_user_id', related_name='pharmacy_medicines',
    )
    legacy_record_id = models.CharField(max_length=80, blank=True, null=True)
    name = models.TextField()
    generic_name = models.TextField(blank=True, null=True)
    manufacturer = models.TextField(default='', blank=True)
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default='other')
    prescription_required = models.BooleanField(default=False)
    price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    stock_quantity = models.IntegerField(default=0)
    unit = models.CharField(max_length=20, choices=UNIT_CHOICES, default='piece')
    pack_size = models.TextField(default='', blank=True)
    description = models.TextField(blank=True, null=True)
    dosage_instructions = models.TextField(blank=True, null=True)
    storage_instructions = models.TextField(blank=True, null=True)
    cold_chain_required = models.BooleanField(default=False)
    expiry_date = models.DateField()
    batch_number = models.TextField(blank=True, null=True)
    images = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)
    is_approved = models.BooleanField(default=False)
    approval_rejected_reason = models.TextField(blank=True, null=True)
    views_count = models.IntegerField(default=0)
    orders_count = models.IntegerField(default=0)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'pharmacy_catalogue_medicines'
        ordering = ['-created_at']

    def __str__(self):
        return self.name

    @property
    def expires_in_days(self):
        if not self.expiry_date:
            return None
        return (self.expiry_date - timezone.now().date()).days

    @property
    def expiry_alert_level(self):
        days = self.expires_in_days
        if days is None:
            return None
        if days < EXPIRY_CRITICAL_DAYS:
            return 'critical'
        if days < EXPIRY_WARNING_DAYS:
            return 'warning'
        if days < EXPIRY_INFO_DAYS:
            return 'info'
        return None

    @property
    def is_low_stock(self):
        return self.stock_quantity < LOW_STOCK_THRESHOLD

    @property
    def stock_status(self):
        if self.stock_quantity <= 0:
            return 'out_of_stock'
        if self.stock_quantity < LOW_STOCK_THRESHOLD:
            return 'low_stock'
        return 'in_stock'


class PharmacySupplier(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pharmacy_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='pharmacy_user_id', related_name='pharmacy_suppliers',
    )
    supplier_name = models.TextField()
    contact_person = models.TextField(default='', blank=True)
    phone = models.CharField(max_length=30, default='', blank=True)
    email = models.CharField(max_length=255, default='', blank=True)
    address = models.TextField(default='', blank=True)
    products_supplied = models.TextField(default='', blank=True)
    payment_terms = models.TextField(blank=True, null=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(blank=True, null=True)
    updated_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'pharmacy_suppliers'
        ordering = ['supplier_name']

    def __str__(self):
        return self.supplier_name


class PharmacyExpiryAlert(models.Model):
    ALERT_LEVEL_CHOICES = [
        ('critical', 'Critical'), ('warning', 'Warning'), ('info', 'Info'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pharmacy_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, models.DO_NOTHING,
        db_column='pharmacy_user_id', related_name='pharmacy_expiry_alerts',
    )
    medicine = models.OneToOneField(
        PharmacyMedicine, models.DO_NOTHING,
        db_column='medicine_id', related_name='expiry_alert',
    )
    expires_in_days = models.IntegerField()
    alert_level = models.CharField(max_length=10, choices=ALERT_LEVEL_CHOICES)
    is_acknowledged = models.BooleanField(default=False)
    created_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'pharmacy_expiry_alerts'
        ordering = ['expires_in_days']
