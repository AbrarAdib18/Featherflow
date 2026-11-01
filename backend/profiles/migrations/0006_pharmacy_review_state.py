"""Pharmacy Admin Portal — review_state column. DDL lives in
pharmacy_admin_portal_extension.sql; state-only, matching 0005.
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('profiles', '0005_admin_shift_payment'),
    ]

    operations = [
        migrations.AddField(
            model_name='pharmacyorganization', name='review_state',
            field=models.CharField(
                blank=True, null=True, default='approved', max_length=30,
                choices=[
                    ('pending_review', 'Pending review'),
                    ('needs_more_information', 'Needs more information'),
                    ('approved', 'Approved'), ('rejected', 'Rejected'), ('closed', 'Closed'),
                ],
            ),
        ),
    ]
