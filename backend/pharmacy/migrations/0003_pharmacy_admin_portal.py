"""Pharmacy Admin Portal — additive tables (employees, sales, commissions,
settlements, appeals). The DDL lives in pharmacy_admin_portal_extension.sql
(the schema is owned by PostgreSQL, not Django); this migration only keeps
Django's model state in sync, matching 0002_real_catalogue.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('pharmacy', '0002_real_catalogue'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='PharmacyEmployee',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.TextField()),
                ('role_title', models.CharField(blank=True, default='', max_length=100)),
                ('phone', models.CharField(blank=True, default='', max_length=30)),
                ('email', models.CharField(blank=True, default='', max_length=255)),
                ('license_number', models.TextField(blank=True, null=True)),
                ('access_level', models.CharField(choices=[('staff', 'Staff'), ('manager', 'Manager'), ('pharmacist', 'Pharmacist')], default='staff', max_length=20)),
                ('is_active', models.BooleanField(default=True)),
                ('added_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('added_by', models.ForeignKey(blank=True, db_column='added_by_id', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_employees', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'pharmacy_employees', 'ordering': ['name'], 'managed': False},
        ),
        migrations.CreateModel(
            name='PharmacySale',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('order_reference', models.TextField(unique=True)),
                ('gross_amount', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('status', models.CharField(choices=[('completed', 'Completed'), ('refunded', 'Refunded')], default='completed', max_length=20)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_sales', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'pharmacy_sales', 'ordering': ['-completed_at'], 'managed': False},
        ),
        migrations.CreateModel(
            name='PharmacyCommission',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('rate', models.DecimalField(decimal_places=4, max_digits=5)),
                ('gross_amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('commission_amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('pharmacy_amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('sale', models.OneToOneField(db_column='sale_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='commission', to='pharmacy.pharmacysale')),
            ],
            options={'db_table': 'pharmacy_commissions', 'ordering': ['-created_at'], 'managed': False},
        ),
        migrations.CreateModel(
            name='PharmacySettlement',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('period_start', models.DateField()),
                ('period_end', models.DateField()),
                ('gross_sales', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('commission', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('payable_amount', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('status', models.CharField(choices=[('pending', 'Pending'), ('approved', 'Approved'), ('paid', 'Paid'), ('failed', 'Failed'), ('reversed', 'Reversed')], default='pending', max_length=20)),
                ('paid_at', models.DateTimeField(blank=True, null=True)),
                ('payment_reference', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('created_by', models.ForeignKey(blank=True, db_column='created_by_id', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_settlements', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'pharmacy_settlements', 'ordering': ['-period_start'], 'managed': False},
        ),
        migrations.CreateModel(
            name='PharmacyAppeal',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('suspension_log_id', models.UUIDField(blank=True, null=True)),
                ('reason', models.TextField(blank=True, default='')),
                ('explanation', models.TextField(blank=True, default='')),
                ('attachments', models.JSONField(blank=True, default=list)),
                ('status', models.CharField(choices=[('submitted', 'Submitted'), ('under_review', 'Under review'), ('more_info_required', 'More information required'), ('approved', 'Approved'), ('denied', 'Denied')], default='submitted', max_length=20)),
                ('admin_response', models.TextField(blank=True, null=True)),
                ('resolved_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('pharmacy_user', models.ForeignKey(db_column='pharmacy_user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='pharmacy_appeals', to=settings.AUTH_USER_MODEL)),
                ('resolved_by', models.ForeignKey(blank=True, db_column='resolved_by_id', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='+', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'pharmacy_appeals', 'ordering': ['-created_at'], 'managed': False},
        ),
    ]
