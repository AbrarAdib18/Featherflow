"""Personal block/mute between community members (state-only).

Unmanaged model over ``user_blocks`` (postgres_backend_extension.sql); the
router blocks DDL, so this only keeps migration state in step.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('community', '0005_community_pass2'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='UserBlock',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('blocker', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='community_blocks', to=settings.AUTH_USER_MODEL)),
                ('blocked', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='community_blocked_by', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'user_blocks', 'managed': False, 'unique_together': {('blocker', 'blocked')}},
        ),
    ]
