"""State-only: flock_events is created by ../feed_flock_extension.sql.
ExistingSchemaRouter blocks DDL for the farms app; this keeps model state in
sync so other apps/tests can use FlockEvent."""
import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('farms', '0002_shed_flock'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='FlockEvent',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('event_type', models.CharField(choices=[
                    ('mortality', 'Mortality'), ('sale', 'Sale'), ('transfer', 'Transfer'),
                    ('vaccination', 'Vaccination'), ('feed_consumption', 'Feed Consumption'),
                    ('weight_measurement', 'Weight Measurement'),
                ], max_length=20)),
                ('quantity', models.IntegerField(blank=True, null=True)),
                ('weight_kg', models.DecimalField(blank=True, decimal_places=3, max_digits=8, null=True)),
                ('event_date', models.DateField()),
                ('notes', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('flock', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='events', to='farms.flock')),
                ('recorded_by', models.ForeignKey(blank=True, db_column='recorded_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='flock_events_recorded', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'flock_events', 'ordering': ['-event_date', '-created_at'], 'managed': False},
        ),
    ]
