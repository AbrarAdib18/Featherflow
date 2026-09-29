"""DEVELOPMENT/DEMO DATA ONLY — never run against a production database.

Creates a small, real, persisted set of Finance Admin demo records so the
Finance dashboard/Subscriptions/Cashout pages have something genuine to show
in a fresh dev environment: subscription plans, subscriptions (active /
expired / cancelled), subscription payments (paid / failed / refunded),
revenue ledger entries for the paid ones, and cashout requests in every
review state. Idempotent — safe to re-run; existing rows are left alone
(only missing ones are created), and nothing is ever deleted.

Run:  backend/venv/Scripts/python.exe manage.py seed_finance_demo_data
"""
import hashlib
from datetime import date, timedelta

from django.core.management.base import BaseCommand
from django.db import IntegrityError
from django.utils import timezone

from api.finance_models import CashoutReview, RevenueEntry
from payments.models import Payment
from subscriptions.models import Subscription, SubscriptionPlan
from users.models import Role, User

PREFIX = 'financedemo+'


class Command(BaseCommand):
    help = 'DEV/DEMO ONLY — seeds real, persisted Finance Admin demo data (plans, subscriptions, payments, revenue, cashouts).'

    def handle(self, *args, **options):
        created = {'users': 0, 'plans': 0, 'subscriptions': 0, 'payments': 0,
                   'revenue_entries': 0, 'cashouts': 0}
        skipped = {'users': 0, 'plans': 0, 'subscriptions': 0, 'payments': 0,
                   'revenue_entries': 0, 'cashouts': 0}

        plans = self._ensure_plans(created, skipped)
        demo_users = self._ensure_users(created, skipped, count=4)
        self._ensure_subscriptions_and_payments(demo_users, plans, created, skipped)
        self._ensure_cashouts(demo_users, created, skipped)

        self.stdout.write(self.style.WARNING(
            'DEV/DEMO DATA ONLY — do not run this against production.'))
        self.stdout.write(self.style.SUCCESS(
            f'created: {created}\nskipped (already existed): {skipped}'))

    def _ensure_plans(self, created, skipped):
        specs = [
            ('Free', 0, None, ['disease_scan_free']),
            ('Monthly Basic', 299, 30, ['disease_scan_50']),
            ('Monthly Premium', 599, 30, ['disease_scan_unlimited', 'priority_support']),
            ('Yearly', 4999, 365, ['disease_scan_unlimited', 'priority_support', 'annual_discount']),
        ]
        plans = {}
        for name, price, duration, features in specs:
            plan, was_created = SubscriptionPlan.objects.get_or_create(
                name=name, defaults=dict(
                    price=price, currency='BDT', duration_days=duration,
                    features_unlocked=features, is_active=True,
                    created_at=timezone.now(), updated_at=timezone.now(),
                ))
            plans[name] = plan
            created['plans' if was_created else 'plans'] += 1 if was_created else 0
            skipped['plans'] += 0 if was_created else 1
        return plans

    def _ensure_users(self, created, skipped, count):
        role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': None})
        users = []
        for i in range(1, count + 1):
            email = f'{PREFIX}user{i}@example.com'
            phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
            user, was_created = User.objects.get_or_create(email=email, defaults=dict(
                full_name=f'Finance Demo User {i}', phone=phone,
                date_of_birth=date(1990, 1, 1), present_address='Dhaka',
                consent_terms=True, account_status='active', is_verified=True,
            ))
            if was_created:
                user.set_password('FeatherflowDemo@2026')
                user.save()
                user.roles.add(role)
            users.append(user)
            created['users'] += 1 if was_created else 0
            skipped['users'] += 0 if was_created else 1
        return users

    def _ensure_subscriptions_and_payments(self, users, plans, created, skipped):
        now = timezone.now()
        basic, premium, yearly = plans['Monthly Basic'], plans['Monthly Premium'], plans['Yearly']
        # (user, plan, sub_status, payment_status, days_ago_started)
        scenarios = [
            (users[0], basic, 'active', 'completed', 5),
            (users[1], premium, 'active', 'completed', 20),
            (users[2], yearly, 'cancelled', 'refunded', 60),
            (users[3], basic, 'expired', 'failed', 90),
        ]
        for user, plan, sub_status, pay_status, days_ago in scenarios:
            existing = Subscription.objects.filter(
                user=user, plan=plan, started_at__date=(now - timedelta(days=days_ago)).date()).first()
            if existing:
                skipped['subscriptions'] += 1
                skipped['payments'] += 1
                continue
            started = now - timedelta(days=days_ago)
            payment = Payment.objects.create(
                user=user, amount=plan.price, currency=plan.currency,
                payment_method='card', payment_type='subscription',
                reference_type='subscription_plan', status=pay_status,
                transaction_id=f'demo:{user.id.hex[:8]}-{plan.id}',
                net_amount=plan.price if pay_status == 'completed' else 0,
                notes=f'Demo subscription payment ({pay_status}).',
                confirmed_at=started if pay_status == 'completed' else None,
                created_at=started,
            )
            created['payments'] += 1
            expires = (started + timedelta(days=plan.duration_days)) if plan.duration_days else None
            Subscription.objects.create(
                user=user, plan=plan, status=sub_status, started_at=started,
                expires_at=expires, auto_renew=(sub_status == 'active'),
                payment_id=payment.id, created_at=started,
            )
            created['subscriptions'] += 1
            if pay_status == 'completed':
                try:
                    RevenueEntry.objects.create(
                        source_payment_id=payment.id, amount=payment.amount,
                        currency=payment.currency, category=RevenueEntry.CATEGORY_SUBSCRIPTION,
                        recognized_at=started, user_id=user.id,
                        subscription_id=None, plan_id=plan.id,
                    )
                    created['revenue_entries'] += 1
                except IntegrityError:
                    skipped['revenue_entries'] += 1
            elif pay_status == 'refunded':
                try:
                    RevenueEntry.objects.create(
                        source_payment_id=payment.id, amount=payment.amount,
                        currency=payment.currency, category=RevenueEntry.CATEGORY_SUBSCRIPTION,
                        recognized_at=started, user_id=user.id, plan_id=plan.id,
                    )
                    RevenueEntry.objects.create(
                        source_payment_id=payment.id, amount=-payment.amount,
                        currency=payment.currency, category=RevenueEntry.CATEGORY_REFUND_ADJUSTMENT,
                        recognized_at=started + timedelta(days=1), user_id=user.id, plan_id=plan.id,
                    )
                    created['revenue_entries'] += 2
                except IntegrityError:
                    skipped['revenue_entries'] += 1

    def _ensure_cashouts(self, users, created, skipped):
        # (user, amount, review_status)
        scenarios = [
            (users[0], 1200, CashoutReview.STATUS_REQUESTED),
            (users[1], 3400, CashoutReview.STATUS_UNDER_REVIEW),
            (users[2], 2500, CashoutReview.STATUS_APPROVED),
            (users[3], 800, CashoutReview.STATUS_PAID),
        ]
        for user, amount, review_status in scenarios:
            existing = Payment.objects.filter(
                user=user, payment_type='cashout', amount=amount).first()
            if existing:
                skipped['cashouts'] += 1
                continue
            now = timezone.now()
            pay_status = {
                CashoutReview.STATUS_REQUESTED: 'pending',
                CashoutReview.STATUS_UNDER_REVIEW: 'pending',
                CashoutReview.STATUS_APPROVED: 'pending',
                CashoutReview.STATUS_PAID: 'completed',
            }[review_status]
            payment = Payment.objects.create(
                user=user, amount=amount, currency='BDT', payment_method='bkash',
                payment_type='cashout', reference_type='cashout', status=pay_status,
                notes='Demo cashout request.', created_at=now,
                confirmed_at=now if review_status == CashoutReview.STATUS_PAID else None,
            )
            CashoutReview.objects.create(
                payment_id=payment.id, status=review_status,
                reviewed_at=now if review_status in CashoutReview.APPROVED_STATUSES else None,
                settled_at=now if review_status == CashoutReview.STATUS_PAID else None,
            )
            created['cashouts'] += 1
