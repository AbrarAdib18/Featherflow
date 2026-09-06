"""Admin Shift Timer + Hourly Payment — state-only.

Tables and columns live in featherflow_schema.sql / postgres_backend_extension.sql;
every model here is ``managed = False`` and the ExistingSchemaRouter blocks
migrations for this app, so this migration never touches the database. It only
keeps Django's migration state in step with ``profiles/models.py``.
"""
import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('profiles', '0004_rider_location'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(model_name='adminprofile', name='hourly_rate',
                            field=models.DecimalField(decimal_places=2, default=0, max_digits=10)),
        migrations.AddField(model_name='adminprofile', name='max_hours_per_week',
                            field=models.IntegerField(blank=True, null=True)),
        migrations.AddField(model_name='adminprofile', name='last_shift_start',
                            field=models.DateTimeField(blank=True, null=True)),
        migrations.AddField(model_name='adminprofile', name='pending_hourly_rate',
                            field=models.DecimalField(blank=True, decimal_places=2, max_digits=10, null=True)),
        migrations.AddField(model_name='adminprofile', name='pending_rate_effective_from',
                            field=models.DateField(blank=True, null=True)),
        migrations.CreateModel(
            name='AdminShift',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('shift_date', models.DateField()),
                ('start_time', models.DateTimeField()),
                ('end_time', models.DateTimeField(blank=True, null=True)),
                ('break_start', models.DateTimeField(blank=True, null=True)),
                ('break_end', models.DateTimeField(blank=True, null=True)),
                ('break_duration_minutes', models.IntegerField(default=0)),
                ('total_hours', models.DecimalField(decimal_places=2, default=0, max_digits=6)),
                ('is_active', models.BooleanField(default=True)),
                ('auto_flagged', models.BooleanField(default=False)),
                ('ip_address', models.CharField(blank=True, max_length=45, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('admin', models.ForeignKey(db_column='admin_id', on_delete=django.db.models.deletion.CASCADE, related_name='shifts', to='profiles.adminprofile')),
                ('ended_by', models.ForeignKey(blank=True, db_column='ended_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='force_ended_shifts', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'admin_shifts', 'ordering': ['-start_time'], 'managed': False},
        ),
        migrations.CreateModel(
            name='AdminPayment',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('period_start', models.DateField()),
                ('period_end', models.DateField()),
                ('total_hours', models.DecimalField(decimal_places=2, default=0, max_digits=7)),
                ('regular_hours', models.DecimalField(decimal_places=2, default=0, max_digits=7)),
                ('overtime_hours', models.DecimalField(decimal_places=2, default=0, max_digits=7)),
                ('hourly_rate', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('overtime_rate', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('total_payment', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('payment_status', models.CharField(choices=[('pending', 'Pending'), ('paid', 'Paid'), ('failed', 'Failed')], default='pending', max_length=10)),
                ('payment_date', models.DateTimeField(blank=True, null=True)),
                ('payment_method', models.CharField(blank=True, choices=[('cash', 'Cash'), ('bank_transfer', 'Bank transfer'), ('mobile_wallet', 'Mobile wallet')], max_length=20, null=True)),
                ('payment_reference', models.TextField(blank=True, null=True)),
                ('notes', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('admin', models.ForeignKey(db_column='admin_id', on_delete=django.db.models.deletion.CASCADE, related_name='payments', to='profiles.adminprofile')),
                ('generated_by', models.ForeignKey(blank=True, db_column='generated_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='generated_admin_payments', to=settings.AUTH_USER_MODEL)),
                ('paid_by', models.ForeignKey(blank=True, db_column='paid_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='paid_admin_payments', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'admin_payments', 'ordering': ['-period_start'], 'managed': False, 'unique_together': {('admin', 'period_start')}},
        ),
    ]
