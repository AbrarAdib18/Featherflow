import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/profile_photo_field.dart';
import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import 'pharmacy_analytics_screen.dart';
import 'pharmacy_catalogue_screen.dart';
import 'pharmacy_inventory_screen.dart';
import 'pharmacy_orders_screen.dart';
import 'pharmacy_suppliers_screen.dart';

class PharmacyDashboardScreen extends StatefulWidget {
  const PharmacyDashboardScreen({super.key});

  @override
  State<PharmacyDashboardScreen> createState() => _PharmacyDashboardScreenState();
}

class _PharmacyDashboardScreenState extends State<PharmacyDashboardScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          _HomeTab(onGoto: (i) => setState(() => _index = i)),
          const PharmacyCatalogueScreen(),
          const PharmacyInventoryScreen(),
          const PharmacyOrdersScreen(),
          const PharmacySuppliersScreen(),
          const PharmacyAnalyticsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        ),
        child: NavigationBar(
          selectedIndex: _index > 4 ? 4 : _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: PhColors.bg,
          indicatorColor: PhColors.secondary.withValues(alpha: .15),
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: 'Catalogue'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
            NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Suppliers'),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final void Function(int) onGoto;
  const _HomeTab({required this.onGoto});

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
            elevation: 0,
            leadingWidth: 56,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ListenableBuilder(
                listenable: AuthService.instance,
                builder: (_, __) => ProfilePhotoField(
                  radius: 18,
                  showLabel: false,
                  currentUrl: AuthService
                          .instance.currentSession?.user.profilePhotoUrl ??
                      '',
                  fallbackInitial: s.profile.name.isNotEmpty
                      ? s.profile.name[0].toUpperCase()
                      : 'P',
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.profile.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(s.profile.location,
                    style: const TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.analytics_outlined),
                tooltip: 'Analytics',
                onPressed: () => onGoto(5),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () async {
                  await AuthService.instance.clearSession();
                  if (context.mounted) context.go(AppRoutes.login);
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: s.refresh,
            color: PhColors.secondary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (s.errorMessage != null)
                  _Banner(
                    icon: Icons.cloud_off_outlined,
                    color: PhColors.red,
                    text: s.errorMessage!,
                    onTap: s.refresh,
                  ),
                if (s.criticalAlerts.isNotEmpty)
                  _Banner(
                    icon: Icons.warning_amber_rounded,
                    color: PhColors.red,
                    text:
                        '${s.criticalAlerts.length} medicine(s) expire within 7 days — review the Inventory tab.',
                    onTap: () => onGoto(2),
                  ),
                if (s.pendingApprovalCount > 0)
                  _Banner(
                    icon: Icons.hourglass_bottom,
                    color: PhColors.amber,
                    text:
                        '${s.pendingApprovalCount} prescription medicine(s) awaiting admin approval.',
                    onTap: () => onGoto(1),
                  ),
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.7,
                  children: [
                    _StatCard('Total Products', '${s.totalProducts}',
                        Icons.medication_outlined, PhColors.medicines, PhColors.medicinesLight,
                        onTap: () => onGoto(1)),
                    _StatCard('Low Stock', '${s.lowStockCount}',
                        Icons.trending_down, PhColors.lowStock, PhColors.lowStockLight,
                        highlight: s.lowStockCount > 0, onTap: () => onGoto(2)),
                    _StatCard('Out of Stock', '${s.outOfStockCount}',
                        Icons.remove_shopping_cart_outlined, PhColors.outOfStock, PhColors.outOfStockLight,
                        highlight: s.outOfStockCount > 0, onTap: () => onGoto(2)),
                    _StatCard('Expiring Soon', '${s.expiringSoonCount}',
                        Icons.event_busy_outlined, PhColors.amber, PhColors.lowStockLight,
                        highlight: s.criticalExpiryCount > 0, onTap: () => onGoto(2)),
                    _StatCard('Incoming Orders', '${s.incomingOrderCount}',
                        Icons.inbox_outlined, PhColors.pending, PhColors.pendingLight,
                        highlight: s.incomingOrderCount > 0, onTap: () => onGoto(3)),
                    _StatCard('Active Deliveries', '${s.activeDeliveryCount}',
                        Icons.local_shipping_outlined, PhColors.shipped, PhColors.shippedLight,
                        onTap: () => onGoto(3)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Recent Orders',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
                const SizedBox(height: 10),
                if (s.recentOrders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: phCard(),
                    child: const Center(
                        child: Text('No orders yet',
                            style: TextStyle(fontSize: 13, color: PhColors.textSecondary))),
                  )
                else
                  ...s.recentOrders.take(5).map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OrderRow(order: o, onTap: () => onGoto(3)),
                      )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bg;
  final bool highlight;
  final VoidCallback? onTap;
  const _StatCard(this.label, this.value, this.icon, this.color, this.bg,
      {this.highlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: phCard(highlight: highlight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 17),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: PhColors.textPrimary)),
                Text(label,
                    style: const TextStyle(fontSize: 10, color: PhColors.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final CatalogueOrder order;
  final VoidCallback onTap;
  const _OrderRow({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = orderStatusColors(order.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: phCard(),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.orderNumber,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(order.farmerName,
                      style: const TextStyle(fontSize: 12, color: PhColors.textSecondary)),
                  Text('${order.itemsCount} item(s) · ৳${order.totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: PhColors.grey)),
                ],
              ),
            ),
            phChip(order.status.label, bg, fg),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  const _Banner({required this.icon, required this.color, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: phCard(borderColor: color.withValues(alpha: .4)),
            child: Row(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 11.5, color: PhColors.textSecondary, height: 1.3)),
              ),
              const Icon(Icons.chevron_right, color: PhColors.grey, size: 18),
            ]),
          ),
        ),
      );
}

(Color, Color) orderStatusColors(PharmacyOrderStatus s) => switch (s) {
      PharmacyOrderStatus.pending => (PhColors.pendingLight, PhColors.pending),
      PharmacyOrderStatus.preparing => (PhColors.processingLight, PhColors.processing),
      PharmacyOrderStatus.readyForDelivery => (PhColors.shippedLight, PhColors.shipped),
      PharmacyOrderStatus.outForDelivery => (PhColors.shippedLight, PhColors.shipped),
      PharmacyOrderStatus.delivered => (PhColors.deliveredLight, PhColors.delivered),
      PharmacyOrderStatus.cancelled => (PhColors.cancelledLight, PhColors.cancelled),
      PharmacyOrderStatus.refunded => (PhColors.cancelledLight, PhColors.cancelled),
      PharmacyOrderStatus.deliveryFailed => (PhColors.outOfStockLight, PhColors.outOfStock),
    };
