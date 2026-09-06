"""State-only: Cost Management Pass 1 additions.

The columns/tables live in farmers_panel_extension.sql (loans application
columns, revenues receipt columns, expenses.paid_at/payment_id) and the base
schema (loan_installments). PostgreSQL owns the schema — ExistingSchemaRouter
blocks DDL for this app, so this migration only keeps model state in sync.
"""
import django.db.models.deletion
import uuid
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('expenses', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField('expense', 'paid_at', models.DateTimeField(blank=True, null=True)),
        migrations.AddField('expense', 'payment_id', models.UUIDField(blank=True, db_column='payment_id', null=True)),
        migrations.AddField('revenue', 'payment_method', models.CharField(blank=True, max_length=50)),
        migrations.AddField('revenue', 'buyer_name', models.CharField(blank=True, max_length=150)),
        migrations.AddField('revenue', 'receipt_url', models.TextField(blank=True)),
        migrations.AlterField('loan', 'interest_rate', models.DecimalField(blank=True, decimal_places=2, max_digits=5, null=True)),
        migrations.AlterField('loan', 'start_date', models.DateField(blank=True, null=True)),
        migrations.AlterField('loan', 'due_date', models.DateField(blank=True, null=True)),
        migrations.AddField('loan', 'purpose', models.TextField(blank=True)),
        migrations.AddField('loan', 'term_months', models.PositiveIntegerField(blank=True, null=True)),
        migrations.AddField('loan', 'requested_by', models.ForeignKey(blank=True, db_column='requested_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='loan_requests', to=settings.AUTH_USER_MODEL)),
        migrations.AddField('loan', 'decided_by', models.ForeignKey(blank=True, db_column='decided_by', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='loan_decisions', to=settings.AUTH_USER_MODEL)),
        migrations.AddField('loan', 'decided_at', models.DateTimeField(blank=True, null=True)),
        migrations.AddField('loan', 'rejection_reason', models.TextField(blank=True)),
        migrations.CreateModel(
            name='LoanInstallment',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('due_date', models.DateField()),
                ('amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('paid_date', models.DateField(blank=True, null=True)),
                ('payment_id', models.UUIDField(blank=True, db_column='payment_id', null=True)),
                ('status', models.CharField(choices=[('pending', 'Pending'), ('paid', 'Paid'), ('overdue', 'Overdue')], default='pending', max_length=10)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('loan', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='installments', to='expenses.loan')),
            ],
            options={'db_table': 'loan_installments', 'ordering': ['due_date'], 'managed': False},
        ),
    ]
