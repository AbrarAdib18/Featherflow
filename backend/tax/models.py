"""Tax records for the farmer panel.

Unlike most FeatherFlow apps (which map onto the hand-written
``featherflow_schema.sql``), the ``tax`` app owns its two small tables and
manages them with ordinary Django migrations — nothing in the base schema
touches tax.
"""
import uuid

from django.conf import settings
from django.db import models

INCOME_TYPES = [('agricultural', 'Agricultural'), ('business', 'Business'), ('mixed', 'Mixed')]
LAND_UNITS = [('katha', 'Katha'), ('bigha', 'Bigha'), ('decimal', 'Decimal'),
              ('shotangsho', 'Shotangsho'), ('acre', 'Acre'), ('kani', 'Kani')]
LAND_USES = [('agricultural', 'Agricultural'), ('residential', 'Residential'),
             ('commercial', 'Commercial')]
LOCATIONS = [('rural', 'Rural (union)'), ('urban', 'Urban (municipal / city)')]
TAX_TYPES = [('income', 'Income / business tax'), ('land', 'Land development tax'),
             ('vehicle', 'Vehicle tax'), ('other', 'Other')]


class TaxProfile(models.Model):
    """The farmer's tax situation — one row per user. Drives the estimate."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                related_name='tax_profile')

    land_area = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    land_unit = models.CharField(max_length=16, choices=LAND_UNITS, default='katha')
    land_use = models.CharField(max_length=16, choices=LAND_USES, default='agricultural')
    location = models.CharField(max_length=16, choices=LOCATIONS, default='rural')

    # [{"type": "motorcycle", "count": 1}, ...]
    vehicles = models.JSONField(default=list, blank=True)

    income_type = models.CharField(max_length=16, choices=INCOME_TYPES, default='agricultural')
    exemptions = models.DecimalField(max_digits=12, decimal_places=2, default=0,
                                     help_text='Other exemptions / deductions in BDT.')
    rebates = models.DecimalField(max_digits=12, decimal_places=2, default=0,
                                  help_text='Investment tax rebate in BDT.')
    is_senior = models.BooleanField(default=False, help_text='Age 65+ / eligible for the higher threshold.')

    district = models.CharField(max_length=80, blank=True)
    upazila = models.CharField(max_length=80, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'tax_profiles'

    def __str__(self):
        return f'TaxProfile<{self.user_id}>'


class TaxPayment(models.Model):
    """A tax payment the farmer recorded (self-reported — not enforced)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                             related_name='tax_payments')

    tax_type = models.CharField(max_length=16, choices=TAX_TYPES)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    payment_date = models.DateField()
    reference_number = models.CharField(max_length=120, blank=True,
                                        help_text='Challan / receipt number.')
    notes = models.TextField(blank=True)
    receipt_url = models.TextField(blank=True)

    # optional link back to a cost-management expense row (so a tax payment can
    # also show up under the "Tax" expense category)
    expense_id = models.UUIDField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'tax_payments'
        ordering = ['-payment_date', '-created_at']

    def __str__(self):
        return f'{self.tax_type} {self.amount} on {self.payment_date}'
