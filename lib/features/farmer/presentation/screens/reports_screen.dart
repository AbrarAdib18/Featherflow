import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:featherflow/core/theme/theme.dart';
import '../../data/cost_management_service.dart';

const _types = {
  'profit_loss': 'Profit & Loss',
  'expense': 'Expense report',
  'revenue': 'Revenue report',
  'batch': 'Batch report',
  'cash_flow': 'Cash flow',
};

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _type = 'profit_loss';
  String _period = 'lifetime';
  bool _busy = false;
  String? _error;

  Future<void> _generate(String export) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await CostManagementService.report(
          type: _type, period: _period, export: export);
      if (!mounted) return;
      if (res.isPdf) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(_types[_type]!),
                leading: IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close)),
              ),
              body: PdfPreview(
                build: (_) async => res.bytes,
                pdfFileName: '${_type}_report.pdf',
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
              ),
            ),
          ),
        );
      } else {
        final text = String.fromCharCodes(res.bytes);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${_types[_type]} (CSV)'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: SelectableText(text,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
        title: const Text('Reports',
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Report type',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _types.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _type == e.key,
                onSelected: (_) => setState(() => _type = e.key),
              ),
          ]),
          const SizedBox(height: 20),
          const Text('Period',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in const ['lifetime', 'monthly', 'yearly'])
              ChoiceChip(
                label: Text(p[0].toUpperCase() + p.substring(1)),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ]),
          const SizedBox(height: 28),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _generate('csv'),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('CSV'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _generate('pdf'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                icon: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          const Text(
              'The PDF preview lets you print or share. CSV opens for '
              'accountants and loan applications.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}
