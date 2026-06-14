import 'package:flutter/material.dart';
import '../../data/models/pharmacy_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';

class PharmacyOrdersScreen extends StatefulWidget {
  const PharmacyOrdersScreen({super.key});

  @override
  State<PharmacyOrdersScreen> createState() => _PharmacyOrdersScreenState();
}

class _PharmacyOrdersScreenState extends State<PharmacyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _statuses = [
    null, // All
    OrderStatus.pending,
    OrderStatus.processing,
    OrderStatus.shipped,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  static const _tabLabels = [
    'All',
    'Pending',
    'Processing',
    'Shipped',
    'Delivered',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

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
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                const Text('Orders',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _PendingBadge(
                    count: PharmacySession.instance.pendingOrderCount),
              ],
            ),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: PhColors.secondary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: _statuses
                .map((s) => _OrdersList(status: s))
                .toList(),
          ),
        );
      },
    );
  }
}

// ── Pending Badge ─────────────────────────────────────────────────────────────

class _PendingBadge extends StatelessWidget {
  final int count;
  const _PendingBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: PhColors.pending, borderRadius: BorderRadius.circular(10)),
      child: Text('$count',
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

// ── Orders List ───────────────────────────────────────────────────────────────

class _OrdersList extends StatelessWidget {
  final OrderStatus? status;
  const _OrdersList({this.status});

  @override
  Widget build(BuildContext context) {
    final orders = PharmacySession.instance.filteredOrders(status);
    if (orders.isEmpty) return const _EmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _OrderCard(order: orders[i]),
      ),
    );
  }
}

// ── Order Card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final PharmacyOrder order;
  const _OrderCard({required this.order});

  (Color, Color, String) get _statusAttrs => switch (order.status) {
        OrderStatus.pending =>
          (PhColors.pendingLight, PhColors.pending, 'Pending'),
        OrderStatus.processing =>
          (PhColors.processingLight, PhColors.processing, 'Processing'),
        OrderStatus.shipped =>
          (PhColors.shippedLight, PhColors.shipped, 'Shipped'),
        OrderStatus.delivered =>
          (PhColors.deliveredLight, PhColors.delivered, 'Delivered'),
        OrderStatus.cancelled =>
          (PhColors.cancelledLight, PhColors.cancelled, 'Cancelled'),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = _statusAttrs;

    return Container(
      decoration: phCard(
          borderColor:
              order.status == OrderStatus.pending ? PhColors.pending.withValues(alpha: 0.35) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(order.orderNumber,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: PhColors.textPrimary)),
                const Spacer(),
                phChip(label, bg, fg),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Farmer info
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: PhColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(order.farmerName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PhColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 14, color: PhColors.grey),
                    const SizedBox(width: 6),
                    Text(order.farmName,
                        style: const TextStyle(
                            fontSize: 12, color: PhColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: PhColors.grey),
                    const SizedBox(width: 6),
                    Text(_formatDate(order.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: PhColors.grey)),
                  ],
                ),
                if (order.notes != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: PhColors.surface2,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes,
                            size: 13, color: PhColors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(order.notes!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: PhColors.textSecondary,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // Items list
                ...order.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 5, color: PhColors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item.productName,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: PhColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                              '${item.quantity} × ৳${item.unitPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: PhColors.grey,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )),
                const Divider(color: PhColors.divider, height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PhColors.textPrimary)),
                    Text('৳${order.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: PhColors.textPrimary)),
                  ],
                ),
                // Actions
                if (order.status != OrderStatus.delivered &&
                    order.status != OrderStatus.cancelled) ...[
                  const SizedBox(height: 12),
                  _ActionRow(order: order),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ── Action Row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final PharmacyOrder order;
  const _ActionRow({required this.order});

  @override
  Widget build(BuildContext context) {
    return switch (order.status) {
      OrderStatus.pending => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _updateStatus(context, OrderStatus.cancelled),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PhColors.cancelled,
                  side: BorderSide(
                      color: PhColors.cancelled.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () =>
                    _updateStatus(context, OrderStatus.processing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PhColors.processing,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text('Start Processing',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      OrderStatus.processing => Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _updateStatus(context, OrderStatus.shipped),
                icon: const Icon(Icons.local_shipping_outlined, size: 14),
                label: const Text('Mark Shipped',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PhColors.shipped,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      OrderStatus.shipped => Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _updateStatus(context, OrderStatus.delivered),
                icon: const Icon(Icons.check_circle_outline, size: 14),
                label: const Text('Mark Delivered',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PhColors.delivered,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      _ => const SizedBox.shrink(),
    };
  }

  void _updateStatus(BuildContext context, OrderStatus newStatus) {
    PharmacySession.instance.updateOrderStatus(order.id, newStatus);
    final label = switch (newStatus) {
      OrderStatus.processing => 'Order moved to Processing.',
      OrderStatus.shipped => 'Order marked as Shipped.',
      OrderStatus.delivered => 'Order marked as Delivered.',
      OrderStatus.cancelled => 'Order cancelled.',
      _ => 'Order updated.',
    };
    final color = switch (newStatus) {
      OrderStatus.delivered => PhColors.delivered,
      OrderStatus.cancelled => PhColors.cancelled,
      _ => PhColors.primary,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          Icon(Icons.receipt_long_outlined,
              size: 52,
              color: PhColors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('No orders here',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: PhColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Orders in this status will appear here.',
              style: TextStyle(fontSize: 13, color: PhColors.grey)),
        ],
      ),
    );
  }
}
