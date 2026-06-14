import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../delivery_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/status_stepper.dart';
import '../widgets/pharmacy_flag_banner.dart';
import 'delivery_detail_screen.dart';

class DeliveryOrdersScreen extends StatefulWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  State<DeliveryOrdersScreen> createState() =>
      _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // TODO: replace with API call
  final List<DeliveryOrder> _newOrders = [
    DeliveryOrder(
      id: 'FF-2024-0051',
      pickupAddress: 'Karwan Bazar Pharmacy, Dhaka',
      dropAddress: 'Badda Poultry Farm, Dhaka',
      customerName: 'Hasan Agro',
      customerPhone: '01812345678',
      distanceKm: 6.8,
      type: OrderType.pharmacy,
      status: OrderStatus.pending,
      items: [
        const OrderItem(name: 'Enrofloxacin 10%', quantity: 2),
        const OrderItem(name: 'Vitamin AD3E', quantity: 1),
      ],
      requiresOtp: true,
      earning: 180.0,
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    DeliveryOrder(
      id: 'FF-2024-0050',
      pickupAddress: 'Farmgate Agro, Dhaka',
      dropAddress: 'Uttara Poultry Hub, Dhaka',
      customerName: 'Karim Farm',
      customerPhone: '01912345678',
      distanceKm: 9.1,
      type: OrderType.regular,
      status: OrderStatus.pending,
      items: [
        const OrderItem(name: 'Layer Feed (50kg)', quantity: 4)
      ],
      requiresOtp: false,
      earning: 220.0,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  // TODO: replace with API call
  DeliveryOrder _activeOrder = DeliveryOrder(
    id: 'FF-2024-0042',
    pickupAddress: 'Farmgate Agro Market, Dhaka',
    dropAddress: 'Mirpur-10 Poultry Hub, Dhaka',
    customerName: 'Rahman Poultry Farm',
    customerPhone: '01712345678',
    distanceKm: 4.2,
    type: OrderType.regular,
    status: OrderStatus.accepted,
    items: [
      const OrderItem(name: 'Broiler Feed (50kg)', quantity: 2),
      const OrderItem(name: 'Vitamin Supplement', quantity: 3),
    ],
    requiresOtp: false,
    earning: 120.0,
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
  );

  // TODO: replace with API call
  final List<DeliveryOrder> _completedOrders = [
    DeliveryOrder(
      id: 'FF-2024-0041',
      pickupAddress: 'Mirpur Agro, Dhaka',
      dropAddress: 'Gulshan Farm, Dhaka',
      customerName: 'Alam Poultry',
      customerPhone: '01612345678',
      distanceKm: 5.3,
      type: OrderType.regular,
      status: OrderStatus.delivered,
      items: [const OrderItem(name: 'Chick Feed', quantity: 3)],
      requiresOtp: false,
      earning: 140.0,
      createdAt:
          DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  // TODO: replace with API call
  final List<DeliveryOrder> _historyOrders = [
    DeliveryOrder(
      id: 'FF-2024-0035',
      pickupAddress: 'Tejgaon Pharmacy',
      dropAddress: 'Rayer Bazar Farm',
      customerName: 'Noor Farm',
      customerPhone: '01512345678',
      distanceKm: 3.2,
      type: OrderType.pharmacy,
      status: OrderStatus.delivered,
      items: [
        const OrderItem(name: 'Tylosin 50%', quantity: 1)
      ],
      requiresOtp: true,
      earning: 95.0,
      createdAt:
          DateTime.now().subtract(const Duration(days: 1)),
    ),
    DeliveryOrder(
      id: 'FF-2024-0031',
      pickupAddress: 'Wari Agro',
      dropAddress: 'Demra Farm',
      customerName: 'Islam Poultry',
      customerPhone: '01412345678',
      distanceKm: 7.8,
      type: OrderType.regular,
      status: OrderStatus.cancelled,
      items: [const OrderItem(name: 'Layer Feed', quantity: 2)],
      requiresOtp: false,
      earning: 0.0,
      createdAt:
          DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

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

  void _acceptOrder(DeliveryOrder order) {
    setState(() => _newOrders.remove(order));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Order #${order.id} accepted'),
        backgroundColor: DColors.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _rejectOrder(DeliveryOrder order) {
    setState(() => _newOrders.remove(order));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Order #${order.id} rejected'),
        backgroundColor: DColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _progressActiveOrder() {
    final nextStatus = switch (_activeOrder.status) {
      OrderStatus.accepted => OrderStatus.pickedUp,
      OrderStatus.pickedUp => OrderStatus.onTheWay,
      OrderStatus.onTheWay => OrderStatus.delivered,
      _ => _activeOrder.status,
    };
    setState(
        () => _activeOrder = _activeOrder.copyWith(status: nextStatus));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        title: const Text(
          'Orders',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.white,
          indicatorWeight: 2,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w400),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('New'),
                  if (_newOrders.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_newOrders.length}',
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
          _buildNewOrders(),
          _buildActiveOrder(),
          _buildCompletedOrders(),
          _buildHistory(),
        ],
      ),
    );
  }

  Widget _buildNewOrders() {
    if (_newOrders.isEmpty) {
      return _emptyState(Icons.inbox_outlined, 'No new orders');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _newOrders.length,
      itemBuilder: (_, i) {
        final order = _newOrders[i];
        return OrderCard(
          order: order,
          showActions: true,
          onAccept: () => _acceptOrder(order),
          onReject: () => _rejectOrder(order),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DeliveryDetailScreen(order: order)),
          ),
        );
      },
    );
  }

  Widget _buildActiveOrder() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activeOrder.type == OrderType.pharmacy) ...[
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
                    Text('#${_activeOrder.id}',
                        style: const TextStyle(
                            color: DColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _statusBadge(_activeOrder.status),
                  ],
                ),
                const SizedBox(height: 16),
                StatusStepper(currentStatus: _activeOrder.status),
                const SizedBox(height: 16),
                _infoRow(Icons.radio_button_checked, DColors.accent,
                    _activeOrder.pickupAddress),
                const SizedBox(height: 6),
                _infoRow(Icons.location_on, DColors.red,
                    _activeOrder.dropAddress),
                const SizedBox(height: 6),
                _infoRow(Icons.person_outline, DColors.primary,
                    _activeOrder.customerName),
                if (_activeOrder.requiresOtp) ...[
                  const SizedBox(height: 14),
                  const Text('OTP Handover',
                      style: TextStyle(
                          color: DColors.textSecondary,
                          fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                        color: DColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter 6-digit OTP',
                      hintStyle: const TextStyle(
                          color: DColors.grey),
                      filled: true,
                      fillColor: DColors.surface2,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: DColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: DColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: DColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_activeOrder.status != OrderStatus.delivered)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _progressActiveOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  _nextActionLabel(_activeOrder.status),
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
                border: Border.all(
                    color: DColors.accent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle,
                      color: DColors.accent, size: 18),
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

  Widget _buildCompletedOrders() {
    if (_completedOrders.isEmpty) {
      return _emptyState(
          Icons.check_circle_outline, 'No completed orders today');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _completedOrders.length,
      itemBuilder: (_, i) => OrderCard(
        order: _completedOrders[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  DeliveryDetailScreen(order: _completedOrders[i])),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_historyOrders.isEmpty) {
      return _emptyState(Icons.history, 'No order history');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _historyOrders.length,
      itemBuilder: (_, i) => OrderCard(
        order: _historyOrders[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  DeliveryDetailScreen(order: _historyOrders[i])),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: DColors.textSecondary, fontSize: 13),
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
      OrderStatus.accepted =>
        ('Accepted', DColors.accentLight, DColors.accent),
      OrderStatus.pickedUp =>
        ('Picked Up', DColors.accentLight, DColors.accent),
      OrderStatus.onTheWay =>
        ('On The Way', DColors.accentLight, DColors.accentMid),
      OrderStatus.delivered =>
        ('Delivered', DColors.accentLight, DColors.accent),
      _ => ('Pending', DColors.orangeLight, DColors.orange),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    );
  }

  String _nextActionLabel(OrderStatus s) => switch (s) {
        OrderStatus.accepted => 'Mark as Picked Up',
        OrderStatus.pickedUp => 'On The Way',
        OrderStatus.onTheWay => 'Mark Delivered',
        _ => 'Update Status',
      };
}
