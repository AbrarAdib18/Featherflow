import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/status_stepper.dart';
import '../widgets/pharmacy_flag_banner.dart';
import 'delivery_detail_screen.dart';

class DeliveryOrdersScreen extends StatefulWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  State<DeliveryOrdersScreen> createState() => _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _acceptOrder(DeliveryOrder order) async {
    try {
      await DeliverySession.instance.respondToRequest(order.id, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
      return;
    }
    if (!mounted) return;
    _tabController.animateTo(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Order #${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()} accepted'),
        backgroundColor: DColors.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _rejectOrder(DeliveryOrder order) async {
    try {
      await DeliverySession.instance.respondToRequest(order.id, false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Order #${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()} rejected'),
        backgroundColor: DColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _progressActiveOrder(DeliveryOrder activeOrder) async {
    final nextStatus = switch (activeOrder.status) {
      OrderStatus.accepted => OrderStatus.pickedUp,
      OrderStatus.pickedUp => OrderStatus.onTheWay,
      OrderStatus.onTheWay => OrderStatus.delivered,
      _ => activeOrder.status,
    };
    String? otpCode;
    if (nextStatus == OrderStatus.delivered) {
      if (activeOrder.requiresOtp) {
        otpCode = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('Enter delivery OTP'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(hintText: '6-digit code'),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
        if (otpCode == null || otpCode.isEmpty || !mounted) return;
      }
      // Always require one final explicit approval before the delivery is
      // actually marked complete — OTP entry alone should not finish it.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.check_circle_outline, color: DColors.secondary),
            SizedBox(width: 10),
            Expanded(child: Text('Confirm Delivery')),
          ]),
          content: const Text(
              'Are you sure you want to mark this order as delivered? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not Yet')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Yes, Delivered'),
              style: FilledButton.styleFrom(
                  backgroundColor: DColors.secondary,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await DeliverySession.instance
          .updateOrderStatus(activeOrder.id, nextStatus, otpCode: otpCode);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeliverySession.instance,
      builder: (context, _) {
        final session = DeliverySession.instance;
        return Scaffold(
          backgroundColor: DColors.bg,
          appBar: AppBar(
            backgroundColor: DColors.appBar,
            elevation: 0,
            title: const Text(
              'Orders',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('New'),
                      if (session.requests.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${session.requests.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Active'),
                const Tab(text: 'Completed'),
                const Tab(text: 'History'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildNewOrders(session),
              _buildActiveOrder(session),
              _buildCompletedOrders(session),
              _buildHistory(session),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewOrders(DeliverySession session) {
    if (session.requests.isEmpty) {
      return _emptyState(Icons.inbox_outlined, 'No new orders');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: session.requests.length,
      itemBuilder: (_, i) {
        final order = session.requests[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrderCard(
              order: order,
              showActions: true,
              onAccept: () => _acceptOrder(order),
              onReject: () => _rejectOrder(order),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DeliveryDetailScreen(order: order)),
              ),
            ),
            if (order.expiresAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 8),
                child: _ExpiryCountdown(expiresAt: order.expiresAt!),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActiveOrder(DeliverySession session) {
    final activeOrder = session.activeOrder;
    if (activeOrder == null) {
      return _emptyState(Icons.local_shipping_outlined, 'No active delivery');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activeOrder.type == OrderType.pharmacy) ...[
            const PharmacyFlagBanner(),
            const SizedBox(height: 14),
          ],
          Container(
            decoration: dCard(highlight: true),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                        '#${activeOrder.id.substring(0, activeOrder.id.length > 8 ? 8 : activeOrder.id.length).toUpperCase()}',
                        style: const TextStyle(
                            color: DColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _statusBadge(activeOrder.status),
                  ],
                ),
                const SizedBox(height: 16),
                StatusStepper(currentStatus: activeOrder.status),
                const SizedBox(height: 16),
                _infoRow(Icons.radio_button_checked, DColors.accent,
                    activeOrder.pickupAddress),
                const SizedBox(height: 6),
                _infoRow(
                    Icons.location_on, DColors.red, activeOrder.dropAddress),
                const SizedBox(height: 6),
                _infoRow(Icons.person_outline, DColors.primary,
                    activeOrder.customerName),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (activeOrder.status != OrderStatus.delivered)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _progressActiveOrder(activeOrder),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  _nextActionLabel(activeOrder.status),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: DColors.accentLight,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: DColors.accent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: DColors.accent, size: 18),
                  SizedBox(width: 8),
                  Text('Delivery Completed',
                      style: TextStyle(
                          color: DColors.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletedOrders(DeliverySession session) {
    if (session.completedOrders.isEmpty) {
      return _emptyState(
          Icons.check_circle_outline, 'No completed orders today');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: session.completedOrders.length,
      itemBuilder: (_, i) => OrderCard(
        order: session.completedOrders[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  DeliveryDetailScreen(order: session.completedOrders[i])),
        ),
      ),
    );
  }

  Widget _buildHistory(DeliverySession session) => const _HistoryTab();

  Widget _infoRow(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: DColors.textSecondary, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _emptyState(IconData icon, String label) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: DColors.greyDark, size: 48),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: DColors.textSecondary, fontSize: 14)),
          ],
        ),
      );

  Widget _statusBadge(OrderStatus s) {
    final (label, bg, fg) = switch (s) {
      OrderStatus.accepted => ('Accepted', DColors.accentLight, DColors.accent),
      OrderStatus.pickedUp => (
          'Picked Up',
          DColors.accentLight,
          DColors.accent
        ),
      OrderStatus.onTheWay => (
          'On The Way',
          DColors.accentLight,
          DColors.accentMid
        ),
      OrderStatus.delivered => (
          'Delivered',
          DColors.accentLight,
          DColors.accent
        ),
      _ => ('Pending', DColors.orangeLight, DColors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  String _nextActionLabel(OrderStatus s) => switch (s) {
        OrderStatus.accepted => 'Mark as Picked Up',
        OrderStatus.pickedUp => 'On The Way',
        OrderStatus.onTheWay => 'Mark Delivered',
        _ => 'Update Status',
      };
}

class _ExpiryCountdown extends StatefulWidget {
  final DateTime expiresAt;
  const _ExpiryCountdown({required this.expiresAt});

  @override
  State<_ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<_ExpiryCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    final expired = remaining.isNegative;
    final seconds = remaining.inSeconds.clamp(0, 999);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 12, color: expired ? DColors.red : DColors.orange),
        const SizedBox(width: 4),
        Text(
          expired ? 'Offer expiring…' : 'Expires in ${seconds}s',
          style: TextStyle(
              color: expired ? DColors.red : DColors.orange,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  static const _filters = [
    (null, 'All'),
    ('delivered', 'Delivered'),
    ('failed', 'Failed'),
    ('cancelled', 'Cancelled'),
    ('rejected', 'Rejected'),
  ];

  String? _status;
  final List<DeliveryOrder> _items = [];
  int _offset = 0;
  static const _limit = 20;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    if (reset) {
      _offset = 0;
      _items.clear();
      _hasMore = true;
    }
    try {
      final page = await DeliverySession.instance
          .fetchHistory(status: _status, limit: _limit, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _limit;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _filters
                .map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _status == f.$1,
                        onSelected: (_) {
                          setState(() => _status = f.$1);
                          _load(reset: true);
                        },
                        selectedColor: DColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                            color: _status == f.$1 ? DColors.primary : DColors.textSecondary),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, color: DColors.greyDark, size: 48),
                      SizedBox(height: 12),
                      Text('No order history',
                          style: TextStyle(color: DColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator(color: DColors.accent)
                              : TextButton(
                                  onPressed: () => _load(),
                                  child: const Text('Load more'),
                                ),
                        ),
                      );
                    }
                    final order = _items[i];
                    return OrderCard(
                      order: order,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DeliveryDetailScreen(order: order)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
