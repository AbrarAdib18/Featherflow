import 'package:flutter/material.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_catalogue_service.dart';
import '../pharmacy_theme.dart';

class PharmacyAnalyticsScreen extends StatefulWidget {
  const PharmacyAnalyticsScreen({super.key});

  @override
  State<PharmacyAnalyticsScreen> createState() => _PharmacyAnalyticsScreenState();
}

class _PharmacyAnalyticsScreenState extends State<PharmacyAnalyticsScreen> {
  final _api = PharmacyCatalogueService.instance;
  String _period = 'daily';
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _top = [];
  Map<String, dynamic> _revenue = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.salesAnalytics(period: _period),
        _api.topProducts(),
        _api.revenueAnalytics(),
      ]);
      if (!mounted) return;
      setState(() {
        _sales = ((results[0] as Map)['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _top = results[1] as List<Map<String, dynamic>>;
        _revenue = results[2] as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhColors.bg,
      appBar: AppBar(
        backgroundColor: PhColors.appBar,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PhColors.secondary))
          : RefreshIndicator(
              onRefresh: _load,
              color: PhColors.secondary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(11),
                      decoration: phCard(borderColor: PhColors.red.withValues(alpha: .4)),
                      child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary)),
                    ),
                  _card('Revenue', [
                    _kv('Total (delivered orders)', '৳${(_revenue['total_revenue'] as num? ?? 0).toStringAsFixed(0)}'),
                    const SizedBox(height: 8),
                    const Text('By category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PhColors.textSecondary)),
                    const SizedBox(height: 4),
                    ..._bars((_revenue['by_category'] as List? ?? const [])
                        .map((e) => (e['category']?.toString() ?? '', (e['revenue'] as num? ?? 0).toDouble()))
                        .toList(), PhColors.medicines),
                    const SizedBox(height: 8),
                    const Text('By payment method', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PhColors.textSecondary)),
                    const SizedBox(height: 4),
                    ..._bars((_revenue['by_payment_method'] as List? ?? const [])
                        .map((e) => (e['method']?.toString() ?? '', (e['revenue'] as num? ?? 0).toDouble()))
                        .toList(), PhColors.delivered),
                  ]),
                  const SizedBox(height: 14),
                  _card('Sales', [
                    Row(children: [
                      _periodChip('daily', 'Daily'),
                      const SizedBox(width: 8),
                      _periodChip('monthly', 'Monthly'),
                    ]),
                    const SizedBox(height: 10),
                    if (_sales.isEmpty)
                      const Text('No delivered orders yet.', style: TextStyle(fontSize: 12, color: PhColors.grey))
                    else
                      ..._bars(_sales
                          .map((e) => (e['period']?.toString() ?? '', (e['revenue'] as num? ?? 0).toDouble()))
                          .toList(), PhColors.secondary),
                  ]),
                  const SizedBox(height: 14),
                  _card('Top products', [
                    if (_top.isEmpty)
                      const Text('No order data yet.', style: TextStyle(fontSize: 12, color: PhColors.grey))
                    else
                      ..._top.take(10).map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(
                                child: Text(p['name']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 12.5, color: PhColors.textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              phChip('${p['orders_count'] ?? 0} orders', PhColors.surface2, PhColors.textSecondary, fontSize: 10),
                              const SizedBox(width: 6),
                              phChip('${p['views_count'] ?? 0} views', PhColors.surface2, PhColors.grey, fontSize: 10),
                            ]),
                          )),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _periodChip(String value, String label) => GestureDetector(
        onTap: () {
          setState(() => _period = value);
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _period == value ? PhColors.secondary : PhColors.surface2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _period == value ? Colors.white : PhColors.textSecondary)),
        ),
      );

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: phCard(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _kv(String k, String v) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(fontSize: 12.5, color: PhColors.textSecondary)),
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: PhColors.textPrimary)),
      ]);

  List<Widget> _bars(List<(String, double)> data, Color color) {
    if (data.isEmpty) {
      return const [Text('No data.', style: TextStyle(fontSize: 12, color: PhColors.grey))];
    }
    final max = data.map((e) => e.$2).fold<double>(1, (a, b) => b > a ? b : a);
    return data.map((e) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 74,
            child: Text(prettyCategory(e.$1),
                style: const TextStyle(fontSize: 11, color: PhColors.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (e.$2 / max).clamp(0.02, 1.0),
                minHeight: 12,
                backgroundColor: PhColors.surface2,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('৳${e.$2.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
        ]),
      );
    }).toList();
  }
}
