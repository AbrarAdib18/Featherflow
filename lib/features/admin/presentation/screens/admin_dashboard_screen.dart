import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Dashboard',
      module: AdminModule.dashboard,
      appBarActions: [_RoleSwitcherButton()],
      child: const _DashboardBody(),
    );
  }
}

// ── Role switcher (demo utility) ─────────────────────────────────────────────

class _RoleSwitcherButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) => TextButton.icon(
        icon: const Icon(Icons.swap_horiz, size: 16, color: AColors.secondary),
        label: Text(
          AdminSession.instance.roleDisplayName,
          style: const TextStyle(
              color: AColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        onPressed: () => _showRolePicker(context),
      ),
    );
  }

  void _showRolePicker(BuildContext context) {
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
            child: Row(
              children: [
                const Text('Switch Role (Demo)',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AColors.textPrimary)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AColors.textSecondary),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          ...AdminRole.values.map((role) => ListenableBuilder(
                listenable: AdminSession.instance,
                builder: (_, __) {
                  final selected = AdminSession.instance.role == role;
                  return ListTile(
                    leading: Icon(Icons.verified_user_outlined,
                        color: selected
                            ? AColors.secondary
                            : AColors.textSecondary,
                        size: 20),
                    title: Text(kRoleDisplayNames[role]!,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected
                                ? AColors.primary
                                : AColors.textPrimary)),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: AColors.secondary, size: 18)
                        : null,
                    onTap: () {
                      AdminSession.instance.setRole(role);
                      Navigator.pop(context);
                    },
                  );
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Dashboard body ────────────────────────────────────────────────────────────

class _DashboardBody extends StatefulWidget {
  const _DashboardBody();

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _activity = [];

  @override
  void initState() {
    super.initState();
    AdminApiService.instance.dashboard().then((data) {
      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
        _tasks = (data['tasks'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _activity = (data['activity'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AlertBanner(
            Icons.warning_amber_rounded,
            '${_stats['urgent_consultations'] ?? 0} urgent consultation cases need escalation',
            AColors.red,
            AColors.redLight,
            '/admin/doctors',
          ),
          const SizedBox(height: 8),
          _AlertBanner(
            Icons.info_outline,
            '${_stats['pending_pharmacies'] ?? 0} pending pharmacy approvals awaiting review',
            AColors.amber,
            AColors.amberLight,
            '/admin/pharmacy',
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Overview'),
          const SizedBox(height: 12),
          _OverviewGrid(stats: _stats),
          const SizedBox(height: 24),
          const _SectionTitle('Pending Tasks'),
          const SizedBox(height: 12),
          _PendingTasksPanel(tasks: _tasks),
          const SizedBox(height: 24),
          const _SectionTitle('Recent Activity'),
          const SizedBox(height: 12),
          _RecentActivityPanel(activity: _activity),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color bg;
  final String route;

  const _AlertBanner(this.icon, this.message, this.color, this.bg, this.route);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => context.go(route),
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('View', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Overview grid — cards filtered by role ───────────────────────────────────

class _OverviewGrid extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _OverviewGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        final session = AdminSession.instance;
        final cards = <_CardDef>[
          if (session.canAccess(AdminModule.userManagement))
            _CardDef(
                'Active Users',
                '${stats['total_users'] ?? 0}',
                Icons.people_outline,
                AColors.secondary,
                AColors.greenLight,
                '/admin/users',
                extra: 'Approved'),
          if (session.canAccess(AdminModule.userManagement))
            _CardDef(
                'Pending Approvals',
                '${stats['pending_approvals'] ?? 0}',
                Icons.pending_actions_outlined,
                AColors.amber,
                AColors.amberLight,
                '/admin/users',
                extra: 'Pending'),
          if (session.canAccess(AdminModule.supportSafety))
            _CardDef(
                'Open Tickets',
                '${stats['open_tickets'] ?? 0}',
                Icons.support_agent_outlined,
                AColors.blue,
                AColors.blueLight,
                '/admin/support'),
          if (session.canAccess(AdminModule.communityModeration))
            _CardDef(
                'Flagged Content',
                '${stats['flagged_content'] ?? 0}',
                Icons.flag_outlined,
                AColors.red,
                AColors.redLight,
                '/admin/community'),
          if (session.canAccess(AdminModule.doctorPatient))
            _CardDef(
                'Active Doctors',
                '${stats['active_doctors'] ?? 0}',
                Icons.medical_services_outlined,
                AColors.secondary,
                AColors.greenLight,
                '/admin/doctors'),
          if (session.canAccess(AdminModule.deliveryManagement))
            _CardDef(
                'Deliveries In Progress',
                '${stats['deliveries_in_progress'] ?? 0}',
                Icons.local_shipping_outlined,
                AColors.orange,
                AColors.orangeLight,
                '/admin/delivery'),
          if (session.canAccess(AdminModule.financeSubscriptions))
            _CardDef(
                'Monthly Revenue',
                '৳${stats['monthly_revenue'] ?? 0}',
                Icons.account_balance_wallet_outlined,
                AColors.green,
                AColors.greenLight,
                '/admin/finance'),
          if (session.canAccess(AdminModule.pharmacyManagement))
            _CardDef(
                'Active Pharmacies',
                '${stats['active_pharmacies'] ?? 0}',
                Icons.local_pharmacy_outlined,
                AColors.purple,
                AColors.purpleLight,
                '/admin/pharmacy'),
        ];

        if (cards.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: aCard(),
            child: const Center(
              child: Text('No overview data for your role.',
                  style: TextStyle(color: AColors.textSecondary, fontSize: 13)),
            ),
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((c) => SizedBox(
                    width: (MediaQuery.of(context).size.width -
                            (MediaQuery.of(context).size.width >=
                                    kBreakpointWide
                                ? kSidebarWidth + 52
                                : 42)) /
                        2,
                    child: _SummaryCard(c),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _CardDef {
  final String label, value, route;
  final IconData icon;
  final Color color, bg;
  final Object? extra;

  const _CardDef(
      this.label, this.value, this.icon, this.color, this.bg, this.route,
      {this.extra});
}

class _SummaryCard extends StatelessWidget {
  final _CardDef c;
  const _SummaryCard(this.c);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(c.route, extra: c.extra),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: aCard(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: c.bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(c.icon, color: c.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.value,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AColors.textPrimary)),
                  Text(c.label,
                      style: const TextStyle(
                          fontSize: 10, color: AColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AColors.grey),
          ],
        ),
      ),
    );
  }
}

String _moduleRoute(AdminModule module) {
  switch (module) {
    case AdminModule.userManagement:
      return '/admin/users';
    case AdminModule.doctorPatient:
      return '/admin/doctors';
    case AdminModule.deliveryManagement:
      return '/admin/delivery';
    case AdminModule.pharmacyManagement:
      return '/admin/pharmacy';
    case AdminModule.financeSubscriptions:
      return '/admin/finance';
    case AdminModule.communityModeration:
      return '/admin/community';
    case AdminModule.researchArticles:
      return '/admin/content';
    case AdminModule.supportSafety:
      return '/admin/support';
    case AdminModule.teamManagement:
      return '/admin/team';
    default:
      return '/admin';
  }
}

// ── Pending tasks ─────────────────────────────────────────────────────────────

class _PendingTasksPanel extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;

  const _PendingTasksPanel({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final mapped = tasks.map((item) {
      final moduleName = item['module']?.toString() ?? '';
      final module = moduleName.contains('Doctor')
          ? AdminModule.doctorPatient
          : moduleName.contains('Support')
              ? AdminModule.supportSafety
              : AdminModule.userManagement;
      return _TaskData(
          item['title']?.toString() ?? '',
          '${item['count'] ?? 0} items awaiting action',
          module == AdminModule.doctorPatient
              ? Icons.medical_services_outlined
              : module == AdminModule.supportSafety
                  ? Icons.support_agent_outlined
                  : Icons.pending_actions_outlined,
          AColors.amber,
          module);
    }).toList();
    final visible = mapped.where((t) => session.canAccess(t.module)).toList();

    if (visible.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: aCard(),
        child: const Center(
          child: Text('No pending tasks for your role.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)),
        ),
      );
    }

    return Container(
      decoration: aCard(),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            _TaskTile(visible[i]),
            if (i < visible.length - 1)
              const Divider(
                  height: 1, indent: 14, endIndent: 14, color: AColors.divider),
          ],
        ],
      ),
    );
  }
}

class _TaskData {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final AdminModule module;

  const _TaskData(
      this.title, this.subtitle, this.icon, this.color, this.module);
}

class _TaskTile extends StatelessWidget {
  final _TaskData task;
  const _TaskTile(this.task);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: task.color.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(task.icon, size: 15, color: task.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AColors.textPrimary)),
                Text(task.subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.go(_moduleRoute(task.module)),
            style: TextButton.styleFrom(
              foregroundColor: AColors.secondary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Act', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _RecentActivityPanel extends StatelessWidget {
  final List<Map<String, dynamic>> activity;

  const _RecentActivityPanel({required this.activity});

  @override
  Widget build(BuildContext context) {
    final items = activity
        .map((item) => _ActivityItem(
              item['created_at']
                      ?.toString()
                      .replaceFirst('T', ' ')
                      .split('.')
                      .first ??
                  '',
              item['action']?.toString() ?? '',
              '${item['module'] ?? ''} · ${item['entity_id'] ?? ''}',
              Icons.history,
              AColors.blue,
            ))
        .toList();
    return Container(
      decoration: aCard(),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _ActivityTile(items[i]),
            if (i < items.length - 1)
              const Divider(
                  height: 1, indent: 14, endIndent: 14, color: AColors.divider),
          ],
        ],
      ),
    );
  }
}

class _ActivityItem {
  final String time, action, user;
  final IconData icon;
  final Color color;

  const _ActivityItem(this.time, this.action, this.user, this.icon, this.color);
}

class _ActivityTile extends StatelessWidget {
  final _ActivityItem item;
  const _ActivityTile(this.item);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(item.icon, size: 14, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.action,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AColors.textPrimary)),
                Text(item.user,
                    style: const TextStyle(
                        fontSize: 11, color: AColors.textSecondary)),
              ],
            ),
          ),
          Text(item.time,
              style: const TextStyle(fontSize: 11, color: AColors.grey)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AColors.textPrimary),
      );
}
