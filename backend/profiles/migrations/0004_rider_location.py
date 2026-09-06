from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('profiles', '0003_add_missing_profile_models'),
    ]

    operations = [
        migrations.RunSQL(
            sql=[
                "ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS current_lat DECIMAL(9,6)",
                "ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS current_lng DECIMAL(9,6)",
                "ALTER TABLE delivery_profiles ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP",
            ],
            reverse_sql=[
                "ALTER TABLE delivery_profiles DROP COLUMN IF EXISTS current_lat",
                "ALTER TABLE delivery_profiles DROP COLUMN IF EXISTS current_lng",
                "ALTER TABLE delivery_profiles DROP COLUMN IF EXISTS location_updated_at",
            ],
            state_operations=[
                migrations.AddField(
                    model_name='deliveryprofile', name='current_lat',
                    field=models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True),
                ),
                migrations.AddField(
                    model_name='deliveryprofile', name='current_lng',
                    field=models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True),
                ),
                migrations.AddField(
                    model_name='deliveryprofile', name='location_updated_at',
                    field=models.DateTimeField(null=True, blank=True),
                ),
            ],
        ),
    ]
