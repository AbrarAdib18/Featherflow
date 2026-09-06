import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/theme/theme.dart';
import '../../data/pharmacy_marketplace_service.dart';

class FarmerPharmacyScreen extends StatefulWidget {
  const FarmerPharmacyScreen({super.key});

  @override
  State<FarmerPharmacyScreen> createState() => _FarmerPharmacyScreenState();
}

class _FarmerPharmacyScreenState extends State<FarmerPharmacyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _searchCtrl = TextEditingController();

  List<MarketMedicine> _results = [];
  final List<CartLine> _cart = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  String? _categoryFilter;
  bool _prescriptionOnly = false;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _tabs.addListener(() => setState(() {}));
    // Near-real-time: refresh My Orders / delivery status every 4s.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_loading) _silentRefresh();
    });
  }

  Future<void> _silentRefresh() async {
    try {
      final orders = await FarmerPharmacyService.myOrders();
      if (mounted) setState(() => _orders = orders);
    } catch (_) {/* transient */}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FarmerPharmacyService.search(
          query: _searchCtrl.text.trim(),
          category: _categoryFilter,
          prescriptionRequired: _prescriptionOnly ? true : null,
        ),
        FarmerPharmacyService.myOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _results = results[0] as List<MarketMedicine>;
        _orders = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int get _cartCount => _cart.fold(0, (a, l) => a + l.quantity);

  void _addToCart(MarketMedicine m) {
    setState(() {
      final existing = _cart.where((l) => l.medicine.id == m.id).firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        if (_cart.isNotEmpty && _cart.first.medicine.pharmacyId != m.pharmacyId) {
          _cart.clear();
        }
        _cart.add(CartLine(m, 1));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${m.name} added to cart'), duration: const Duration(milliseconds: 900)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacy'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Browse'),
            Tab(text: _cartCount > 0 ? 'Cart ($_cartCount)' : 'Cart'),
            const Tab(text: 'My Orders'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _browseTab(),
          _CartTab(
            cart: _cart,
            onChanged: () => setState(() {}),
            onPlaced: () {
              setState(() => _cart.clear());
              _tabs.animateTo(2);
              _load();
            },
          ),
          _ordersTab(),
        ],
      ),
    );
  }

  Widget _browseTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search medicine, generic, brand…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.tune), onPressed: _load),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            FilterChip(
              label: const Text('Prescription only'),
              selected: _prescriptionOnly,
              onSelected: (v) {
                setState(() => _prescriptionOnly = v);
                _load();
              },
            ),
            const SizedBox(width: 8),
            for (final c in const ['antibiotic', 'vaccine', 'vitamin', 'antiparasitic', 'feed_supplement', 'equipment']) ...[
              ChoiceChip(
                label: Text(c.replaceAll('_', ' ')),
                selected: _categoryFilter == c,
                onSelected: (v) {
                  setState(() => _categoryFilter = v ? c : null);
                  _load();
                },
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView()
                  : _results.isEmpty
                      ? const Center(child: Text('No medicines match your search.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (_, i) => _MedicineCard(
                              medicine: _results[i],
                              onDetail: () => _showDetail(_results[i]),
                              onAdd: () => _addToCart(_results[i]),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _ordersTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_orders.isEmpty) {
      return const Center(child: Text('You have not ordered any medicine yet.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, i) => _OrderCard(
          order: _orders[i],
          onAction: _load,
        ),
      ),
    );
  }

  Widget _errorView() => ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!, textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('Retry'))),
      ]);

  void _showDetail(MarketMedicine m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MedicineDetailSheet(medicine: m, onAdd: () {
        Navigator.pop(context);
        _addToCart(m);
      }),
    );
  }
}

// ── medicine card ──────────────────────────────────────────────────────────

class _MedicineCard extends StatelessWidget {
  final MarketMedicine medicine;
  final VoidCallback onDetail;
  final VoidCallback onAdd;
  const _MedicineCard({required this.medicine, required this.onDetail, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onDetail,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (medicine.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(medicine.images.first, width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44)),
                  ),
                ),
              Expanded(
                child: Text(medicine.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('৳${medicine.price.toStringAsFixed(0)}/${medicine.unit}',
                  style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(
                '${medicine.genericName.isNotEmpty ? '${medicine.genericName} · ' : ''}'
                '${medicine.manufacturer}',
                style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
            Text(medicine.pharmacyName,
                style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (medicine.prescriptionRequired)
                const Chip(label: Text('Prescription'), visualDensity: VisualDensity.compact),
              if (medicine.coldChainRequired)
                const Chip(label: Text('🧊 Cold chain'), visualDensity: VisualDensity.compact),
              Chip(
                label: Text(medicine.stock > 0 ? '${medicine.stock} in stock' : 'Out of stock'),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: medicine.stock > 0 ? onAdd : null,
                icon: const Icon(Icons.add_shopping_cart, size: 17),
                label: const Text('Add to cart'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MedicineDetailSheet extends StatelessWidget {
  final MarketMedicine medicine;
  final VoidCallback onAdd;
  const _MedicineDetailSheet({required this.medicine, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(medicine.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (medicine.genericName.isNotEmpty)
            Text(medicine.genericName, style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (medicine.images.isNotEmpty)
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: medicine.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(medicine.images[i], width: 200, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 200)),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _kv('Price', '৳${medicine.price.toStringAsFixed(0)} / ${medicine.unit}'),
          _kv('Pack size', medicine.packSize.isEmpty ? '—' : medicine.packSize),
          _kv('Manufacturer', medicine.manufacturer),
          _kv('Pharmacy', medicine.pharmacyName),
          _kv('In stock', '${medicine.stock}'),
          if (medicine.description.isNotEmpty) _para('Description', medicine.description),
          if (medicine.dosageInstructions.isNotEmpty) _para('Dosage', medicine.dosageInstructions),
          if (medicine.storageInstructions.isNotEmpty) _para('Storage', medicine.storageInstructions),
          if (medicine.prescriptionRequired)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('⚠ A prescription photo is required to order this medicine.',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
          if (medicine.coldChainRequired)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('🧊 Delivered cold — rider uses an insulated bag.',
                  style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: medicine.stock > 0 ? onAdd : null,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Add to cart'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.onSurfaceVariant))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _para(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(color: AppColors.onSurfaceVariant, height: 1.4)),
        ]),
      );
}

// ── cart tab ───────────────────────────────────────────────────────────────

class _CartTab extends StatefulWidget {
  final List<CartLine> cart;
  final VoidCallback onChanged;
  final VoidCallback onPlaced;
  const _CartTab({required this.cart, required this.onChanged, required this.onPlaced});

  @override
  State<_CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<_CartTab> {
  String _deliveryMethod = 'delivery';
  String _paymentMethod = 'cod';
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _prescriptionUrl;
  bool _uploading = false;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.instance.getStoredSession().then((s) {
      if (mounted) _addressCtrl.text = s?.user.presentAddress ?? '';
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _needsPrescription => widget.cart.any((l) => l.medicine.prescriptionRequired);
  double get _subtotal => widget.cart.fold(0, (a, l) => a + l.subtotal);
  double get _deliveryFee => _deliveryMethod == 'delivery' ? 60 : 0;

  Future<void> _pickPrescription() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await FarmerPharmacyService.uploadPrescription(file!.bytes!, file.name);
      if (mounted) setState(() => _prescriptionUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _placeOrder() async {
    if (widget.cart.isEmpty) return;
    if (_needsPrescription && _prescriptionUrl == null) {
      setState(() => _error = 'Upload a prescription photo for the prescription medicines in your cart.');
      return;
    }
    if (_deliveryMethod == 'delivery' && _addressCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter a delivery address.');
      return;
    }
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      await FarmerPharmacyService.placeOrder(
        pharmacyId: widget.cart.first.medicine.pharmacyId,
        cart: widget.cart,
        deliveryMethod: _deliveryMethod,
        paymentMethod: _paymentMethod,
        deliveryAddress: _addressCtrl.text.trim(),
        prescriptionImage: _prescriptionUrl,
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed — the pharmacy will confirm shortly.')),
      );
      widget.onPlaced();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _placing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cart.isEmpty) {
      return const Center(child: Text('Your cart is empty.'));
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('From ${widget.cart.first.medicine.pharmacyName}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...widget.cart.map((line) => Card(
              child: ListTile(
                title: Text(line.medicine.name),
                subtitle: Text('৳${line.medicine.price.toStringAsFixed(0)} × ${line.quantity} = ৳${line.subtotal.toStringAsFixed(0)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      line.quantity--;
                      if (line.quantity <= 0) widget.cart.remove(line);
                      widget.onChanged();
                    }),
                  ),
                  Text('${line.quantity}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: line.quantity < line.medicine.stock
                        ? () => setState(() {
                              line.quantity++;
                              widget.onChanged();
                            })
                        : null,
                  ),
                ]),
              ),
            )),
        if (_needsPrescription) ...[
          const SizedBox(height: 8),
          Card(
            color: AppColors.errorContainer.withValues(alpha: .25),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Prescription required',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Some items need a vet prescription. Upload a clear photo — the order cannot be placed without it.',
                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (_prescriptionUrl != null)
                  Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(_prescriptionUrl!, width: 60, height: 60, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long)),
                    ),
                    const SizedBox(width: 10),
                    TextButton(onPressed: _uploading ? null : _pickPrescription, child: const Text('Replace')),
                  ])
                else
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickPrescription,
                    icon: _uploading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file),
                    label: const Text('Upload prescription'),
                  ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Delivery', style: TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<String>(
                groupValue: _deliveryMethod,
                onChanged: (v) => setState(() => _deliveryMethod = v ?? 'delivery'),
                child: const Column(children: [
                  RadioListTile(value: 'delivery', title: Text('Home delivery (৳60 base)')),
                  RadioListTile(value: 'pickup', title: Text('Pick up at pharmacy (free)')),
                ]),
              ),
              if (_deliveryMethod == 'delivery')
                TextField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Delivery address', border: OutlineInputBorder()),
                  minLines: 1,
                  maxLines: 2,
                ),
              const SizedBox(height: 12),
              const Text('Payment', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 8, children: [
                for (final m in const ['cod', 'bkash', 'nagad', 'bank'])
                  ChoiceChip(
                    label: Text(m == 'cod' ? 'Cash on delivery' : m),
                    selected: _paymentMethod == m,
                    onSelected: (_) => setState(() => _paymentMethod = m),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Order notes (optional)', border: OutlineInputBorder()),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(children: [
              _summaryRow('Subtotal', _subtotal),
              _summaryRow('Delivery fee', _deliveryFee),
              const Divider(),
              _summaryRow('Total', _subtotal + _deliveryFee, bold: true),
            ]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.error)),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _placing ? null : _placeOrder,
          child: _placing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Place order'),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
          Text('৳${value.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

// ── order card ─────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAction;
  const _OrderCard({required this.order, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? 'pending';
    final pharmacy = (order['pharmacy'] as Map?)?.cast<String, dynamic>() ?? const {};
    final delivery = (order['delivery'] as Map?)?.cast<String, dynamic>();
    final timeline = (order['timeline'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final canCancel = order['can_cancel'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(order['order_number']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Chip(label: Text(status.replaceAll('_', ' ')), visualDensity: VisualDensity.compact),
          ]),
          Text(pharmacy['name']?.toString() ?? '',
              style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 6),
          Text('৳${(order['total_amount'] as num? ?? 0).toStringAsFixed(0)} · '
              'payment ${order['payment_status'] ?? 'pending'}',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          _Timeline(steps: timeline),
          if (delivery != null && status == 'out_for_delivery') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.secondaryContainer.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.two_wheeler, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${delivery['rider_name'] ?? 'Rider'} · OTP ${delivery['otp_code'] ?? '—'}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                if ((delivery['rider_phone']?.toString() ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.call, size: 18),
                    onPressed: () => launchUrl(Uri.parse('tel:${delivery['rider_phone']}')),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if ((pharmacy['phone']?.toString() ?? '').isNotEmpty)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:${pharmacy['phone']}')),
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Contact pharmacy'),
              ),
            const Spacer(),
            if (order['payment_status'] == 'pending' &&
                order['payment_method'] != 'cod' &&
                (status == 'preparing' || status == 'ready_for_delivery'))
              TextButton(onPressed: () => _pay(context), child: const Text('Pay now')),
            if (canCancel)
              TextButton(
                onPressed: () => _cancel(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.error)),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _pay(BuildContext context) async {
    try {
      await FarmerPharmacyService.payOrder(order['order_id'].toString(),
          order['payment_method']?.toString() ?? 'bkash');
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text('You can only cancel before the pharmacy confirms it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FarmerPharmacyService.cancelOrder(order['order_id'].toString(), 'Cancelled by farmer');
      onAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class _Timeline extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  const _Timeline({required this.steps});

  static const _labels = {
    'pending': 'Placed',
    'preparing': 'Preparing',
    'ready_for_delivery': 'Ready',
    'out_for_delivery': 'On the way',
    'delivered': 'Delivered',
  };

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Row(
      children: steps.map((s) {
        final done = s['done'] == true;
        return Expanded(
          child: Column(children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16, color: done ? AppColors.secondary : AppColors.disabled),
            const SizedBox(height: 2),
            Text(_labels[s['step']] ?? s['step'].toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 8.5,
                    color: done ? AppColors.secondary : AppColors.onSurfaceVariant)),
          ]),
        );
      }).toList(),
    );
  }
}
