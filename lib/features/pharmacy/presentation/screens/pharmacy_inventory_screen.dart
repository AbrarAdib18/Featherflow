import 'package:flutter/material.dart';
import '../../data/models/pharmacy_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import '../widgets/add_medicine_dialog.dart';

class PharmacyInventoryScreen extends StatefulWidget {
  const PharmacyInventoryScreen({super.key});

  @override
  State<PharmacyInventoryScreen> createState() =>
      _PharmacyInventoryScreenState();
}

class _PharmacyInventoryScreenState extends State<PharmacyInventoryScreen> {
  ProductCategory? _selectedCategory;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

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
        final products = PharmacySession.instance.filteredProducts(
          category: _selectedCategory,
          query: _query,
        );

        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: const Text('Inventory',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => _showAddProductDialog(context),
                  icon: const Icon(Icons.add,
                      color: PhColors.secondary, size: 18),
                  label: const Text('Add',
                      style: TextStyle(
                          color: PhColors.secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(
                      fontSize: 14, color: PhColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search products or manufacturer…',
                    hintStyle:
                        const TextStyle(color: PhColors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: PhColors.grey, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: PhColors.grey, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: PhColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Category filter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    _CategoryChip(
                      label: 'All',
                      selected: _selectedCategory == null,
                      color: PhColors.primary,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Medicines',
                      selected: _selectedCategory == ProductCategory.medicines,
                      color: PhColors.medicines,
                      onTap: () => setState(
                          () => _selectedCategory = ProductCategory.medicines),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Vaccines',
                      selected: _selectedCategory == ProductCategory.vaccines,
                      color: PhColors.vaccines,
                      onTap: () => setState(
                          () => _selectedCategory = ProductCategory.vaccines),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Supplements',
                      selected:
                          _selectedCategory == ProductCategory.supplements,
                      color: PhColors.supplements,
                      onTap: () => setState(() =>
                          _selectedCategory = ProductCategory.supplements),
                    ),
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: 'Equipment',
                      selected: _selectedCategory == ProductCategory.equipment,
                      color: PhColors.equipment,
                      onTap: () => setState(
                          () => _selectedCategory = ProductCategory.equipment),
                    ),
                  ],
                ),
              ),
              // Products list
              Expanded(
                child: products.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: products.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ProductCard(
                            product: products[i],
                            onTap: () =>
                                _showEditProductDialog(context, products[i]),
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

  Future<void> _showAddProductDialog(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      barrierColor: PhColors.primary.withValues(alpha: .58),
      builder: (_) => const AddMedicineDialog(),
    );
    if (created == true && context.mounted) {
      showPharmacyNotice(
        context,
        'Medicine added and sent for admin approval.',
        PhColors.green,
        Icons.check_circle_outline,
      );
    }
  }

  Future<void> _showLegacyAddProductDialog(BuildContext context) async {
    final name = TextEditingController();
    final manufacturer = TextEditingController();
    final stock = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '5');
    final price = TextEditingController();
    final unit = TextEditingController(text: 'piece');
    final expiry = TextEditingController(
        text: DateTime.now()
            .add(const Duration(days: 365))
            .toIso8601String()
            .split('T')
            .first);
    final description = TextEditingController();
    var category = ProductCategory.medicines;
    String? formError;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: PhColors.bg,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: PhColors.cardBorder)),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          title: const Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: PhColors.medicinesLight,
              child: Icon(Icons.add_box_outlined,
                  color: PhColors.medicines, size: 21),
            ),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Add Medicine',
                  style: TextStyle(
                      fontSize: 18,
                      color: PhColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Create a new inventory item',
                  style: TextStyle(
                      fontSize: 11,
                      color: PhColors.textSecondary,
                      fontWeight: FontWeight.w400)),
            ]),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    style: phFieldText,
                    decoration: phInput(
                        'Medicine / product name', Icons.medication_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: manufacturer,
                    style: phFieldText,
                    decoration:
                        phInput('Manufacturer', Icons.factory_outlined)),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProductCategory>(
                  initialValue: category,
                  dropdownColor: PhColors.bg,
                  style: phFieldText,
                  decoration: phInput('Category', Icons.category_outlined),
                  items: ProductCategory.values
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                              v.name[0].toUpperCase() + v.name.substring(1))))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: stock,
                          style: phFieldText,
                          keyboardType: TextInputType.number,
                          decoration: phInput(
                              'Opening stock', Icons.inventory_2_outlined))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: minimum,
                          style: phFieldText,
                          keyboardType: TextInputType.number,
                          decoration: phInput('Low-stock alert',
                              Icons.warning_amber_outlined))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: price,
                          style: phFieldText,
                          keyboardType: TextInputType.number,
                          decoration:
                              phInput('Price (৳)', Icons.payments_outlined))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: unit,
                          style: phFieldText,
                          decoration:
                              phInput('Unit', Icons.straighten_outlined))),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: expiry,
                    style: phFieldText,
                    decoration: phInput(
                        'Expiry date (YYYY-MM-DD)', Icons.event_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: description,
                    style: phFieldText,
                    minLines: 2,
                    maxLines: 3,
                    decoration: phInput(
                        'Description (optional)', Icons.notes_outlined)),
                if (formError != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.error_outline,
                        color: PhColors.red, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(formError!,
                            style: const TextStyle(
                                color: PhColors.red, fontSize: 12)))
                  ])
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final parsedExpiry = DateTime.tryParse(expiry.text.trim());
                if (name.text.trim().isEmpty ||
                    manufacturer.text.trim().isEmpty ||
                    double.tryParse(price.text) == null ||
                    parsedExpiry == null) {
                  setDialogState(() => formError =
                      'Complete the medicine name, manufacturer, valid price, and expiry date.');
                  return;
                }
                setDialogState(() => formError = null);
                try {
                  await PharmacySession.instance.addProduct(PharmacyProduct(
                    id: 'PRD-${DateTime.now().millisecondsSinceEpoch}',
                    name: name.text.trim(),
                    category: category,
                    stockCount: int.tryParse(stock.text) ?? 0,
                    minStock: int.tryParse(minimum.text) ?? 0,
                    unit: unit.text.trim().isEmpty ? 'piece' : unit.text.trim(),
                    price: double.parse(price.text),
                    manufacturer: manufacturer.text.trim(),
                    expiryDate: parsedExpiry,
                    description: description.text.trim().isEmpty
                        ? null
                        : description.text.trim(),
                  ));
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  setDialogState(() => formError = error.toString());
                }
              },
              style: TextButton.styleFrom(
                  backgroundColor: PhColors.secondary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Add Medicine',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    manufacturer.dispose();
    stock.dispose();
    minimum.dispose();
    price.dispose();
    unit.dispose();
    expiry.dispose();
    description.dispose();
    if (created == true && context.mounted) {
      showPharmacyNotice(context, 'Medicine added and sent for admin approval.',
          PhColors.green, Icons.check_circle_outline);
    }
  }

  Future<void> _showEditProductDialog(
      BuildContext context, PharmacyProduct product) async {
    final stock = TextEditingController(text: '${product.stockCount}');
    final minimum = TextEditingController(text: '${product.minStock}');
    final price = TextEditingController(text: product.price.toStringAsFixed(0));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PhColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(product.name,
            style: const TextStyle(
                color: PhColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock')),
          TextField(
              controller: minimum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum stock')),
          TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price')),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (context) => AlertDialog(
                  title: const Text('Remove product?'),
                  content: Text('Remove ${product.name} from inventory?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Remove')),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await PharmacySession.instance.deleteProduct(product.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child: const Text('Remove', style: TextStyle(color: PhColors.red)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await PharmacySession.instance.editProduct(product.copyWith(
                  stockCount: int.tryParse(stock.text) ?? product.stockCount,
                  minStock: int.tryParse(minimum.text) ?? product.minStock,
                  price: double.tryParse(price.text) ?? product.price,
                ));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
            child:
                const Text('Save', style: TextStyle(color: PhColors.secondary)),
          ),
        ],
      ),
    );
    stock.dispose();
    minimum.dispose();
    price.dispose();
  }
}

// ── Category Chip ─────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : PhColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : PhColors.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : PhColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Product Card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final PharmacyProduct product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  (Color, Color, String) get _categoryAttrs => switch (product.category) {
        ProductCategory.medicines => (
            PhColors.medicinesLight,
            PhColors.medicines,
            'Medicine'
          ),
        ProductCategory.vaccines => (
            PhColors.vaccinesLight,
            PhColors.vaccines,
            'Vaccine'
          ),
        ProductCategory.supplements => (
            PhColors.supplementsLight,
            PhColors.supplements,
            'Supplement'
          ),
        ProductCategory.equipment => (
            PhColors.equipmentLight,
            PhColors.equipment,
            'Equipment'
          ),
      };

  (Color, Color, String) get _stockAttrs => switch (product.stockStatus) {
        StockStatus.inStock => (
            PhColors.inStockLight,
            PhColors.inStock,
            'In Stock'
          ),
        StockStatus.lowStock => (
            PhColors.lowStockLight,
            PhColors.lowStock,
            'Low Stock'
          ),
        StockStatus.outOfStock => (
            PhColors.outOfStockLight,
            PhColors.outOfStock,
            'Out of Stock'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (catBg, catFg, catLabel) = _categoryAttrs;
    final (stockBg, stockFg, stockLabel) = _stockAttrs;
    final isAlert = product.stockStatus != StockStatus.inStock;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: phCard(
            borderColor: isAlert ? stockFg.withValues(alpha: 0.35) : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with category + stock badges
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  phChip(catLabel, catBg, catFg),
                  const SizedBox(width: 6),
                  phChip(stockLabel, stockBg, stockFg),
                  const Spacer(),
                  Text('৳${product.price.toStringAsFixed(0)}/${product.unit}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PhColors.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(product.name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: PhColors.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
              child: Text(product.manufacturer,
                  style: const TextStyle(
                      fontSize: 12, color: PhColors.textSecondary)),
            ),
            if (product.description != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Text(product.description!,
                    style: const TextStyle(
                        fontSize: 11, color: PhColors.grey, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            // Stock bar + controls
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _StockBar(product: product),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  Text(
                    'Expires: ${_formatDate(product.expiryDate)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isExpiringSoon(product.expiryDate)
                          ? PhColors.amber
                          : PhColors.grey,
                      fontWeight: _isExpiringSoon(product.expiryDate)
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  _StockAdjuster(product: product),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  bool _isExpiringSoon(DateTime d) {
    return d.difference(DateTime.now()).inDays <= 90;
  }
}

// ── Stock Bar ─────────────────────────────────────────────────────────────────

class _StockBar extends StatelessWidget {
  final PharmacyProduct product;
  const _StockBar({required this.product});

  @override
  Widget build(BuildContext context) {
    final ratio = product.minStock > 0
        ? (product.stockCount / (product.minStock * 3)).clamp(0.0, 1.0)
        : 1.0;
    final color = switch (product.stockStatus) {
      StockStatus.inStock => PhColors.inStock,
      StockStatus.lowStock => PhColors.lowStock,
      StockStatus.outOfStock => PhColors.outOfStock,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Stock: ${product.stockCount} ${product.unit}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: PhColors.textSecondary)),
            Text('Min: ${product.minStock}',
                style: const TextStyle(fontSize: 11, color: PhColors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: PhColors.surface2,
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ── Stock Adjuster ────────────────────────────────────────────────────────────

class _StockAdjuster extends StatelessWidget {
  final PharmacyProduct product;
  const _StockAdjuster({required this.product});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AdjustButton(
          icon: Icons.remove,
          onTap: product.stockCount > 0 ? () => _adjust(context, -1) : null,
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text('${product.stockCount}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PhColors.textPrimary)),
        ),
        _AdjustButton(
          icon: Icons.add,
          onTap: () => _adjust(context, 1),
        ),
      ],
    );
  }

  Future<void> _adjust(BuildContext context, int delta) async {
    try {
      await PharmacySession.instance.adjustStock(product.id, delta);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()),
          backgroundColor: PhColors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}

class _AdjustButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _AdjustButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap != null
              ? PhColors.secondary.withValues(alpha: 0.1)
              : PhColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: onTap != null
                  ? PhColors.secondary.withValues(alpha: 0.3)
                  : PhColors.cardBorder),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap != null ? PhColors.secondary : PhColors.grey),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 52, color: PhColors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('No products found',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: PhColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Try a different search or category.',
              style: TextStyle(fontSize: 13, color: PhColors.grey)),
        ],
      ),
    );
  }
}
