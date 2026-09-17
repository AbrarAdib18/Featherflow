import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/catalogue_image.dart';
import 'package:featherflow/core/widgets/error_state.dart';
import '../../data/feed_marketplace_service.dart';
import 'farmer_feed_product_detail_screen.dart';

/// Feed Marketplace / E-commerce — reached only from inside Feed Management
/// (`/farmer/feed-management/marketplace`). Farmers select only from the
/// admin-approved catalogue (never free text) — Browse / Cart / My Orders.
class FarmerFeedMarketplaceScreen extends StatefulWidget {
  const FarmerFeedMarketplaceScreen({super.key, this.initialTab = 0});

  /// 0 = Browse, 1 = Cart, 2 = My Orders — lets "My Feed Orders" on the Feed
  /// Management hub deep-link straight into the Orders tab.
  final int initialTab;

  @override
  State<FarmerFeedMarketplaceScreen> createState() => _FarmerFeedMarketplaceScreenState();
}

class _FarmerFeedMarketplaceScreenState extends State<FarmerFeedMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  final _searchCtrl = TextEditingController();
  FeedMarketplaceFilters _filters = const FeedMarketplaceFilters();

  List<FeedMarketProduct> _results = [];
  List<Map<String, dynamic>> _brands = [];
  final List<FeedCartLine> _cart = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _tabs.addListener(() => setState(() {}));
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && !_loading) _silentRefreshOrders();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _silentRefreshOrders() async {
    try {
      final orders = await FeedMarketplaceService.myOrders();
      if (mounted) setState(() => _orders = orders);
    } catch (_) {/* transient */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FeedMarketplaceService.search(
          query: _searchCtrl.text.trim(),
          birdType: _filters.birdType,
          feedType: _filters.feedType,
          companyId: _filters.companyId,
          minPrice: _filters.minPrice,
          maxPrice: _filters.maxPrice,
          inStockOnly: _filters.inStockOnly,
        ),
        FeedMarketplaceService.myOrders(),
        FeedMarketplaceService.companies(),
      ]);
      if (!mounted) return;
      setState(() {
        _results = results[0] as List<FeedMarketProduct>;
        _orders = results[1] as List<Map<String, dynamic>>;
        _brands = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorStateView.humanize(e);
          _loading = false;
        });
      }
    }
  }

  int get _cartCount => _cart.fold(0, (a, l) => a + l.quantity);

  void _addToCart(FeedMarketProduct p, [int quantity = 1]) {
    setState(() {
      final existing = _cart.where((l) => l.product.id == p.id).firstOrNull;
      if (existing != null) {
        existing.quantity += quantity;
      } else {
        _cart.add(FeedCartLine(p, quantity));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.productName} added to cart'), duration: const Duration(milliseconds: 900)),
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<FeedMarketplaceFilters>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(initial: _filters, brands: _brands),
    );
    if (result != null) {
      setState(() => _filters = result);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.canPop() ? context.pop() : context.go('/farmer/feed-management')),
        title: const Text('Feed Marketplace', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: 'Filters',
            onPressed: _openFilters,
          ),
          Stack(alignment: Alignment.center, children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
              onPressed: () => _tabs.animateTo(1),
            ),
            if (_cartCount > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text('$_cartCount', textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'Browse'),
            Tab(text: _cartCount > 0 ? 'Cart ($_cartCount)' : 'Cart'),
            const Tab(text: 'My Orders'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _browseTab(),
        _CartTab(
          cart: _cart,
          onChanged: () => setState(() {}),
          onContinueShopping: () => _tabs.animateTo(0),
          onPlaced: () {
            setState(() => _cart.clear());
            _tabs.animateTo(2);
            _load();
          },
        ),
        _ordersTab(),
      ]),
    );
  }

  Widget _browseTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
        child: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search feed products…',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
            isDense: true,
          ),
          onSubmitted: (_) => _load(),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in const {
              null: 'All', 'broiler': 'Broiler', 'layer': 'Layer',
              'chick': 'Chick', 'breeder': 'Breeder',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: _filters.birdType == entry.key,
                  onSelected: (_) {
                    setState(() => _filters = _filters.copyWith(birdType: () => entry.key));
                    _load();
                  },
                ),
              ),
            if (_filters.isActive)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear filters'),
                  onPressed: () {
                    setState(() => _filters = const FeedMarketplaceFilters());
                    _load();
                  },
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorStateView(message: _error!, onRetry: _load)
                : _results.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.grass, size: 40, color: AppColors.onSurfaceVariant),
                          const SizedBox(height: 8),
                          const Text('No approved feed products match your filters.'),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.68),
                          itemCount: _results.length,
                          itemBuilder: (context, i) => _ProductCard(
                            product: _results[i],
                            onAdd: () => _addToCart(_results[i]),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FarmerFeedProductDetailScreen(
                                  product: _results[i],
                                  onAddToCart: (p, qty) => _addToCart(p, qty),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
      ),
    ]);
  }

  Widget _ordersTab() {
    if (_orders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 8),
          const Text('No feed orders yet.'),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _silentRefreshOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _orders.length,
        itemBuilder: (context, i) => _OrderCard(order: _orders[i], onCancelled: _load),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.brands});
  final FeedMarketplaceFilters initial;
  final List<Map<String, dynamic>> brands;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _feedType = widget.initial.feedType;
  late String? _companyId = widget.initial.companyId;
  late bool _inStockOnly = widget.initial.inStockOnly;
  late final _minCtrl = TextEditingController(text: widget.initial.minPrice?.toStringAsFixed(0) ?? '');
  late final _maxCtrl = TextEditingController(text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '');

  static const _feedStages = ['starter', 'grower', 'finisher', 'layer', 'breeder', 'supplement', 'other'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Filter products', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('Feed stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Wrap(spacing: 6, children: [
            for (final s in _feedStages)
              ChoiceChip(
                label: Text(s), selected: _feedType == s,
                onSelected: (v) => setState(() => _feedType = v ? s : null),
              ),
          ]),
          const SizedBox(height: 12),
          if (widget.brands.isNotEmpty) ...[
            const Text('Company / brand', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            DropdownButton<String?>(
              isExpanded: true,
              value: _companyId,
              hint: const Text('All companies'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All companies')),
                for (final b in widget.brands) DropdownMenuItem(value: b['id'].toString(), child: Text(b['name'] ?? '')),
              ],
              onChanged: (v) => setState(() => _companyId = v),
            ),
            const SizedBox(height: 12),
          ],
          const Text('Price range (৳)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Row(children: [
            Expanded(child: TextField(controller: _minCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Min'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _maxCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Max'))),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('In stock only'),
            value: _inStockOnly,
            onChanged: (v) => setState(() => _inStockOnly = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, const FeedMarketplaceFilters()),
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  FeedMarketplaceFilters(
                    birdType: widget.initial.birdType,
                    feedType: _feedType,
                    companyId: _companyId,
                    minPrice: double.tryParse(_minCtrl.text.trim()),
                    maxPrice: double.tryParse(_maxCtrl.text.trim()),
                    inStockOnly: _inStockOnly,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd, required this.onTap});
  final FeedMarketProduct product;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.outline)),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: Stack(fit: StackFit.expand, children: [
              CatalogueImage(url: product.imageUrl, borderRadius: BorderRadius.zero),
              if (product.approvalBadge)
                const Positioned(
                  left: 6, top: 6,
                  child: _Badge(label: 'Approved', color: AppColors.secondary),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.productName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(product.companyName.isNotEmpty ? product.companyName : product.brand,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
              Text('${product.birdType} · ${product.feedType}',
                  style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('৳${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 13)),
                Text(product.inStock ? 'In stock' : 'Out of stock',
                    style: TextStyle(fontSize: 9, color: product.inStock ? AppColors.secondary : AppColors.error)),
              ]),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: product.inStock ? onAdd : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6), minimumSize: const Size(0, 32)),
                  child: Text(product.inStock ? 'Add to cart' : 'Out of stock', style: const TextStyle(fontSize: 11)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

extension on FeedMarketProduct {
  // Every product a farmer can see is already approval_status='approved'
  // (enforced server-side) — the badge is just a visual confirmation of
  // that guarantee, not a client-side trust decision.
  bool get approvalBadge => true;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}

class _CartTab extends StatefulWidget {
  const _CartTab({
    required this.cart,
    required this.onChanged,
    required this.onPlaced,
    required this.onContinueShopping,
  });
  final List<FeedCartLine> cart;
  final VoidCallback onChanged;
  final VoidCallback onPlaced;
  final VoidCallback onContinueShopping;

  @override
  State<_CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<_CartTab> {
  bool _checkingOut = false;
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _upazilaCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cod';
  bool _busy = false;
  String? _error;

  static const _deliveryFeeEstimate = 60.0;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentSession?.user;
    _addressCtrl.text = user?.presentAddress ?? '';
    _phoneCtrl.text = user?.phone ?? '';
  }

  double get _subtotal => widget.cart.fold(0.0, (a, l) => a + l.lineTotal);

  Future<void> _placeOrder() async {
    if (widget.cart.isEmpty || _busy) return;
    if (_addressCtrl.text.trim().isEmpty) {
      setState(() => _error = 'A delivery address is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final address = [
        _addressCtrl.text.trim(),
        if (_upazilaCtrl.text.trim().isNotEmpty) _upazilaCtrl.text.trim(),
        if (_districtCtrl.text.trim().isNotEmpty) _districtCtrl.text.trim(),
      ].join(', ');
      await FeedMarketplaceService.placeOrder(
        cart: widget.cart, deliveryAddress: address,
        paymentMethod: _method, contactPhone: _phoneCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed!')));
        widget.onPlaced();
      }
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cart.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 8),
          const Text('Your cart is empty. Add feed products from Browse.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: widget.onContinueShopping, child: const Text('Browse feed products')),
        ]),
      );
    }
    if (!_checkingOut) return _cartItemsView();
    return _checkoutView();
  }

  Widget _cartItemsView() {
    return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
      for (final line in widget.cart)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              SizedBox(width: 56, height: 56, child: CatalogueImage(url: line.product.imageUrl, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(line.product.productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(line.product.companyName, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  Text('৳${line.product.price.toStringAsFixed(0)} × ${line.quantity} = ৳${line.lineTotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: line.quantity > line.product.minOrderQuantity
                      ? () {
                          line.quantity--;
                          widget.onChanged();
                        }
                      : () {
                          widget.cart.remove(line);
                          widget.onChanged();
                        },
                ),
                Text('${line.quantity}'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () {
                    if (line.quantity < line.product.stockQuantity) {
                      line.quantity++;
                      widget.onChanged();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                  onPressed: () {
                    widget.cart.remove(line);
                    widget.onChanged();
                  },
                ),
              ]),
            ]),
          ),
        ),
      const Divider(),
      _summaryRow('Subtotal', _subtotal),
      _summaryRow('Estimated delivery', _deliveryFeeEstimate, note: 'final fee calculated at checkout'),
      const Divider(),
      _summaryRow('Estimated total', _subtotal + _deliveryFeeEstimate, bold: true),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: widget.onContinueShopping, child: const Text('Continue shopping'))),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: () => setState(() => _checkingOut = true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Proceed to checkout'),
          ),
        ),
      ]),
    ]);
  }

  Widget _summaryRow(String label, double value, {bool bold = false, String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 13)),
            if (note != null) Text(note, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
          ]),
          Text('৳${value.toStringAsFixed(0)}', style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 16 : 13)),
        ]),
      );

  Widget _checkoutView() {
    return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
      TextButton.icon(
        onPressed: () => setState(() => _checkingOut = false),
        icon: const Icon(Icons.arrow_back, size: 16),
        label: const Text('Back to cart'),
      ),
      const Text('Delivery details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 8),
      TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Delivery address *')),
      const SizedBox(height: 8),
      TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone number')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _districtCtrl, decoration: const InputDecoration(labelText: 'District'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _upazilaCtrl, decoration: const InputDecoration(labelText: 'Upazila'))),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Delivery notes (optional)'), maxLines: 2),
      const SizedBox(height: 16),
      const Text('Payment method', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, children: [
        for (final m in const {'cod': 'Cash on delivery', 'bkash': 'bKash', 'nagad': 'Nagad', 'card': 'Card'}.entries)
          ChoiceChip(label: Text(m.value), selected: _method == m.key, onSelected: (_) => setState(() => _method = m.key)),
      ]),
      if (_method != 'cod')
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Sandbox/development payment — no real provider is configured yet.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A5A00))),
        ),
      const SizedBox(height: 16),
      _summaryRow('Subtotal', _subtotal),
      _summaryRow('Delivery fee', _deliveryFeeEstimate, note: 'server-computed final total'),
      const Divider(),
      _summaryRow('Final total', _subtotal + _deliveryFeeEstimate, bold: true),
      if (_error != null) ...[
        const SizedBox(height: 8),
        ErrorStateView(message: _error!, compact: true, onRetry: _placeOrder),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _placeOrder,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Place order'),
        ),
      ),
    ]);
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.order, required this.onCancelled});
  final Map<String, dynamic> order;
  final VoidCallback onCancelled;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;
  String? _error;

  static const _flowLabels = {
    'created': 'Pending', 'confirmed': 'Confirmed', 'preparing': 'Preparing',
    'ready_for_pickup': 'Ready for pickup', 'assigned': 'Assigned', 'picked_up': 'Picked up',
    'out_for_delivery': 'Out for delivery', 'delivered': 'Delivered',
  };

  Future<void> _cancel() async {
    setState(() => _error = null);
    try {
      await FeedMarketplaceService.cancelOrder(widget.order['id'].toString());
      widget.onCancelled();
    } catch (e) {
      if (mounted) setState(() => _error = ErrorStateView.humanize(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final items = (order['items'] as List?) ?? const [];
    final status = (order['status'] ?? '').toString();
    final timeline = (order['timeline'] as List?) ?? const [];
    final isTerminalBad = status == 'cancelled' || status == 'delivery_failed';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(order['order_number']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
              _StatusPill(status: status),
            ]),
            const SizedBox(height: 4),
            for (final item in items)
              Text('${item['product_name']} × ${item['quantity']}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text('Total: ৳${order['total_amount']} (${order['payment_status']})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            if ((order['delivery_address'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text(order['delivery_address'], style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant))),
                ]),
              ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (isTerminalBad)
                Text(status == 'cancelled' ? 'This order was cancelled.' : 'Delivery failed — it will be reassigned or refunded.',
                    style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600))
              else
                _Timeline(timeline: timeline, labels: _flowLabels),
              if (_error != null) ...[
                const SizedBox(height: 8),
                ErrorStateView(message: _error!, compact: true, onRetry: _cancel),
              ],
            ],
            if (order['can_cancel'] == true) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(onPressed: _cancel, child: const Text('Cancel order')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  Color get _color => switch (status) {
        'delivered' => AppColors.secondary,
        'cancelled' || 'delivery_failed' => AppColors.error,
        'created' => Colors.orange,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _color)),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline, required this.labels});
  final List timeline;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in timeline)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(step['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16, color: step['done'] == true ? AppColors.secondary : AppColors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(labels[step['step']] ?? step['step'].toString(),
                  style: TextStyle(
                      fontSize: 12,
                      color: step['done'] == true ? AppColors.onSurface : AppColors.onSurfaceVariant,
                      fontWeight: step['done'] == true ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
      ],
    );
  }
}
