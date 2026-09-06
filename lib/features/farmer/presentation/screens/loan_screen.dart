import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/cost_management_service.dart';
import '../widgets/cost_dialogs.dart';
import 'cost_management_screen.dart' show taka;

class LoanScreen extends StatefulWidget {
  const LoanScreen({super.key});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> {
  List _loans = const [];
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
      final d = await CostManagementService.loans();
      if (mounted) {
        setState(() {
          _loans = (d['results'] as List?) ?? [];
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

  Future<void> _repay(Map<String, dynamic> l) async {
    final ctrl = TextEditingController(
        text: ((l['next_payment_amount'] as num?) ?? 0) > 0
            ? ((l['next_payment_amount'] as num).toStringAsFixed(0))
            : '');
    String method = 'cash';
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repay loan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Amount (৳)', prefixText: '৳ '),
          ),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (_, setLocal) => DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Paid via'),
              items: [
                for (final m in kPaymentMethods)
                  DropdownMenuItem(value: m, child: Text(prettyMethod(m))),
              ],
              onChanged: (v) => setLocal(() => method = v ?? method),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(ctrl.text.trim())),
              child: const Text('Repay')),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      await CostManagementService.repayLoan(l['id'].toString(), amount, method);
      _snack('Repayment recorded');
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
        title: const Text('Loans',
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
          final ok = await showLoanRequestSheet(context);
          if (ok == true) {
            _snack('Loan request submitted');
            _load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Request loan'),
      ),
      body: _loans.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _loans.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(
                              child: Text('No loans yet.',
                                  style: TextStyle(color: Colors.black54))),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          itemCount: _loans.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final l =
                                Map<String, dynamic>.from(_loans[i] as Map);
                            return _LoanCard(loan: l, onRepay: () => _repay(l));
                          },
                        ),
                ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  final Map<String, dynamic> loan;
  final VoidCallback onRepay;
  const _LoanCard({required this.loan, required this.onRepay});

  @override
  Widget build(BuildContext context) {
    final status = loan['status'].toString();
    final installments = (loan['installments'] as List?) ?? [];
    final c = switch (status) {
      'active' => AppColors.secondaryContainer,
      'pending' => Colors.orange,
      'overdue' => AppColors.error,
      'rejected' => AppColors.error,
      _ => Colors.black45,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: const Color(0xFFDEEAE5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(loan['lender_name'].toString(),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.black87)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: AppRadius.smAll),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: c)),
          ),
        ]),
        if ((loan['purpose'] ?? '').toString().isNotEmpty)
          Text(loan['purpose'].toString(),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Row(children: [
          _kv('Principal', taka((loan['loan_amount'] as num?) ?? 0)),
          _kv('Balance', taka((loan['remaining_balance'] as num?) ?? 0)),
          _kv('Rate', '${(loan['interest_rate'] as num?) ?? 0}%'),
        ]),
        if ((loan['next_payment_date'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
              'Next payment ${taka((loan['next_payment_amount'] as num?) ?? 0)} on ${loan['next_payment_date']}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
        if (((loan['overdue_amount'] as num?) ?? 0) > 0)
          Text('Overdue ${taka((loan['overdue_amount'] as num?) ?? 0)}',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700)),
        if (status == 'rejected' &&
            (loan['rejection_reason'] ?? '').toString().isNotEmpty)
          Text('Reason: ${loan['rejection_reason']}',
              style: const TextStyle(fontSize: 12, color: AppColors.error)),
        if (installments.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Schedule',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54)),
          for (final raw in installments.take(6))
            Builder(builder: (_) {
              final it = Map<String, dynamic>.from(raw as Map);
              final paid = it['status'] == 'paid';
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(paid ? Icons.check_circle : Icons.circle_outlined,
                      size: 13,
                      color: paid ? AppColors.secondaryContainer : Colors.black26),
                  const SizedBox(width: 6),
                  Text('${it['due_date']}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                  const Spacer(),
                  Text(taka((it['amount'] as num?) ?? 0),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ]),
              );
            }),
        ],
        if (status == 'active' || status == 'overdue') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRepay,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Repay'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k,
              style: const TextStyle(fontSize: 10, color: Colors.black45)),
          Text(v,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
        ]),
      );
}
