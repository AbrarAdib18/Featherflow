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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: _statuses.map((s) => _OrdersList(status: s)).toList(),
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
    return RefreshIndicator(
      onRefresh: PharmacySession.instance.refresh,
      color: PhColors.secondary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderCard(order: orders[i]),
        ),
      ),
    );
  }
}

// ── Order Card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final PharmacyOrder order;
  const _OrderCard({required this.order});

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
      decoration: phCard(
          borderColor: order.status == OrderStatus.pending
              ? PhColors.pending.withValues(alpha: 0.35)
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        const Icon(Icons.notes, size: 13, color: PhColors.grey),
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
                const SizedBox(height: 12),
                _OrderProgress(status: order.status),
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
                onPressed: () => _updateStatus(context, OrderStatus.processing),
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
              child: OutlinedButton.icon(
                onPressed: () => _updateStatus(context, OrderStatus.pending),
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Back to Pending',
                    style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PhColors.pending,
                  side:
                      BorderSide(color: PhColors.pending.withValues(alpha: .5)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _updateStatus(context, OrderStatus.shipped),
                icon: const Icon(Icons.local_shipping_outlined, size: 14),
                label:
                    const Text('Mark Shipped', style: TextStyle(fontSize: 12)),
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
      OrderStatus.shipped => Row(children: [
          Expanded(
              child: OutlinedButton.icon(
            onPressed: () => _updateStatus(context, OrderStatus.processing),
            icon: const Icon(Icons.undo, size: 14),
            label: const Text('Return to Processing',
                style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: PhColors.processing,
              side:
                  BorderSide(color: PhColors.processing.withValues(alpha: .5)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: ElevatedButton.icon(
            onPressed: () => _updateStatus(context, OrderStatus.delivered),
            icon: const Icon(Icons.check_circle_outline, size: 14),
            label: const Text('Mark Delivered', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: PhColors.delivered,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          )),
        ]),
      _ => const SizedBox.shrink(),
    };
  }

  Future<void> _updateStatus(
      BuildContext context, OrderStatus newStatus) async {
    final messageController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PhColors.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: PhColors.cardBorder),
        ),
        title: Row(children: [
          CircleAvatar(
            backgroundColor: newStatus == OrderStatus.delivered
                ? PhColors.deliveredLight
                : PhColors.processingLight,
            child: Icon(
                newStatus == OrderStatus.delivered
                    ? Icons.check_circle_outline
                    : Icons.sync_alt,
                color: newStatus == OrderStatus.delivered
                    ? PhColors.delivered
                    : PhColors.processing),
          ),
          const SizedBox(width: 12),
          Text(
              newStatus == OrderStatus.delivered
                  ? 'Confirm Delivery'
                  : 'Update Order Status',
              style: const TextStyle(
                  color: PhColors.textPrimary, fontWeight: FontWeight.w700)),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_statusName(order.status)}  →  ${_statusName(newStatus)}',
                    style: const TextStyle(
                        color: PhColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                    newStatus == OrderStatus.delivered
                        ? 'Are you sure this order has been delivered? Confirming will complete the order and notify the farmer.'
                        : 'The farmer will receive this update in their notification bar.',
                    style: const TextStyle(
                        color: PhColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  style: phFieldText,
                  minLines: 2,
                  maxLines: 4,
                  autofocus: true,
                  decoration: phInput('Message / reason for this change',
                      Icons.message_outlined),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: newStatus == OrderStatus.cancelled
                    ? PhColors.cancelled
                    : PhColors.secondary,
                foregroundColor: Colors.white),
            onPressed: () {
              if (messageController.text.trim().isEmpty) {
                showPharmacyNotice(
                    dialogContext,
                    'Please enter a message explaining the status change.',
                    PhColors.red,
                    Icons.error_outline);
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Confirm Update'),
          ),
        ],
      ),
    );
    final message = messageController.text.trim();
    messageController.dispose();
    if (confirmed != true || !context.mounted) return;
    try {
      await PharmacySession.instance
          .updateOrderStatus(order.id, newStatus, message);
    } catch (error) {
      if (context.mounted) {
        showPharmacyNotice(
            context, error.toString(), PhColors.red, Icons.error_outline);
      }
      return;
    }
    if (!context.mounted) return;
    final label = switch (newStatus) {
      OrderStatus.processing => 'Order moved to Processing.',
      OrderStatus.pending => 'Order returned to Pending.',
      OrderStatus.shipped => 'Order marked as Shipped.',
      OrderStatus.delivered => 'Order marked as Delivered.',
      OrderStatus.cancelled => 'Order cancelled.',
    };
    final color = switch (newStatus) {
      OrderStatus.delivered => PhColors.delivered,
      OrderStatus.cancelled => PhColors.cancelled,
      _ => PhColors.primary,
    };
    final icon = newStatus == OrderStatus.delivered
        ? Icons.check_circle_outline
        : newStatus == OrderStatus.cancelled
            ? Icons.cancel_outlined
            : Icons.sync_alt;
    showPharmacyNotice(context, label, color, icon);
  }

  String _statusName(OrderStatus status) => switch (status) {
        OrderStatus.pending => 'Pending',
        OrderStatus.processing => 'Processing',
        OrderStatus.shipped => 'Shipped',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
      };
}

class _OrderProgress extends StatelessWidget {
  final OrderStatus status;
  const _OrderProgress({required this.status});
  @override
  Widget build(BuildContext context) {
    const steps = [
      OrderStatus.pending,
      OrderStatus.processing,
      OrderStatus.shipped,
      OrderStatus.delivered
    ];
    if (status == OrderStatus.cancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
            color: PhColors.cancelledLight,
            borderRadius: BorderRadius.circular(8)),
        child: const Text('Order Cancelled',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: PhColors.cancelled,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
    }
    final current = steps.indexOf(status);
    return Row(
        children: List.generate(steps.length, (index) {
      final done = index <= current;
      final label = ['Pending', 'Processing', 'Shipped', 'Delivered'][index];
      return Expanded(
          child: Column(children: [
        Row(children: [
          if (index > 0)
            Expanded(
                child: Container(
                    height: 2,
                    color: done ? PhColors.secondary : PhColors.cardBorder)),
          Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? PhColors.secondary : PhColors.surface2,
                  border: Border.all(
                      color: done ? PhColors.secondary : PhColors.cardBorder)),
              child: done
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null),
          if (index < steps.length - 1)
            Expanded(
                child: Container(
                    height: 2,
                    color: index < current
                        ? PhColors.secondary
                        : PhColors.cardBorder)),
        ]),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                color: done ? PhColors.secondary : PhColors.grey)),
      ]));
    }));
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
              size: 52, color: PhColors.grey.withValues(alpha: 0.4)),
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
