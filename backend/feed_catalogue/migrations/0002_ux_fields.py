"""State-only: new columns are created by ../feed_marketplace_ux_extension.sql.
ExistingSchemaRouter blocks DDL for this app (see featherflow_backend/database_router.py)."""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('feed_catalogue', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='feedcompany', name='district',
            field=models.CharField(blank=True, default='', max_length=100),
        ),
        migrations.AddField(
            model_name='feedcompany', name='upazila',
            field=models.CharField(blank=True, default='', max_length=100),
        ),
        migrations.AddField(
            model_name='feedcompany', name='description',
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='feedcompany', name='logo_url',
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='feedcompany', name='cover_url',
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name='feedcompany', name='status',
            field=models.CharField(choices=[
                ('pending', 'Pending'), ('active', 'Active'),
                ('suspended', 'Suspended'), ('rejected', 'Rejected'),
            ], default='active', max_length=20),
        ),
        migrations.AddField(
            model_name='feedproduct', name='gallery_urls',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
