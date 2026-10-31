"""Pharmacy Admin Portal — two additive columns on the shared `conversations`
table, used only by pharmacy<->admin support threads (doctor-farmer
consultation threads never set them). DDL lives in
pharmacy_admin_portal_extension.sql; state-only, matching pharmacy/0002 and
profiles/0005's convention for this managed=False schema.
"""
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('doctor', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='conversation', name='pharmacy_chat_status',
            field=models.CharField(blank=True, default='open', max_length=20, null=True),
        ),
        migrations.AddField(
            model_name='conversation', name='assigned_admin',
            field=models.ForeignKey(
                blank=True, db_column='assigned_admin_id', null=True,
                on_delete=django.db.models.deletion.DO_NOTHING, related_name='+',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
    ]
