import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../data/cost_management_service.dart';
import '../../data/farmer_profile_service.dart';

const kExpenseCategories = [
  'Feed', 'Medicines', 'Labor', 'Utilities', 'Chicks',
  'Vaccines', 'Litter', 'Transport', 'Repairs',
];
const kRevenueSources = [
  'Bird Sales', 'Egg Sales', 'By-products', 'Refunds', 'Other',
];
const kPaymentMethods = ['cash', 'bkash', 'nagad', 'bank_transfer', 'card'];
const kCashoutMethods = ['bkash', 'nagad', 'bank_transfer'];

String prettyMethod(String m) => switch (m) {
      'bank_transfer' => 'Bank transfer',
      'bkash' => 'bKash',
      'nagad' => 'Nagad',
      _ => m.isEmpty ? '—' : '${m[0].toUpperCase()}${m.substring(1)}',
    };

/// Pick a payment method. Returns the selected value or null.
Future<String?> pickPaymentMethod(BuildContext context,
    {List<String> methods = kPaymentMethods, String title = 'Payment method'}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87)),
        ),
        for (final m in methods)
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined,
                color: AppColors.secondary),
            title: Text(prettyMethod(m),
                style: const TextStyle(color: Colors.black87)),
            onTap: () => Navigator.pop(ctx, m),
          ),
        const SizedBox(height: AppSpacing.sm),
      ]),
    ),
  );
}

/// Add or edit an expense. Pass [existing] (an expense json map) to edit.
/// Returns true if the sheet saved.
Future<bool?> showExpenseSheet(BuildContext context,
    {String? presetCategory, Map<String, dynamic>? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _EntrySheet(
        kind: _EntryKind.expense,
        presetCategory: presetCategory,
        existing: existing,
      ),
    ),
  );
}

Future<bool?> showRevenueSheet(BuildContext context,
    {String? presetSource, Map<String, dynamic>? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _EntrySheet(
        kind: _EntryKind.revenue,
        presetCategory: presetSource,
        existing: existing,
      ),
    ),
  );
}

enum _EntryKind { expense, revenue }

class _EntrySheet extends StatefulWidget {
  final _EntryKind kind;
  final String? presetCategory;
  final Map<String, dynamic>? existing;
  const _EntrySheet({required this.kind, this.presetCategory, this.existing});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _amount = TextEditingController();
  final _party = TextEditingController();
  final _notes = TextEditingController();
  late String _category;
  String _method = 'cash';
  String _status = 'pending';
  DateTime _date = DateTime.now();
  String? _flockId;
  String? _receiptUrl;
  List<Map<String, dynamic>> _flocks = const [];
  bool _busy = false;
  String? _error;

  bool get _isExpense => widget.kind == _EntryKind.expense;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final options = _isExpense ? kExpenseCategories : kRevenueSources;
    final e = widget.existing;
    _category = e?[_isExpense ? 'category' : 'source']?.toString() ??
        widget.presetCategory ??
        options.first;
    if (!options.contains(_category)) _category = options.first;
    if (e != null) {
      _amount.text = (e['amount'] as num?)?.toStringAsFixed(0) ?? '';
      _party.text =
          (e[_isExpense ? 'supplier_name' : 'buyer_name'] ?? '').toString();
      _notes.text = (e['description'] ?? '').toString();
      _method = (e['payment_method'] ?? 'cash').toString().isEmpty
          ? 'cash'
          : e['payment_method'].toString();
      _status = (e['payment_status'] ?? 'pending').toString();
      _flockId = e['flock_id']?.toString();
      _receiptUrl = (e['receipt_url'] ?? '').toString();
      final d = DateTime.tryParse(
          (e[_isExpense ? 'expense_date' : 'revenue_date'] ?? '').toString());
      if (d != null) _date = d;
    }
    _loadFlocks();
  }

  Future<void> _loadFlocks() async {
    try {
      final r = await FarmerProfileService.flocks(status: 'active');
      if (mounted) {
        setState(() => _flocks = List<Map<String, dynamic>>.from(
            (r['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e))));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _amount.dispose();
    _party.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() => _busy = true);
    try {
      _receiptUrl =
          await CostManagementService.uploadReceipt(file!.bytes!, file.name);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dateStr =
        _date.toIso8601String().split('T').first;
    try {
      if (_isExpense) {
        final body = {
          'category': _category,
          'amount': amount,
          'expense_date': dateStr,
          'payment_method': _method,
          'payment_status': _status,
          'supplier_name': _party.text.trim(),
          'description': _notes.text.trim(),
          if (_flockId != null) 'flock_id': _flockId,
          if (_receiptUrl != null && _receiptUrl!.isNotEmpty)
            'receipt_url': _receiptUrl,
        };
        if (_isEdit) {
          await CostManagementService.updateExpense(
              widget.existing!['id'].toString(), body);
        } else {
          await CostManagementService.addExpense(body);
        }
      } else {
        final body = {
          'source': _category,
          'amount': amount,
          'revenue_date': dateStr,
          'payment_method': _method,
          'buyer_name': _party.text.trim(),
          'description': _notes.text.trim(),
          if (_flockId != null) 'flock_id': _flockId,
          if (_receiptUrl != null && _receiptUrl!.isNotEmpty)
            'receipt_url': _receiptUrl,
        };
        if (_isEdit) {
          await CostManagementService.updateRevenue(
              widget.existing!['id'].toString(), body);
        } else {
          await CostManagementService.addRevenue(body);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _isExpense ? kExpenseCategories : kRevenueSources;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(
                _isEdit
                    ? 'Edit ${_isExpense ? 'expense' : 'revenue'}'
                    : _isExpense
                        ? 'Add expense'
                        : 'Add revenue',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black87)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: InputDecoration(
                labelText: _isExpense ? 'Category' : 'Source', filled: true),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Amount (৳)', filled: true, prefixText: '৳ '),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _party,
            decoration: InputDecoration(
                labelText: _isExpense ? 'Supplier / vendor' : 'Buyer',
                filled: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration:
                      const InputDecoration(labelText: 'Date', filled: true),
                  child: Text(_date.toIso8601String().split('T').first,
                      style: const TextStyle(color: Colors.black87)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _method,
                decoration:
                    const InputDecoration(labelText: 'Paid via', filled: true),
                items: [
                  for (final m in kPaymentMethods)
                    DropdownMenuItem(value: m, child: Text(prettyMethod(m))),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
            ),
          ]),
          if (_isExpense) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                  labelText: 'Payment status', filled: true),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'paid', child: Text('Paid')),
                DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
          ],
          if (_flocks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String?>(
              initialValue: _flockId,
              decoration: const InputDecoration(
                  labelText: 'Batch / flock (optional)', filled: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not linked')),
                for (final fl in _flocks)
                  DropdownMenuItem(
                      value: fl['id'].toString(),
                      child: Text(fl['batch_name'].toString())),
              ],
              onChanged: (v) => setState(() => _flockId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Notes', filled: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickReceipt,
            icon: Icon(_receiptUrl != null && _receiptUrl!.isNotEmpty
                ? Icons.check_circle
                : Icons.receipt_long_outlined),
            label: Text(_receiptUrl != null && _receiptUrl!.isNotEmpty
                ? 'Receipt attached'
                : 'Attach receipt'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save changes' : 'Add'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Loan request form. Returns true if submitted.
Future<bool?> showLoanRequestSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _LoanRequestSheet(),
    ),
  );
}

class _LoanRequestSheet extends StatefulWidget {
  const _LoanRequestSheet();
  @override
  State<_LoanRequestSheet> createState() => _LoanRequestSheetState();
}

class _LoanRequestSheetState extends State<_LoanRequestSheet> {
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  final _lender = TextEditingController();
  int _term = 12;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    _lender.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount you need.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CostManagementService.requestLoan({
        'loan_amount': amount,
        'purpose': _purpose.text.trim(),
        'term_months': _term,
        if (_lender.text.trim().isNotEmpty) 'lender_name': _lender.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Request a loan',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black87)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Amount needed (৳)', filled: true, prefixText: '৳ '),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _purpose,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Purpose', filled: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _lender,
            decoration: const InputDecoration(
                labelText: 'Preferred lender (optional)', filled: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            initialValue: _term,
            decoration: const InputDecoration(
                labelText: 'Repayment period', filled: true),
            items: const [
              DropdownMenuItem(value: 3, child: Text('3 months')),
              DropdownMenuItem(value: 6, child: Text('6 months')),
              DropdownMenuItem(value: 12, child: Text('12 months')),
              DropdownMenuItem(value: 24, child: Text('24 months')),
            ],
            onChanged: (v) => setState(() => _term = v ?? 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
              'Your request is reviewed by a Featherflow finance admin. '
              'You will be notified once it is approved or declined.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit request'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Cashout form. Returns true if submitted.
Future<bool?> showCashoutSheet(BuildContext context, double available) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _CashoutSheet(available: available),
    ),
  );
}

class _CashoutSheet extends StatefulWidget {
  final double available;
  const _CashoutSheet({required this.available});
  @override
  State<_CashoutSheet> createState() => _CashoutSheetState();
}

class _CashoutSheetState extends State<_CashoutSheet> {
  final _amount = TextEditingController();
  final _account = TextEditingController();
  String _method = 'bkash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a cashout amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CostManagementService.cashout(amount, _method,
          accountDetails: _account.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Cash out',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black87)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Available cash balance: ৳${widget.available.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Amount (৳)', filled: true, prefixText: '৳ '),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration:
                const InputDecoration(labelText: 'Cash out to', filled: true),
            items: [
              for (final m in kCashoutMethods)
                DropdownMenuItem(value: m, child: Text(prettyMethod(m))),
            ],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _account,
            decoration: const InputDecoration(
                labelText: 'Account / wallet number', filled: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
              'Cashouts are settled manually by the finance team in Pass 1.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Request cashout'),
            ),
          ),
        ]),
      ),
    );
  }
}
