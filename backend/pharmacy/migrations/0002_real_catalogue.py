"""Pharmacy catalogue moves from the JSON `pharmacy-products` module to real
tables. The DDL lives in ``postgres_backend_extension.sql`` (the schema is
owned by PostgreSQL, not Django — see ExistingSchemaRouter); this migration
only keeps Django's model state in sync, matching delivery/0002.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('audit', '0003_admin_rbac'),
        ('pharmacy', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.DeleteModel(name='PharmacyMedicine'),
        migrations.CreateModel(
            name='PharmacyMedicineRecord',
            fields=[],
            options={
                'verbose_name_plural': 'Pharmacy medicine approvals',
                'proxy': True,
                'indexes': [],
                'constraints': [],
            },
            bases=('audit.adminpanelrecord',),
        ),
        migrations.CreateModel(
            name='PharmacyMedicine',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('legacy_record_id', models.CharField(blank=True, max_length=80, null=True)),
                ('name', models.TextField()),
                ('generic_name', models.TextField(blank=True, null=True)),
                ('manufacturer', models.TextField(blank=True, default='')),
                ('category', models.CharField(choices=[('antibiotic', 'Antibiotic'), ('vaccine', 'Vaccine'), ('vitamin', 'Vitamin'), ('antiparasitic', 'Antiparasitic'), ('disinfectant', 'Disinfectant'), ('feed_supplement', 'Feed supplement'), ('equipment', 'Equipment'), ('other', 'Other')], default='other', max_length=20)),
                ('prescription_required', models.BooleanField(default=False)),
                ('price', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('stock_quantity', models.IntegerField(default=0)),
                ('unit', models.CharField(choices=[('tablet', 'Tablet'), ('capsule', 'Capsule'), ('ml', 'ml'), ('gram', 'Gram'), ('kg', 'Kg'), ('piece', 'Piece'), ('pack', 'Pack'), ('bottle', 'Bottle')], default='piece', max_length=20)),
                ('pack_size', models.TextField(blank=True, default='')),
                ('description', models.TextField(blank=True, null=True)),
                ('dosage_instructions', models.TextField(blank=True, null=True)),
                ('storage_instructions', models.TextField(blank=True, null=True)),
                ('cold_chain_required', models.BooleanField(default=False)),
                ('expiry_date', models.DateField()),
                ('batch_number', models.TextField(blank=True, null=True)),
                ('images', models.JSONField(blank=True, default=list)),
                ('is_active', models.BooleanField(default=True)),
                ('is_approved', models.BooleanField(default=False)),
                ('approval_rejected_reason', models.TextField(blank=True, null=True)),
                ('views_count', models.IntegerField(default=0)),
                ('orders_count', models.IntegerField(default=0)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_medicines', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'pharmacy_catalogue_medicines',
                'ordering': ['-created_at'],
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='PharmacySupplier',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('supplier_name', models.TextField()),
                ('contact_person', models.TextField(blank=True, default='')),
                ('phone', models.CharField(blank=True, default='', max_length=30)),
                ('email', models.CharField(blank=True, default='', max_length=255)),
                ('address', models.TextField(blank=True, default='')),
                ('products_supplied', models.TextField(blank=True, default='')),
                ('payment_terms', models.TextField(blank=True, null=True)),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_suppliers', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'pharmacy_suppliers',
                'ordering': ['supplier_name'],
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='PharmacyExpiryAlert',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('expires_in_days', models.IntegerField()),
                ('alert_level', models.CharField(choices=[('critical', 'Critical'), ('warning', 'Warning'), ('info', 'Info')], max_length=10)),
                ('is_acknowledged', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_expiry_alerts', to=settings.AUTH_USER_MODEL)),
                ('medicine', models.OneToOneField(db_column='medicine_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='expiry_alert', to='pharmacy.pharmacymedicine')),
            ],
            options={
                'db_table': 'pharmacy_expiry_alerts',
                'ordering': ['expires_in_days'],
                'managed': False,
            },
        ),
    ]
