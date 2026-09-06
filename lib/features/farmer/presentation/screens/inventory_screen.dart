import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/cost_management_service.dart';
import 'cost_management_screen.dart' show taka;

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _batches;
  String? _error;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        CostManagementService.inventory(),
        CostManagementService.batches(),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0];
          _batches = results[1];
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Inventory & Batches',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
                icon: const Icon(Icons.home, color: Colors.white),
                onPressed: () => context.go('/farmer')),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.secondary,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Stock'), Tab(text: 'Batch cost')],
          ),
        ),
        body: _data == null
            ? Center(
                child: _error != null
                    ? Text(_error!)
                    : const CircularProgressIndicator())
            : TabBarView(children: [_stockTab(), _batchTab()]),
      ),
    );
  }

  Widget _stockTab() {
    final feed = (_data!['feed'] as List?) ?? [];
    final other = (_data!['other'] as Map?) ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Feed stock',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: Colors.black87)),
          const SizedBox(height: 8),
          if (feed.isEmpty)
            const Text('No feed stock recorded. Add stock in Feed Management.',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
          for (final raw in feed)
            Builder(builder: (_) {
              final s = Map<String, dynamic>.from(raw as Map);
              final st = s['status'].toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: const Color(0xFFDEEAE5))),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'].toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87)),
                          Text(
                              '${(s['quantity'] as num?)?.toStringAsFixed(0)} ${s['unit']} • value ${taka((s['value'] as num?) ?? 0)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54)),
                        ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: (st == 'out'
                                ? AppColors.error
                                : st == 'low'
                                    ? Colors.orange
                                    : AppColors.secondaryContainer)
                            .withValues(alpha: 0.12),
                        borderRadius: AppRadius.smAll),
                    child: Text(st.toUpperCase(),
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: st == 'out'
                                ? AppColors.error
                                : st == 'low'
                                    ? Colors.orange
                                    : AppColors.secondaryContainer)),
                  ),
                ]),
              );
            }),
          const SizedBox(height: 16),
          const Text('Other consumables (spend)',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: Colors.black87)),
          const SizedBox(height: 4),
          const Text('Quantity tracking for these arrives in a later pass.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 8),
          for (final entry in other.entries)
            Builder(builder: (_) {
              final v = Map<String, dynamic>.from(entry.value as Map);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                    entry.key[0].toUpperCase() + entry.key.substring(1),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.black87)),
                subtitle: Text('${v['purchases']} purchases',
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(taka((v['total_spent'] as num?) ?? 0),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.black87)),
              );
            }),
        ],
      ),
    );
  }

  Widget _batchTab() {
    final rows = (_batches?['results'] as List?) ?? [];
    final unlinked = (_batches?['unlinked'] as Map?) ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                  child: Text(
                      'No batches yet. Add a flock in your farm profile,\nthen link expenses and revenue to it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54))),
            ),
          for (final raw in rows)
            Builder(builder: (_) {
              final b = Map<String, dynamic>.from(raw as Map);
              final profit = (b['net_profit'] as num?) ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: const Color(0xFFDEEAE5))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(b['batch_name'].toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87)),
                        ),
                        Text('${b['current_quantity']} birds',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ]),
                      if ((b['breed'] ?? '').toString().isNotEmpty)
                        Text(b['breed'].toString(),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _kv('Expense',
                            taka((b['total_expense'] as num?) ?? 0)),
                        _kv('Revenue',
                            taka((b['total_revenue'] as num?) ?? 0)),
                        _kv('Net',
                            taka(profit),
                            color: profit >= 0
                                ? AppColors.secondaryContainer
                                : AppColors.error),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                          'Cost per bird ৳${((b['cost_per_bird'] as num?) ?? 0).toStringAsFixed(2)} • mortality ${b['mortality']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    ]),
              );
            }),
          if ((unlinked['total_expense'] ?? 0) != 0 ||
              (unlinked['total_revenue'] ?? 0) != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Not linked to a batch: expense ${taka((unlinked['total_expense'] as num?) ?? 0)}, revenue ${taka((unlinked['total_revenue'] as num?) ?? 0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 10, color: Colors.black45)),
          Text(v,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color ?? Colors.black87)),
        ]),
      );
}
