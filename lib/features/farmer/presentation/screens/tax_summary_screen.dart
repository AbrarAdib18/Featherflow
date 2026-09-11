import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/tax_api_service.dart';
import '../../data/models/tax_summary.dart';
import 'cost_management_screen.dart' show taka;

/// Tax home — YTD paid, estimated for the year, and what's still pending.
class TaxSummaryScreen extends StatefulWidget {
  const TaxSummaryScreen({super.key});

  @override
  State<TaxSummaryScreen> createState() => _TaxSummaryScreenState();
}

class _TaxSummaryScreenState extends State<TaxSummaryScreen> {
  TaxSummary? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await TaxApiService.getTaxSummary();
      if (mounted) {
        setState(() {
          _summary = s;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.canPop() ? context.pop() : context.go('/farmer')),
        title: const Text('Tax',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () => context.go('/farmer')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      _headline(s!),
                      const SizedBox(height: 16),
                      _actions(context),
                      const SizedBox(height: 20),
                      const Text('This year, tax by type',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
                      const SizedBox(height: 8),
                      for (final line in s.lines) _lineCard(line),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(color: const Color(0xFFFFE082))),
                        child: Row(children: [
                          const Icon(Icons.info_outline, size: 18, color: Color(0xFF8D6E00)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(s.disclaimer,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Color(0xFF6D5200), height: 1.4))),
                        ]),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _headline(TaxSummary s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
            color: AppColors.primary, borderRadius: AppRadius.lgAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Estimated tax for ${s.year}${s.taxYear.isNotEmpty ? '  (FY ${s.taxYear})' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(taka(s.estimatedTotal),
              style: const TextStyle(
                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 14),
          Row(children: [
            _pill('Paid so far', taka(s.totalPaid), AppColors.secondary),
            const SizedBox(width: 10),
            _pill('Still pending', taka(s.pending),
                s.pending > 0 ? const Color(0xFFFFB74D) : Colors.white),
          ]),
        ]),
      );

  Widget _pill(String label, String value, Color valueColor) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.white24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(color: valueColor, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _actions(BuildContext context) => Row(children: [
        _actionBtn(context, Icons.calculate_outlined, 'Estimate', '/farmer/tax/calculator'),
        const SizedBox(width: 10),
        _actionBtn(context, Icons.tune, 'My details', '/farmer/tax/profile'),
        const SizedBox(width: 10),
        _actionBtn(context, Icons.receipt_long, 'Payments', '/farmer/tax/payments'),
      ]);

  Widget _actionBtn(BuildContext context, IconData icon, String label, String route) => Expanded(
        child: InkWell(
          onTap: () => context.push(route).then((_) => _load()),
          borderRadius: AppRadius.mdAll,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
            child: Column(children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ]),
          ),
        ),
      );

  Widget _lineCard(TaxSummaryLine line) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: const Color(0xFFDEEAE5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(line.label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 8),
          Row(children: [
            _miniStat('Estimated', taka(line.estimated), Colors.black54),
            _miniStat('Paid', taka(line.paid), AppColors.secondary),
            _miniStat('Pending', taka(line.pending),
                line.pending > 0 ? AppColors.error : Colors.black38),
          ]),
        ]),
      );

  Widget _miniStat(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.black26),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
