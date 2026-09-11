import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/subscription_service.dart';
import '../../data/models/subscription_models.dart';

// ── shared bits ─────────────────────────────────────────────────────────────

AppBar _bar(BuildContext context, String title, {String fallback = '/subscription'}) =>
    AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () =>
            context.canPop() ? context.pop() : context.go(fallback),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
    );

Widget _devModeBanner() => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFFFF4E5),
      child: const Row(children: [
        Icon(Icons.construction, size: 18, color: Color(0xFF8A5A00)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Development payment mode — no real money moves. This is a '
            'simulated checkout for testing.',
            style: TextStyle(
                fontSize: 12, color: Color(0xFF8A5A00), fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );

String _newIdempotencyKey() {
  // NB: `1 << 32` overflows to 0 in dart2js (JS bitwise ops are 32-bit), which
  // makes Random.nextInt throw a RangeError — keep the bound under 2^31.
  final r = Random();
  return 'ck_${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(0x7fffffff)}';
}

// ── 1. Plan review ─────────────────────────────────────────────────────────

class PlanReviewScreen extends StatefulWidget {
  const PlanReviewScreen({super.key, required this.plan, required this.isDevMode});
  final SubPlan plan;
  final bool isDevMode;

  @override
  State<PlanReviewScreen> createState() => _PlanReviewScreenState();
}

class _PlanReviewScreenState extends State<PlanReviewScreen> {
  bool _busy = false;
  String? _error;
  // One key per review screen instance → a double-tap makes one intent.
  final _idem = _newIdempotencyKey();

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final intent = await SubscriptionService.checkout(
          planId: widget.plan.id, idempotencyKey: _idem);
      if (!mounted) return;
      context.push('/subscription/pay', extra: intent);
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorStateView.humanize(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _bar(context, 'Review your plan'),
      body: Column(children: [
        if (widget.isDevMode) _devModeBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: AppColors.secondary, width: 2),
                color: AppColors.secondary.withValues(alpha: 0.04),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondary)),
                  if (p.recommended) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: AppRadius.smAll),
                      child: const Text('Recommended',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(p.tagline,
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(p.priceDisplay.split(RegExp(r'[/ ]')).first == p.priceDisplay
                          ? p.priceDisplay
                          : '${p.currency} ${p.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                      const SizedBox(width: 6),
                      Text(p.intervalLabel,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ]),
                const Divider(height: 24),
                for (final f in p.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(f,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            _OrderLine('Plan', p.name),
            _OrderLine('Billing', p.intervalLabel),
            _OrderLine('Total due now', '${p.currency} ${p.price.toStringAsFixed(0)}',
                bold: true),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorStateView(message: _error!, compact: true, onRetry: _continue),
            ],
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _continue,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Continue to payment',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  color: bold ? Colors.black87 : Colors.black54,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 16 : 13,
                  color: bold ? AppColors.primary : Colors.black87,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

// ── 2. Payment method selection ────────────────────────────────────────────

class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({super.key, required this.intent});
  final PaymentIntent intent;

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  PayMethod? _method;
  bool _busy = false;
  String? _error;

  Future<void> _pay() async {
    if (_method == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated =
          await SubscriptionService.selectMethod(widget.intent.id, _method!);
      if (!mounted) return;
      if (updated.isDevMode) {
        context.push('/subscription/checkout', extra: updated);
      } else {
        // Production: hand off to the provider's hosted checkout.
        context.push('/subscription/checkout', extra: updated);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.intent;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _bar(context, 'Choose payment method'),
      body: Column(children: [
        if (i.isDevMode) _devModeBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                  color: Color(0xFFF0F7F4),
                  borderRadius: AppRadius.mdAll),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${i.planName} · ${i.interval == 'year' ? 'yearly' : 'monthly'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.black87)),
                    Text(i.amountDisplay,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ]),
            ),
            const SizedBox(height: 16),
            _MethodTile(
              selected: _method == PayMethod.card,
              onTap: () => setState(() => _method = PayMethod.card),
              leading: const Icon(Icons.credit_card, color: AppColors.primary),
              title: 'Card',
              subtitle: 'Visa · Mastercard — entered on the secure provider page',
              badges: const ['VISA', 'Mastercard'],
            ),
            _MethodTile(
              selected: _method == PayMethod.bkash,
              onTap: () => setState(() => _method = PayMethod.bkash),
              leading: _brandChip('bKash', const Color(0xFFE2136E)),
              title: 'bKash',
              subtitle: 'Pay from your bKash wallet',
            ),
            _MethodTile(
              selected: _method == PayMethod.nagad,
              onTap: () => setState(() => _method = PayMethod.nagad),
              leading: _brandChip('Nagad', const Color(0xFFEE7000)),
              title: 'Nagad',
              subtitle: 'Pay from your Nagad wallet',
            ),
            const SizedBox(height: 12),
            const Row(children: [
              Icon(Icons.lock_outline, size: 13, color: Colors.black38),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Card details are never sent to or stored by Featherflow — '
                  'the payment provider handles them.',
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorStateView(message: _error!, compact: true, onRetry: _pay),
            ],
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_method == null || _busy) ? null : _pay,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _method == null
                            ? 'Select a method'
                            : 'Pay ${i.amountDisplay}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

Widget _brandChip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.badges = const [],
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppColors.secondary.withValues(alpha: 0.06) : Colors.white,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                  color: selected ? AppColors.secondary : const Color(0xFFDEEAE5),
                  width: selected ? 2 : 1),
            ),
            child: Row(children: [
              SizedBox(width: 44, child: Center(child: leading)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              fontSize: 15)),
                      for (final b in badges) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFFEEF2F1),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(b,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3A4A45))),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.secondary : Colors.black26,
                  size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── 3. Checkout (dev simulation / provider handoff) ────────────────────────

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.intent});
  final PaymentIntent intent;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _finish(String outcome) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await SubscriptionService.devConfirm(widget.intent.id, outcome);
      if (!mounted) return;
      context.pushReplacement('/subscription/result', extra: result);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      final result = await SubscriptionService.cancel(widget.intent.id);
      if (mounted) context.pushReplacement('/subscription/result', extra: result);
    } catch (_) {
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.intent;
    final methodLabel = switch (i.paymentMethod) {
      'bkash' => 'bKash',
      'nagad' => 'Nagad',
      'card' => 'Card',
      _ => 'Payment',
    };

    if (!i.isDevMode) {
      // Production: a real provider integration would open the hosted
      // checkout / SDK here. Until one is wired in, be explicit.
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _bar(context, 'Payment'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              const Text(
                'A live payment provider is configured but its checkout screen '
                'is not wired into this build yet. See PAYMENT_INTEGRATION.md.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go('/subscription'),
                child: const Text('Back to plans'),
              ),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: _bar(context, '$methodLabel checkout'),
      body: Column(children: [
        _devModeBanner(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.lgAll,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 16)
                    ]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Simulated $methodLabel payment',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.black87)),
                  const SizedBox(height: 4),
                  const Text('No card or wallet details are collected.',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                  const SizedBox(height: 20),
                  const _OrderLine('Merchant', 'Featherflow'),
                  _OrderLine('Plan', i.planName),
                  _OrderLine('Amount', i.amountDisplay, bold: true),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    ErrorStateView(
                        message: _error!,
                        compact: true,
                        onRetry: () => _finish('success')),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _finish('success'),
                      icon: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text('Approve payment · ${i.amountDisplay}'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _finish('failure'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error)),
                      child: const Text('Simulate a declined payment'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text('Cancel and go back'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 4. Result ──────────────────────────────────────────────────────────────

class PaymentResultScreen extends StatelessWidget {
  const PaymentResultScreen({super.key, required this.intent});
  final PaymentIntent intent;

  @override
  Widget build(BuildContext context) {
    final ok = intent.succeeded;
    final cancelled = intent.cancelled;
    final color = ok
        ? const Color(0xFF2E7D32)
        : cancelled
            ? Colors.orange
            : AppColors.error;
    final icon = ok
        ? Icons.check_circle
        : cancelled
            ? Icons.info
            : Icons.error;
    final title = ok
        ? 'Payment successful'
        : cancelled
            ? 'Payment cancelled'
            : 'Payment failed';
    final body = ok
        ? 'Your ${intent.planName} subscription is now active.'
        : cancelled
            ? 'No payment was taken. You can pick a plan again whenever you are ready.'
            : (intent.failureReason ??
                'The payment did not go through. No subscription was activated.');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Payment',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4)),
            const SizedBox(height: 20),
            if (ok) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                    color: Color(0xFFF0F7F4),
                    borderRadius: AppRadius.mdAll),
                child: Column(children: [
                  _OrderLine('Plan', intent.planName),
                  _OrderLine('Amount paid', intent.amountDisplay),
                  _OrderLine('Payment ref', intent.id.substring(0, 8)),
                  if (intent.isDevMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Development mode — no real charge was made.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8A5A00),
                              fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/farmer'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Done'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/subscription'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(cancelled ? 'Back to plans' : 'Try again'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/farmer'),
              child: const Text('Go to dashboard'),
            ),
          ]),
        ),
      ),
    );
  }
}

// Guard for a screen reached with no `extra` (e.g. a hard refresh mid-flow).
Widget subscriptionExtraGuard(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) context.go('/subscription');
  });
  return const Scaffold(
      body: Center(child: CircularProgressIndicator()));
}
