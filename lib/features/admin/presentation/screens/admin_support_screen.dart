import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/audit_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/permission_guard.dart';

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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tickets = List.of(_kTickets);
    _flags = List.of(_kFlags);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _resolve(String id) {
    final t = _tickets.firstWhere((t) => t.id == id);
    setState(() {
      final i = _tickets.indexOf(t);
      _tickets[i] = t.copyWith(status: 'Resolved');
    });
    AuditService.instance.log('Support', 'Resolve Ticket', t.subject);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ticket ${t.id} resolved'),
        backgroundColor: AColors.green,
        duration: const Duration(seconds: 2)));
  }

  void _escalate(String id) {
    final t = _tickets.firstWhere((t) => t.id == id);
    setState(() {
      final i = _tickets.indexOf(t);
      _tickets[i] = t.copyWith(status: 'Escalated');
    });
    AuditService.instance.log('Support', 'Escalate Ticket', t.subject);
  }

  void _clearFlag(String id) {
    final f = _flags.firstWhere((f) => f.id == id);
    setState(() {
      final i = _flags.indexOf(f);
      _flags[i] = f.copyWith(cleared: true);
    });
    AuditService.instance
        .log('Support', 'Clear Security Flag', f.user);
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
            child: TabBarView(
              controller: _tabs,
              children: [
                _TicketList(
                    tickets: _tickets,
                    onResolve: _resolve,
                    onEscalate: _escalate),
                _RecoveryList(tickets: _tickets
                    .where((t) => t.type == 'Account Recovery')
                    .toList()),
                _SecurityFlagList(flags: _flags, onClear: _clearFlag),
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

  const _TicketList(
      {required this.tickets,
      required this.onResolve,
      required this.onEscalate});

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const Center(
          child: Text('No tickets.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _TicketCard(
          ticket: tickets[i], onResolve: onResolve, onEscalate: onEscalate),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final _TicketData ticket;
  final void Function(String) onResolve;
  final void Function(String) onEscalate;

  const _TicketCard(
      {required this.ticket,
      required this.onResolve,
      required this.onEscalate});

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
              style: const TextStyle(
                  fontSize: 11, color: AColors.textSecondary)),
          Text(ticket.date,
              style:
                  const TextStyle(fontSize: 10, color: AColors.grey)),
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
                  child: _Chip('Resolve', AColors.green,
                      () => onResolve(ticket.id)),
                ),
                const SizedBox(width: 8),
                PermissionGuard(
                  module: AdminModule.supportSafety,
                  permission: AdminPermission.edit,
                  child: _Chip('Escalate', AColors.orange,
                      () => onEscalate(ticket.id)),
                ),
                const SizedBox(width: 8),
                _Chip('Reply', AColors.blue, () {}),
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

  const _RecoveryList({required this.tickets});

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return const Center(
          child: Text('No recovery requests.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
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
                      style: const TextStyle(
                          fontSize: 10, color: AColors.grey)),
                ],
              ),
            ),
            PermissionGuard(
              module: AdminModule.supportSafety,
              permission: AdminPermission.edit,
              child: _Chip('Process', AColors.secondary, () {}),
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

  const _SecurityFlagList(
      {required this.flags, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final active = flags.where((f) => !f.cleared).toList();
    if (active.isEmpty) {
      return const Center(
          child: Text('No active security flags.',
              style:
                  TextStyle(color: AColors.textSecondary, fontSize: 13)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: active.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _FlagCard(flag: active[i], onClear: onClear),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final _FlagData flag;
  final void Function(String) onClear;

  const _FlagCard({required this.flag, required this.onClear});

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
                  style: const TextStyle(
                      fontSize: 10, color: AColors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(flag.description,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AColors.textPrimary)),
          Text('User: ${flag.user}',
              style: const TextStyle(
                  fontSize: 11, color: AColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              PermissionGuard(
                module: AdminModule.supportSafety,
                permission: AdminPermission.edit,
                child: _Chip('Clear Flag', AColors.green,
                    () => onClear(flag.id)),
              ),
              const SizedBox(width: 8),
              _Chip('Investigate', AColors.blue, () {}),
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

const _kTickets = [
  _TicketData(
      id: 'SUP-041',
      user: 'Karim Hossain',
      subject: 'Cannot login after password reset',
      type: 'Login Issue',
      priority: 'High',
      status: 'Open',
      date: 'Jun 12, 2024 09:15 AM',
      description:
          'User says they reset password via email link but still getting invalid credentials error.'),
  _TicketData(
      id: 'SUP-042',
      user: 'MedPlus Pharmacy',
      subject: 'Account suspended without notice',
      type: 'Account Issue',
      priority: 'High',
      status: 'Open',
      date: 'Jun 11, 2024 02:30 PM',
      description:
          'Pharmacy account was suspended. Owner claims no policy violation. Requesting immediate review.'),
  _TicketData(
      id: 'SUP-043',
      user: 'Rahim Uddin',
      subject: 'Delivery earnings not credited',
      type: 'Payment Issue',
      priority: 'Medium',
      status: 'Escalated',
      date: 'Jun 10, 2024 11:00 AM',
      description:
          'Delivery rider reports ৳2,400 from last week not credited to wallet.'),
  _TicketData(
      id: 'SUP-044',
      user: 'Sumaiya Islam',
      subject: 'Cannot access account — 2FA not working',
      type: 'Account Recovery',
      priority: 'Medium',
      status: 'Open',
      date: 'Jun 9, 2024 04:45 PM',
      description:
          'Researcher lost access to 2FA app after phone replacement. Requesting recovery.'),
];

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

const _kFlags = [
  _FlagData(
      id: 'SF001',
      user: 'Unknown IP 192.168.45.12',
      type: 'Brute Force',
      severity: 'Critical',
      description: '47 failed login attempts in 10 minutes targeting admin panel',
      date: 'Jun 12, 2024',
      cleared: false),
  _FlagData(
      id: 'SF002',
      user: 'Farmer Alam',
      type: 'Suspicious Activity',
      severity: 'High',
      description: 'Account accessed from 3 different countries within 2 hours',
      date: 'Jun 11, 2024',
      cleared: false),
  _FlagData(
      id: 'SF003',
      user: 'Spam Account #42',
      type: 'Content Abuse',
      severity: 'Medium',
      description: 'Posted 15 identical spam messages in 5 minutes',
      date: 'Jun 10, 2024',
      cleared: false),
];
