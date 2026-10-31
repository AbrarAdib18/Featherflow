"""Feed Inventory Owner profile — additive table. DDL lives in
feed_owner_extension.sql (the schema is owned by PostgreSQL, not Django);
this migration only keeps Django's model state in sync, matching
pharmacy/migrations/0003_pharmacy_admin_portal.py.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('profiles', '0006_pharmacy_review_state'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='FeedOwnerProfile',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('business_name', models.CharField(blank=True, default='', max_length=200)),
                ('inventory_location', models.TextField(blank=True, default='')),
                ('assigned_categories', models.JSONField(blank=True, default=list)),
                ('profile_photo_url', models.TextField(blank=True, null=True)),
                ('status', models.CharField(choices=[('active', 'Active'), ('inactive', 'Inactive')], default='active', max_length=20)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('approved_by_admin', models.ForeignKey(blank=True, db_column='approved_by_admin_id', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='approved_feed_owner_profiles', to=settings.AUTH_USER_MODEL)),
                ('user', models.OneToOneField(db_column='user_id', on_delete=django.db.models.deletion.DO_NOTHING, related_name='feed_owner_profile', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'feed_owner_profiles', 'managed': False},
        ),
    ]
