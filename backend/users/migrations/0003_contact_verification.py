from django.db import migrations, models


class Migration(migrations.Migration):
    """State-only: records users.email_verified_at / phone_verified_at, which are
    added to the real Postgres schema by verification_extension.sql. The database
    router blocks DDL for the (unmanaged) users app — no ALTER is issued here."""

    dependencies = [
        ('users', '0002_user_updated_at'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='email_verified_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='user',
            name='phone_verified_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
