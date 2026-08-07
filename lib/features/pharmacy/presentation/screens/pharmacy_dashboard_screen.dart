import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../data/models/pharmacy_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import 'pharmacy_inventory_screen.dart';
import 'pharmacy_orders_screen.dart';

class PharmacyDashboardScreen extends StatefulWidget {
  const PharmacyDashboardScreen({super.key});

  @override
  State<PharmacyDashboardScreen> createState() =>
      _PharmacyDashboardScreenState();
}

class _PharmacyDashboardScreenState extends State<PharmacyDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(onOpenInventory: _openInventory),
          const PharmacyInventoryScreen(),
          const PharmacyOrdersScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        backgroundColor: PhColors.bg,
        selectedItemColor: PhColors.primary,
        unselectedItemColor: PhColors.grey,
        selectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
        ],
      ),
    );
  }

  void _openInventory() => setState(() => _currentIndex = 1);
}

// ── Home Tab ──────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final VoidCallback onOpenInventory;
  const _HomeTab({required this.onOpenInventory});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final session = PharmacySession.instance;
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.profile.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  session.profile.location,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Profile',
                onPressed: () => _showProfileSheet(context),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: session.refresh,
            color: PhColors.secondary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (session.errorMessage != null)
                  _ErrorBanner(
                      message: session.errorMessage!, onRetry: session.refresh),
                _StatsGrid(session: session),
                if (session.lowStockProducts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _LowStockSection(products: session.lowStockProducts),
                ],
                const SizedBox(height: 20),
                _RecentOrdersSection(
                    orders: session.recentOrders.take(4).toList()),
                const SizedBox(height: 20),
                _QuickActions(onOpenInventory: onOpenInventory),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProfileSheet(BuildContext context) {
    final session = PharmacySession.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: PhColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: PhColors.cardBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
            CircleAvatar(
              radius: 32,
              backgroundColor: PhColors.secondary.withValues(alpha: 0.15),
              child: const Icon(Icons.local_pharmacy,
                  color: PhColors.secondary, size: 32),
            ),
            const SizedBox(height: 12),
            Text(session.profile.name,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: PhColors.textPrimary)),
            const SizedBox(height: 4),
            Text(session.profile.licenseNumber,
                style: const TextStyle(
                    fontSize: 12, color: PhColors.textSecondary)),
            const SizedBox(height: 4),
            Text(session.profile.location,
                style: const TextStyle(
                    fontSize: 13, color: PhColors.textSecondary)),
            const SizedBox(height: 4),
            Text(session.profile.phone,
                style: const TextStyle(
                    fontSize: 13, color: PhColors.textSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await AuthService.instance.clearSession();
                  if (context.mounted) {
                    context.go(AppRoutes.login);
                  }
                },
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PhColors.red,
                  side: const BorderSide(color: PhColors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats Grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final PharmacySession session;
  const _StatsGrid({required this.session});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        _StatCard(
          label: 'Pending Orders',
          value: '${session.pendingOrderCount}',
          icon: Icons.pending_actions_outlined,
          iconColor: PhColors.pending,
          iconBg: PhColors.pendingLight,
          highlight: session.pendingOrderCount > 0,
        ),
        _StatCard(
          label: 'Stock Alerts',
          value: '${session.lowStockCount + session.outOfStockCount}',
          icon: Icons.warning_amber_outlined,
          iconColor: PhColors.outOfStock,
          iconBg: PhColors.outOfStockLight,
          highlight: session.outOfStockCount > 0,
        ),
        _StatCard(
          label: 'Today Revenue',
          value: session.todayRevenue > 0
              ? '৳${session.todayRevenue.toStringAsFixed(0)}'
              : '৳0',
          icon: Icons.payments_outlined,
          iconColor: PhColors.delivered,
          iconBg: PhColors.deliveredLight,
        ),
        _StatCard(
          label: 'Total Products',
          value: '${session.totalProducts}',
          icon: Icons.inventory_2_outlined,
          iconColor: PhColors.medicines,
          iconBg: PhColors.medicinesLight,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final bool highlight;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: phCard(highlight: highlight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: PhColors.textPrimary)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: PhColors.textSecondary,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Low Stock Section ─────────────────────────────────────────────────────────

class _LowStockSection extends StatelessWidget {
  final List<PharmacyProduct> products;
  const _LowStockSection({required this.products});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: PhColors.outOfStockLight,
                  borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.warning_amber,
                  color: PhColors.outOfStock, size: 14),
            ),
            const SizedBox(width: 8),
            const Text('Stock Alerts',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PhColors.textPrimary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: PhColors.outOfStockLight,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${products.length}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PhColors.outOfStock)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...products.map((p) => _LowStockRow(product: p)),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  final PharmacyProduct product;
  const _LowStockRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final isOut = product.stockStatus == StockStatus.outOfStock;
    final color = isOut ? PhColors.outOfStock : PhColors.lowStock;
    final bg = isOut ? PhColors.outOfStockLight : PhColors.lowStockLight;
    final label = isOut ? 'OUT' : 'LOW';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: phCard(borderColor: color.withValues(alpha: 0.3)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(product.name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PhColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('${product.stockCount} ${product.unit}',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Recent Orders Section ─────────────────────────────────────────────────────

class _RecentOrdersSection extends StatelessWidget {
  final List<PharmacyOrder> orders;
  const _RecentOrdersSection({required this.orders});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Orders',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: PhColors.textPrimary)),
        const SizedBox(height: 10),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: phCard(),
            child: const Center(
              child: Text('No orders yet',
                  style:
                      TextStyle(fontSize: 13, color: PhColors.textSecondary)),
            ),
          )
        else
          ...orders.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OrderRow(order: o),
              )),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  final PharmacyOrder order;
  const _OrderRow({required this.order});

  (Color, Color, String) get _statusAttrs => switch (order.status) {
        OrderStatus.pending => (
            PhColors.pendingLight,
            PhColors.pending,
            'Pending'
          ),
        OrderStatus.processing => (
            PhColors.processingLight,
            PhColors.processing,
            'Processing'
          ),
        OrderStatus.shipped => (
            PhColors.shippedLight,
            PhColors.shipped,
            'Shipped'
          ),
        OrderStatus.delivered => (
            PhColors.deliveredLight,
            PhColors.delivered,
            'Delivered'
          ),
        OrderStatus.cancelled => (
            PhColors.cancelledLight,
            PhColors.cancelled,
            'Cancelled'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _statusAttrs;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: phCard(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.orderNumber,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: PhColors.textPrimary)),
                const SizedBox(height: 2),
                Text(order.farmerName,
                    style: const TextStyle(
                        fontSize: 12, color: PhColors.textSecondary)),
                Text(
                    '${order.items.length} item(s) · ৳${order.totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, color: PhColors.grey)),
              ],
            ),
          ),
          phChip(label, bg, fg),
        ],
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onOpenInventory;
  const _QuickActions({required this.onOpenInventory});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: PhColors.textPrimary)),
        const SizedBox(height: 10),
        Row(
          children: [
            _ActionButton(
              icon: Icons.add_box_outlined,
              label: 'Add Stock',
              color: PhColors.secondary,
              onTap: onOpenInventory,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              icon: Icons.bar_chart_outlined,
              label: 'Revenue',
              color: PhColors.medicines,
              onTap: () => _showRevenueDialog(context),
            ),
            const SizedBox(width: 10),
            _ActionButton(
              icon: Icons.badge_outlined,
              label: 'License',
              color: PhColors.supplements,
              onTap: () => _showLicenseDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showRevenueDialog(BuildContext context) {
    final s = PharmacySession.instance;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revenue Summary',
            style: TextStyle(
                color: PhColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogRow(
                'Total Revenue', '৳${s.totalRevenue.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            _DialogRow(
                'Today',
                s.todayRevenue > 0
                    ? '৳${s.todayRevenue.toStringAsFixed(0)}'
                    : '৳0'),
            const SizedBox(height: 8),
            _DialogRow('Delivered Orders',
                '${s.orders.where((o) => o.status == OrderStatus.delivered).length}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: PhColors.secondary))),
        ],
      ),
    );
  }

  void _showLicenseDialog(BuildContext context) {
    final p = PharmacySession.instance.profile;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('License Info',
            style: TextStyle(
                color: PhColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogRow('Pharmacy', p.name),
            const SizedBox(height: 6),
            _DialogRow('License #', p.licenseNumber),
            const SizedBox(height: 6),
            _DialogRow('Location', p.location),
            const SizedBox(height: 6),
            _DialogRow('Phone', p.phone),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: PhColors.secondary))),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: phCard(borderColor: PhColors.red.withValues(alpha: .4)),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined, color: PhColors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: PhColors.textSecondary))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: phCard(),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PhColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogRow extends StatelessWidget {
  final String label;
  final String value;
  const _DialogRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: PhColors.textSecondary)),
        Flexible(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PhColors.textPrimary),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
