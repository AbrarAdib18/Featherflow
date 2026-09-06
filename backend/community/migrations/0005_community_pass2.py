"""Community & Blog — Pass 2 (state-only).

The tables live in featherflow_schema.sql / postgres_backend_extension.sql and
every model in ``community/models.py`` is ``managed = False`` (the
ExistingSchemaRouter also blocks migrations for this app), so this migration
never touches the database. It only keeps Django's migration state in step with
the models so a future ``makemigrations`` stays quiet.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('community', '0004_report_alter_bookmark_options_alter_comment_options_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(model_name='post', name='post_type',
            field=models.CharField(choices=[('text', 'Text'), ('poll', 'Poll'), ('question', 'Question')], default='text', max_length=10)),
        migrations.AddField(model_name='post', name='title',
            field=models.TextField(blank=True, null=True)),
        migrations.AddField(model_name='post', name='tags',
            field=models.JSONField(blank=True, default=list)),
        migrations.AddField(model_name='post', name='mentions',
            field=models.JSONField(blank=True, default=list)),
        migrations.AddField(model_name='post', name='poll_options',
            field=models.JSONField(blank=True, null=True)),
        migrations.AddField(model_name='post', name='poll_multi',
            field=models.BooleanField(default=False)),
        migrations.AddField(model_name='post', name='is_trending',
            field=models.BooleanField(default=False)),
        migrations.AddField(model_name='post', name='hidden_reason',
            field=models.TextField(blank=True, null=True)),
        migrations.AlterField(model_name='post', name='status',
            field=models.CharField(blank=True, choices=[('active', 'Active'), ('flagged', 'Flagged'), ('hidden', 'Hidden'), ('removed', 'Removed')], default='active', max_length=10, null=True)),
        migrations.AddField(model_name='comment', name='is_anonymous',
            field=models.BooleanField(default=False)),
        migrations.AddField(model_name='comment', name='hidden_reason',
            field=models.TextField(blank=True, null=True)),
        migrations.AlterField(model_name='comment', name='status',
            field=models.CharField(blank=True, choices=[('active', 'Active'), ('flagged', 'Flagged'), ('hidden', 'Hidden'), ('removed', 'Removed')], default='active', max_length=10, null=True)),
        migrations.AlterField(model_name='reaction', name='reaction_type',
            field=models.CharField(choices=[('like', 'Like'), ('love', 'Love'), ('helpful', 'Helpful'), ('insightful', 'Insightful')], default='helpful', max_length=20)),
        migrations.CreateModel(
            name='PollVote',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('option_indexes', models.JSONField(default=list)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('post', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='poll_votes', to='community.post')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='poll_votes', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'poll_votes', 'managed': False, 'unique_together': {('post', 'user')}},
        ),
        migrations.CreateModel(
            name='Repost',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('comment', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('post', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='reposts', to='community.post')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='reposts', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'post_reposts', 'managed': False, 'unique_together': {('post', 'user')}},
        ),
        migrations.CreateModel(
            name='CommunityMute',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('reason', models.TextField(blank=True, null=True)),
                ('is_active', models.BooleanField(default=True)),
                ('expires_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='community_mutes', to=settings.AUTH_USER_MODEL)),
                ('muted_by', models.ForeignKey(blank=True, db_column='muted_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='community_mutes_issued', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'community_mutes', 'managed': False},
        ),
    ]
