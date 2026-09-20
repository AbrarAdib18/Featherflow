import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/labour_payment_service.dart';
import '../../data/models/labour_payment_models.dart';
import '../../data/models/subscription_models.dart' show PayMethod, PayMethodX;

/// Labour-payment review -> method -> checkout -> result flow. Mirrors
/// `subscription_flow_screens.dart` structure (same visual language, same
/// dev-mode-simulation pattern) but operates on a *list* of intents so
/// "Pay All" can settle several workers through one method choice — see
/// FEED_AND_DATA_INTEGRITY_AUDIT.md Priority 3.

AppBar _bar(BuildContext context, String title, {String fallback = '/farmer/labor'}) => AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.canPop() ? context.pop() : context.go(fallback),
      ),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
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
            style: TextStyle(fontSize: 12, color: Color(0xFF8A5A00), fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );

String _fmtPeriod(LabourPaymentIntent i) => '${i.periodStart} → ${i.periodEnd}';

double _total(List<LabourPaymentIntent> intents) =>
    intents.fold(0.0, (sum, i) => sum + i.amount);

// ── 1. Review ────────────────────────────────────────────────────────────

class LabourPayReviewScreen extends StatelessWidget {
  const LabourPayReviewScreen({super.key, required this.intents});
  final List<LabourPaymentIntent> intents;

  @override
  Widget build(BuildContext context) {
    if (intents.isEmpty) {
      return Scaffold(
        appBar: _bar(context, 'Pay workers'),
        body: const Center(child: Text('Nothing is due right now.')),
      );
    }
    final currency = intents.first.currency;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _bar(context, intents.length == 1 ? 'Review payment' : 'Review payments'),
      body: Column(children: [
        if (intents.first.isDevMode) _devModeBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final i in intents)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                    color: Color(0xFFF0F7F4), borderRadius: AppRadius.mdAll),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.workerName,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text('Pay period: ${_fmtPeriod(i)}',
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ]),
                  ),
                  Text(i.amountDisplay,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                ]),
              ),
            const Divider(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total due now',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
              Text('$currency ${_total(intents).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ]),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/farmer/labor/pay-method', extra: intents),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Continue to payment', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 2. Method selection ─────────────────────────────────────────────────

class LabourPaymentMethodScreen extends StatefulWidget {
  const LabourPaymentMethodScreen({super.key, required this.intents});
  final List<LabourPaymentIntent> intents;

  @override
  State<LabourPaymentMethodScreen> createState() => _LabourPaymentMethodScreenState();
}

class _LabourPaymentMethodScreenState extends State<LabourPaymentMethodScreen> {
  PayMethod? _method;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    if (_method == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = <LabourPaymentIntent>[];
      for (final i in widget.intents) {
        updated.add(await LabourPaymentService.selectMethod(i.id, _method!));
      }
      if (!mounted) return;
      context.push('/farmer/labor/pay-checkout', extra: updated);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final intents = widget.intents;
    final isDevMode = intents.isNotEmpty && intents.first.isDevMode;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _bar(context, 'Choose payment method'),
      body: Column(children: [
        if (isDevMode) _devModeBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: Color(0xFFF0F7F4), borderRadius: AppRadius.mdAll),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(intents.length == 1 ? intents.first.workerName : '${intents.length} workers',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
                Text(
                    '${intents.isNotEmpty ? intents.first.currency : 'BDT'} '
                    '${_total(intents).toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
              ]),
            ),
            const SizedBox(height: 16),
            for (final m in PayMethod.values)
              _MethodTile(
                selected: _method == m,
                onTap: () => setState(() => _method = m),
                title: m.label,
              ),
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
                onPressed: (_method == null || _busy) ? null : _continue,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _busy
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_method == null ? 'Select a method' : 'Continue',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.selected, required this.onTap, required this.title});
  final bool selected;
  final VoidCallback onTap;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
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
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.black87, fontSize: 15))),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.secondary : Colors.black26, size: 20),
              ]),
            ),
          ),
        ),
      );
}

// ── 3. Checkout (dev simulation) ────────────────────────────────────────

class LabourCheckoutScreen extends StatefulWidget {
  const LabourCheckoutScreen({super.key, required this.intents});
  final List<LabourPaymentIntent> intents;

  @override
  State<LabourCheckoutScreen> createState() => _LabourCheckoutScreenState();
}

class _LabourCheckoutScreenState extends State<LabourCheckoutScreen> {
  bool _busy = false;
  String? _error;

  // A batch used to fail atomically: one intent throwing mid-loop discarded
  // every result already collected, so a partial "Pay All" left some workers
  // confirmed and some untouched with nothing but a generic error banner. Each
  // intent is now confirmed independently and the result screen — which
  // already renders success/cancelled/failed per row — gets every outcome,
  // including the original request object for whichever call didn't complete.
  Future<void> _finish(String outcome) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final results = <LabourPaymentIntent>[];
    for (final i in widget.intents) {
      try {
        results.add(await LabourPaymentService.devConfirm(i.id, outcome));
      } catch (e) {
        results.add(i.withFailure(ErrorStateView.humanize(e)));
      }
    }
    if (!mounted) return;
    context.pushReplacement('/farmer/labor/pay-result', extra: results);
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    final results = <LabourPaymentIntent>[];
    for (final i in widget.intents) {
      try {
        results.add(await LabourPaymentService.cancel(i.id));
      } catch (e) {
        results.add(i.withFailure(ErrorStateView.humanize(e)));
      }
    }
    if (mounted) context.pushReplacement('/farmer/labor/pay-result', extra: results);
  }

  @override
  Widget build(BuildContext context) {
    final intents = widget.intents;
    final isDevMode = intents.isNotEmpty && intents.first.isDevMode;
    final methodLabel = switch (intents.isNotEmpty ? intents.first.paymentMethod : null) {
      'bkash' => 'bKash',
      'nagad' => 'Nagad',
      'card' => 'Card',
      _ => 'Payment',
    };

    if (!isDevMode) {
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
                onPressed: () => context.go('/farmer/labor'),
                child: const Text('Back to labour management'),
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
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16)]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Simulated $methodLabel payment',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 4),
                  const Text('No wallet or card details are collected.',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                  const SizedBox(height: 20),
                  for (final i in intents)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Text(i.workerName, style: const TextStyle(fontSize: 13))),
                        Text(i.amountDisplay, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  const Divider(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${intents.isNotEmpty ? intents.first.currency : 'BDT'} ${_total(intents).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    ErrorStateView(message: _error!, compact: true, onRetry: () => _finish('success')),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => _finish('success'),
                      icon: _busy
                          ? const SizedBox(
                              height: 16, width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text('Approve payment · ${intents.isNotEmpty ? intents.first.currency : 'BDT'} '
                          '${_total(intents).toStringAsFixed(0)}'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondaryContainer,
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
                          foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                      child: const Text('Simulate a declined payment'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel and go back')),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 4. Result ────────────────────────────────────────────────────────────

class LabourPaymentResultScreen extends StatelessWidget {
  const LabourPaymentResultScreen({super.key, required this.intents});
  final List<LabourPaymentIntent> intents;

  @override
  Widget build(BuildContext context) {
    final allSucceeded = intents.isNotEmpty && intents.every((i) => i.succeeded);
    final anyCancelled = intents.any((i) => i.cancelled);
    final color = allSucceeded
        ? AppColors.secondaryContainer
        : anyCancelled
            ? Colors.orange
            : AppColors.error;
    final icon = allSucceeded
        ? Icons.check_circle
        : anyCancelled
            ? Icons.info
            : Icons.error;
    final title = allSucceeded
        ? (intents.length == 1 ? 'Payment successful' : 'Payments successful')
        : anyCancelled
            ? 'Payment cancelled'
            : 'Payment failed';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Payment',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
            const SizedBox(height: 20),
            for (final i in intents)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Color(0xFFF0F7F4), borderRadius: AppRadius.mdAll),
                child: Row(children: [
                  Icon(
                      i.succeeded
                          ? Icons.check_circle
                          : i.cancelled
                              ? Icons.info_outline
                              : Icons.error_outline,
                      size: 18,
                      color: i.succeeded
                          ? AppColors.secondaryContainer
                          : i.cancelled
                              ? Colors.orange
                              : AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.workerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          i.succeeded
                              ? 'Paid ${i.amountDisplay}'
                              : i.cancelled
                                  ? 'Cancelled — not paid'
                                  : (i.failureReason ?? 'Failed — not paid'),
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                ]),
              ),
            if (intents.any((i) => i.isDevMode))
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 12),
                child: Text('Development mode — no real money moved.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8A5A00), fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            if (!allSucceeded)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go('/farmer/labor'),
                  child: const Text('Back to labour management'),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/farmer/labor'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Guard for a screen reached with no/invalid `extra` (e.g. hard refresh mid-flow).
Widget labourPaymentExtraGuard(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) context.go('/farmer/labor');
  });
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
