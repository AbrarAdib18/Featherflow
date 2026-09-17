import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/catalogue_image.dart';
import '../../../../core/widgets/error_state.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';
import 'admin_feed_product_form_screen.dart';

/// Feed Admin panel (Priorities 5-8) — companies, catalogue approval,
/// inventory/pricing, and feed-order/delivery assignment. Backend-enforced
/// via the `feed_admin` role (see `feed_marketplace_extension.sql` +
/// `feed_catalogue/admin_views.py`) — this screen only shows what
/// `AdminModule.feedCatalogue`/`feedOrders`/`feedDelivery` permit.
class AdminFeedScreen extends StatefulWidget {
  const AdminFeedScreen({super.key});

  @override
  State<AdminFeedScreen> createState() => _AdminFeedScreenState();
}

class _AdminFeedScreenState extends State<AdminFeedScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _api = AdminApiService.instance;

  Map<String, dynamic> _analytics = const {};
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _riders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.feedAnalytics(), _api.feedCompanies(), _api.feedProducts(),
        _api.feedOrders(), _api.availableFeedRiders(),
      ]);
      if (!mounted) return;
      setState(() {
        _analytics = results[0] as Map<String, dynamic>;
        _companies = results[1] as List<Map<String, dynamic>>;
        _products = results[2] as List<Map<String, dynamic>>;
        _orders = results[3] as List<Map<String, dynamic>>;
        _riders = results[4] as List<Map<String, dynamic>>;
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

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _addProduct({String? productId}) async {
    if (_companies.isEmpty && productId == null) {
      _toast('Add a feed client/company first.', AColors.red);
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminFeedProductFormScreen(productId: productId)),
    );
    if (changed == true) _load();
  }

  Future<void> _productAction(Map<String, dynamic> product, String action) async {
    String reason = '';
    if (action == 'reject') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Reject ${product['product_name']}'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true || ctrl.text.trim().isEmpty) return;
      reason = ctrl.text.trim();
    }
    try {
      await _api.feedProductAction(product['id'].toString(), action, reason: reason);
      await _load();
      final pastTense = {'approve': 'approved', 'reject': 'rejected', 'suspend': 'suspended'}[action] ?? action;
      _toast('Product $pastTense', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _assignRider(Map<String, dynamic> order) async {
    if (_riders.isEmpty) {
      _toast('No approved riders available.', AColors.red);
      return;
    }
    String riderId = _riders.first['id'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Assign rider — ${order['order_number']}'),
          content: DropdownButtonFormField<String>(
            initialValue: riderId,
            decoration: const InputDecoration(labelText: 'Rider'),
            items: [for (final r in _riders) DropdownMenuItem(value: r['id'].toString(),
                child: Text(
                  r['max_concurrent_orders'] != null
                      ? '${r['name']} (${r['active_orders']}/${r['max_concurrent_orders']} active)'
                          '${r['at_capacity'] == true ? ' — full' : ''}'
                      : '${r['name']} (${r['active_orders']} active)',
                  style: r['at_capacity'] == true
                      ? const TextStyle(color: AColors.red)
                      : null,
                ))],
            onChanged: (v) => setLocal(() => riderId = v ?? riderId),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.assignFeedOrder(order['id'].toString(), riderId);
      await _load();
      _toast('Rider assigned', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Feed Management',
      module: AdminModule.feedCatalogue,
      child: Column(children: [
        if (!_loading && _error == null)
          Container(
            color: AColors.appBar,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              _stat('Companies', '${_analytics['total_companies'] ?? _companies.length}'),
              _stat('Products', '${_analytics['total_products'] ?? _products.length}'),
              _stat('Pending review', '${_analytics['products_pending_review'] ?? 0}'),
              _stat('Orders', '${_analytics['total_orders'] ?? _orders.length}'),
            ]),
          ),
        Container(
          color: AColors.appBar,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AColors.secondary,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(text: 'Dashboard'),
              Tab(text: 'Products'),
              Tab(text: 'Orders & Delivery'),
              Tab(text: 'Analytics'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorStateView(message: _error!, onRetry: _load)
                  : TabBarView(controller: _tabs, children: [
                      _dashboardTab(),
                      _catalogueTab(),
                      _ordersTab(),
                      _analyticsTab(),
                    ]),
        ),
      ]),
    );
  }

  Widget _dashboardTab() {
    final activeCompanies = _analytics['active_companies'] ?? _companies.where((c) => c['status'] == 'active').length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            _dashCard('Clients', '${_analytics['total_companies'] ?? _companies.length}', Icons.storefront_outlined, AColors.green),
            _dashCard('Active clients', '$activeCompanies', Icons.verified_outlined, AColors.green),
            _dashCard('Approved products', '${_analytics['products_approved'] ?? 0}', Icons.inventory_2_outlined, AColors.green),
            _dashCard('Pending approvals', '${_analytics['products_pending_review'] ?? 0}', Icons.pending_actions_outlined, Colors.orange),
            _dashCard('Low stock', '${_analytics['low_stock_products'] ?? 0}', Icons.warning_amber_outlined, Colors.orange),
            _dashCard('New orders', '${_analytics['new_orders'] ?? 0}', Icons.shopping_bag_outlined, AColors.green),
            _dashCard('Awaiting assignment', '${_analytics['orders_awaiting_assignment'] ?? 0}', Icons.local_shipping_outlined, Colors.orange),
            _dashCard('Active deliveries', '${_analytics['active_deliveries'] ?? 0}', Icons.pedal_bike_outlined, AColors.green),
            _dashCard('Failed/cancelled', '${_analytics['failed_cancelled_orders'] ?? 0}', Icons.report_gmailerrorred_outlined, AColors.red),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          PermissionGuard(
            module: AdminModule.feedCatalogue, permission: AdminPermission.create,
            child: _quickAction('Add product', Icons.add_box_outlined, () => _addProduct()),
          ),
          PermissionGuard(
            module: AdminModule.feedClients, permission: AdminPermission.create,
            child: _quickAction('Add client', Icons.add_business_outlined,
                () => context.push('/admin/feed-clients')),
          ),
          _quickAction('Review pending', Icons.fact_check_outlined, () => _tabs.animateTo(1)),
          _quickAction('View new orders', Icons.receipt_long_outlined, () => _tabs.animateTo(2)),
          _quickAction('View clients', Icons.storefront_outlined, () => context.push('/admin/feed-clients')),
        ]),
      ]),
    );
  }

  Widget _dashCard(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _quickAction(String label, IconData icon, VoidCallback onTap) => OutlinedButton.icon(
      onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      );

  Widget _catalogueTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Feed Products', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          PermissionGuard(
            module: AdminModule.feedCatalogue, permission: AdminPermission.create,
            child: TextButton.icon(onPressed: () => _addProduct(), icon: const Icon(Icons.add), label: const Text('Add product')),
          ),
        ]),
        if (_companies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No clients yet — add one from the Clients section before adding products.',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
          ),
        for (final p in _products)
          _ProductRow(
            product: p,
            onAction: _productAction,
            onTap: () => _addProduct(productId: p['id'].toString()),
          ),
      ]),
    );
  }

  Widget _ordersTab() {
    if (_orders.isEmpty) return const Center(child: Text('No feed orders yet.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (context, i) {
          final o = _orders[i];
          final items = (o['items'] as List?) ?? const [];
          final canAssign = o['can_assign_rider'] == true;
          final deliveryStatus = o['delivery_status']?.toString();
          final needsReassign = o['status'] == 'assigned' &&
              (deliveryStatus == 'rejected' || deliveryStatus == 'failed');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(o['order_number']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text((o['status'] ?? '').toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                Text('${o['farmer_name']} · ${o['farmer_phone']} · ${o['delivery_address']}'),
                if (o['latitude'] != null)
                  Text('Map: ${o['latitude']}, ${o['longitude']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                for (final it in items) Text('  ${it['product_name']} × ${it['quantity']}'),
                Text('Total: ৳${o['total_amount']} (${o['payment_status']})'),
                if (needsReassign)
                  Text('Rider ${deliveryStatus == 'rejected' ? 'rejected' : 'did not respond to'} this assignment — needs a new rider.',
                      style: const TextStyle(fontSize: 12, color: AColors.red, fontWeight: FontWeight.w600)),
                if (canAssign)
                  PermissionGuard(
                    module: AdminModule.feedOrders, permission: AdminPermission.assign,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () => _assignRider(o),
                          child: Text(needsReassign ? 'Reassign rider' : 'Assign rider')),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _analyticsTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _analyticsRow('Total orders', '${_analytics['total_orders'] ?? 0}'),
      _analyticsRow('Paid revenue', '৳${_analytics['paid_revenue'] ?? 0}'),
      _analyticsRow('Products approved', '${_analytics['products_approved'] ?? 0}'),
      _analyticsRow('Products pending review', '${_analytics['products_pending_review'] ?? 0}'),
      _analyticsRow('Low stock products (<50)', '${_analytics['low_stock_products'] ?? 0}'),
      const SizedBox(height: 12),
      const Text('Orders by status', style: TextStyle(fontWeight: FontWeight.w800)),
      for (final entry in (_analytics['orders_by_status'] as Map? ?? const {}).entries)
        _analyticsRow(entry.key.toString(), '${entry.value}'),
    ]);
  }

  Widget _analyticsRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onAction, required this.onTap});
  final Map<String, dynamic> product;
  final void Function(Map<String, dynamic>, String) onAction;
  final VoidCallback onTap;

  Color _statusColor(String status) => switch (status) {
        'approved' => AColors.green,
        'pending_review' => Colors.orange,
        'rejected' || 'suspended' => AColors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final status = product['approval_status']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 44, height: 44,
          child: CatalogueImage(url: product['image_url'], borderRadius: BorderRadius.circular(6)),
        ),
        title: Text(product['product_name'] ?? ''),
        subtitle: Text('${product['company_name']} · ${product['bird_type']}/${product['feed_type']} · '
            '৳${product['price']} · stock ${product['stock_quantity']}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => onAction(product, v),
            itemBuilder: (context) => [
              if (status != 'approved') const PopupMenuItem(value: 'approve', child: Text('Approve')),
              if (status != 'rejected') const PopupMenuItem(value: 'reject', child: Text('Reject')),
              if (status != 'suspended') const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
            ],
          ),
        ]),
      ),
    );
  }
}
