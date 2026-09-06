import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('articles', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.DeleteModel(
            name='Article',
        ),
        migrations.CreateModel(
            name='Article',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('title', models.CharField(max_length=300)),
                ('abstract', models.TextField()),
                ('body', models.TextField()),
                ('content_type', models.CharField(blank=True, choices=[('research_paper', 'Research paper'), ('news', 'News'), ('innovation', 'Innovation'), ('disease_study', 'Disease study'), ('feed_study', 'Feed study'), ('market_report', 'Market report'), ('team_update', 'Team Featherflow update')], max_length=20, null=True)),
                ('category', models.CharField(blank=True, max_length=100, null=True)),
                ('keywords', models.JSONField(blank=True, default=list)),
                ('references_list', models.JSONField(blank=True, default=list)),
                ('pdf_url', models.TextField(blank=True, null=True)),
                ('farmer_summary', models.TextField(blank=True, null=True)),
                ('status', models.CharField(choices=[('draft', 'Draft'), ('pending_review', 'Pending review'), ('needs_revision', 'Needs revision'), ('published', 'Published'), ('archived', 'Archived')], default='draft', max_length=20)),
                ('version', models.IntegerField(default=1)),
                ('read_count', models.IntegerField(default=0)),
                ('co_authors', models.JSONField(blank=True, default=list)),
                ('content_details', models.JSONField(blank=True, default=dict)),
                ('review_notes', models.TextField(blank=True, null=True)),
                ('is_featured', models.BooleanField(default=False)),
                ('published_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('updated_at', models.DateTimeField(blank=True, null=True)),
                ('author', models.ForeignKey(on_delete=django.db.models.deletion.DO_NOTHING, related_name='authored_articles', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'verbose_name_plural': 'Articles',
                'db_table': 'articles',
                'managed': False,
            },
        ),
        migrations.CreateModel(
            name='ArticleAuthor',
            fields=[
                ('pk', models.CompositePrimaryKey('article_id', 'user_id', blank=True, editable=False, primary_key=True, serialize=False)),
                ('author_role', models.CharField(choices=[('lead_author', 'Lead author'), ('co_author', 'Co-author'), ('editor', 'Editor')], max_length=15)),
                ('created_at', models.DateTimeField(blank=True, null=True)),
                ('article', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='article_authors', to='articles.article')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='article_author_roles', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'article_authors',
                'managed': False,
            },
        ),
    ]
