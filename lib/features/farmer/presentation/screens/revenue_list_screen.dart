import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/cost_management_service.dart';
import '../widgets/cost_dialogs.dart';
import 'cost_management_screen.dart' show taka;

class RevenueListScreen extends StatefulWidget {
  const RevenueListScreen({super.key});

  @override
  State<RevenueListScreen> createState() => _RevenueListScreenState();
}

class _RevenueListScreenState extends State<RevenueListScreen> {
  List _rows = const [];
  List _bySource = const [];
  double _total = 0;
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
      final d = await CostManagementService.revenue();
      if (mounted) {
        setState(() {
          _rows = (d['results'] as List?) ?? [];
          _bySource = (d['by_source'] as List?) ?? [];
          _total = ((d['total'] as num?) ?? 0).toDouble();
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

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete revenue entry?'),
        content: Text('${r['source']} • ${taka((r['amount'] as num?) ?? 0)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CostManagementService.deleteRevenue(r['id'].toString());
      _load();
    } catch (e) {
      _snack(e.toString());
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
            onPressed: () => Navigator.pop(context)),
        title: const Text('Revenue',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () => context.go('/farmer')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final ok = await showRevenueSheet(context);
          if (ok == true) {
            _snack('Revenue added');
            _load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total revenue',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(taka(_total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            if (_bySource.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in _bySource)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: const BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: AppRadius.smAll),
                      child: Text(
                          '${s['source']} ${taka((s['total'] as num?) ?? 0)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ),
                ]),
              ),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = Map<String, dynamic>.from(_rows[i] as Map);
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadius.mdAll,
                                border: Border.all(
                                    color: const Color(0xFFDEEAE5))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                          r['description']
                                                      ?.toString()
                                                      .isNotEmpty ==
                                                  true
                                              ? r['description'].toString()
                                              : r['source'].toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black87)),
                                    ),
                                    Text(
                                        '+${taka((r['amount'] as num?) ?? 0)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors
                                                .secondaryContainer)),
                                  ]),
                                  Text(
                                      '${r['source']} • ${r['revenue_date']}'
                                      '${(r['buyer_name'] ?? '').toString().isNotEmpty ? ' • ${r['buyer_name']}' : ''}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54)),
                                  Row(children: [
                                    TextButton.icon(
                                        onPressed: () async {
                                          final ok = await showRevenueSheet(
                                              context,
                                              existing: r);
                                          if (ok == true) _load();
                                        },
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 16),
                                        label: const Text('Edit')),
                                    const Spacer(),
                                    IconButton(
                                        onPressed: () => _delete(r),
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18,
                                            color: AppColors.error)),
                                  ]),
                                ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
