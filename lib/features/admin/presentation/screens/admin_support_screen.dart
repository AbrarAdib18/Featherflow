import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';
import '../widgets/admin_dialogs.dart';

class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<_TicketData> _tickets;
  late List<_FlagData> _flags;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tickets = [];
    _flags = [];
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
        AdminApiService.instance.list('support-tickets'),
        AdminApiService.instance.list('security-flags'),
      ]);
      if (!mounted) return;
      setState(() {
        _tickets = data[0].map(_TicketData.fromJson).toList();
        _flags = data[1].map(_FlagData.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString()), backgroundColor: AColors.red));
    }
  }

  Future<void> _resolve(String id) async {
    final t = _tickets.firstWhere((t) => t.id == id);
    final updated = _TicketData.fromJson(await AdminApiService.instance
        .update('support-tickets', id, {'status': 'Resolved'}));
    if (!mounted) return;
    setState(() {
      final i = _tickets.indexOf(t);
      _tickets[i] = updated;
    });
    AuditService.instance.log('Support', 'Resolve Ticket', t.subject);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ticket ${t.id} resolved'),
        backgroundColor: AColors.green,
        duration: const Duration(seconds: 2)));
  }

  Future<void> _escalate(String id) async {
    final t = _tickets.firstWhere((t) => t.id == id);
    final updated = _TicketData.fromJson(await AdminApiService.instance
        .update('support-tickets', id, {'status': 'Escalated'}));
    if (!mounted) return;
    setState(() {
      final i = _tickets.indexOf(t);
      _tickets[i] = updated;
    });
    AuditService.instance.log('Support', 'Escalate Ticket', t.subject);
  }

  Future<void> _clearFlag(String id) async {
    final f = _flags.firstWhere((f) => f.id == id);
    final updated = _FlagData.fromJson(await AdminApiService.instance
        .update('security-flags', id, {'cleared': true}));
    if (!mounted) return;
    setState(() {
      final i = _flags.indexOf(f);
      _flags[i] = updated;
    });
    AuditService.instance.log('Support', 'Clear Security Flag', f.user);
  }

  Future<void> _reply(String id) async {
    final ticket = _tickets.firstWhere((t) => t.id == id);
    final reply = await showAdminTextPrompt(context,
        title: 'Reply to ${ticket.user}',
        label: 'Support message',
        actionLabel: 'Send Reply');
    if (reply == null || !mounted) return;
    await AdminApiService.instance
        .update('support-tickets', id, {'last_reply': reply});
    if (!mounted) return;
    AuditService.instance
        .log('Support', 'Reply to Ticket', ticket.subject, details: reply);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Reply sent for ticket ${ticket.id}'),
        backgroundColor: AColors.blue));
  }

  Future<void> _processRecovery(String id) async {
    final ticket = _tickets.firstWhere((t) => t.id == id);
    final updated = _TicketData.fromJson(await AdminApiService.instance
        .update('support-tickets', id, {'status': 'Resolved'}));
    if (!mounted) return;
    setState(() {
      final i = _tickets.indexOf(ticket);
      _tickets[i] = updated;
    });
    AuditService.instance.log(
        'Support', 'Process Account Recovery', ticket.user,
        details: ticket.subject);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Identity verified and recovery instructions sent'),
        backgroundColor: AColors.green));
  }

  void _investigate(_FlagData flag) {
    AuditService.instance.log('Support', 'Investigate Security Flag', flag.id,
        details: flag.description);
    showAdminDetails(context,
        title: 'Security investigation ${flag.id}',
        icon: Icons.security_outlined,
        fields: [
          MapEntry('Affected account / source', flag.user),
          MapEntry('Signal type', flag.type),
          MapEntry('Severity', flag.severity),
          MapEntry('Detected', flag.date),
          MapEntry('Evidence', flag.description),
          const MapEntry('Recommended action',
              'Review authentication activity, verify the account owner, then clear the flag only when the activity is confirmed safe.'),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Support & Safety',
      module: AdminModule.supportSafety,
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
                Tab(text: 'Tickets'),
                Tab(text: 'Account Recovery'),
                Tab(text: 'Security Flags'),
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
                      _TicketList(
                          tickets: _tickets,
                          onResolve: _resolve,
                          onEscalate: _escalate,
                          onReply: _reply),
                      _RecoveryList(
                          tickets: _tickets
                              .where((t) => t.type == 'Account Recovery')
                              .toList(),
                          onProcess: _processRecovery),
                      _SecurityFlagList(
                          flags: _flags,
                          onClear: _clearFlag,
                          onInvestigate: _investigate),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Tickets tab ───────────────────────────────────────────────────────────────

class _TicketList extends StatelessWidget {
  final List<_TicketData> tickets;
  final void Function(String) onResolve;
  final void Function(String) onEscalate;
  final void Function(String) onReply;

  const _TicketList(
      {required this.tickets,
      required this.onResolve,
      required this.onEscalate,
      required this.onReply});

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const Center(
          child: Text('No tickets.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _TicketCard(
          ticket: tickets[i],
          onResolve: onResolve,
          onEscalate: onEscalate,
          onReply: onReply),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final _TicketData ticket;
  final void Function(String) onResolve;
  final void Function(String) onEscalate;
  final void Function(String) onReply;

  const _TicketCard(
      {required this.ticket,
      required this.onResolve,
      required this.onEscalate,
      required this.onReply});

  Color get _priorityColor {
    switch (ticket.priority) {
      case 'High':
        return AColors.red;
      case 'Medium':
        return AColors.amber;
      default:
        return AColors.secondary;
    }
  }

  Color get _statusColor {
    switch (ticket.status) {
      case 'Open':
        return AColors.blue;
      case 'Resolved':
        return AColors.green;
      case 'Escalated':
        return AColors.orange;
      default:
        return AColors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: ticket.priority == 'High'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              aChip(ticket.priority, _priorityColor, _priorityColor),
              const SizedBox(width: 6),
              aChip(ticket.type, AColors.blue, AColors.blue),
              const Spacer(),
              aChip(ticket.status, _statusColor, _statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(ticket.subject,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          Text('${ticket.user} · ${ticket.id}',
              style:
                  const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          Text(ticket.date,
              style: const TextStyle(fontSize: 10, color: AColors.grey)),
          const SizedBox(height: 4),
          Text(ticket.description,
              style: const TextStyle(
                  fontSize: 12, color: AColors.grey, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          if (ticket.status == 'Open')
            Row(
              children: [
                PermissionGuard(
                  module: AdminModule.supportSafety,
                  permission: AdminPermission.edit,
                  child: _Chip(
                      'Resolve', AColors.green, () => onResolve(ticket.id)),
                ),
                const SizedBox(width: 8),
                PermissionGuard(
                  module: AdminModule.supportSafety,
                  permission: AdminPermission.edit,
                  child: _Chip(
                      'Escalate', AColors.orange, () => onEscalate(ticket.id)),
                ),
                const SizedBox(width: 8),
                _Chip('Reply', AColors.blue, () => onReply(ticket.id)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Account recovery tab ──────────────────────────────────────────────────────

class _RecoveryList extends StatelessWidget {
  final List<_TicketData> tickets;
  final void Function(String) onProcess;

  const _RecoveryList({required this.tickets, required this.onProcess});

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const Center(
          child: Text('No recovery requests.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(14),
        decoration: aCard(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AColors.blueLight,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.lock_reset_outlined,
                  color: AColors.blue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tickets[i].subject,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AColors.textPrimary)),
                  Text(tickets[i].user,
                      style: const TextStyle(
                          fontSize: 11, color: AColors.textSecondary)),
                  Text(tickets[i].date,
                      style:
                          const TextStyle(fontSize: 10, color: AColors.grey)),
                ],
              ),
            ),
            PermissionGuard(
              module: AdminModule.supportSafety,
              permission: AdminPermission.edit,
              child: _Chip(
                  'Process', AColors.secondary, () => onProcess(tickets[i].id)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Security flags tab ────────────────────────────────────────────────────────

class _SecurityFlagList extends StatelessWidget {
  final List<_FlagData> flags;
  final void Function(String) onClear;
  final void Function(_FlagData) onInvestigate;

  const _SecurityFlagList(
      {required this.flags,
      required this.onClear,
      required this.onInvestigate});

  @override
  Widget build(BuildContext context) {
    final active = flags.where((f) => !f.cleared).toList();
    if (active.isEmpty) {
      return const Center(
          child: Text('No active security flags.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: active.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _FlagCard(
          flag: active[i], onClear: onClear, onInvestigate: onInvestigate),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final _FlagData flag;
  final void Function(String) onClear;
  final void Function(_FlagData) onInvestigate;

  const _FlagCard(
      {required this.flag, required this.onClear, required this.onInvestigate});

  Color get _severityColor {
    switch (flag.severity) {
      case 'Critical':
        return AColors.red;
      case 'High':
        return AColors.orange;
      default:
        return AColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(highlight: flag.severity == 'Critical'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              aChip(flag.severity, _severityColor, _severityColor),
              const SizedBox(width: 6),
              aChip(flag.type, AColors.purple, AColors.purple),
              const Spacer(),
              Text(flag.date,
                  style: const TextStyle(fontSize: 10, color: AColors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(flag.description,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AColors.textPrimary)),
          Text('User: ${flag.user}',
              style:
                  const TextStyle(fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.supportSafety,
                permission: AdminPermission.edit,
                child:
                    _Chip('Clear Flag', AColors.green, () => onClear(flag.id)),
              ),
              const SizedBox(width: 8),
              _Chip('Investigate', AColors.blue, () => onInvestigate(flag)),
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

class _TicketData {
  final String id, user, subject, type, priority, status, date, description;

  const _TicketData({
    required this.id,
    required this.user,
    required this.subject,
    required this.type,
    required this.priority,
    required this.status,
    required this.date,
    required this.description,
  });

  factory _TicketData.fromJson(Map<String, dynamic> json) => _TicketData(
        id: json['id'].toString(),
        user: json['user']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        priority: json['priority']?.toString() ?? 'Low',
        status: json['status']?.toString() ?? 'Open',
        date: json['date']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );

  _TicketData copyWith({String? status}) => _TicketData(
        id: id,
        user: user,
        subject: subject,
        type: type,
        priority: priority,
        status: status ?? this.status,
        date: date,
        description: description,
      );
}

class _FlagData {
  final String id, user, type, severity, description, date;
  final bool cleared;

  const _FlagData({
    required this.id,
    required this.user,
    required this.type,
    required this.severity,
    required this.description,
    required this.date,
    required this.cleared,
  });

  factory _FlagData.fromJson(Map<String, dynamic> json) => _FlagData(
        id: json['id'].toString(),
        user: json['user']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        severity: json['severity']?.toString() ?? 'Medium',
        description: json['description']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        cleared: json['cleared'] == true,
      );

  _FlagData copyWith({bool? cleared}) => _FlagData(
        id: id,
        user: user,
        type: type,
        severity: severity,
        description: description,
        date: date,
        cleared: cleared ?? this.cleared,
      );
}

