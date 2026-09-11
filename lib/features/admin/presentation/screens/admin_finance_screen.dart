import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/module_activity.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key});

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_PaymentData> _payments;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _payments = [];
    _loadPayments();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    try {
      final data = await AdminApiService.instance.list('payments');
      if (!mounted) return;
      setState(() {
        _payments = data.map(_PaymentData.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _refund(String id) async {
    final p = _payments.firstWhere((p) => p.id == id);
    final response = await AdminApiService.instance
        .update('payments', id, {'status': 'Refunded'});
    final updated = _PaymentData.fromJson(response);
    if (!mounted) return;
    setState(() {
      final i = _payments.indexOf(p);
      _payments[i] = updated;
    });
    AuditService.instance
        .log('Finance', 'Refund', p.user, details: '৳${p.amount}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Refund of ৳${p.amount} issued to ${p.user}'),
        backgroundColor: AColors.blue,
        duration: const Duration(seconds: 2)));
  }

  Future<void> _edit(_PaymentData payment) async {
    final values = await showAdminRecordEditor(context,
        title: 'Edit Payment Record',
        fields: {
          'User': payment.user,
          'Type': payment.type,
          'Plan / Method': payment.plan,
          'Status': payment.status,
          'Amount': '${payment.amount}',
          'Date': payment.date,
        });
    if (values == null) return;
    final response =
        await AdminApiService.instance.update('payments', payment.id, {
      'user': values['User'],
      'type': values['Type'],
      'plan': values['Plan / Method'],
      'status': values['Status'],
      'amount': int.tryParse(values['Amount'] ?? '') ?? payment.amount,
      'date': values['Date'],
    });
    if (!mounted) return;
    setState(() => _payments[_payments.indexOf(payment)] =
        _PaymentData.fromJson(response));
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final hasFinanceAccess =
        session.can(AdminModule.financeSubscriptions, AdminPermission.view);

    if (!hasFinanceAccess) {
      return const AdminScaffold(
        title: 'Finance',
        module: AdminModule.financeSubscriptions,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: AColors.grey),
              SizedBox(height: 16),
              Text('Access Restricted',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AColors.textPrimary)),
              SizedBox(height: 8),
              Text('Finance data is restricted to Finance Admins.',
                  style: TextStyle(fontSize: 13, color: AColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return AdminScaffold(
      title: 'Finance & Subscriptions',
      module: AdminModule.financeSubscriptions,
      appBarActions: const [
        ModuleActivityButton(title: 'Finance', modules: ['payments']),
      ],
      child: Column(
        children: [
          _SummaryBar(),
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
                Tab(text: 'All Payments'),
                Tab(text: 'Failed'),
                Tab(text: 'Refunds'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AColors.secondary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _PaymentList(
                          payments: _payments,
                          onRefund: _refund,
                          onEdit: _edit),
                      _PaymentList(
                          payments: _payments
                              .where((p) => p.status == 'Failed')
                              .toList(),
                          onRefund: _refund,
                          onEdit: _edit),
                      _PaymentList(
                          payments: _payments
                              .where((p) =>
                                  p.status == 'Refunded' ||
                                  p.type == 'Refund Request')
                              .toList(),
                          onRefund: _refund,
                          onEdit: _edit),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatefulWidget {
  @override
  State<_SummaryBar> createState() => _SummaryBarState();
}

class _SummaryBarState extends State<_SummaryBar> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    AdminApiService.instance.financeSummary().then((data) {
      if (mounted) setState(() => _summary = data);
    }).catchError((_) {});
  }

  String _money(String key) {
    final v = (_summary?[key] as num?)?.toDouble() ?? 0;
    if (v >= 1000000) return '৳${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '৳${(v / 1000).toStringAsFixed(1)}K';
    return '৳${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AColors.surface2,
      child: Row(
        children: [
          Expanded(
              child: _StatCard(_money('mrr'), 'Monthly Revenue',
                  Icons.trending_up, AColors.green, AColors.greenLight)),
          const SizedBox(width: 8),
          Expanded(
              child: _StatCard(_money('pending_payout_liability'),
                  'Pending Payouts', Icons.schedule, AColors.blue, AColors.blueLight)),
          const SizedBox(width: 8),
          Expanded(
              child: _StatCard(_money('total_refunds'), 'Refunds',
                  Icons.replay_outlined, AColors.red, AColors.redLight)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color, bg;

  const _StatCard(this.value, this.label, this.icon, this.color, this.bg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AColors.textSecondary),
              maxLines: 2),
        ],
      ),
    );
  }
}

// ── Payment list ──────────────────────────────────────────────────────────────

class _PaymentList extends StatelessWidget {
  final List<_PaymentData> payments;
  final void Function(String) onRefund;
  final void Function(_PaymentData) onEdit;

  const _PaymentList(
      {required this.payments, required this.onRefund, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const Center(
          child: Text('No records found.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PaymentCard(
          payment: payments[i], onRefund: onRefund, onEdit: onEdit),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final _PaymentData payment;
  final void Function(String) onRefund;
  final void Function(_PaymentData) onEdit;

  const _PaymentCard(
      {required this.payment, required this.onRefund, required this.onEdit});

  Color get _statusColor {
    switch (payment.status) {
      case 'Paid':
        return AColors.green;
      case 'Pending':
        return AColors.amber;
      case 'Failed':
        return AColors.red;
      case 'Refunded':
        return AColors.blue;
      default:
        return AColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: payment.status == 'Failed'),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.account_balance_wallet_outlined,
                color: _statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(payment.user,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    aChip(payment.status, _statusColor, _statusColor,
                        fontSize: 10),
                  ],
                ),
                Text('${payment.type} · ${payment.plan}',
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
                Text(payment.date,
                    style: const TextStyle(fontSize: 10, color: AColors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('৳${payment.amount}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: payment.status == 'Refunded'
                          ? AColors.blue
                          : AColors.textPrimary)),
              const SizedBox(height: 6),
              PermissionGuard(
                module: AdminModule.financeSubscriptions,
                permission: AdminPermission.edit,
                child: _Chip('Edit', AColors.grey, () => onEdit(payment)),
              ),
              const SizedBox(height: 4),
              if (payment.status != 'Refunded' && payment.status != 'Failed')
                PermissionGuard(
                  module: AdminModule.financeSubscriptions,
                  permission: AdminPermission.refund,
                  child:
                      _Chip('Refund', AColors.blue, () => onRefund(payment.id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Chip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
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
      ),
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

class _PaymentData {
  final String id, user, type, plan, status, date;
  final int amount;

  const _PaymentData({
    required this.id,
    required this.user,
    required this.type,
    required this.plan,
    required this.status,
    required this.date,
    required this.amount,
  });

  factory _PaymentData.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString() ?? 'Pending';
    return _PaymentData(
      id: json['id'].toString(),
      user: json['user']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Subscription',
      plan: json['plan']?.toString() ?? json['method']?.toString() ?? '',
      status: rawStatus == 'Completed' ? 'Paid' : rawStatus,
      date: json['date']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  _PaymentData copyWith({String? status}) => _PaymentData(
        id: id,
        user: user,
        type: type,
        plan: plan,
        status: status ?? this.status,
        date: date,
        amount: amount,
      );
}
