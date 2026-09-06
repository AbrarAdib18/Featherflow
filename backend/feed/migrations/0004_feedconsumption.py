"""State-only: feed_consumption already exists in featherflow_schema.sql;
this maps it. ExistingSchemaRouter blocks DDL for the feed app.
"""
import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('feed', '0003_feedstock_stock_status_feedorder'),
        ('farms', '0002_shed_flock'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='FeedConsumption',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('consumed_date', models.DateField()),
                ('quantity_consumed', models.DecimalField(decimal_places=2, max_digits=10)),
                ('notes', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('feed_type', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='consumption', to='feed.feedtype')),
                ('flock', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='feed_consumption', to='farms.flock')),
                ('recorded_by', models.ForeignKey(db_column='recorded_by', on_delete=django.db.models.deletion.DO_NOTHING, related_name='feed_consumption_logs', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'feed_consumption', 'ordering': ['-consumed_date'], 'managed': False},
        ),
    ]
