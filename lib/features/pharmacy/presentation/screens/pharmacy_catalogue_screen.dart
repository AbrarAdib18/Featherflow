import 'package:flutter/material.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import '../widgets/add_medicine_dialog.dart';

class PharmacyCatalogueScreen extends StatefulWidget {
  const PharmacyCatalogueScreen({super.key});

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
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: const Text('Catalogue',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              TextButton.icon(
                onPressed: () => _openDialog(context, null),
                icon: const Icon(Icons.add, color: PhColors.secondary, size: 18),
                label: const Text('Add',
                    style: TextStyle(color: PhColors.secondary, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: meds.length,
                              itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MedCard(
                                  m: meds[i],
                                  onTap: () => _openDialog(context, meds[i]),
                                  onDelete: () => _confirmDelete(context, meds[i]),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
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

class _MedCard extends StatelessWidget {
  final Medicine m;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _MedCard({required this.m, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final (stockBg, stockFg, stockLabel) = switch (m.stockStatus) {
      MedStock.inStock => (PhColors.inStockLight, PhColors.inStock, 'In stock'),
      MedStock.lowStock => (PhColors.lowStockLight, PhColors.lowStock, 'Low stock'),
      MedStock.outOfStock => (PhColors.outOfStockLight, PhColors.outOfStock, 'Out of stock'),
    };
    final (apprBg, apprFg, apprLabel) = switch (m.approvalStatus) {
      'approved' => (PhColors.deliveredLight, PhColors.delivered, 'Approved'),
      'rejected' => (PhColors.cancelledLight, PhColors.cancelled, 'Rejected'),
      _ => (PhColors.pendingLight, PhColors.pending, 'Pending approval'),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: phCard(
            borderColor: m.stockStatus != MedStock.inStock ? stockFg.withValues(alpha: .3) : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (m.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(m.images.first, width: 40, height: 40, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40)),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
                  Text('${m.manufacturer}${m.packSize.isNotEmpty ? ' · ${m.packSize}' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary)),
                ]),
              ),
              Text('৳${m.price.toStringAsFixed(0)}/${m.unit}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              phChip(prettyCategory(m.category), PhColors.medicinesLight, PhColors.medicines, fontSize: 10),
              phChip('$stockLabel · ${m.stockQuantity}', stockBg, stockFg, fontSize: 10),
              phChip(apprLabel, apprBg, apprFg, fontSize: 10),
              if (m.prescriptionRequired)
                phChip('Rx', PhColors.pendingLight, PhColors.amber, fontSize: 10),
              if (m.coldChainRequired)
                phChip('🧊 Cold chain', PhColors.processingLight, PhColors.processing, fontSize: 10),
              if (m.expiryAlertLevel != null)
                phChip('Expires in ${m.expiresInDays}d',
                    m.expiryAlertLevel == 'critical' ? PhColors.outOfStockLight : PhColors.lowStockLight,
                    m.expiryAlertLevel == 'critical' ? PhColors.outOfStock : PhColors.lowStock,
                    fontSize: 10),
            ]),
            if (m.approvalStatus == 'rejected' && m.approvalRejectedReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reason: ${m.approvalRejectedReason}',
                  style: const TextStyle(fontSize: 11, color: PhColors.cancelled)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              _StockStepper(m: m),
              const Spacer(),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: PhColors.grey),
                visualDensity: VisualDensity.compact,
              ),
            ]),
          ],
        ),
      ),
    );
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
      _btn(Icons.remove, m.stockQuantity > 0 ? () => _adjust(context, -1) : null),
      Container(
        width: 40,
        alignment: Alignment.center,
        child: Text('${m.stockQuantity}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
      ),
      _btn(Icons.add, () => _adjust(context, 1)),
    ]);
  }

  Widget _btn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: onTap != null ? PhColors.secondary.withValues(alpha: .1) : PhColors.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: onTap != null ? PhColors.secondary.withValues(alpha: .3) : PhColors.cardBorder),
          ),
          child: Icon(icon, size: 15, color: onTap != null ? PhColors.secondary : PhColors.grey),
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
