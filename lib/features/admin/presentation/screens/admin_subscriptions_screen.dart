import 'package:flutter/material.dart';

import '../../data/models/admin_role.dart';
import '../../data/services/admin_api_service.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_states.dart';

/// Finance Admin's Subscriptions module — Plans / Subscribed Users /
/// Payments. See FINANCE_ADMIN_DASHBOARD_AND_SUBSCRIPTIONS.md. Reuses the
/// existing `subscriptions`/`payments` backend models — no parallel billing
/// system.
class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() => _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  // Created eagerly in initState (not as a `late final` field initializer)
  // so it always exists by the time dispose() runs — build()'s
  // access-restricted early-return never touches `_tabs`, and a `late`
  // field's initializer would otherwise defer creating the TabController
  // (and its vsync lookup) until that first, unsafe access inside dispose().
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSession.instance;
    final hasAccess = session.canAccess(AdminModule.subscriptions);
    if (!hasAccess) {
      return const AdminScaffold(
        title: 'Subscriptions',
        module: AdminModule.subscriptions,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: AColors.grey),
              SizedBox(height: 16),
              Text('Access Restricted',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AColors.textPrimary)),
              SizedBox(height: 8),
              Text('Subscription management is restricted to Finance Admins.',
                  style: TextStyle(fontSize: 13, color: AColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    return AdminScaffold(
      title: 'Subscriptions',
      module: AdminModule.subscriptions,
      child: Column(
        children: [
          Container(
            color: AColors.appBar,
            child: TabBar(
              controller: _tabs,
              indicatorColor: AColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [Tab(text: 'Plans'), Tab(text: 'Subscribed Users'), Tab(text: 'Payments')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [_PlansTab(), _SubscribedUsersTab(), _SubscriptionPaymentsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plans ────────────────────────────────────────────────────────────────────

class _PlansTab extends StatefulWidget {
  const _PlansTab();
  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  List<Map<String, dynamic>> _plans = [];
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
      final data = await AdminApiService.instance.subscriptionPlans();
      if (!mounted) return;
      setState(() {
        _plans = (data['results'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _toggleActive(Map<String, dynamic> plan) async {
    try {
      await AdminApiService.instance
          .updateSubscriptionPlan(plan['id'] as int, {'is_active': !(plan['is_active'] as bool)});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) return const AdminLoading();
    if (_error != null && !_hasLoadedOnce) return AdminError(_error!, _load);
    if (_plans.isEmpty) return const AdminEmpty('No subscription plans yet');
    final canManage = AdminSession.instance.can(AdminModule.subscriptions, AdminPermission.edit);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = _plans[i];
          final active = p['is_active'] == true;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(p['name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(width: 8),
                        aChip(active ? 'Active' : 'Inactive', active ? AColors.green : AColors.grey,
                            active ? AColors.green : AColors.grey),
                      ]),
                      const SizedBox(height: 4),
                      Text('৳${p['price']} ${p['currency']} · ${p['billing_interval']}',
                          style: const TextStyle(fontSize: 13, color: AColors.textSecondary)),
                      Text('${p['subscriber_count']} subscriber(s)',
                          style: const TextStyle(fontSize: 12, color: AColors.grey)),
                      if ((p['features'] as List?)?.isNotEmpty ?? false)
                        Text((p['features'] as List).join(', '),
                            style: const TextStyle(fontSize: 11, color: AColors.grey)),
                    ],
                  ),
                ),
                if (canManage)
                  Switch(
                      value: active,
                      onChanged: (_) => _toggleActive(p),
                      activeThumbColor: AColors.secondary),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Subscribed Users ─────────────────────────────────────────────────────────

class _SubscribedUsersTab extends StatefulWidget {
  const _SubscribedUsersTab();
  @override
  State<_SubscribedUsersTab> createState() => _SubscribedUsersTabState();
}

class _SubscribedUsersTabState extends State<_SubscribedUsersTab> {
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await AdminApiService.instance.list('subscriptions');
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) return const AdminLoading();
    if (_error != null && !_hasLoadedOnce) return AdminError(_error!, _load);
    if (_rows.isEmpty) return const AdminEmpty('No subscribed users yet');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _rows[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(s['user']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  aChip(s['status']?.toString() ?? '', AColors.secondary, AColors.secondary),
                ]),
                const SizedBox(height: 4),
                Text('Plan: ${s['plan']} · ৳${s['price']}',
                    style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
                Text('Started ${s['started'] ?? '—'} · Expires ${s['expires'] ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: AColors.grey)),
                Text(s['auto_renew'] == true ? 'Auto-renew: on' : 'Auto-renew: off',
                    style: const TextStyle(fontSize: 11, color: AColors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Subscription Payments ────────────────────────────────────────────────────

class _SubscriptionPaymentsTab extends StatefulWidget {
  const _SubscriptionPaymentsTab();
  @override
  State<_SubscriptionPaymentsTab> createState() => _SubscriptionPaymentsTabState();
}

class _SubscriptionPaymentsTabState extends State<_SubscriptionPaymentsTab> {
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await AdminApiService.instance.list('payments');
      if (!mounted) return;
      setState(() {
        _rows = rows.where((r) => r['type'] != 'Payout').toList();
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

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) return const AdminLoading();
    if (_error != null && !_hasLoadedOnce) return AdminError(_error!, _load);
    if (_rows.isEmpty) return const AdminEmpty('No subscription payments yet');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = _rows[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: aCard(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['user']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${p['type']} · ${p['method'] ?? ''} · ${p['date'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: AColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('৳${p['amount']}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AColors.secondary)),
                    aChip(p['status']?.toString() ?? '', AColors.blue, AColors.blue, fontSize: 10),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
