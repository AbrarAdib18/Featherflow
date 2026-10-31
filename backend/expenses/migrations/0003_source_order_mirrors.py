"""State-only: reconcile `Expense.source_intent_id` / `source_pharmacy_order_id`
(already present on the model and in the live schema — pharmacy_cost_management
_extension.sql / billing — but never previously migrated, a pre-existing state
drift) and add `source_feed_order_id` (feed_owner_extension.sql) for the same
exactly-once feed-order-delivery -> Cost Management mirror.
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('expenses', '0002_farmer_panel'),
    ]

    operations = [
        migrations.AddField('expense', 'source_intent_id', models.UUIDField(blank=True, db_column='source_intent_id', null=True)),
        migrations.AddField('expense', 'source_pharmacy_order_id', models.CharField(blank=True, db_column='source_pharmacy_order_id', max_length=64, null=True)),
        migrations.AddField('expense', 'source_feed_order_id', models.CharField(blank=True, db_column='source_feed_order_id', max_length=64, null=True)),
    ]
