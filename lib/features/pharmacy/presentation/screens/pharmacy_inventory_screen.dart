import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

class PharmacyInventoryScreen extends StatefulWidget {
  const PharmacyInventoryScreen({super.key});

  @override
  State<PharmacyInventoryScreen> createState() => _PharmacyInventoryScreenState();
}

class _PharmacyInventoryScreenState extends State<PharmacyInventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: const Text('Inventory',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Bulk CSV upload',
                icon: const Icon(Icons.upload_file, size: 20),
                onPressed: () => _bulkUpload(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: PhColors.secondary,
              labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Low Stock'),
                Tab(text: 'Expiring'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(s: s),
              _LowStockTab(s: s),
              _ExpiringTab(s: s),
            ],
          ),
        );
      },
    );
  }

  Future<void> _bulkUpload(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    try {
      final data = await PharmacySession.instance.bulkUpload(file!.bytes!, file.name);
      final created = data['created'] ?? 0;
      final errors = (data['errors'] as List?)?.length ?? 0;
      if (context.mounted) {
        showPharmacyNotice(
          context,
          'Imported $created medicine(s)${errors > 0 ? ', $errors row(s) skipped' : ''}.',
          errors > 0 ? PhColors.amber : PhColors.green,
          Icons.upload_file,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showPharmacyNotice(context, e.toString(), PhColors.red, Icons.error_outline);
      }
    }
  }
}

class _OverviewTab extends StatelessWidget {
  final PharmacySession s;
  const _OverviewTab({required this.s});

  @override
  Widget build(BuildContext context) {
    final sm = s.summary;
    return RefreshIndicator(
      onRefresh: s.refresh,
      color: PhColors.secondary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _row('Active products', '${sm.totalProducts}', Icons.medication_outlined, PhColors.medicines),
          _row('Stock value', '৳${sm.stockValue.toStringAsFixed(0)}', Icons.savings_outlined, PhColors.delivered),
          _row('Low stock (<10)', '${sm.lowStockCount}', Icons.trending_down, PhColors.lowStock),
          _row('Out of stock', '${sm.outOfStockCount}', Icons.remove_shopping_cart_outlined, PhColors.outOfStock),
          _row('Expiring within 60d', '${sm.expiringSoonCount}', Icons.event_busy_outlined, PhColors.amber),
          _row('Critical (<7d)', '${sm.criticalExpiryCount}', Icons.warning_amber_rounded, PhColors.red),
          _row('Pending admin approval', '${sm.pendingApprovalCount}', Icons.hourglass_bottom, PhColors.pending),
        ],
      ),
    );
  }

  Widget _row(String label, String value, IconData icon, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: phCard(),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: PhColors.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: PhColors.textPrimary)),
        ]),
      );
}

class _LowStockTab extends StatelessWidget {
  final PharmacySession s;
  const _LowStockTab({required this.s});

  @override
  Widget build(BuildContext context) {
    final low = s.lowStockProducts;
    if (low.isEmpty) return const _EmptyTab(icon: Icons.check_circle_outline, text: 'All medicines are well stocked.');
    return RefreshIndicator(
      onRefresh: s.refresh,
      color: PhColors.secondary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: low.length,
        itemBuilder: (_, i) {
          final m = low[i];
          final out = m.stockStatus == MedStock.outOfStock;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: phCard(borderColor: (out ? PhColors.outOfStock : PhColors.lowStock).withValues(alpha: .35)),
            child: Row(children: [
              phChip(out ? 'OUT' : 'LOW',
                  out ? PhColors.outOfStockLight : PhColors.lowStockLight,
                  out ? PhColors.outOfStock : PhColors.lowStock, fontSize: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PhColors.textPrimary)),
                  Text('${m.stockQuantity} ${m.unit} left', style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary)),
                ]),
              ),
              OutlinedButton(
                onPressed: () => _restock(context, m),
                style: OutlinedButton.styleFrom(
                    foregroundColor: PhColors.secondary,
                    side: const BorderSide(color: PhColors.secondary),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                child: const Text('Restock', style: TextStyle(fontSize: 12)),
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _restock(BuildContext context, Medicine m) async {
    final ctrl = TextEditingController(text: '50');
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        title: Text('Restock ${m.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: phFieldText,
          decoration: phInput('New stock quantity', Icons.inventory_2_outlined),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PhColors.secondary),
            onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text.trim())),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (qty == null || qty < 0) return;
    try {
      await PharmacySession.instance.setStock(m.id, qty);
      if (context.mounted) {
        showPharmacyNotice(context, 'Stock updated.', PhColors.green, Icons.check_circle_outline);
      }
    } catch (e) {
      if (context.mounted) showPharmacyNotice(context, e.toString(), PhColors.red, Icons.error_outline);
    }
  }
}

class _ExpiringTab extends StatelessWidget {
  final PharmacySession s;
  const _ExpiringTab({required this.s});

  @override
  Widget build(BuildContext context) {
    final groups = s.expiryAlerts;
    final all = [
      ...?groups['critical'],
      ...?groups['warning'],
      ...?groups['info'],
    ];
    if (all.isEmpty) {
      return const _EmptyTab(icon: Icons.event_available_outlined, text: 'Nothing expiring in the next 60 days.');
    }
    return RefreshIndicator(
      onRefresh: s.refresh,
      color: PhColors.secondary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await s.acknowledgeAlerts(all.map((a) => a.alertId).toList());
                if (context.mounted) {
                  showPharmacyNotice(context, 'Alerts acknowledged.', PhColors.grey, Icons.done_all);
                }
              },
              icon: const Icon(Icons.done_all, size: 16),
              label: const Text('Acknowledge all'),
            ),
          ),
          for (final level in const ['critical', 'warning', 'info'])
            if ((groups[level] ?? const []).isNotEmpty) ...[
              _levelHeader(level, groups[level]!.length),
              ...groups[level]!.map((a) => _AlertRow(alert: a, level: level)),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _levelHeader(String level, int count) {
    final (color, label) = switch (level) {
      'critical' => (PhColors.red, 'Critical — under 7 days'),
      'warning' => (PhColors.amber, 'Warning — under 30 days'),
      _ => (PhColors.lowStock, 'Info — under 60 days'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('$label  ($count)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final ExpiryAlert alert;
  final String level;
  const _AlertRow({required this.alert, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      'critical' => PhColors.red,
      'warning' => PhColors.amber,
      _ => PhColors.lowStock,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: phCard(borderColor: color.withValues(alpha: .3)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.medicineName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PhColors.textPrimary)),
            Text(
                '${alert.stockQuantity} in stock'
                '${alert.batchNumber.isNotEmpty ? ' · batch ${alert.batchNumber}' : ''}',
                style: const TextStyle(fontSize: 11, color: PhColors.textSecondary)),
          ]),
        ),
        phChip('${alert.expiresInDays}d', color.withValues(alpha: .12), color),
        if (alert.isAcknowledged)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.check, size: 14, color: PhColors.grey),
          ),
      ]),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyTab({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 46, color: PhColors.grey.withValues(alpha: .4)),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 13, color: PhColors.textSecondary)),
        ]),
      );
}
