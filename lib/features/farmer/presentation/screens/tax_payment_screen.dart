import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/tax_api_service.dart';
import '../../data/models/tax_payment.dart';
import 'cost_management_screen.dart' show taka;

/// Record a tax payment (challan) and see the payment history.
class TaxPaymentScreen extends StatefulWidget {
  const TaxPaymentScreen({super.key});

  @override
  State<TaxPaymentScreen> createState() => _TaxPaymentScreenState();
}

class _TaxPaymentScreenState extends State<TaxPaymentScreen> {
  List<TaxPayment> _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await TaxApiService.getTaxPayments();
      if (mounted) {
        setState(() {
          _payments = rows;
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

  Future<void> _record() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RecordPaymentSheet(),
    );
    if (ok == true) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Tax payment recorded')));
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
        title: const Text('Tax payments',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _record,
        icon: const Icon(Icons.add),
        label: const Text('Record payment'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _payments.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No tax payments recorded yet.\nTap "Record payment" after you pay land, '
                          'vehicle or income tax.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: _payments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _card(_payments[i]),
                      ),
                    ),
    );
  }

  Widget _card(TaxPayment p) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: const Color(0xFFDEEAE5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p.taxTypeLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
            ),
            Text('-${taka(p.amount)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.error)),
          ]),
          const SizedBox(height: 2),
          Text(
              '${p.paymentDate}'
              '${p.referenceNumber.isNotEmpty ? '  •  ref ${p.referenceNumber}' : ''}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          if (p.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(p.notes, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          if (p.receiptUrl.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.attachment, size: 14, color: AppColors.secondary),
                SizedBox(width: 4),
                Text('Receipt attached',
                    style: TextStyle(fontSize: 11, color: AppColors.secondary)),
              ]),
            ),
        ]),
      );
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet();

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  String _type = 'land';
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _receiptUrl = '';
  bool _logAsExpense = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    setState(() => _uploading = true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final file = res?.files.firstOrNull;
      if (file?.bytes != null) {
        _receiptUrl = await TaxApiService.uploadReceipt(file!.bytes!, file.name);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await TaxApiService.recordTaxPayment(TaxPayment.toCreateJson(
        taxType: _type,
        amount: amount,
        paymentDate:
            '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        referenceNumber: _ref.text.trim(),
        notes: _notes.text.trim(),
        receiptUrl: _receiptUrl,
        logAsExpense: _logAsExpense,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Center(
            child: Text('Record a tax payment',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Tax type', isDense: true, border: OutlineInputBorder()),
            items: [
              for (final t in TaxPayment.types)
                DropdownMenuItem(value: t, child: Text(TaxPayment.typeLabel(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
                labelText: 'Amount paid (BDT)', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(DateTime.now().year - 5),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Payment date', isDense: true, border: OutlineInputBorder()),
              child: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ref,
            decoration: const InputDecoration(
                labelText: 'Challan / reference number (optional)',
                isDense: true,
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Notes (optional)', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickReceipt,
            icon: _uploading
                ? const SizedBox(
                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_receiptUrl.isEmpty ? Icons.upload_file : Icons.check_circle,
                    color: _receiptUrl.isEmpty ? null : AppColors.secondary),
            label: Text(_receiptUrl.isEmpty ? 'Attach receipt photo' : 'Receipt attached'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _logAsExpense,
            onChanged: (v) => setState(() => _logAsExpense = v ?? true),
            title: const Text('Also add to Cost Management as a "Tax" expense',
                style: TextStyle(fontSize: 12.5)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(48)),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save payment'),
          ),
        ]),
      ),
    );
  }
}
