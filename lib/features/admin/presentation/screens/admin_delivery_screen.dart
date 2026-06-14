import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';

class AdminDeliveryScreen extends StatefulWidget {
  const AdminDeliveryScreen({super.key});

  @override
  State<AdminDeliveryScreen> createState() => _AdminDeliveryScreenState();
}

class _AdminDeliveryScreenState extends State<AdminDeliveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_OrderData> _orders;
  late List<_RiderData> _riders;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _orders = List.of(_kOrders);
    _riders = List.of(_kRiders);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _assignRider(String orderId, String riderName) {
    setState(() {
      final i = _orders.indexWhere((o) => o.id == orderId);
      if (i >= 0) {
        _orders[i] = _orders[i].copyWith(
            assignedRider: riderName, status: 'Assigned');
      }
    });
    AuditService.instance
        .log('Delivery Management', 'Assign', orderId, details: riderName);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Order $orderId assigned to $riderName'),
      backgroundColor: AColors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  void _flagOrder(String orderId) {
    setState(() {
      final i = _orders.indexWhere((o) => o.id == orderId);
      if (i >= 0) _orders[i] = _orders[i].copyWith(status: 'Flagged');
    });
    AuditService.instance.log('Delivery Management', 'Flag', orderId);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Delivery Management',
      module: AdminModule.deliveryManagement,
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Active Orders'),
                Tab(text: 'Riders'),
                Tab(text: 'Issues'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _OrdersTab(
                    orders: _orders,
                    riders: _riders,
                    onAssign: _assignRider,
                    onFlag: _flagOrder),
                _RidersTab(riders: _riders),
                _IssuesTab(orders: _orders
                    .where((o) =>
                        o.status == 'Delayed' || o.status == 'Failed')
                    .toList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Orders tab ────────────────────────────────────────────────────────────────

class _OrdersTab extends StatelessWidget {
  final List<_OrderData> orders;
  final List<_RiderData> riders;
  final void Function(String, String) onAssign;
  final void Function(String) onFlag;

  const _OrdersTab(
      {required this.orders,
      required this.riders,
      required this.onAssign,
      required this.onFlag});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _OrderCard(
          order: orders[i],
          riders: riders,
          onAssign: onAssign,
          onFlag: onFlag),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final _OrderData order;
  final List<_RiderData> riders;
  final void Function(String, String) onAssign;
  final void Function(String) onFlag;

  const _OrderCard(
      {required this.order,
      required this.riders,
      required this.onAssign,
      required this.onFlag});

  Color get _statusColor {
    switch (order.status) {
      case 'In Transit':
        return AColors.blue;
      case 'Assigned':
        return AColors.secondary;
      case 'Delayed':
        return AColors.orange;
      case 'Failed':
        return AColors.red;
      case 'Flagged':
        return AColors.purple;
      default:
        return AColors.amber;
    }
  }

  void _showAssignSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Assign Rider for ${order.id}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AColors.textPrimary)),
          ),
          const Divider(height: 1, color: AColors.divider),
          ...riders
              .where((r) => r.status == 'Online')
              .map((r) => ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AColors.secondary.withValues(alpha: 0.15),
                      child: Text(r.name[0],
                          style: const TextStyle(
                              color: AColors.secondary,
                              fontWeight: FontWeight.w700)),
                    ),
                    title: Text(r.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AColors.textPrimary)),
                    subtitle: Text('${r.activeOrders} active · ${r.zone}',
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                    trailing: aChip('Online', AColors.secondary, AColors.secondary),
                    onTap: () {
                      Navigator.pop(context);
                      onAssign(order.id, r.name);
                    },
                  )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(
          highlight:
              order.status == 'Delayed' || order.status == 'Failed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.id,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AColors.textPrimary)),
                    Text('${order.customer} → ${order.destination}',
                        style: const TextStyle(
                            fontSize: 11, color: AColors.textSecondary)),
                  ],
                ),
              ),
              aChip(order.status, _statusColor, _statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Pill(Icons.inventory_2_outlined, order.items, AColors.grey),
              const SizedBox(width: 10),
              _Pill(Icons.schedule, order.eta, AColors.blue),
              if (order.assignedRider != null) ...[
                const SizedBox(width: 10),
                _Pill(Icons.delivery_dining, order.assignedRider!, AColors.secondary),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (order.assignedRider == null)
                PermissionGuard(
                  module: AdminModule.deliveryManagement,
                  permission: AdminPermission.assign,
                  child: _Chip('Assign Rider', AColors.secondary,
                      () => _showAssignSheet(context)),
                ),
              if (order.assignedRider != null)
                PermissionGuard(
                  module: AdminModule.deliveryManagement,
                  permission: AdminPermission.assign,
                  child: _Chip('Reassign', AColors.blue,
                      () => _showAssignSheet(context)),
                ),
              const SizedBox(width: 8),
              PermissionGuard(
                module: AdminModule.deliveryManagement,
                permission: AdminPermission.edit,
                child: _Chip('Flag Issue', AColors.red,
                    () => onFlag(order.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Riders tab ────────────────────────────────────────────────────────────────

class _RidersTab extends StatelessWidget {
  final List<_RiderData> riders;

  const _RidersTab({required this.riders});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: riders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _RiderCard(riders[i]),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final _RiderData rider;
  const _RiderCard(this.rider);

  @override
  Widget build(BuildContext context) {
    final onlineColor =
        rider.status == 'Online' ? AColors.secondary : AColors.grey;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: onlineColor.withValues(alpha: 0.15),
            child: Text(rider.name[0],
                style: TextStyle(
                    color: onlineColor, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AColors.textPrimary)),
                Text('${rider.zone} · ${rider.activeOrders} active',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Pill(Icons.star_outline, rider.rating.toString(),
                        AColors.amber),
                    const SizedBox(width: 8),
                    _Pill(Icons.check_circle_outline,
                        '${rider.completedOrders} done', AColors.green),
                  ],
                ),
              ],
            ),
          ),
          aChip(rider.status, onlineColor, onlineColor),
        ],
      ),
    );
  }
}

// ── Issues tab ────────────────────────────────────────────────────────────────

class _IssuesTab extends StatelessWidget {
  final List<_OrderData> orders;

  const _IssuesTab({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
          child: Text('No issues at this time.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _IssueCard(orders[i]),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final _OrderData order;
  const _IssueCard(this.order);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: true),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AColors.redLight,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_amber_rounded,
                color: AColors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order ${order.id} — ${order.status}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AColors.textPrimary)),
                Text(order.customer,
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                Text('ETA was: ${order.eta}',
                    style: const TextStyle(
                        fontSize: 10, color: AColors.red)),
              ],
            ),
          ),
          PermissionGuard(
            module: AdminModule.deliveryManagement,
            permission: AdminPermission.edit,
            child: _Chip('Resolve', AColors.secondary, () {}),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Chip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _OrderData {
  final String id, customer, destination, items, eta, status;
  final String? assignedRider;

  const _OrderData({
    required this.id,
    required this.customer,
    required this.destination,
    required this.items,
    required this.eta,
    required this.status,
    this.assignedRider,
  });

  _OrderData copyWith({String? status, String? assignedRider}) => _OrderData(
        id: id,
        customer: customer,
        destination: destination,
        items: items,
        eta: eta,
        status: status ?? this.status,
        assignedRider: assignedRider ?? this.assignedRider,
      );
}

const _kOrders = [
  _OrderData(
      id: 'D-0041',
      customer: 'Karim Hossain',
      destination: 'Mirpur, Dhaka',
      items: '3 items',
      eta: 'Today 2:30 PM',
      status: 'In Transit',
      assignedRider: 'Rahim Uddin'),
  _OrderData(
      id: 'D-0042',
      customer: 'Hossain Farm',
      destination: 'Gazipur',
      items: '1 item',
      eta: 'Today 4:00 PM',
      status: 'Pending'),
  _OrderData(
      id: 'D-0039',
      customer: 'Green Valley Co.',
      destination: 'Narayanganj',
      items: '5 items',
      eta: 'Yesterday',
      status: 'Delayed',
      assignedRider: 'Jamal Mia'),
  _OrderData(
      id: 'D-0038',
      customer: 'Comilla Farm',
      destination: 'Comilla',
      items: '2 items',
      eta: '2 days ago',
      status: 'Failed'),
];

class _RiderData {
  final String name, zone, status;
  final double rating;
  final int activeOrders, completedOrders;

  const _RiderData({
    required this.name,
    required this.zone,
    required this.status,
    required this.rating,
    required this.activeOrders,
    required this.completedOrders,
  });
}

const _kRiders = [
  _RiderData(
      name: 'Rahim Uddin',
      zone: 'Dhaka North',
      status: 'Online',
      rating: 4.8,
      activeOrders: 2,
      completedOrders: 184),
  _RiderData(
      name: 'Jamal Mia',
      zone: 'Dhaka South',
      status: 'Online',
      rating: 4.2,
      activeOrders: 1,
      completedOrders: 97),
  _RiderData(
      name: 'Sumon Haque',
      zone: 'Narayanganj',
      status: 'Offline',
      rating: 4.5,
      activeOrders: 0,
      completedOrders: 213),
  _RiderData(
      name: 'Belal Ahmed',
      zone: 'Gazipur',
      status: 'Online',
      rating: 4.6,
      activeOrders: 1,
      completedOrders: 155),
];
