import uuid

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('audit', '0002_securityflag_supportticket'),
        ('profiles', '0003_add_missing_profile_models'),
        ('delivery', '0001_initial'),
    ]

    operations = [
        migrations.DeleteModel(name='DeliveryOrder'),
        migrations.DeleteModel(name='DeliveryRider'),
        migrations.CreateModel(
            name='DeliveryQueueRecord',
            fields=[],
            options={
                'verbose_name': 'Delivery queue entry',
                'verbose_name_plural': 'Delivery queue entries',
                'proxy': True,
                'indexes': [],
                'constraints': [],
            },
            bases=('audit.adminpanelrecord',),
        ),
        migrations.CreateModel(
            name='DeliveryOrder',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('order_reference_id', models.UUIDField()),
                ('order_type', models.CharField(choices=[('medicine', 'Medicine'), ('marketplace', 'Marketplace')], max_length=15)),
                ('pickup_address', models.TextField()),
                ('delivery_address', models.TextField()),
                ('pickup_lat', models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True)),
                ('pickup_lng', models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True)),
                ('delivery_lat', models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True)),
                ('delivery_lng', models.DecimalField(blank=True, decimal_places=6, max_digits=9, null=True)),
                ('status', models.CharField(default='pending', max_length=20)),
                ('otp_code', models.CharField(blank=True, max_length=10, null=True)),
                ('proof_of_delivery_url', models.TextField(blank=True, null=True)),
                ('failure_reason', models.TextField(blank=True, null=True)),
                ('is_pharmacy_delivery', models.BooleanField(default=False)),
                ('is_cold_chain', models.BooleanField(default=False)),
                ('is_prescription_required', models.BooleanField(default=False)),
                ('notes', models.TextField(blank=True, null=True)),
                ('assigned_at', models.DateTimeField(blank=True, null=True)),
                ('delivered_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('delivery_person', models.ForeignKey(db_column='delivery_person_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='delivery_orders', to='profiles.deliveryprofile')),
            ],
            options={
                'db_table': 'delivery_orders',
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='DeliveryEarning',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('base_pay', models.DecimalField(decimal_places=2, max_digits=10)),
                ('bonus', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('penalty', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('total_earned', models.DecimalField(decimal_places=2, max_digits=10)),
                ('payout_status', models.CharField(default='pending', max_length=10)),
                ('payout_date', models.DateField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('delivery_person', models.ForeignKey(db_column='delivery_person_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='earnings', to='profiles.deliveryprofile')),
                ('delivery_order', models.OneToOneField(db_column='delivery_order_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='earning', to='delivery.deliveryorder')),
            ],
            options={
                'db_table': 'delivery_earnings',
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='DeliveryAttendance',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('attendance_date', models.DateField()),
                ('check_in_time', models.DateTimeField(blank=True, null=True)),
                ('check_out_time', models.DateTimeField(blank=True, null=True)),
                ('status', models.CharField(default='present', max_length=10)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('delivery_person', models.ForeignKey(db_column='delivery_person_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='attendance', to='profiles.deliveryprofile')),
            ],
            options={
                'db_table': 'delivery_attendance',
                'managed': False,
                'unique_together': {('delivery_person', 'attendance_date')},
            },
        ),
    ]
