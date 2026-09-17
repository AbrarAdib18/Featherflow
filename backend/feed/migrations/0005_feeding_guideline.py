"""State-only: feeding_guidelines is created by ../feed_flock_extension.sql."""
import uuid
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('feed', '0004_feedconsumption'),
    ]

    operations = [
        migrations.CreateModel(
            name='FeedingGuideline',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('bird_type', models.CharField(choices=[
                    ('broiler', 'Broiler'), ('layer', 'Layer'), ('chick', 'Chick'),
                    ('breeder', 'Breeder'), ('other', 'Other'),
                ], max_length=20)),
                ('min_age_days', models.IntegerField()),
                ('max_age_days', models.IntegerField()),
                ('stage_label', models.CharField(max_length=60)),
                ('feed_type_label', models.CharField(max_length=100)),
                ('recommended_grams_per_bird_per_day', models.DecimalField(blank=True, decimal_places=2, max_digits=6, null=True)),
                ('frequency_per_day', models.IntegerField(default=2)),
                ('guidance_text', models.TextField()),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
            ],
            options={'db_table': 'feeding_guidelines', 'ordering': ['bird_type', 'min_age_days'], 'managed': False},
        ),
    ]
