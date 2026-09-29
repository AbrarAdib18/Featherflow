import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/shift_timer_widget.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Finance Admin gets its own dashboard body entirely (Monthly/Total
    // Revenue, Active Subscriptions, Recent Payments, Pending/Approved
    // Cashout Requests) instead of the Operations-oriented one below — see
    // FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md. This never touches the
    // Operations/Super Admin body, preserving the existing hierarchy as-is.
    final isFinance = AdminSession.instance.role == AdminRole.financeAdmin;
    return AdminScaffold(
      title: 'Dashboard',
      module: AdminModule.dashboard,
      appBarActions: const [_RoleBadge()],
      child: isFinance ? const _FinanceDashboardBody() : const _DashboardBody(),
    );
  }
}

// ── Finance Admin dashboard body ─────────────────────────────────────────────

class _FinanceDashboardBody extends StatefulWidget {
  const _FinanceDashboardBody();
  @override
  State<_FinanceDashboardBody> createState() => _FinanceDashboardBodyState();
}

class _FinanceDashboardBodyState extends State<_FinanceDashboardBody> {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  bool _hasLoadedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await AdminApiService.instance.financeDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _hasLoadedOnce = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _bdt(num v) => '৳${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    final recentPayments = (_data['recent_payments'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AColors.redLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AColors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          _hasLoadedOnce
                              ? 'Could not refresh: $_error (showing last loaded data)'
                              : 'Could not load dashboard: $_error',
                          style: const TextStyle(color: AColors.red, fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _load,
                      child: const Text('Retry', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                // Same _SummaryCard/_CardDef design the rest of the admin
                // panel's overview cards already use (icon + value + label +
                // trailing chevron, whole card tappable) — Monthly/Total
                // Revenue, Subscriptions, and both Cashout cards all share
                // it now, instead of the plain non-navigable card used
                // before.
                _SummaryCard(_CardDef('Monthly Revenue', _bdt((_data['monthly_revenue'] as num?) ?? 0),
                    Icons.trending_up, AColors.green, AColors.greenLight, '/admin/subscriptions')),
                _SummaryCard(_CardDef('Total Revenue', _bdt((_data['total_revenue'] as num?) ?? 0),
                    Icons.account_balance_wallet_outlined, AColors.secondary, AColors.greenLight,
                    '/admin/subscriptions')),
                // Doubles as the "Subscriptions" quick link beside the
                // revenue cards — the module's subscriber count, one tap
                // away from the full Subscriptions screen.
                _SummaryCard(_CardDef('Subscriptions', '${_data['active_subscriptions'] ?? 0} active',
                    Icons.workspace_premium_outlined, AColors.blue, AColors.blueLight,
                    '/admin/subscriptions')),
                // Active Users has no Finance-accessible detail page to
                // link to (the Users module is Operations/Super-Admin-only
                // — see FINANCE_ADMIN_RBAC_CHANGES.md), so it stays a plain,
                // non-navigable figure rather than an arrow to nowhere.
                _FinanceStatCard('Active Users', '${_data['active_users'] ?? 0}',
                    Icons.people_outline, AColors.purple),
                _SummaryCard(_CardDef('Pending Cashout Requests',
                    '${_data['pending_cashout_requests'] ?? 0}', Icons.hourglass_top_outlined,
                    AColors.amber, AColors.amberLight, '/admin/cashouts/pending')),
                _SummaryCard(_CardDef('Approved Cashout Requests',
                    '${_data['approved_cashout_requests'] ?? 0}', Icons.verified_outlined,
                    AColors.green, AColors.greenLight, '/admin/cashouts/approved')),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Pending Tasks'),
            const SizedBox(height: 8),
            _FinancePendingTasksPanel(pendingCashouts: (_data['pending_cashout_requests'] as num?)?.toInt() ?? 0),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Payments',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
                TextButton(
                  onPressed: () => context.go('/admin/subscriptions'),
                  child: const Text('View all payments'),
                ),
              ],
            ),
            if (recentPayments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No payments yet.', style: TextStyle(color: AColors.textSecondary)),
              )
            else
              ...recentPayments.map((p) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: aCard(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['user']?.toString() ?? 'Unknown',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${p['plan']} · ${p['method'] ?? ''}',
                                  style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${p['currency']} ${p['amount']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AColors.secondary)),
                            Text(p['status']?.toString() ?? '',
                                style: const TextStyle(fontSize: 11, color: AColors.grey)),
                          ],
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// A plain, non-navigable metric card — used only for figures with no
// Finance-accessible detail page to link to (e.g. Active Users). Every
// other Finance overview card uses the shared _SummaryCard/_CardDef
// design instead (icon + value + label + trailing chevron).
class _FinanceStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _FinanceStatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AColors.textPrimary),
              overflow: TextOverflow.ellipsis),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AColors.textSecondary),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Finance: Pending Tasks (pending cashout requests) ───────────────────────

class _FinancePendingTasksPanel extends StatelessWidget {
  final int pendingCashouts;
  const _FinancePendingTasksPanel({required this.pendingCashouts});

  @override
  Widget build(BuildContext context) {
    if (pendingCashouts == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: aCard(),
        child: const Center(
          child: Text('No pending tasks.',
              style: TextStyle(color: AColors.textSecondary, fontSize: 13)),
        ),
      );
    }
    // Same _TaskTile design the generic Operations dashboard's Pending
    // Tasks panel already uses — Finance Admin's own pending task is
    // simply "cashout requests awaiting review", so it's fed here
    // directly rather than through the generic dashboard's task-title
    // heuristic (which doesn't know about cashouts).
    return Container(
      decoration: aCard(),
      child: _TaskTile(_TaskData(
        'Cashout Requests',
        '$pendingCashouts item${pendingCashouts == 1 ? '' : 's'} awaiting review',
        Icons.hourglass_top_outlined,
        AColors.amber,
        AdminModule.cashoutsPending,
      )),
    );
  }
}

// ── Role badge (read-only — role comes from the backend) ─────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        final session = AdminSession.instance;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Chip(
            avatar: Icon(
              session.isSuperAdmin
                  ? Icons.shield_moon_outlined
                  : Icons.verified_user_outlined,
              size: 15,
              color: AColors.secondary,
            ),
            label: Text('${session.roleDisplayName} · T${session.tier}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AColors.primary)),
            backgroundColor: AColors.secondary.withValues(alpha: 0.12),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      },
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
  String? _error;
  // Distinguishes "never loaded yet" (show a skeleton, not fabricated
  // zeroes) from "loaded once, now refreshing" (keep showing the last good
  // data — a failed background refresh must not erase it). See
  // OPERATIONS_ADMIN_DASHBOARD_AUDIT.md.
  bool _hasLoadedOnce = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await AdminApiService.instance.dashboard();
      if (!mounted) return;
      setState(() {
        _error = null;
        _loading = false;
        _hasLoadedOnce = true;
        _stats = Map<String, dynamic>.from(data['stats'] as Map? ?? {});
        _tasks = (data['tasks'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _activity = (data['activity'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      // _stats/_tasks/_activity are intentionally left untouched here — a
      // failed refresh keeps showing the last successfully-loaded values
      // instead of clearing them.
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AColors.redLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AColors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        _hasLoadedOnce
                            ? 'Could not refresh: $_error (showing last loaded data)'
                            : 'Could not load dashboard: $_error',
                        style: const TextStyle(color: AColors.red, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    style: TextButton.styleFrom(
                        foregroundColor: AColors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32)),
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const ShiftTimerWidget(),
          _DashboardAlerts(stats: _stats),
          const SizedBox(height: 20),
          const _QuickLinks(),
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
      ),
    );
  }
}

class _DashboardAlerts extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _DashboardAlerts({required this.stats});

  int _n(String key) => (stats[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final banners = <Widget>[];
    if (_n('pending_approval_requests') > 0 &&
        session.canAccess(AdminModule.approvals)) {
      banners.add(_AlertBanner(Icons.gavel_outlined,
          '${_n('pending_approval_requests')} admin actions awaiting your approval',
          AColors.orange, AColors.orangeLight, '/admin/approvals'));
    }
    if (_n('open_escalations') > 0 && session.canAccess(AdminModule.escalations)) {
      banners.add(_AlertBanner(Icons.priority_high_rounded,
          '${_n('open_escalations')} open escalation(s)',
          AColors.red, AColors.redLight, '/admin/oversight'));
    }
    if (_n('pending_admin_registrations') > 0 && session.isOperationsAdmin) {
      banners.add(_AlertBanner(Icons.badge_outlined,
          '${_n('pending_admin_registrations')} admin registration(s) to review',
          AColors.blue, AColors.blueLight, '/admin/admins'));
    }
    if (_n('urgent_consultations') > 0 &&
        session.canAccess(AdminModule.doctorPatient)) {
      banners.add(_AlertBanner(Icons.warning_amber_rounded,
          '${_n('urgent_consultations')} urgent consultation case(s) need attention',
          AColors.red, AColors.redLight, '/admin/doctors'));
    }
    if (_n('pending_pharmacies') > 0 &&
        session.canAccess(AdminModule.pharmacyManagement)) {
      banners.add(_AlertBanner(Icons.info_outline,
          '${_n('pending_pharmacies')} pending pharmacy approval(s)',
          AColors.amber, AColors.amberLight, '/admin/pharmacy'));
    }
    if (_n('pending_delivery') > 0 &&
        session.canAccess(AdminModule.deliveryManagement)) {
      banners.add(_AlertBanner(Icons.local_shipping_outlined,
          '${_n('pending_delivery')} delivery worker(s) pending review',
          AColors.amber, AColors.amberLight, '/admin/delivery'));
    }
    if (banners.isEmpty) {
      banners.add(const _AlertBanner(Icons.check_circle_outline,
          'No urgent items — everything is up to date.',
          AColors.green, AColors.greenLight, '/admin'));
    }
    return Column(
      children: [
        for (var i = 0; i < banners.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          banners[i],
        ],
      ],
    );
  }
}

class _QuickLinks extends StatelessWidget {
  const _QuickLinks();
  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final links = <(String, IconData, String, AdminModule)>[
      ('Users', Icons.people_outline, '/admin/users', AdminModule.userManagement),
      ('Doctors', Icons.medical_services_outlined, '/admin/doctors', AdminModule.doctorPatient),
      ('Delivery', Icons.local_shipping_outlined, '/admin/delivery', AdminModule.deliveryManagement),
      ('Pharmacy', Icons.local_pharmacy_outlined, '/admin/pharmacy', AdminModule.pharmacyManagement),
      ('Feed', Icons.grass_outlined, '/admin/feed', AdminModule.feedCatalogue),
      ('Content', Icons.article_outlined, '/admin/content', AdminModule.researchArticles),
      ('Finance', Icons.account_balance_wallet_outlined, '/admin/finance', AdminModule.financeSubscriptions),
      ('Approvals', Icons.gavel_outlined, '/admin/approvals', AdminModule.approvals),
      ('Audit Trail', Icons.fact_check_outlined, '/admin/audit', AdminModule.auditTrail),
      ('Admins', Icons.shield_outlined, '/admin/admins', AdminModule.adminManagement),
      ('Oversight', Icons.insights_outlined, '/admin/oversight', AdminModule.oversight),
    ].where((l) => session.canAccess(l.$4)).toList();
    if (links.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final l in links)
          ActionChip(
            avatar: Icon(l.$2, size: 16, color: AColors.primary),
            label: Text(l.$1, style: const TextStyle(fontSize: 12)),
            onPressed: () => context.go(l.$3),
            backgroundColor: AColors.surface2,
            side: const BorderSide(color: AColors.cardBorder),
          ),
      ],
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
                // account_status == 'active' — was previously bound to
                // total_users (User.objects.count(), every row regardless of
                // status), which is why this card showed a number far larger
                // than the actual approved-account count. See
                // OPERATIONS_ADMIN_DASHBOARD_AUDIT.md.
                '${stats['active_users'] ?? 0}',
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
    case AdminModule.feedCatalogue:
    case AdminModule.feedOrders:
    case AdminModule.feedDelivery:
      return '/admin/feed';
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
    case AdminModule.cashoutsPending:
      return '/admin/cashouts/pending';
    case AdminModule.cashoutsApproved:
      return '/admin/cashouts/approved';
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
