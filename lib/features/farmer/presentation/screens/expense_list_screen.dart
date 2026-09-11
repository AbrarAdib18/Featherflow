import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/cost_management_service.dart';
import '../widgets/cost_dialogs.dart';
import 'cost_management_screen.dart' show taka;

class ExpenseListScreen extends StatefulWidget {
  final String? category;
  const ExpenseListScreen({super.key, this.category});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  List _rows = const [];
  double _total = 0;
  String? _error;
  bool _loading = true;
  String _status = 'all';
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
      final d = await CostManagementService.expenses(
        category: widget.category,
        status: _status == 'all' ? null : _status,
      );
      if (mounted) {
        setState(() {
          _rows = (d['results'] as List?) ?? [];
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

  Future<void> _pay(Map<String, dynamic> e) async {
    final method = await pickPaymentMethod(context);
    if (method == null) return;
    try {
      await CostManagementService.payExpense(e['id'].toString(), method);
      _snack('Marked paid');
      _load();
    } catch (err) {
      _snack(err.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('${e['category']} • ${taka((e['amount'] as num?) ?? 0)}'),
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
      await CostManagementService.deleteExpense(e['id'].toString());
      _load();
    } catch (err) {
      _snack(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.category ?? 'All';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: Text('$title expenses',
            style: const TextStyle(
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
          final ok =
              await showExpenseSheet(context, presetCategory: widget.category);
          if (ok == true) {
            _snack('Expense added');
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
            const Text('Total spent',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(taka(_total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            for (final s in const ['all', 'pending', 'paid', 'overdue'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s[0].toUpperCase() + s.substring(1)),
                  selected: _status == s,
                  onSelected: (_) {
                    setState(() => _status = s);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _rows.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorStateView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final e = Map<String, dynamic>.from(_rows[i] as Map);
                          final status = e['payment_status'].toString();
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadius.mdAll,
                                border: Border.all(
                                    color: const Color(0xFFDEEAE5))),
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                          e['description']
                                                      ?.toString()
                                                      .isNotEmpty ==
                                                  true
                                              ? e['description'].toString()
                                              : (e['supplier_name']
                                                          ?.toString()
                                                          .isNotEmpty ==
                                                      true
                                                  ? e['supplier_name']
                                                      .toString()
                                                  : e['category'].toString()),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black87)),
                                    ),
                                    Text(taka((e['amount'] as num?) ?? 0),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primary)),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${e['category']} • ${e['expense_date']} • ${status.toUpperCase()}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: status == 'paid'
                                              ? AppColors.secondaryContainer
                                              : status == 'overdue'
                                                  ? AppColors.error
                                                  : Colors.orange)),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    if (status != 'paid')
                                      TextButton.icon(
                                          onPressed: () => _pay(e),
                                          icon: const Icon(Icons.payments_outlined,
                                              size: 16),
                                          label: const Text('Pay')),
                                    TextButton.icon(
                                        onPressed: () async {
                                          final ok = await showExpenseSheet(
                                              context,
                                              existing: e);
                                          if (ok == true) _load();
                                        },
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 16),
                                        label: const Text('Edit')),
                                    const Spacer(),
                                    IconButton(
                                        onPressed: () => _delete(e),
                                        icon: const Icon(
                                            Icons.delete_outline,
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
