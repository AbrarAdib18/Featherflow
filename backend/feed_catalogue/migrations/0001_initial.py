"""State-only: feed_companies / feed_products are created by
../feed_marketplace_extension.sql. ExistingSchemaRouter blocks DDL for this
app (see featherflow_backend/database_router.py)."""
import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='FeedCompany',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=200)),
                ('contact_person', models.CharField(blank=True, default='', max_length=150)),
                ('contact_phone', models.CharField(blank=True, default='', max_length=20)),
                ('contact_email', models.EmailField(blank=True, default='', max_length=255)),
                ('address', models.TextField(blank=True, default='')),
                ('license_number', models.CharField(blank=True, max_length=100, null=True)),
                ('status', models.CharField(choices=[('active', 'Active'), ('suspended', 'Suspended')], default='active', max_length=20)),
                ('admin_notes', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('created_by', models.ForeignKey(blank=True, db_column='created_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='feed_companies_created', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'feed_companies', 'ordering': ['name'], 'managed': False},
        ),
        migrations.CreateModel(
            name='FeedProduct',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('product_name', models.CharField(max_length=200)),
                ('brand', models.CharField(blank=True, default='', max_length=150)),
                ('feed_type', models.CharField(choices=[
                    ('starter', 'Starter'), ('grower', 'Grower'), ('finisher', 'Finisher'),
                    ('layer', 'Layer'), ('breeder', 'Breeder'), ('supplement', 'Supplement'), ('other', 'Other'),
                ], default='other', max_length=30)),
                ('bird_type', models.CharField(choices=[
                    ('broiler', 'Broiler'), ('layer', 'Layer'), ('chick', 'Chick'),
                    ('breeder', 'Breeder'), ('other', 'Other'),
                ], default='other', max_length=20)),
                ('description', models.TextField(blank=True, null=True)),
                ('ingredients', models.TextField(blank=True, null=True)),
                ('nutritional_info', models.JSONField(blank=True, default=dict)),
                ('unit', models.CharField(choices=[
                    ('kg', 'Kg'), ('bag_25kg', 'Bag 25kg'), ('bag_50kg', 'Bag 50kg'),
                    ('ton', 'Ton'), ('piece', 'Piece'),
                ], default='kg', max_length=20)),
                ('price', models.DecimalField(decimal_places=2, default=0, max_digits=10)),
                ('stock_quantity', models.IntegerField(default=0)),
                ('min_order_quantity', models.IntegerField(default=1)),
                ('image_url', models.TextField(blank=True, null=True)),
                ('approval_status', models.CharField(choices=[
                    ('draft', 'Draft'), ('pending_review', 'Pending review'), ('approved', 'Approved'),
                    ('rejected', 'Rejected'), ('suspended', 'Suspended'),
                ], default='draft', max_length=20)),
                ('rejection_reason', models.TextField(blank=True, null=True)),
                ('orders_count', models.IntegerField(default=0)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('company', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='products', to='feed_catalogue.feedcompany')),
                ('created_by', models.ForeignKey(blank=True, db_column='created_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='feed_products_created', to=settings.AUTH_USER_MODEL)),
                ('approved_by', models.ForeignKey(blank=True, db_column='approved_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='feed_products_approved', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'feed_products', 'ordering': ['-created_at'], 'managed': False},
        ),
    ]
