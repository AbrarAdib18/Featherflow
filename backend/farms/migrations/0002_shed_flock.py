"""State-only: sheds + flocks already exist in featherflow_schema.sql.
ExistingSchemaRouter blocks DDL for the farms app; this keeps model state in
sync so other apps can declare FKs to Flock/Shed in their own migrations.
"""
import django.db.models.deletion
import uuid
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('farms', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='Shed',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('shed_name', models.CharField(max_length=100)),
                ('capacity', models.IntegerField()),
                ('current_bird_count', models.IntegerField(blank=True, null=True)),
                ('shed_type', models.CharField(blank=True, max_length=50, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('farm', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='sheds', to='farms.farm')),
            ],
            options={'db_table': 'sheds', 'managed': False},
        ),
        migrations.CreateModel(
            name='Flock',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('batch_name', models.CharField(max_length=100)),
                ('bird_type', models.CharField(blank=True, max_length=20, null=True)),
                ('breed', models.CharField(blank=True, max_length=100, null=True)),
                ('quantity', models.IntegerField()),
                ('current_quantity', models.IntegerField()),
                ('start_date', models.DateField()),
                ('end_date', models.DateField(blank=True, null=True)),
                ('status', models.CharField(blank=True, max_length=10, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('farm', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='flocks', to='farms.farm')),
                ('shed', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.DO_NOTHING, to='farms.shed')),
            ],
            options={'db_table': 'flocks', 'managed': False},
        ),
    ]
