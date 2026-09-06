import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

/// Super Admin: every admin's shift status, hours, rate and payment due, plus
/// the weekly payroll run. Polls every 10s so who's-online stays live.
class AdminPayrollScreen extends StatefulWidget {
  const AdminPayrollScreen({super.key});

  @override
  State<AdminPayrollScreen> createState() => _AdminPayrollScreenState();
}

class _AdminPayrollScreenState extends State<AdminPayrollScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Timer? _poll;

  List<Map<String, dynamic>> _admins = [];
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | online | offline

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdminApiService.instance.allAdmins(),
        AdminApiService.instance.adminPayments(),
      ]);
      if (!mounted) return;
      setState(() {
        final a = results[0] as Map<String, dynamic>;
        _admins = (a['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = Map<String, dynamic>.from(a['summary'] as Map? ?? {});
        _payments = results[1] as List<Map<String, dynamic>>;
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

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'online':
        return _admins.where((a) => a['is_on_shift'] == true).toList();
      case 'offline':
        return _admins.where((a) => a['is_on_shift'] != true).toList();
      default:
        return _admins;
    }
  }

  Future<void> _editRate(Map<String, dynamic> admin) async {
    final range = (admin['rate_range'] as List?)?.cast<num>() ?? const [0, 0];
    final value = await showAdminTextPrompt(context,
        title: 'Hourly rate — ${admin['name']}',
        label: 'Rate ৳/h  (band: ৳${range[0]}–৳${range[1]})',
        actionLabel: 'Save',
        initialValue: '${admin['hourly_rate']}',
        maxLines: 1);
    if (value == null) return;
    final rate = num.tryParse(value);
    if (rate == null) return;
    try {
      await AdminApiService.instance.setHourlyRate(admin['id'].toString(), rate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rate updated (effective next Monday if they have prior pay).'),
          backgroundColor: AColors.green));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _forceEnd(Map<String, dynamic> admin) async {
    final shifts = await AdminApiService.instance
        .adminShiftsList(adminId: admin['id'].toString());
    final active = shifts.firstWhere((s) => s['is_active'] == true, orElse: () => {});
    if (active.isEmpty || !mounted) return;
    final reason = await showAdminTextPrompt(context,
        title: 'Force-end ${admin['name']}\'s shift',
        label: 'Reason', actionLabel: 'Force end');
    if (reason == null) return;
    try {
      await AdminApiService.instance
          .forceEndShift(active['id'].toString(), reason: reason);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _generatePayroll() async {
    try {
      final r = await AdminApiService.instance.generatePayroll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Payroll for ${r['period_start']}–${r['period_end']}: '
              '${r['created']} new, ${r['updated']} updated, ${r['skipped_paid']} already paid'),
          backgroundColor: AColors.green));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _markPaid(Map<String, dynamic> payment) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AColors.bg,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Payment method', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final m in const ['cash', 'bank_transfer', 'mobile_wallet'])
            ListTile(
              title: Text(m.replaceAll('_', ' ')),
              onTap: () => Navigator.pop(context, m),
            ),
        ],
      ),
    );
    if (method == null || !mounted) return;
    final ref = await showAdminTextPrompt(context,
        title: 'Transaction reference',
        label: 'Reference / txn id (optional)',
        actionLabel: 'Mark paid',
        maxLines: 1);
    try {
      await AdminApiService.instance.markPaymentPaid(payment['id'].toString(),
          method: method, reference: ref ?? '');
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _export() async {
    try {
      final r = await AdminApiService.instance.exportPayroll();
      if (!mounted) return;
      showAdminDetails(context,
          title: r.filename,
          icon: Icons.download,
          fields: [MapEntry('CSV (${r.csv.split('\n').length - 1} rows)', r.csv)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Team & Payroll',
      module: AdminModule.teamPayroll,
      appBarActions: [
        IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
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
              tabs: const [Tab(text: 'Team'), Tab(text: 'Payroll')],
            ),
          ),
          Expanded(
            child: _loading
                ? const AdminLoading()
                : _error != null
                    ? AdminError(_error!, _load)
                    : TabBarView(
                        controller: _tabs,
                        children: [_teamTab(), _payrollTab()],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _teamTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _summaryCard('Admins', '${_summary['total_admins'] ?? _admins.length}'),
          _summaryCard('On shift now', '${_summary['on_shift'] ?? 0}', color: AColors.green),
          _summaryCard('Hours this week', '${_summary['total_hours_this_week'] ?? 0}'),
          _summaryCard('Payroll due', '৳${_summary['payment_due_this_week'] ?? 0}', color: AColors.orange),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final f in const ['all', 'online', 'offline'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f == 'all' ? 'All' : (f == 'online' ? "Who's online" : "Who's offline")),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        for (final a in _filtered) _adminCard(a),
        if (_filtered.isEmpty) const AdminEmpty('No admins in this view'),
      ],
    );
  }

  Widget _adminCard(Map<String, dynamic> a) {
    final onShift = a['is_on_shift'] == true;
    final onBreak = a['on_break'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 9, height: 9,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onBreak ? AColors.amber : (onShift ? AColors.green : AColors.grey),
              ),
            ),
            Expanded(
              child: Text(a['name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            aChip(a['role_display']?.toString() ?? 'Admin', AColors.blue, AColors.blue, fontSize: 10),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _kv('Week', '${a['hours_this_week']} h'),
            _kv('Month', '${a['hours_this_month']} h'),
            _kv('Rate', '৳${a['hourly_rate']}/h'),
            _kv('OT', '${a['overtime_hours_week']} h'),
            _kv('Due (wk)', '৳${a['payment_due_this_week']}'),
          ]),
          if (a['pending_hourly_rate'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'New rate ৳${a['pending_hourly_rate']} from ${a['pending_rate_effective_from']}',
                  style: const TextStyle(fontSize: 10, color: AColors.orange)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: () => _editRate(a),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Set rate'),
            ),
            if (onShift)
              OutlinedButton(
                onPressed: () => _forceEnd(a),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AColors.red, visualDensity: VisualDensity.compact),
                child: const Text('Force end shift'),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _payrollTab() {
    final pending = _payments.where((p) => p['status'] == 'pending').toList();
    final done = _payments.where((p) => p['status'] != 'pending').toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _generatePayroll,
              icon: const Icon(Icons.calculate_outlined, size: 16),
              label: const Text('Generate Weekly Payroll'),
              style: FilledButton.styleFrom(backgroundColor: AColors.primary),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Generates the last completed week (Mon–Sun). Paid rows are never overwritten.',
            style: TextStyle(fontSize: 11, color: AColors.grey)),
        const SizedBox(height: 12),
        if (pending.isNotEmpty) ...[
          const Text('Pending', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          for (final p in pending) _paymentCard(p, payable: true),
          const SizedBox(height: 12),
        ],
        const Text('History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        if (done.isEmpty) const AdminEmpty('No payments yet'),
        for (final p in done) _paymentCard(p, payable: false),
      ],
    );
  }

  Widget _paymentCard(Map<String, dynamic> p, {required bool payable}) {
    final statusColor = {
      'pending': AColors.amber,
      'paid': AColors.green,
      'failed': AColors.red,
    }[p['status']] ?? AColors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(p['admin']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            aChip(p['status']?.toString() ?? '', statusColor, statusColor, fontSize: 10),
          ]),
          const SizedBox(height: 4),
          Text('${p['period_start']} → ${p['period_end']}',
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            '${p['regular_hours']} h reg + ${p['overtime_hours']} h OT · '
            '৳${p['hourly_rate']}/h  →  ৳${p['total_payment']}',
            style: const TextStyle(fontSize: 12, color: AColors.textPrimary),
          ),
          if ((p['payment_method'] ?? '').toString().isNotEmpty)
            Text('Paid via ${p['payment_method']} · ${p['payment_reference']}',
                style: const TextStyle(fontSize: 10, color: AColors.grey)),
          if (payable) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _markPaid(p),
              style: FilledButton.styleFrom(
                  backgroundColor: AColors.green, visualDensity: VisualDensity.compact),
              child: const Text('Mark paid'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, {Color color = AColors.primary}) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: aCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          ],
        ),
      );

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 9, color: AColors.grey)),
          Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      );
}
