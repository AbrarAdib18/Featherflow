import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
import '../widgets/permission_guard.dart';

class AdminPharmacyScreen extends StatefulWidget {
  const AdminPharmacyScreen({super.key});

  @override
  State<AdminPharmacyScreen> createState() => _AdminPharmacyScreenState();
}

class _AdminPharmacyScreenState extends State<AdminPharmacyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _api = AdminApiService.instance;

  List<Map<String, dynamic>> _pharmacies = [];
  List<Map<String, dynamic>> _medicines = [];
  List<Map<String, dynamic>> _expiry = [];
  List<Map<String, dynamic>> _orders = [];
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
        _api.list('pharmacies'),
        _api.pharmacyMedicines(),
        _api.pharmacyExpiryAlerts(),
        _api.pharmacyOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _pharmacies = results[0] as List<Map<String, dynamic>>;
        _medicines = results[1] as List<Map<String, dynamic>>;
        _expiry = ((results[2] as Map)['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _orders = results[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> med) async {
    try {
      await _api.approvePharmacyMedicine(med['id'].toString());
      AuditService.instance.log('Pharmacy Management', 'Approve Medicine', med['name']?.toString() ?? '');
      await _load();
      _toast('${med['name']} approved', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _reject(Map<String, dynamic> med) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reject ${med['name']}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.rejectPharmacyMedicine(med['id'].toString(), reason);
      AuditService.instance.log('Pharmacy Management', 'Reject Medicine', med['name']?.toString() ?? '');
      await _load();
      _toast('${med['name']} rejected', AColors.red);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _setPharmacyStatus(Map<String, dynamic> ph, String status) async {
    try {
      await _api.update('pharmacies', ph['id'].toString(), {'status': status});
      AuditService.instance.log('Pharmacy Management', '$status Pharmacy', ph['name']?.toString() ?? '');
      await _load();
      _toast('${ph['name']} → $status', status == 'Suspended' ? AColors.red : AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _showAnalytics(Map<String, dynamic> ph) async {
    try {
      final a = await _api.pharmacyAnalytics(ph['id'].toString());
      if (!mounted) return;
      showAdminDetails(context, title: '${ph['name']} — performance',
          icon: Icons.insights_outlined, fields: [
            MapEntry('Total medicines', '${a['total_medicines'] ?? 0}'),
            MapEntry('Active / approved', '${a['active_medicines'] ?? 0}'),
            MapEntry('Pending approval', '${a['pending_approval'] ?? 0}'),
            MapEntry('Total orders', '${a['total_orders'] ?? 0}'),
            MapEntry('Delivered orders', '${a['delivered_orders'] ?? 0}'),
            MapEntry('Active deliveries', '${a['active_deliveries'] ?? 0}'),
            MapEntry('Revenue', '৳${(a['total_revenue'] as num? ?? 0).toStringAsFixed(0)}'),
            MapEntry('Expiry alerts', '${a['expiry_alerts'] ?? 0}'),
          ]);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _medicines.where((m) => m['approval_status'] == 'pending').length;
    final activeDeliveries =
        _orders.where((o) => o['delivery'] != null).length;
    return AdminScaffold(
      title: 'Pharmacy Management',
      module: AdminModule.pharmacyManagement,
      appBarActions: const [
        ModuleActivityButton(title: 'Pharmacy', modules: ['pharmacies', 'medicines']),
      ],
      child: Column(children: [
        if (!_loading && _error == null)
          Container(
            color: AColors.appBar,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              _stat('Pharmacies', '${_pharmacies.length}'),
              _stat('Pending approvals', '$pendingCount'),
              _stat('Active deliveries', '$activeDeliveries'),
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
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Pharmacies'),
              Tab(text: 'Medicine Approvals'),
              Tab(text: 'Expiry Monitoring'),
              Tab(text: 'Orders & Delivery'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AColors.secondary))
              : _error != null
                  ? _errorView()
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _pharmaciesTab(),
                        _approvalsTab(),
                        _expiryTab(),
                        _ordersTab(),
                      ],
                    ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ]),
      );

  Widget _errorView() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_error!, style: const TextStyle(color: AColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );

  // ── Pharmacies ───────────────────────────────────────────────────────────
  Widget _pharmaciesTab() {
    if (_pharmacies.isEmpty) return _empty('No pharmacies registered.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _pharmacies.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final ph = _pharmacies[i];
          final status = ph['status']?.toString() ?? 'Pending';
          final color = status == 'Verified'
              ? AColors.green
              : status == 'Pending'
                  ? AColors.amber
                  : AColors.red;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(highlight: status == 'Pending'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_pharmacy_outlined, color: AColors.blue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ph['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                    Text(ph['location']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
                  ]),
                ),
                aChip(status, color, color),
              ]),
              const SizedBox(height: 8),
              Text('${ph['product_count'] ?? 0} products · ${ph['monthly_orders'] ?? 0} orders',
                  style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip('Analytics', AColors.blue, () => _showAnalytics(ph)),
                if (status != 'Verified')
                  PermissionGuard(
                    module: AdminModule.pharmacyManagement,
                    permission: AdminPermission.approve,
                    child: _chip('Verify', AColors.green, () => _setPharmacyStatus(ph, 'Verified')),
                  ),
                if (status == 'Verified')
                  PermissionGuard(
                    module: AdminModule.pharmacyManagement,
                    permission: AdminPermission.suspend,
                    child: _chip('Suspend', AColors.red, () => _setPharmacyStatus(ph, 'Suspended')),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  // ── Medicine approvals ───────────────────────────────────────────────────
  Widget _approvalsTab() {
    final pending = _medicines.where((m) => m['approval_status'] == 'pending').toList();
    final rest = _medicines.where((m) => m['approval_status'] != 'pending').toList();
    if (_medicines.isEmpty) return _empty('No prescription medicines to review.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (pending.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Awaiting decision',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AColors.textSecondary, fontSize: 12)),
            ),
          ...pending.map((m) => _medicineCard(m, actions: true)),
          if (rest.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Reviewed',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AColors.textSecondary, fontSize: 12)),
            ),
            ...rest.map((m) => _medicineCard(m, actions: false)),
          ],
        ],
      ),
    );
  }

  Widget _medicineCard(Map<String, dynamic> m, {required bool actions}) {
    final status = m['approval_status']?.toString() ?? 'pending';
    final color = status == 'approved'
        ? AColors.green
        : status == 'rejected'
            ? AColors.red
            : AColors.amber;
    final pharmacy = (m['pharmacy'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: status == 'pending'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(m['name']?.toString() ?? '',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          ),
          aChip(status, color, color, fontSize: 10),
        ]),
        Text('${pharmacy['name'] ?? ''} · ৳${(m['price'] as num? ?? 0).toStringAsFixed(0)} · ${m['category'] ?? ''}',
            style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
        if ((m['generic_name']?.toString() ?? '').isNotEmpty)
          Text('Generic: ${m['generic_name']}', style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
        if (m['cold_chain_required'] == true)
          const Text('🧊 Cold chain required', style: TextStyle(fontSize: 11, color: AColors.blue)),
        if (status == 'rejected' && (m['approval_rejected_reason']?.toString() ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Reason: ${m['approval_rejected_reason']}',
                style: const TextStyle(fontSize: 11, color: AColors.red)),
          ),
        if (actions) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            PermissionGuard(
              module: AdminModule.pharmacyManagement,
              permission: AdminPermission.approve,
              child: _chip('Approve', AColors.green, () => _approve(m)),
            ),
            PermissionGuard(
              module: AdminModule.pharmacyManagement,
              permission: AdminPermission.reject,
              child: _chip('Reject', AColors.red, () => _reject(m)),
            ),
          ]),
        ],
      ]),
    );
  }

  // ── Expiry ──────────────────────────────────────────────────────────────
  Widget _expiryTab() {
    if (_expiry.isEmpty) return _empty('No expiry alerts across pharmacies.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _expiry.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final a = _expiry[i];
          final level = a['alert_level']?.toString() ?? 'info';
          final color = level == 'critical'
              ? AColors.red
              : level == 'warning'
                  ? AColors.orange
                  : AColors.amber;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(highlight: level == 'critical'),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['medicine_name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                  Text('${a['pharmacy_name'] ?? ''} · ${a['stock_quantity'] ?? 0} in stock',
                      style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                ]),
              ),
              aChip('${a['expires_in_days'] ?? 0}d', color, color),
            ]),
          );
        },
      ),
    );
  }

  // ── Orders & delivery ───────────────────────────────────────────────────
  Widget _ordersTab() {
    if (_orders.isEmpty) return _empty('No pharmacy orders yet.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = _orders[i];
          final delivery = (o['delivery'] as Map?)?.cast<String, dynamic>();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(highlight: delivery != null),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(o['order_number']?.toString() ?? o['order_id']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                ),
                aChip((o['status']?.toString() ?? '').replaceAll('_', ' '),
                    AColors.blue, AColors.blue, fontSize: 10),
              ]),
              Text('${o['farmer_name'] ?? ''} · ৳${(o['total_amount'] as num? ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
              if (o['requires_cold_chain'] == true || o['requires_prescription'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, children: [
                    if (o['requires_cold_chain'] == true)
                      aChip('🧊 Cold chain', AColors.blue, AColors.blue, fontSize: 9),
                    if (o['requires_prescription'] == true)
                      aChip('Rx', AColors.orange, AColors.orange, fontSize: 9),
                  ]),
                ),
              if (delivery != null) ...[
                const Divider(height: 16),
                Text(
                    'Rider: ${delivery['rider_name'] ?? '—'} · ${(delivery['delivery_status']?.toString() ?? '').replaceAll('_', ' ')} · OTP ${delivery['otp_code'] ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Text(text, style: const TextStyle(color: AColors.textSecondary, fontSize: 13)));

  Widget _chip(String label, Color color, VoidCallback onTap) => GestureDetector(
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
