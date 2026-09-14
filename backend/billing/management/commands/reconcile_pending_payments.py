"""Reconciliation for PaymentIntents that never got a webhook result.

    python manage.py reconcile_pending_payments [--stale-minutes 30]
                                                 [--timeout-hours 24] [--dry-run]

This is a provider-agnostic safety net for two failure modes that a webhook
alone can't recover from: the provider never called our webhook back at all
(network issue, misconfigured URL, provider outage), or it called back and we
failed to process it (our server was down, the request errored before it
reached ``billing.views.webhook``). Neither failure mode calls any provider
API here — there is no generic "check status" call across Stripe/bKash/Nagad,
and wiring one in per-provider is out of scope until real credentials exist
(see PAYMENT_RUNBOOK.md). What this command *can* do safely with only our own
data:

  1. Flag every ``PaymentIntent`` stuck in 'created' or 'pending' longer than
     ``--stale-minutes`` — an audit-log entry so admins can see it (and, once
     a provider is wired in, this is the hook point for an actual status
     lookup per intent).
  2. Time out intents stuck longer than ``--timeout-hours`` — mark them
     'failed' with a clear reason, the same terminal state a real provider
     'failure' webhook would produce. This never guesses success; a timed-out
     intent can never silently become an active subscription.

Both thresholds and the failing behaviour are opt-out via ``--dry-run``
(report only, changes nothing) so this is safe to run from cron on a fresh
deployment before verifying it against real traffic.
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from billing.models import PaymentIntent


class Command(BaseCommand):
    help = ('Flag/timeout PaymentIntents stuck in created/pending with no '
            'webhook result (missed or delayed provider callbacks).')

    def add_arguments(self, parser):
        parser.add_argument('--stale-minutes', type=int, default=30,
                            help='Age (minutes) after which a stuck intent is flagged for review (default 30).')
        parser.add_argument('--timeout-hours', type=int, default=24,
                            help='Age (hours) after which a stuck intent is marked failed (default 24).')
        parser.add_argument('--dry-run', action='store_true',
                            help='Report what would be flagged/timed-out without changing anything.')

    def handle(self, *args, **opts):
        now = timezone.now()
        stale_cutoff = now - timedelta(minutes=opts['stale_minutes'])
        timeout_cutoff = now - timedelta(hours=opts['timeout_hours'])

        stuck = (PaymentIntent.objects
                .filter(status__in=('created', 'pending'), created_at__lt=stale_cutoff)
                .order_by('created_at'))

        flagged, timed_out = 0, 0
        for intent in stuck.iterator():
            age = now - intent.created_at
            if intent.created_at < timeout_cutoff:
                timed_out += 1
                self.stdout.write(
                    f'  TIMEOUT  {intent.id}  {intent.provider}/{intent.payment_method or "?"}  '
                    f'{intent.amount} {intent.currency}  age={age}')
                if not opts['dry_run']:
                    self._time_out(intent)
            else:
                flagged += 1
                self.stdout.write(
                    f'  STALE    {intent.id}  {intent.provider}/{intent.payment_method or "?"}  '
                    f'{intent.amount} {intent.currency}  age={age}')
                if not opts['dry_run']:
                    self._flag(intent, age)

        verb = 'Would flag' if opts['dry_run'] else 'Flagged'
        verb2 = 'would time out' if opts['dry_run'] else 'timed out'
        self.stdout.write(self.style.SUCCESS(
            f'{verb} {flagged} stale intent(s), {verb2} {timed_out} intent(s) '
            f'past {opts["timeout_hours"]}h with no webhook result.'))

    def _flag(self, intent, age):
        from audit.models import ActivityLog
        ActivityLog.objects.create(
            user=intent.user, module='billing',
            action='Payment intent stuck awaiting provider webhook',
            action_type=None, entity_type='payment_intent', entity_id=intent.id,
            reason=f'No webhook result after {age}.',
            new_values={'status': intent.status, 'amount': str(intent.amount),
                       'currency': intent.currency, 'provider': intent.provider},
        )

    def _time_out(self, intent):
        from billing import services
        # Re-fetch in case a delayed webhook landed between the query above and now.
        current = PaymentIntent.objects.filter(pk=intent.pk).first()
        if current is None or current.status not in ('created', 'pending'):
            return
        current.status = 'failed'
        current.failure_reason = 'Payment timed out — no confirmation received from the provider.'
        current.save(update_fields=['status', 'failure_reason', 'updated_at'])
        services.record_audit_event(current, 'Payment timed out — no webhook received',
                                    action_type=None, reason=current.failure_reason)
