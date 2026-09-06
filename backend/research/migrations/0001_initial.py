import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('articles', '0002_delete_article_articleauthor_article'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ResearchTag',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=100)),
                ('slug', models.SlugField(max_length=120, unique=True)),
                ('category', models.CharField(choices=[('disease', 'Disease'), ('breed', 'Breed'), ('age_group', 'Age group'), ('nutrition', 'Nutrition'), ('research_field', 'Research field'), ('market', 'Market'), ('other', 'Other')], max_length=20)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
            ],
            options={
                'db_table': 'research_tags',
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='ArticleTag',
            fields=[
                ('pk', models.CompositePrimaryKey('article_id', 'tag_id', blank=True, editable=False, primary_key=True, serialize=False)),
                ('article', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='article_tags', to='articles.article')),
                ('tag', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='article_tags', to='research.researchtag')),
            ],
            options={
                'db_table': 'article_tags',
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='ArticleVersionSnapshot',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('version', models.IntegerField()),
                ('snapshot', models.JSONField(default=dict)),
                ('change_note', models.CharField(blank=True, max_length=200, null=True)),
                ('changed_at', models.DateTimeField(blank=True, null=True)),
                ('article', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='version_snapshots', to='articles.article')),
                ('changed_by', models.ForeignKey(blank=True, db_column='changed_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='article_version_changes', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'article_version_snapshots',
                'ordering': ['version'],
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='ProfileChangeApplication',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('field_name', models.CharField(max_length=60)),
                ('old_value', models.TextField(blank=True, null=True)),
                ('new_value', models.TextField()),
                ('reason', models.TextField()),
                ('status', models.CharField(choices=[('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')], default='pending', max_length=15)),
                ('review_note', models.TextField(blank=True, null=True)),
                ('decided_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='profile_change_applications', to=settings.AUTH_USER_MODEL)),
                ('reviewed_by', models.ForeignKey(blank=True, db_column='reviewed_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='reviewed_profile_change_applications', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'profile_change_applications',
                'ordering': ['-created_at'],
                'managed': False,
            },
        ),
    ]
