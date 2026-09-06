"""Admin Panel RBAC pass — state-only.

The tables live in featherflow_schema.sql / postgres_backend_extension.sql and
every model here is ``managed = False`` (the ExistingSchemaRouter also blocks
migrations for this app), so this migration never touches the database. It only
keeps Django's migration state in step with ``audit/models.py`` so a future
``makemigrations`` stays quiet.
"""

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('audit', '0002_securityflag_supportticket'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.DeleteModel(name='SupportTicket'),
        migrations.AddField(
            model_name='activitylog',
            name='action_type',
            field=models.CharField(blank=True, max_length=20, null=True),
        ),
        migrations.AddField(
            model_name='activitylog',
            name='reason',
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='activitylog',
            name='user_agent',
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='activitylog',
            name='request_id',
            field=models.UUIDField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name='AdminApprovalQueue',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('action_type', models.CharField(max_length=20)),
                ('module_affected', models.CharField(max_length=40)),
                ('target_id', models.UUIDField(blank=True, null=True)),
                ('target_type', models.CharField(blank=True, max_length=50, null=True)),
                ('request_data', models.JSONField(default=dict)),
                ('status', models.CharField(default='pending', max_length=15)),
                ('required_tier', models.SmallIntegerField(default=2)),
                ('reason', models.TextField(blank=True, null=True)),
                ('rejection_reason', models.TextField(blank=True, null=True)),
                ('result_ref_id', models.UUIDField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('decided_at', models.DateTimeField(blank=True, null=True)),
                ('requested_by', models.ForeignKey(db_column='requested_by', on_delete=django.db.models.deletion.DO_NOTHING, related_name='approval_requests', to=settings.AUTH_USER_MODEL)),
                ('approved_by', models.ForeignKey(blank=True, db_column='approved_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='approval_decisions', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'admin_approval_queue', 'ordering': ['-created_at'], 'managed': False},
        ),
        migrations.CreateModel(
            name='AdminEscalation',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('module', models.CharField(max_length=40)),
                ('target_id', models.UUIDField(blank=True, null=True)),
                ('target_type', models.CharField(blank=True, max_length=50, null=True)),
                ('priority', models.CharField(default='medium', max_length=10)),
                ('subject', models.CharField(max_length=200)),
                ('detail', models.TextField(blank=True, null=True)),
                ('status', models.CharField(default='open', max_length=15)),
                ('resolution', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('resolved_at', models.DateTimeField(blank=True, null=True)),
                ('raised_by', models.ForeignKey(db_column='raised_by', on_delete=django.db.models.deletion.DO_NOTHING, related_name='raised_escalations', to=settings.AUTH_USER_MODEL)),
                ('assigned_to', models.ForeignKey(blank=True, db_column='assigned_to', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='assigned_escalations', to=settings.AUTH_USER_MODEL)),
                ('resolved_by', models.ForeignKey(blank=True, db_column='resolved_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='resolved_escalations', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'admin_escalations', 'ordering': ['-created_at'], 'managed': False},
        ),
        migrations.CreateModel(
            name='SupportTicket',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('ticket_number', models.CharField(max_length=20, unique=True)),
                ('raised_by_name', models.CharField(blank=True, max_length=150, null=True)),
                ('category', models.CharField(default='general', max_length=40)),
                ('subject', models.CharField(max_length=200)),
                ('description', models.TextField(blank=True, null=True)),
                ('priority', models.CharField(default='medium', max_length=10)),
                ('status', models.CharField(default='open', max_length=15)),
                ('is_escalated', models.BooleanField(default=False)),
                ('resolution', models.TextField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('resolved_at', models.DateTimeField(blank=True, null=True)),
                ('raised_by', models.ForeignKey(blank=True, db_column='raised_by', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='support_tickets', to=settings.AUTH_USER_MODEL)),
                ('assigned_to', models.ForeignKey(blank=True, db_column='assigned_to', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='assigned_support_tickets', to=settings.AUTH_USER_MODEL)),
                ('escalation', models.ForeignKey(blank=True, db_column='escalation_id', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='support_tickets', to='audit.adminescalation')),
            ],
            options={'db_table': 'support_tickets', 'ordering': ['-created_at'], 'managed': False},
        ),
        migrations.CreateModel(
            name='SupportTicketReply',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('author_role', models.CharField(blank=True, max_length=30, null=True)),
                ('body', models.TextField()),
                ('is_internal', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('ticket', models.ForeignKey(db_column='ticket_id', on_delete=django.db.models.deletion.CASCADE, related_name='replies', to='audit.supportticket')),
                ('author', models.ForeignKey(blank=True, db_column='author_id', null=True, on_delete=django.db.models.deletion.DO_NOTHING, related_name='support_ticket_replies', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'support_ticket_replies', 'ordering': ['created_at'], 'managed': False},
        ),
    ]
