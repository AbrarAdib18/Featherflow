import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
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
  late List<_PayoutData> _payouts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _orders = [];
    _riders = [];
    _payouts = [];
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await Future.wait([
        AdminApiService.instance.list('delivery-orders'),
        AdminApiService.instance.list('riders'),
        AdminApiService.instance.list('payouts'),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = data[0].map(_OrderData.fromJson).toList();
        _riders = data[1].map(_RiderData.fromJson).toList();
        _payouts = data[2].map(_PayoutData.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _approveRider(String riderId) async {
    try {
      final response = await AdminApiService.instance
          .update('riders', riderId, {'action': 'approve'});
      final updated = _RiderData.fromJson(response);
      if (!mounted) return;
      setState(() {
        final i = _riders.indexWhere((r) => r.id == riderId);
        if (i >= 0) _riders[i] = updated;
      });
      AuditService.instance.log('Delivery Management', 'Approve Rider', riderId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _markPaid(_PayoutData payout) async {
    try {
      await AdminApiService.instance
          .update('payouts', payout.id, {'action': 'mark_paid'});
      if (!mounted) return;
      setState(() => _payouts.removeWhere((p) => p.id == payout.id));
      AuditService.instance.log('Delivery Management', 'Mark Payout Paid', payout.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payout of ৳${payout.amount.toStringAsFixed(0)} marked paid'),
        backgroundColor: AColors.green,
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _assignRider(_OrderData order, _RiderData rider, [String notes = '']) async {
    try {
      final response = await AdminApiService.instance.update(
        'delivery-orders',
        order.id,
        {
          'action': order.isQueue ? 'assign' : 'reassign',
          'rider_id': rider.id,
          'notes': notes,
        },
      );
      final updated = _OrderData.fromJson(response);
      if (!mounted) return;
      setState(() {
        _orders.removeWhere((o) => o.id == order.id);
        _orders.insert(0, updated);
      });
      AuditService.instance.log('Delivery Management',
          order.isQueue ? 'Assign' : 'Reassign', order.id,
          details: rider.name);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order assigned to ${rider.name}'),
        backgroundColor: AColors.green,
        duration: const Duration(seconds: 2),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _cancelOrder(_OrderData order) async {
    try {
      if (order.isQueue) {
        await AdminApiService.instance.update('delivery-orders', order.id, {'action': 'cancel'});
      } else {
        await AdminApiService.instance.update(
            'delivery-orders', order.id, {'action': 'cancel', 'reason': 'Cancelled by admin.'});
      }
      if (!mounted) return;
      setState(() => _orders.removeWhere((o) => o.id == order.id));
      AuditService.instance.log('Delivery Management', 'Cancel', order.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order ${order.id} cancelled'), backgroundColor: AColors.red));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = _orders.where((o) => const {'Failed', 'Cancelled'}.contains(o.status)).toList();
    return AdminScaffold(
      title: 'Delivery Management',
      module: AdminModule.deliveryManagement,
      appBarActions: const [
        ModuleActivityButton(
            title: 'Delivery', modules: ['delivery-orders', 'riders', 'payouts']),
      ],
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Active Orders'),
                Tab(text: 'Riders'),
                Tab(text: 'Issues'),
                Tab(text: 'Payouts'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AColors.secondary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _OrdersTab(
                        orders: _orders.where((o) => !issues.contains(o)).toList(),
                        riders: _riders,
                        onAssign: _assignRider,
                        onCancel: _cancelOrder,
                      ),
                      _RidersTab(riders: _riders, onApprove: _approveRider),
                      _IssuesTab(orders: issues, riders: _riders, onReassign: _assignRider),
                      _PayoutsTab(payouts: _payouts, onMarkPaid: _markPaid),
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
  final void Function(_OrderData, _RiderData, [String]) onAssign;
  final void Function(_OrderData) onCancel;

  const _OrdersTab(
      {required this.orders, required this.riders, required this.onAssign, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
          child: Text('No delivery orders yet.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _OrderCard(
          order: orders[i], riders: riders, onAssign: onAssign, onCancel: onCancel),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final _OrderData order;
  final List<_RiderData> riders;
  final void Function(_OrderData, _RiderData, [String]) onAssign;
  final void Function(_OrderData) onCancel;

  const _OrderCard(
      {required this.order, required this.riders, required this.onAssign, required this.onCancel});

  Color get _statusColor {
    switch (order.status) {
      case 'In Transit':
        return AColors.blue;
      case 'Assigned':
      case 'Accepted':
      case 'Picked Up':
        return AColors.secondary;
      case 'Failed':
        return AColors.red;
      case 'Cancelled':
        return AColors.grey;
      default:
        return AColors.amber;
    }
  }

  void _showAssignSheet(BuildContext context) {
    final available = riders.where((r) => r.approved).toList();
    final notesController = TextEditingController();
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
                    fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: notesController,
              style: const TextStyle(fontSize: 12, color: AColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Note for the rider (optional)',
                hintStyle: TextStyle(fontSize: 12, color: AColors.textSecondary),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AColors.divider),
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No approved riders available. Approve a rider first.',
                  style: TextStyle(color: AColors.textSecondary, fontSize: 12)),
            ),
          ...available.map((r) => ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AColors.secondary.withValues(alpha: 0.15),
                  child: Text(r.name.isNotEmpty ? r.name[0] : '?',
                      style: const TextStyle(
                          color: AColors.secondary, fontWeight: FontWeight.w700)),
                ),
                title: Text(r.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: AColors.textPrimary)),
                subtitle: Text('${r.activeOrders} active · ${r.zone}',
                    style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                trailing: aChip(r.status, AColors.secondary, AColors.secondary),
                onTap: () {
                  Navigator.pop(context);
                  onAssign(order, r, notesController.text.trim());
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
      decoration: aCard(highlight: order.status == 'Failed'),
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
                            fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                    Text('${order.customer} → ${order.destination}',
                        style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
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
              if (order.assignedRider != null) ...[
                const SizedBox(width: 10),
                _Pill(Icons.delivery_dining, order.assignedRider!, AColors.secondary),
              ],
            ],
          ),
          if (order.isColdChain || order.isPrescriptionRequired) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (order.isColdChain) ...[
                  const _Pill(Icons.ac_unit, 'Cold Chain', AColors.blue),
                  const SizedBox(width: 10),
                ],
                if (order.isPrescriptionRequired)
                  const _Pill(Icons.medication_outlined, 'Prescription', AColors.amber),
              ],
            ),
          ],
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(order.notes,
                style: const TextStyle(fontSize: 11, color: AColors.textSecondary, fontStyle: FontStyle.italic)),
          ],
          if (order.history.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${order.history.length} prior attempt(s) on this delivery',
                style: const TextStyle(fontSize: 11, color: AColors.grey)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.deliveryManagement,
                permission: AdminPermission.assign,
                child: _Chip(order.isQueue ? 'Assign Rider' : 'Reassign',
                    order.isQueue ? AColors.secondary : AColors.blue,
                    () => _showAssignSheet(context)),
              ),
              const SizedBox(width: 8),
              if (order.status != 'Delivered')
                PermissionGuard(
                  module: AdminModule.deliveryManagement,
                  permission: AdminPermission.edit,
                  child: _Chip('Cancel', AColors.red, () => onCancel(order)),
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
  final void Function(String) onApprove;

  const _RidersTab({required this.riders, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    if (riders.isEmpty) {
      return const Center(
          child: Text('No riders registered yet.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: riders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _RiderCard(riders[i], onApprove: onApprove),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final _RiderData rider;
  final void Function(String) onApprove;
  const _RiderCard(this.rider, {required this.onApprove});

  void _showMap(BuildContext context) {
    if (rider.currentLat == null || rider.currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No location reported yet for this rider.'),
          backgroundColor: AColors.grey));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 360,
          height: 320,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
                target: LatLng(rider.currentLat!, rider.currentLng!), zoom: 14),
            markers: {
              Marker(
                markerId: const MarkerId('rider'),
                position: LatLng(rider.currentLat!, rider.currentLng!),
                infoWindow: InfoWindow(title: rider.name),
              ),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onlineColor = rider.status == 'Online' ? AColors.secondary : AColors.grey;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: onlineColor.withValues(alpha: 0.15),
            child: Text(rider.name.isNotEmpty ? rider.name[0] : '?',
                style: TextStyle(color: onlineColor, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                Text('${rider.zone.isEmpty ? 'No zone set' : rider.zone} · ${rider.activeOrders} active',
                    style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Pill(Icons.star_outline, rider.rating.toStringAsFixed(1), AColors.amber),
                    const SizedBox(width: 8),
                    _Pill(Icons.check_circle_outline, '${rider.completedOrders} done', AColors.green),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.location_on_outlined, color: AColors.blue, size: 20),
            tooltip: 'View on map',
            onPressed: () => _showMap(context),
          ),
          if (!rider.approved)
            PermissionGuard(
              module: AdminModule.deliveryManagement,
              permission: AdminPermission.approve,
              child: _Chip('Approve', AColors.green, () => onApprove(rider.id)),
            )
          else
            aChip(rider.status, onlineColor, onlineColor),
        ],
      ),
    );
  }
}

// ── Issues tab ────────────────────────────────────────────────────────────────

class _IssuesTab extends StatelessWidget {
  final List<_OrderData> orders;
  final List<_RiderData> riders;
  final void Function(_OrderData, _RiderData, [String]) onReassign;

  const _IssuesTab({required this.orders, required this.riders, required this.onReassign});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
          child: Text('No issues at this time.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) =>
          _IssueCard(orders[i], riders: riders, onReassign: onReassign),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final _OrderData order;
  final List<_RiderData> riders;
  final void Function(_OrderData, _RiderData, [String]) onReassign;
  const _IssueCard(this.order, {required this.riders, required this.onReassign});

  void _showReassignSheet(BuildContext context) {
    final available = riders.where((r) => r.approved).toList();
    final notesController = TextEditingController();
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
            child: Text('Reassign ${order.id}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: notesController,
              style: const TextStyle(fontSize: 12, color: AColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Note for the new rider (optional)',
                hintStyle: TextStyle(fontSize: 12, color: AColors.textSecondary),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AColors.divider),
          ...available.map((r) => ListTile(
                title: Text(r.name, style: const TextStyle(fontSize: 13, color: AColors.textPrimary)),
                subtitle: Text(r.zone, style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                onTap: () {
                  Navigator.pop(context);
                  onReassign(order, r, notesController.text.trim());
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
      decoration: aCard(highlight: true),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AColors.redLight, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_amber_rounded, color: AColors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order ${order.id} — ${order.status}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                Text(order.customer, style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
              ],
            ),
          ),
          PermissionGuard(
            module: AdminModule.deliveryManagement,
            permission: AdminPermission.assign,
            child: _Chip('Reassign', AColors.secondary, () => _showReassignSheet(context)),
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
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
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
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Data models ──────────────────────────────────────────────────────────────

class _OrderData {
  final String id, customer, destination, items, status, notes;
  final String? assignedRider;
  final bool isQueue, isColdChain, isPrescriptionRequired;
  final List<Map<String, dynamic>> history;

  const _OrderData({
    required this.id,
    required this.customer,
    required this.destination,
    required this.items,
    required this.status,
    required this.isQueue,
    this.assignedRider,
    this.notes = '',
    this.isColdChain = false,
    this.isPrescriptionRequired = false,
    this.history = const [],
  });

  factory _OrderData.fromJson(Map<String, dynamic> json) => _OrderData(
        id: json['id'].toString(),
        customer: json['customer']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        items: json['items']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Pending',
        isQueue: json['is_queue'] == true,
        assignedRider: json['assigned_rider']?.toString(),
        notes: json['notes']?.toString() ?? '',
        isColdChain: json['is_cold_chain'] == true,
        isPrescriptionRequired: json['is_prescription_required'] == true,
        history: json['history'] is List
            ? (json['history'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [],
      );
}

class _RiderData {
  final String id, name, zone, status;
  final double rating;
  final int activeOrders, completedOrders;
  final bool approved;
  final double? currentLat, currentLng;

  const _RiderData({
    required this.id,
    required this.name,
    required this.zone,
    required this.status,
    required this.rating,
    required this.activeOrders,
    required this.completedOrders,
    required this.approved,
    this.currentLat,
    this.currentLng,
  });

  factory _RiderData.fromJson(Map<String, dynamic> json) => _RiderData(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        zone: json['zone']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Offline',
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        activeOrders: (json['active_orders'] as num?)?.toInt() ?? 0,
        completedOrders: (json['completed_orders'] as num?)?.toInt() ?? 0,
        approved: json['approved'] == true,
        currentLat: (json['current_lat'] as num?)?.toDouble(),
        currentLng: (json['current_lng'] as num?)?.toDouble(),
      );
}

class _PayoutData {
  final String id, riderId, riderName;
  final double amount;

  const _PayoutData({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.amount,
  });

  factory _PayoutData.fromJson(Map<String, dynamic> json) => _PayoutData(
        id: json['id'].toString(),
        riderId: json['rider_id']?.toString() ?? '',
        riderName: json['rider_name']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

// ── Payouts tab ──────────────────────────────────────────────────────────────

class _PayoutsTab extends StatelessWidget {
  final List<_PayoutData> payouts;
  final void Function(_PayoutData) onMarkPaid;

  const _PayoutsTab({required this.payouts, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    if (payouts.isEmpty) {
      return const Center(
          child: Text('No pending payouts.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: payouts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final payout = payouts[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: aCard(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payout.riderName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                    Text('৳${payout.amount.toStringAsFixed(0)} pending',
                        style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                  ],
                ),
              ),
              PermissionGuard(
                module: AdminModule.deliveryManagement,
                permission: AdminPermission.edit,
                child: _Chip('Mark Paid', AColors.green, () => onMarkPaid(payout)),
              ),
            ],
          ),
        );
      },
    );
  }
}
