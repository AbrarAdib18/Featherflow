import 'package:flutter/material.dart';

import '../../../../core/widgets/product_card.dart';
import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import '../widgets/add_medicine_dialog.dart';

class PharmacyCatalogueScreen extends StatefulWidget {
  /// True when shown as a tab inside [PharmacyDashboardScreen]'s single
  /// AppBar+TabBar shell — no Scaffold/AppBar of its own then (the shell
  /// already provides one). False when reached via the standalone
  /// `/pharmacy/catalogue` route, which gets its own AppBar + back button
  /// since there's no shell to fall back on.
  final bool embedded;
  const PharmacyCatalogueScreen({super.key, this.embedded = false});

  @override
  State<PharmacyCatalogueScreen> createState() => _PharmacyCatalogueScreenState();
}

class _PharmacyCatalogueScreenState extends State<PharmacyCatalogueScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _category;
  bool _prescriptionOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        var meds = s.filteredMedicines(category: _category, query: _query);
        if (_prescriptionOnly) {
          meds = meds.where((m) => m.prescriptionRequired).toList();
        }
        final body = _body(context, s, meds);
        if (widget.embedded) return body;
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            leading: phBackLeading(context, embedded: false),
            title: const Text('Catalogue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [_addButton(context)],
          ),
          body: body,
        );
      },
    );
  }

  Widget _addButton(BuildContext context) => TextButton.icon(
        onPressed: () => _openDialog(context, null),
        icon: const Icon(Icons.add, color: PhColors.secondary, size: 18),
        label: const Text('Add',
            style: TextStyle(color: PhColors.secondary, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _body(BuildContext context, PharmacySession s, List<Medicine> meds) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14, color: PhColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search name, generic, manufacturer…',
                  hintStyle: const TextStyle(color: PhColors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: PhColors.grey, size: 20),
                  filled: true,
                  fillColor: PhColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            // Embedded (tab) mode has no AppBar action slot of its own, so the
            // Add button moves inline next to search instead of disappearing.
            if (widget.embedded) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openDialog(context, null),
                style: FilledButton.styleFrom(backgroundColor: PhColors.secondary, padding: const EdgeInsets.symmetric(horizontal: 12)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            _chip('All', _category == null, () => setState(() => _category = null)),
            const SizedBox(width: 8),
            _chip('Rx only', _prescriptionOnly,
                () => setState(() => _prescriptionOnly = !_prescriptionOnly),
                color: PhColors.amber),
            const SizedBox(width: 8),
            for (final c in kMedicineCategories) ...[
              _chip(prettyCategory(c), _category == c,
                  () => setState(() => _category = _category == c ? null : c)),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        Expanded(
          child: !s.ready
              ? const Center(child: CircularProgressIndicator(color: PhColors.secondary))
              : meds.isEmpty
                  ? const _Empty()
                  : RefreshIndicator(
                      onRefresh: s.refresh,
                      color: PhColors.secondary,
                      child: ResponsiveProductGrid(
                        maxCardWidth: 210,
                        // 300 clipped real content (image + delivery text +
                        // 2-line name + subtitle + status chips, which can
                        // wrap to 2 rows + price row + unit/stock lines +
                        // stock stepper + button) — the next row then bled
                        // into the cut-off card, reading as overlapping divs.
                        cardHeight: 372,
                        children: [
                          for (final m in meds)
                            ProductCard(
                              imageUrl: m.images.isNotEmpty ? m.images.first : null,
                              fallbackIcon: Icons.medication_outlined,
                              discountLabel: (m.previousPrice != null && m.previousPrice! > m.price)
                                  ? '৳${(m.previousPrice! - m.price).round()} OFF'
                                  : null,
                              topSeller: m.isTopSeller,
                              deliveryText: 'Delivery 1–2 hours',
                              name: m.name,
                              subtitle: m.genericName.isNotEmpty ? m.genericName : m.manufacturer,
                              price: m.price,
                              previousPrice: m.previousPrice,
                              unit: m.unit,
                              minQuantity: m.minOrderQuantity,
                              stockLabel: _stockLabel(m),
                              inStock: m.stockStatus != MedStock.outOfStock,
                              extra: _statusChips(m),
                              quantitySelector: _StockStepper(m: m),
                              actionLabel: 'Edit',
                              actionColor: PhColors.secondary,
                              onAction: () => _openDialog(context, m),
                              onTap: () => _openDialog(context, m),
                              trailingActions: [
                                IconButton(
                                  onPressed: () => _confirmDelete(context, m),
                                  icon: const Icon(Icons.delete_outline, size: 18, color: PhColors.grey),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Retire medicine',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  String _stockLabel(Medicine m) => switch (m.stockStatus) {
        MedStock.inStock => 'In stock · ${m.stockQuantity}',
        MedStock.lowStock => 'Low stock · ${m.stockQuantity}',
        MedStock.outOfStock => 'Out of stock',
      };

  Widget _statusChips(Medicine m) {
    final (apprBg, apprFg, apprLabel) = switch (m.approvalStatus) {
      'approved' => (PhColors.deliveredLight, PhColors.delivered, 'Approved'),
      'rejected' => (PhColors.cancelledLight, PhColors.cancelled, 'Rejected'),
      _ => (PhColors.pendingLight, PhColors.pending, 'Pending'),
    };
    return Wrap(spacing: 4, runSpacing: 4, children: [
      phChip(apprLabel, apprBg, apprFg, fontSize: 9),
      if (m.prescriptionRequired) phChip('Rx', PhColors.pendingLight, PhColors.amber, fontSize: 9),
      if (m.coldChainRequired) phChip('🧊', PhColors.processingLight, PhColors.processing, fontSize: 9),
      if (m.expiryAlertLevel != null)
        phChip('${m.expiresInDays}d left',
            m.expiryAlertLevel == 'critical' ? PhColors.outOfStockLight : PhColors.lowStockLight,
            m.expiryAlertLevel == 'critical' ? PhColors.outOfStock : PhColors.lowStock,
            fontSize: 9),
    ]);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color color = PhColors.primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : PhColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : PhColors.cardBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : PhColors.textSecondary)),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context, Medicine? existing) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: PhColors.primary.withValues(alpha: .55),
      builder: (_) => AddMedicineDialog(existing: existing),
    );
    if (ok == true && context.mounted) {
      showPharmacyNotice(
        context,
        existing != null ? 'Medicine updated.' : 'Medicine added to your catalogue.',
        PhColors.green,
        Icons.check_circle_outline,
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Medicine m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        title: const Text('Retire medicine?'),
        content: Text('${m.name} will be hidden from farmers. Existing orders are unaffected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Retire', style: TextStyle(color: PhColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PharmacySession.instance.deleteMedicine(m.id);
      if (context.mounted) {
        showPharmacyNotice(context, 'Medicine retired.', PhColors.grey, Icons.inventory_2_outlined);
      }
    } catch (e) {
      if (context.mounted) {
        showPharmacyNotice(context, e.toString(), PhColors.red, Icons.error_outline);
      }
    }
  }
}

class _StockStepper extends StatelessWidget {
  final Medicine m;
  const _StockStepper({required this.m});

  Future<void> _adjust(BuildContext context, int delta) async {
    try {
      await PharmacySession.instance.adjustStock(m.id, delta);
    } catch (e) {
      if (context.mounted) {
        showPharmacyNotice(context, e.toString(), PhColors.red, Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(context, Icons.remove, m.stockQuantity > 0 ? () => _adjust(context, -1) : null),
      Container(
        width: 32,
        alignment: Alignment.center,
        child: Text('${m.stockQuantity}',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
      ),
      _btn(context, Icons.add, () => _adjust(context, 1)),
    ]);
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: onTap != null ? PhColors.secondary.withValues(alpha: .1) : PhColors.surface2,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: onTap != null ? PhColors.secondary.withValues(alpha: .3) : PhColors.cardBorder),
          ),
          child: Icon(icon, size: 12, color: onTap != null ? PhColors.secondary : PhColors.grey),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.medication_outlined, size: 50, color: PhColors.grey.withValues(alpha: .4)),
          const SizedBox(height: 14),
          const Text('No medicines yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PhColors.textSecondary)),
          const SizedBox(height: 6),
          const Text('Tap Add to list your first medicine.',
              style: TextStyle(fontSize: 12.5, color: PhColors.grey)),
        ]),
      );
}
