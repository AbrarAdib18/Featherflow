import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/tax_api_service.dart';
import '../../data/models/tax_calculation_result.dart';
import '../../data/models/tax_profile.dart';
import 'cost_management_screen.dart' show taka;

/// Real-time tax estimate. Prefilled from the saved profile + this year's
/// cost-management revenue; the farmer can play with the numbers.
class TaxCalculationScreen extends StatefulWidget {
  const TaxCalculationScreen({super.key});

  @override
  State<TaxCalculationScreen> createState() => _TaxCalculationScreenState();
}

class _TaxCalculationScreenState extends State<TaxCalculationScreen> {
  final _revenue = TextEditingController();
  final _expenses = TextEditingController();
  String _incomeType = 'agricultural';
  bool _isSenior = false;

  TaxCalculationResult? _result;
  String? _error;
  bool _loading = true;
  bool _calculating = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _revenue.dispose();
    _expenses.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final profile = await TaxApiService.getTaxProfile();
      final summary = await TaxApiService.getTaxSummary();
      if (!mounted) return;
      setState(() {
        _incomeType = profile.incomeType;
        _isSenior = profile.isSenior;
        _revenue.text = summary.estimate.totalRevenue > 0
            ? summary.estimate.totalRevenue.toStringAsFixed(0)
            : '';
        _result = summary.estimate;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _scheduleCalc() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), _calc);
  }

  Future<void> _calc() async {
    setState(() => _calculating = true);
    try {
      final rev = double.tryParse(_revenue.text.trim());
      final exp = double.tryParse(_expenses.text.trim());
      final result = await TaxApiService.calculateTax(
        revenueBreakdown:
            rev != null ? {'Farm revenue (all sources)': rev} : null,
        expenses: exp,
        incomeType: _incomeType,
        isSenior: _isSenior,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _error = null;
          _calculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _calculating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.canPop() ? context.pop() : context.go('/farmer/tax')),
        title: const Text('Tax estimate',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _resultCard(),
                const SizedBox(height: 18),
                const Text('Your numbers',
                    style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87)),
                const SizedBox(height: 10),
                _field(_revenue, 'Total farm revenue this year (BDT)',
                    'Bird sales, egg sales, by-products…'),
                const SizedBox(height: 12),
                _field(_expenses, 'Farm expenses this year (BDT)',
                    'Feed, chicks, medicine, labour… (optional)'),
                const SizedBox(height: 12),
                _incomeTypePicker(),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _isSenior,
                  onChanged: (v) {
                    setState(() => _isSenior = v ?? false);
                    _scheduleCalc();
                  },
                  title: const Text('I am 65 or older (higher tax-free limit)',
                      style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/farmer/tax/profile').then((_) => _bootstrap()),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Land & vehicles'),
                    ),
                  ),
                ]),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ),
                const SizedBox(height: 18),
                _breakdown(),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => _scheduleCalc(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _incomeTypePicker() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Income type', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          for (final t in TaxProfile.incomeTypes)
            ChoiceChip(
              label: Text({
                'agricultural': 'Agricultural (farming)',
                'business': 'Business / trading',
                'mixed': 'Mixed',
              }[t]!),
              selected: _incomeType == t,
              onSelected: (_) {
                setState(() => _incomeType = t);
                _scheduleCalc();
              },
            ),
        ]),
        if (_incomeType == 'agricultural')
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('First BDT 200,000 of farming income is tax-free.',
                style: TextStyle(fontSize: 11, color: AppColors.secondary)),
          ),
      ]);

  Widget _resultCard() {
    final r = _result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
          color: AppColors.primary, borderRadius: AppRadius.lgAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Estimated tax for the year',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          if (_calculating)
            const SizedBox(
                height: 12,
                width: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
        ]),
        const SizedBox(height: 4),
        Text(r == null ? '—' : taka(r.total),
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 14),
        Row(children: [
          _seg('Income tax', r?.incomeTax),
          const SizedBox(width: 8),
          _seg('Land tax', r?.landTax),
          const SizedBox(width: 8),
          _seg('Vehicle tax', r?.vehicleTax),
        ]),
      ]),
    );
  }

  Widget _seg(String label, double? value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.white24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
            const SizedBox(height: 3),
            Text(value == null ? '—' : taka(value),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _breakdown() {
    final lines = _result?.breakdown ?? const [];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Material(
      type: MaterialType.card,
      color: const Color(0xFFF6FAF8),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: Color(0xFFDEEAE5)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('How this was worked out',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.black87)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: line == line.toUpperCase() && line.trim().isNotEmpty ? 11.5 : 12,
                      fontWeight: line == line.toUpperCase() && line.trim().isNotEmpty
                          ? FontWeight.w800
                          : FontWeight.w400,
                      color: line.startsWith('ESTIMATED TOTAL')
                          ? AppColors.primary
                          : Colors.black.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
