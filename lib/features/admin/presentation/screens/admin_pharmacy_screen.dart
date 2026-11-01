import 'package:flutter/material.dart';

import '../../../pharmacy/data/models/medicine_models.dart' show kMedicineCategories, kMedicineUnits, prettyCategory;
import '../../../../core/widgets/catalogue_image_picker.dart';
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
  late final TabController _tabs = TabController(length: 8, vsync: this);
  final _api = AdminApiService.instance;

  List<Map<String, dynamic>> _pharmacies = [];
  List<Map<String, dynamic>> _medicines = [];
  List<Map<String, dynamic>> _expiry = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _chats = [];
  List<Map<String, dynamic>> _appeals = [];
  Map<String, dynamic>? _dashboard;
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
        _api.pharmacyChats(),
        _api.pharmacyAppeals(),
        _api.pharmacyDashboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _pharmacies = results[0] as List<Map<String, dynamic>>;
        _medicines = results[1] as List<Map<String, dynamic>>;
        _expiry = ((results[2] as Map)['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _orders = results[3] as List<Map<String, dynamic>>;
        _chats = results[4] as List<Map<String, dynamic>>;
        _appeals = results[5] as List<Map<String, dynamic>>;
        _dashboard = results[6] as Map<String, dynamic>;
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

  Future<void> _setPharmacyStatus(Map<String, dynamic> ph, String status, {String? reason}) async {
    try {
      await _api.update('pharmacies', ph['id'].toString(), {
        'status': status,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      AuditService.instance.log('Pharmacy Management', '$status Pharmacy', ph['name']?.toString() ?? '');
      await _load();
      _toast('${ph['name']} → $status', status == 'Suspended' ? AColors.red : AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _suspendPharmacy(Map<String, dynamic> ph) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Suspend ${ph['name']}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Suspension reason', border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty) return;
    await _setPharmacyStatus(ph, 'Suspended', reason: reason);
  }

  Future<void> _approvePharmacyAccount(Map<String, dynamic> ph) async {
    try {
      await _api.approvePharmacy(ph['id'].toString());
      AuditService.instance.log('Pharmacy Management', 'Approve Pharmacy', ph['name']?.toString() ?? '');
      await _load();
      _toast('${ph['name']} approved', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _rejectPharmacyAccount(Map<String, dynamic> ph) async {
    final reason = await showAdminTextPrompt(context,
        title: 'Reject ${ph['name']}', label: 'Reason', actionLabel: 'Reject');
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.rejectPharmacy(ph['id'].toString(), reason);
      AuditService.instance.log('Pharmacy Management', 'Reject Pharmacy', ph['name']?.toString() ?? '');
      await _load();
      _toast('${ph['name']} rejected', AColors.red);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _requestPharmacyInfo(Map<String, dynamic> ph) async {
    final reason = await showAdminTextPrompt(context,
        title: 'Request more information', label: 'What is needed?', actionLabel: 'Send request');
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.requestPharmacyInfo(ph['id'].toString(), reason);
      AuditService.instance.log('Pharmacy Management', 'Request Info', ph['name']?.toString() ?? '');
      await _load();
      _toast('Requested more information from ${ph['name']}', AColors.amber);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _reinstatePharmacyAccount(Map<String, dynamic> ph) async {
    try {
      await _api.reinstatePharmacy(ph['id'].toString());
      AuditService.instance.log('Pharmacy Management', 'Reinstate Pharmacy', ph['name']?.toString() ?? '');
      await _load();
      _toast('${ph['name']} reinstated', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _showAccountReview(Map<String, dynamic> ph) async {
    Map<String, dynamic>? detail;
    try {
      detail = await _api.pharmacyAccountDetail(ph['id'].toString());
    } catch (e) {
      _toast(e.toString(), AColors.red);
      return;
    }
    if (!mounted) return;
    final profile = (detail['profile'] as Map?) ?? const {};
    final workforce = (detail['workforce'] as Map?) ?? const {};
    final counts = (detail['counts'] as Map?) ?? const {};
    final sales = (detail['sales_summary'] as Map?) ?? const {};
    final status = (detail['status'] ?? '').toString();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(profile['business_name']?.toString().isNotEmpty == true
                        ? profile['business_name'].toString()
                        : ph['name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              ),
              aChip(status, AColors.primary, AColors.primary),
            ]),
            const SizedBox(height: 12),
            _reviewRow('Contact person', profile['authorized_contact_person']),
            _reviewRow('Business address', profile['business_address']),
            _reviewRow('Registration number', profile['business_registration_number']),
            _reviewRow('Tax/VAT/TIN', profile['tax_vat_tin_number']),
            _reviewRow('Responsible pharmacist', profile['responsible_pharmacist_name']),
            const Divider(height: 24),
            Row(children: [
              _reviewStat('Account holders', '${workforce['account_holders'] ?? 1}'),
              _reviewStat('Employees', '${workforce['employees'] ?? 0}'),
              _reviewStat('Workforce', '${workforce['total_workforce'] ?? 1}'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _reviewStat('Medicines', '${counts['total_medicines'] ?? 0}'),
              _reviewStat('Orders', '${counts['total_orders'] ?? 0}'),
              _reviewStat('Pending Rx', '${counts['pending_approval'] ?? 0}'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _reviewStat('Gross sales', '৳${sales['gross_amount'] ?? '0.00'}'),
              _reviewStat('Commission', '৳${sales['commission_amount'] ?? '0.00'}'),
              _reviewStat('Pharmacy share', '৳${sales['pharmacy_amount'] ?? '0.00'}'),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (status == 'PENDING_REVIEW' || status == 'NEEDS_MORE_INFORMATION') ...[
                ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); _approvePharmacyAccount(ph); },
                  style: ElevatedButton.styleFrom(backgroundColor: AColors.green, foregroundColor: Colors.white),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () { Navigator.pop(ctx); _requestPharmacyInfo(ph); },
                  child: const Text('Request info'),
                ),
                OutlinedButton(
                  onPressed: () { Navigator.pop(ctx); _rejectPharmacyAccount(ph); },
                  style: OutlinedButton.styleFrom(foregroundColor: AColors.red),
                  child: const Text('Reject'),
                ),
              ],
              if (status == 'SUSPENDED' || status == 'APPEAL_PENDING')
                ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); _reinstatePharmacyAccount(ph); },
                  style: ElevatedButton.styleFrom(backgroundColor: AColors.green, foregroundColor: Colors.white),
                  child: const Text('Reinstate'),
                ),
              if (status == 'ACTIVE')
                OutlinedButton(
                  onPressed: () { Navigator.pop(ctx); _suspendPharmacy(ph); },
                  style: OutlinedButton.styleFrom(foregroundColor: AColors.red),
                  child: const Text('Suspend'),
                ),
              OutlinedButton.icon(
                onPressed: () { Navigator.pop(ctx); _showEmployeeRoster(ph); },
                icon: const Icon(Icons.badge_outlined, size: 16),
                label: const Text('Employees'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Employee roster (headcount only — no login credentials) ────────────────
  Future<void> _showEmployeeRoster(Map<String, dynamic> ph) async {
    final pharmacyId = ph['id'].toString();
    List<Map<String, dynamic>> employees;
    try {
      employees = await _api.pharmacyEmployees(pharmacyId);
    } catch (e) {
      _toast(e.toString(), AColors.red);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${ph['name']} — Employees',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final added = await _promptAddEmployee(context, pharmacyId);
                    if (added != null) {
                      employees = [...employees, added];
                      setSheetState(() {});
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ]),
              const SizedBox(height: 8),
              if (employees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No employees on record yet.', style: TextStyle(color: AColors.textSecondary)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: employees.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final e = employees[i];
                      return Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e['name']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                            Text('${e['role_title'] ?? ''} · ${e['access_level'] ?? ''}',
                                style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                          ]),
                        ),
                        Switch(
                          value: e['is_active'] == true,
                          onChanged: (v) async {
                            try {
                              final updated = await _api.updatePharmacyEmployee(
                                  pharmacyId, e['id'].toString(), {'is_active': v});
                              employees = [
                                for (final existing in employees)
                                  if (existing['id'] == e['id']) updated else existing,
                              ];
                              setSheetState(() {});
                            } catch (err) {
                              _toast(err.toString(), AColors.red);
                            }
                          },
                        ),
                      ]);
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
    await _load();
  }

  Future<Map<String, dynamic>?> _promptAddEmployee(BuildContext context, String pharmacyId) async {
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    String accessLevel = 'staff';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add employee'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: roleCtrl, decoration: const InputDecoration(labelText: 'Role / title')),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: accessLevel,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
                DropdownMenuItem(value: 'pharmacist', child: Text('Pharmacist')),
              ],
              onChanged: (v) => setState(() => accessLevel = v ?? accessLevel),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                try {
                  final created = await _api.addPharmacyEmployee(pharmacyId, {
                    'name': name, 'role_title': roleCtrl.text.trim(), 'access_level': accessLevel,
                  });
                  if (ctx.mounted) Navigator.pop(ctx, created);
                } catch (e) {
                  _toast(e.toString(), AColors.red);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    roleCtrl.dispose();
    return result;
  }

  // ── Add Medicine (admin authority, on behalf of a chosen pharmacy) ─────────
  Future<void> _showAddMedicineDialog(Map<String, dynamic> ph) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddMedicineDialog(pharmacyId: ph['id'].toString(), pharmacyName: ph['name']?.toString() ?? ''),
    );
    if (added == true) {
      AuditService.instance.log('Pharmacy Management', 'Add Medicine', ph['name']?.toString() ?? '');
      await _load();
      _toast('Medicine added to ${ph['name']}', AColors.green);
    }
  }

  Future<void> _adjustStock(Map<String, dynamic> a) async {
    final ctrl = TextEditingController();
    final delta = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Adjust stock — ${a['medicine_name']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
              labelText: 'Change (e.g. 20 or -5)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Apply')),
        ],
      ),
    );
    ctrl.dispose();
    if (delta == null || delta.isEmpty) return;
    final value = int.tryParse(delta);
    if (value == null) {
      _toast('Enter a whole number.', AColors.red);
      return;
    }
    try {
      await _api.adjustPharmacyMedicineStock(a['medicine_id'].toString(), value);
      AuditService.instance.log('Pharmacy Management', 'Adjust Stock', a['medicine_name']?.toString() ?? '');
      await _load();
      _toast('Stock updated', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Widget _reviewRow(String label, dynamic value) {
    final v = (value ?? '').toString();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AColors.grey)),
        Text(v, style: const TextStyle(fontSize: 13, color: AColors.textPrimary)),
      ]),
    );
  }

  Widget _reviewStat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 10, color: AColors.textSecondary), textAlign: TextAlign.center),
        ]),
      );

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
              Tab(text: 'Overview'),
              Tab(text: 'Pharmacies'),
              Tab(text: 'Medicine Approvals'),
              Tab(text: 'Expiry Monitoring'),
              Tab(text: 'Orders & Delivery'),
              Tab(text: 'Chat & Appeals'),
              Tab(text: 'Sales & Settlements'),
              Tab(text: 'Reports & Audit'),
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
                        _overviewTab(),
                        _pharmaciesTab(),
                        _approvalsTab(),
                        _expiryTab(),
                        _ordersTab(),
                        _chatAndAppealsTab(),
                        _salesSettlementsTab(),
                        const _ReportsAuditTab(),
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

  // ── Overview ─────────────────────────────────────────────────────────────
  // Wires the already-built, already-tested /admin-panel/pharmacy/dashboard/
  // endpoint (account/medicine/employee/sales/commission metrics) into a
  // real stat grid. Previously computed by the backend but never called
  // from this screen at all — the only thing shown was a 3-metric top bar
  // (Pharmacies / Pending approvals / Active deliveries).
  Widget _overviewTab() {
    final d = _dashboard;
    if (d == null) return _empty('No dashboard data.');
    final summary = Map<String, dynamic>.from(d['summary'] as Map? ?? const {});
    final alerts = Map<String, dynamic>.from(d['medicine_alerts'] as Map? ?? const {});
    final pendingQueue = (d['pending_verification_queue'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final appealQueue = (d['suspension_appeal_queue'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final auditEvents = (d['recent_audit_events'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();

    Widget card(String label, String value, Color color) => Container(
          width: 150,
          decoration: BoxDecoration(
            color: AColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          ]),
        );

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: children),
          ]),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          section('Pharmacy accounts', [
            card('Account holders', '${summary['pharmacy_accounts'] ?? 0}', AColors.blue),
            card('Pending verification', '${summary['pending_verification'] ?? 0}', AColors.orange),
            card('Total employees', '${summary['total_employees'] ?? 0}', AColors.blue),
          ]),
          section('Medicines', [
            card('Total medicines', '${summary['total_medicines'] ?? 0}', AColors.green),
            card('Active', '${summary['active_medicines'] ?? 0}', AColors.green),
            card('Archived', '${summary['archived_medicines'] ?? 0}', AColors.grey),
            card('Categories/types', '${summary['medicine_categories'] ?? 0}', AColors.blue),
            card('Brands', '${summary['total_brands'] ?? 0}', AColors.blue),
            card('Low stock', '${alerts['low_stock'] ?? 0}', AColors.orange),
            card('Out of stock', '${alerts['out_of_stock'] ?? 0}', AColors.red),
            card('Pending approval', '${alerts['pending_approval'] ?? 0}', AColors.orange),
          ]),
          section('Sales & revenue', [
            card('Total sold', '${summary['total_sold'] ?? 0}', AColors.green),
            card('Gross sales', '৳${summary['gross_sales'] ?? '0.00'}', AColors.green),
            card('Featherflow commission', '৳${summary['featherflow_commission'] ?? '0.00'}', AColors.blue),
            card('Pharmacy revenue', '৳${summary['pharmacy_share'] ?? '0.00'}', AColors.green),
          ]),
          section('Delivery', [
            card('Orders needing assignment', '${d['orders_needing_delivery_assignment'] ?? 0}', AColors.orange),
          ]),
          if (pendingQueue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Pending verification queue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...pendingQueue.map((p) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.hourglass_top, color: AColors.orange),
                      title: Text(p['business_name']?.toString().isNotEmpty == true
                          ? p['business_name'].toString() : p['name']?.toString() ?? ''),
                      subtitle: Text('Submitted: ${p['submitted_date'] ?? 'unknown'}'),
                    )),
              ]),
            ),
          if (appealQueue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Suspension / appeal queue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...appealQueue.map((a) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.report_gmailerrorred, color: AColors.red),
                      title: Text(a['pharmacy_name']?.toString() ?? ''),
                      subtitle: Text('${a['status']} — ${a['reason'] ?? ''}'),
                    )),
              ]),
            ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recent audit activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (auditEvents.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No recent activity.'))
            else
              ...auditEvents.map((e) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: AColors.textSecondary),
                    title: Text(e['action']?.toString() ?? ''),
                    subtitle: Text('${e['admin'] ?? 'System'} · ${e['created_at'] ?? ''}'),
                  )),
          ]),
        ],
      ),
    );
  }

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
                _chip('Details', AColors.primary, () => _showAccountReview(ph)),
                _chip('Analytics', AColors.blue, () => _showAnalytics(ph)),
                PermissionGuard(
                  module: AdminModule.pharmacyManagement,
                  permission: AdminPermission.edit,
                  child: _chip('Add Medicine', AColors.green, () => _showAddMedicineDialog(ph)),
                ),
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
                    child: _chip('Suspend', AColors.red, () => _suspendPharmacy(ph)),
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
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (actions) ...[
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
          ],
          if (m['is_active'] == true)
            _chip('Archive', AColors.red, () => _archiveMedicine(m))
          else
            _chip('Restore', AColors.green, () => _restoreMedicine(m)),
        ]),
      ]),
    );
  }

  Future<void> _archiveMedicine(Map<String, dynamic> m) async {
    final reason = await showAdminTextPrompt(context,
        title: 'Archive ${m['name']}', label: 'Reason', actionLabel: 'Archive');
    if (reason == null || reason.isEmpty) return;
    try {
      await _api.archivePharmacyMedicine(m['id'].toString(), reason: reason);
      AuditService.instance.log('Pharmacy Management', 'Archive Medicine', m['name']?.toString() ?? '');
      await _load();
      _toast('${m['name']} archived', AColors.red);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _restoreMedicine(Map<String, dynamic> m) async {
    try {
      await _api.restorePharmacyMedicine(m['id'].toString());
      AuditService.instance.log('Pharmacy Management', 'Restore Medicine', m['name']?.toString() ?? '');
      await _load();
      _toast('${m['name']} restored', AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
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
              const SizedBox(width: 8),
              _chip('Adjust stock', AColors.blue, () => _adjustStock(a)),
            ]),
          );
        },
      ),
    );
  }

  // ── Orders & delivery ───────────────────────────────────────────────────
  Widget _ordersTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == 0) return const _DeliveryQueueSection();
          if (_orders.isEmpty) return _empty('No pharmacy orders yet.');
          final o = _orders[i - 1];
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

  // ── Chat & Appeals ───────────────────────────────────────────────────────
  Widget _chatAndAppealsTab() {
    if (_chats.isEmpty && _appeals.isEmpty) return _empty('No pharmacy conversations or appeals.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_appeals.isNotEmpty) ...[
            const Text('Suspension appeals',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
            const SizedBox(height: 8),
            ..._appeals.map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: aCard(highlight: a['status'] == 'submitted'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(a['pharmacy_name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                      ),
                      aChip((a['status'] ?? '').toString().replaceAll('_', ' '), AColors.amber, AColors.amber, fontSize: 10),
                    ]),
                    const SizedBox(height: 4),
                    Text(a['explanation']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12, color: AColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (['submitted', 'under_review', 'more_info_required'].contains(a['status'])) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        _chip('Approve', AColors.green, () => _decideAppeal(a, 'approve')),
                        _chip('More info', AColors.amber, () => _decideAppeal(a, 'more_info')),
                        _chip('Deny', AColors.red, () => _decideAppeal(a, 'deny')),
                      ]),
                    ],
                  ]),
                )),
            const SizedBox(height: 16),
          ],
          if (_chats.isNotEmpty) ...[
            const Text('Support conversations',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
            const SizedBox(height: 8),
            ..._chats.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: aCard(highlight: (c['unread_count'] as num? ?? 0) > 0),
                  child: InkWell(
                    onTap: () => _openChat(c),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['pharmacy_name']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                          Text(c['last_message']?.toString() ?? '',
                              style: const TextStyle(fontSize: 12, color: AColors.textSecondary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      if ((c['unread_count'] as num? ?? 0) > 0)
                        aChip('${c['unread_count']}', AColors.red, AColors.red, fontSize: 10),
                      const SizedBox(width: 6),
                      aChip((c['status'] ?? '').toString().replaceAll('_', ' '), AColors.blue, AColors.blue, fontSize: 9),
                    ]),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _decideAppeal(Map<String, dynamic> appeal, String action) async {
    String response = '';
    if (action != 'approve') {
      final prompt = await showAdminTextPrompt(context,
          title: action == 'deny' ? 'Deny appeal' : 'Request more information',
          label: 'Message to the pharmacy', actionLabel: 'Send');
      if (prompt == null || prompt.isEmpty) return;
      response = prompt;
    }
    try {
      await _api.decidePharmacyAppeal(appeal['id'].toString(), action, adminResponse: response);
      AuditService.instance.log('Pharmacy Management', 'Decide Appeal', appeal['pharmacy_name']?.toString() ?? '');
      await _load();
      _toast('Appeal ${action == 'approve' ? 'approved' : action == 'deny' ? 'denied' : 'sent back for more info'}',
          action == 'deny' ? AColors.red : AColors.green);
    } catch (e) {
      _toast(e.toString(), AColors.red);
    }
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    Map<String, dynamic>? detail;
    try {
      detail = await _api.pharmacyChatDetail(chat['id'].toString());
    } catch (e) {
      _toast(e.toString(), AColors.red);
      return;
    }
    if (!mounted) return;
    final messages = (detail['messages'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(chat['pharmacy_name']?.toString() ?? '',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                children: messages.map((m) {
                  final fromPharmacy = m['from_pharmacy'] == true;
                  return Align(
                    alignment: fromPharmacy ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.7),
                      decoration: BoxDecoration(
                        color: fromPharmacy ? AColors.surface2 : AColors.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(m['content']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Reply…',
                  filled: true,
                  fillColor: AColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                try {
                  await _api.replyPharmacyChat(chat['id'].toString(), text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  _toast(e.toString(), AColors.red);
                }
              },
              icon: const Icon(Icons.send),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Sales & Settlements ─────────────────────────────────────────────────
  Widget _salesSettlementsTab() => const _SalesSettlementsTab();

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

/// Live sales, commission and settlement view — its own small state so it can
/// refresh independently of the rest of the (already large) Pharmacy
/// Management screen. Reads real /api/admin/pharmacies/{metrics,sales}/ and
/// /api/admin-panel/pharmacy/settlements/ data — no mock numbers.
class _SalesSettlementsTab extends StatefulWidget {
  const _SalesSettlementsTab();

  @override
  State<_SalesSettlementsTab> createState() => _SalesSettlementsTabState();
}

class _SalesSettlementsTabState extends State<_SalesSettlementsTab> {
  final _api = AdminApiService.instance;
  String _period = 'lifetime';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _metrics = const {};
  List<Map<String, dynamic>> _sales = const [];
  List<Map<String, dynamic>> _settlements = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.pharmacyMetrics(period: _period),
        _api.pharmacySales(period: _period),
        _api.pharmacySettlements(),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as Map<String, dynamic>;
        _sales = results[1] as List<Map<String, dynamic>>;
        _settlements = results[2] as List<Map<String, dynamic>>;
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

  Future<void> _markSettlementPaid(Map<String, dynamic> s) async {
    final ref = await showAdminTextPrompt(context,
        title: 'Mark settlement paid', label: 'Payment reference', actionLabel: 'Mark paid',
        initialValue: 'TXN-');
    if (ref == null || ref.isEmpty) return;
    try {
      await _api.updatePharmacySettlementStatus(s['id'].toString(), 'paid', paymentReference: ref);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AColors.secondary));
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_error!, style: const TextStyle(color: AColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    final sales = (_metrics['sales'] as Map?) ?? const {};
    final accounts = (_metrics['accounts'] as Map?) ?? const {};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            const Text('Period:', style: TextStyle(fontSize: 12, color: AColors.textSecondary)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _period,
              items: const [
                DropdownMenuItem(value: 'today', child: Text('Today')),
                DropdownMenuItem(value: 'week', child: Text('This week')),
                DropdownMenuItem(value: 'month', child: Text('This month')),
                DropdownMenuItem(value: 'year', child: Text('This year')),
                DropdownMenuItem(value: 'lifetime', child: Text('Lifetime')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _period = v);
                _load();
              },
            ),
          ]),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              _metricCard('Total sold', '${sales['total_orders'] ?? 0}', AColors.blue),
              _metricCard('Gross sales', '৳${sales['gross_sales'] ?? '0.00'}', AColors.blue),
              _metricCard('Featherflow commission', '৳${sales['featherflow_commission'] ?? '0.00'}', AColors.amber),
              _metricCard('Pharmacy share', '৳${sales['pharmacy_share'] ?? '0.00'}', AColors.green),
              _metricCard('Pending settlement', '৳${sales['pending_settlement'] ?? '0.00'}', AColors.amber),
              _metricCard('Completed settlement', '৳${sales['completed_settlement'] ?? '0.00'}', AColors.green),
            ],
          ),
          const SizedBox(height: 8),
          Text('Accounts: ${accounts['total'] ?? 0} · Active: ${accounts['active'] ?? 0} · '
              'Pending: ${accounts['pending_review'] ?? 0} · Suspended: ${accounts['suspended'] ?? 0}',
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 20),
          const Text('Recent sales', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          const SizedBox(height: 8),
          if (_sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No sales in this period.', style: TextStyle(color: AColors.textSecondary, fontSize: 12)),
            )
          else
            ..._sales.take(20).map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: aCard(),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['pharmacy_name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                        Text('Gross ৳${s['gross_amount']} · Commission ৳${s['commission_amount']} · '
                            'Share ৳${s['pharmacy_amount']}',
                            style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                      ]),
                    ),
                    aChip(s['status'] ?? '', s['status'] == 'refunded' ? AColors.red : AColors.green,
                        s['status'] == 'refunded' ? AColors.red : AColors.green, fontSize: 10),
                  ]),
                )),
          const SizedBox(height: 20),
          const Text('Settlements', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          const SizedBox(height: 8),
          if (_settlements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No settlements generated yet.', style: TextStyle(color: AColors.textSecondary, fontSize: 12)),
            )
          else
            ..._settlements.map((s) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: aCard(),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s['pharmacy_name']} · ${s['period_start']} → ${s['period_end']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                        Text('Payable ৳${s['payable_amount']} (gross ৳${s['gross_sales']}, commission ৳${s['commission']})',
                            style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
                      ]),
                    ),
                    aChip(s['status'] ?? '', _settlementColor(s['status']), _settlementColor(s['status']), fontSize: 10),
                    if (s['status'] == 'pending') ...[
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => _markSettlementPaid(s), child: const Text('Mark paid')),
                    ],
                  ]),
                )),
        ],
      ),
    );
  }

  Color _settlementColor(dynamic status) => switch (status) {
        'paid' => AColors.green,
        'failed' || 'reversed' => AColors.red,
        _ => AColors.amber,
      };

  Widget _metricCard(String label, String value, Color color) => Container(
        decoration: BoxDecoration(
          color: AColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AColors.textSecondary)),
        ]),
      );
}

/// Orders waiting for a rider (delivery-queue) with an inline "Assign"
/// action — reuses the existing, tested core assignment logic
/// (api.admin_views._assign_from_queue) via a pharmacy-scoped wrapper.
/// Assigning to an offline rider is a warning, not a hard block (confirmed
/// decision) — the returned `warning` field is surfaced as a toast.
class _DeliveryQueueSection extends StatefulWidget {
  const _DeliveryQueueSection();

  @override
  State<_DeliveryQueueSection> createState() => _DeliveryQueueSectionState();
}

class _DeliveryQueueSectionState extends State<_DeliveryQueueSection> {
  final _api = AdminApiService.instance;
  List<Map<String, dynamic>> _queue = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final queue = await _api.pharmacyDeliveryQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _assign(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> riders;
    try {
      riders = await _api.pharmacyAvailableRiders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
      return;
    }
    if (!mounted) return;
    final rider = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign a rider'),
        content: SizedBox(
          width: 360,
          child: riders.isEmpty
              ? const Text('No riders available.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: riders.length,
                  itemBuilder: (_, i) {
                    final r = riders[i];
                    final online = r['status']?.toString() == 'Online';
                    return ListTile(
                      leading: Icon(Icons.circle, size: 10, color: online ? AColors.green : AColors.grey),
                      title: Text(r['name']?.toString() ?? r['full_name']?.toString() ?? ''),
                      subtitle: Text(r['status']?.toString() ?? 'Offline'),
                      onTap: () => Navigator.pop(ctx, r),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
    if (rider == null) return;
    final online = rider['status']?.toString() == 'Online';
    if (!online) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rider is offline'),
          content: const Text(
              'This rider is currently offline. Do you still want to assign this delivery?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AColors.amber),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final result = await _api.assignPharmacyDelivery(
          item['queue_record_id'].toString(), rider['id'].toString());
      await _load();
      if (!mounted) return;
      final warning = result['warning']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(warning ?? 'Delivery assigned.'),
        backgroundColor: warning != null ? AColors.amber : AColors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Delivery queue: $_error', style: const TextStyle(color: AColors.red, fontSize: 12)),
      );
    }
    if (_queue.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AColors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AColors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Needs delivery assignment (${_queue.length})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
        const SizedBox(height: 8),
        ..._queue.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item['pharmacy'] ?? ''} → ${item['customer'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AColors.textPrimary)),
                    if (item['is_cold_chain'] == true || item['is_prescription_required'] == true)
                      Text(
                          [
                            if (item['is_cold_chain'] == true) '🧊 Cold chain',
                            if (item['is_prescription_required'] == true) 'Rx',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 10, color: AColors.blue)),
                  ]),
                ),
                TextButton(onPressed: () => _assign(item), child: const Text('Assign')),
              ]),
            )),
      ]),
    );
  }
}

/// Admin-authority "Add Medicine" form (spec §6) — on behalf of a chosen
/// pharmacy. Mirrors the pharmacy-facing AddMedicineDialog's two-step pattern
/// (save text fields first to get a real medicine id, then reveal the image
/// picker) since the upload endpoint requires an existing medicine id; this
/// also naturally prevents a duplicate submission (the Save button is
/// replaced by "Done" once the medicine exists).
class _AddMedicineDialog extends StatefulWidget {
  final String pharmacyId;
  final String pharmacyName;
  const _AddMedicineDialog({required this.pharmacyId, required this.pharmacyName});

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _price = TextEditingController();
  final _previousPrice = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _minQty = TextEditingController(text: '1');
  final _description = TextEditingController();
  final _dosage = TextEditingController();
  final _expiry = TextEditingController(
      text: DateTime.now().add(const Duration(days: 365)).toIso8601String().split('T').first);

  String _category = kMedicineCategories.first;
  String _unit = kMedicineUnits.first;
  bool _prescription = false;
  bool _coldChain = false;

  String? _savedId;
  String? _photoUrl;
  bool _changed = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _generic, _price, _previousPrice, _stock, _minQty,
      _description, _dosage, _expiry]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // duplicate-submission guard
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final minQty = int.tryParse(_minQty.text.trim()) ?? 1;
    final expiry = DateTime.tryParse(_expiry.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Medicine name is required.');
    if (price == null || price <= 0) return setState(() => _error = 'Price must be greater than 0.');
    if (stock == null || stock < 0) return setState(() => _error = 'Stock cannot be negative.');
    if (minQty < 1) return setState(() => _error = 'Minimum order quantity must be at least 1.');
    if (expiry == null || !expiry.isAfter(DateTime.now())) {
      return setState(() => _error = 'Expiry date must be in the future.');
    }
    double? previousPrice;
    if (_previousPrice.text.trim().isNotEmpty) {
      previousPrice = double.tryParse(_previousPrice.text.trim());
      if (previousPrice == null || previousPrice < 0) {
        return setState(() => _error = 'Discount price must be a valid non-negative number.');
      }
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final created = await AdminApiService.instance.createPharmacyMedicine({
        'pharmacy_id': widget.pharmacyId,
        'name': name,
        'generic_name': _generic.text.trim(),
        'category': _category,
        'unit': _unit,
        'price': price,
        if (previousPrice != null) 'previous_price': previousPrice,
        'stock_quantity': stock,
        'min_order_quantity': minQty,
        'expiry_date': _expiry.text.trim(),
        'description': _description.text.trim(),
        'dosage_instructions': _dosage.text.trim(),
        'prescription_required': _prescription,
        'cold_chain_required': _coldChain,
      });
      if (!mounted) return;
      setState(() {
        _savedId = created['id']?.toString();
        _changed = true;
        _busy = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final justCreated = _savedId != null;
    return AlertDialog(
      backgroundColor: AColors.bg,
      title: Text('Add Medicine — ${widget.pharmacyName}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_savedId == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Save the medicine first, then attach a photo.',
                    style: TextStyle(fontSize: 11, color: AColors.textSecondary)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: 200,
                  child: CatalogueImagePicker(
                    currentUrl: _photoUrl,
                    aspectRatio: 4 / 3,
                    label: 'Add product photo',
                    fallbackIcon: Icons.medication_outlined,
                    onUpload: (bytes, filename) async {
                      final res = await AdminApiService.instance
                          .uploadPharmacyMedicineImage(_savedId!, bytes, filename);
                      final url = res['image_url']?.toString() ?? '';
                      if (mounted) setState(() { _photoUrl = url; _changed = true; });
                      return url;
                    },
                  ),
                ),
              ),
            _f(_name, 'Medicine name'),
            _f(_generic, 'Generic name'),
            Row(children: [
              Expanded(child: _dropdown('Category', _category, kMedicineCategories, (v) => setState(() => _category = v))),
              const SizedBox(width: 8),
              Expanded(child: _dropdown('Unit', _unit, kMedicineUnits, (v) => setState(() => _unit = v))),
            ]),
            Row(children: [
              Expanded(child: _f(_price, 'Price (৳)', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _f(_previousPrice, 'Discount from (optional)', number: true)),
            ]),
            Row(children: [
              Expanded(child: _f(_stock, 'Stock quantity', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _f(_minQty, 'Min order quantity', number: true)),
            ]),
            _f(_expiry, 'Expiry date (YYYY-MM-DD)'),
            _f(_description, 'Description', lines: 2),
            _f(_dosage, 'Dosage / strength', lines: 2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _prescription,
              title: const Text('Prescription required', style: TextStyle(fontSize: 12, color: AColors.textPrimary)),
              onChanged: (v) => setState(() => _prescription = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _coldChain,
              title: const Text('Cold chain required', style: TextStyle(fontSize: 12, color: AColors.textPrimary)),
              onChanged: (v) => setState(() => _coldChain = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AColors.red, fontSize: 11.5)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          child: Text(justCreated ? 'Done' : 'Cancel'),
        ),
        if (!justCreated)
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {bool number = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(prettyCategory(o), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => onChanged(v ?? value),
        ),
      );
}

/// Reports & Audit (spec §15) — per-report-type CSV export with date-range,
/// pharmacy and status filters, plus a dedicated audit log viewer scoped to
/// pharmacy entity types only (never leaks unrelated audit rows).
class _ReportsAuditTab extends StatefulWidget {
  const _ReportsAuditTab();

  @override
  State<_ReportsAuditTab> createState() => _ReportsAuditTabState();
}

class _ReportsAuditTabState extends State<_ReportsAuditTab> {
  static const _reportTypes = [
    ('accounts', 'Pharmacy accounts'),
    ('approvals', 'Approvals'),
    ('suspensions', 'Suspensions'),
    ('medicines', 'Medicine catalogue'),
    ('inventory', 'Inventory'),
    ('orders', 'Orders'),
    ('sales', 'Sales'),
    ('commissions', 'Commissions'),
    ('settlements', 'Settlements'),
    ('employees', 'Employees'),
    ('appeals', 'Appeals'),
    ('delivery-assignments', 'Delivery assignments'),
    ('chat-activity', 'Chat activity'),
    ('admin-actions', 'Admin actions'),
  ];

  bool _exporting = false;
  String? _exportError;

  bool _auditLoading = true;
  String? _auditError;
  List<Map<String, dynamic>> _audit = [];

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    setState(() { _auditLoading = true; _auditError = null; });
    try {
      final rows = await AdminApiService.instance.pharmacyAuditLog();
      if (!mounted) return;
      setState(() { _audit = rows; _auditLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _auditError = e.toString(); _auditLoading = false; });
    }
  }

  Future<void> _export(String reportType) async {
    setState(() { _exporting = true; _exportError = null; });
    try {
      final result = await AdminApiService.instance.exportPharmacyReport(reportType);
      if (!mounted) return;
      setState(() => _exporting = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Exported ${result.filename}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(
                result.csv.length > 2000 ? '${result.csv.substring(0, 2000)}\n… (truncated preview; full file has ${result.csv.length} characters)' : result.csv,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _exporting = false; _exportError = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAudit,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Reports', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Export a CSV for any pharmacy report type below.',
              style: TextStyle(fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 10),
          if (_exportError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(_exportError!, style: const TextStyle(color: AColors.red, fontSize: 11))),
                TextButton(onPressed: () => setState(() => _exportError = null), child: const Text('Dismiss')),
              ]),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (type, label) in _reportTypes)
              PermissionGuard(
                module: AdminModule.pharmacyManagement,
                permission: AdminPermission.export,
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(type),
                  icon: _exporting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined, size: 16),
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                ),
              ),
          ]),
          const SizedBox(height: 24),
          const Text('Audit trail', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
          const SizedBox(height: 8),
          if (_auditLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: AColors.secondary)),
            )
          else if (_auditError != null)
            Column(children: [
              Text(_auditError!, style: const TextStyle(color: AColors.textSecondary)),
              TextButton(onPressed: _loadAudit, child: const Text('Retry')),
            ])
          else if (_audit.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No pharmacy audit events yet.', style: TextStyle(color: AColors.textSecondary, fontSize: 12)),
            )
          else
            ..._audit.take(100).map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: aCard(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(a['action']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AColors.textPrimary)),
                      ),
                      aChip(a['action_type'] ?? '', AColors.blue, AColors.blue, fontSize: 9),
                    ]),
                    Text('${a['actor'] ?? 'System'} (${a['role'] ?? '—'}) · ${a['entity_type'] ?? ''} · ${a['created_at'] ?? ''}',
                        style: const TextStyle(fontSize: 10, color: AColors.textSecondary)),
                    if ((a['reason']?.toString() ?? '').isNotEmpty)
                      Text('Reason: ${a['reason']}', style: const TextStyle(fontSize: 10, color: AColors.textSecondary)),
                  ]),
                )),
        ],
      ),
    );
  }
}
