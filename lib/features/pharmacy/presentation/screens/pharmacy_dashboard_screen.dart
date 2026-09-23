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
import 'pharmacy_profile_screen.dart';
import 'pharmacy_suppliers_screen.dart';

class PharmacyDashboardScreen extends StatefulWidget {
  const PharmacyDashboardScreen({super.key});

  @override
  State<PharmacyDashboardScreen> createState() => _PharmacyDashboardScreenState();
}

/// Single AppBar (avatar, name/location, sign-out) + a bottom [NavigationBar]
/// for all six pharmacy sections. A horizontal *top* TabBar was tried first,
/// but real usage showed the bottom is where this app's users expect the
/// primary navigation to live — moved back per that feedback. Still just one
/// navigation surface covering all six sections (the original bottom nav
/// only had 5; Analytics was a separate AppBar icon action, an inconsistent
/// second surface) and each section still renders content-only when
/// embedded, so there's no duplicate AppBar underneath this one.
class _PharmacyDashboardScreenState extends State<PharmacyDashboardScreen> {
  int _index = 0;

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
            leadingWidth: 52,
            leading: Center(
              child: GestureDetector(
                // Not editable here — at this small header size the widget's
                // camera-badge overlay (sized for its usual 24-42px radius
                // uses elsewhere) is nearly as big as the avatar itself and
                // hides the pharmacy's logo/photo behind it. Tapping it
                // instead opens the full-size Profile tab, where the photo
                // actually is editable — that's the "edit profile" entry
                // point, not a cramped camera badge crammed into the AppBar.
                onTap: () => setState(() => _index = 6),
                child: ListenableBuilder(
                  listenable: AuthService.instance,
                  builder: (_, __) => ProfilePhotoField(
                    radius: 17,
                    showLabel: false,
                    editable: false,
                    currentUrl: AuthService
                            .instance.currentSession?.user.profilePhotoUrl ??
                        '',
                    fallbackIcon: Icons.local_pharmacy_outlined,
                  ),
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
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () async {
                  await AuthService.instance.clearSession();
                  if (context.mounted) context.go(AppRoutes.login);
                },
              ),
            ],
          ),
          body: IndexedStack(
            index: _index,
            children: [
              _HomeTab(onGoto: (i) => setState(() => _index = i)),
              const PharmacyCatalogueScreen(embedded: true),
              const PharmacyInventoryScreen(embedded: true),
              const PharmacyOrdersScreen(embedded: true),
              const PharmacySuppliersScreen(embedded: true),
              const PharmacyAnalyticsScreen(embedded: true),
              const PharmacyProfileScreen(embedded: true),
            ],
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              backgroundColor: PhColors.bg,
              indicatorColor: PhColors.secondary.withValues(alpha: .15),
              height: 64,
              // 7 destinations with always-visible labels got cramped at
              // narrow widths (320px) — only the selected item's label shows
              // now, unselected ones stay icon-only, a standard pattern for
              // nav bars with more than ~5 items.
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication), label: 'Catalogue'),
                NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
                NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Orders'),
                NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Suppliers'),
                NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'Analytics'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dashboard overview content. Embedded directly in the shell's TabBarView —
/// no Scaffold/AppBar of its own (the shell provides one shared AppBar+TabBar
/// for all six sections now).
class _HomeTab extends StatelessWidget {
  final void Function(int) onGoto;
  const _HomeTab({required this.onGoto});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        return RefreshIndicator(
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
