import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/l10n/language_dialog.dart';
import 'package:featherflow/core/network/auth_service.dart';
import '../../data/farm_management_service.dart';
import '../../data/farmer_profile_service.dart';
import 'cost_management_screen.dart' show taka;

class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({super.key});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  int _selectedIndex = 0;
  String _displayName = 'Farmer';
  int _unreadNotifications = 0;
  bool _notificationCountLoaded = false;
  Timer? _timer;
  Map<String, dynamic>? _home;

  @override
  void initState() {
    super.initState();
    if (!LanguageNotifier.instance.hasShownInitialDialog) {
      LanguageNotifier.instance.markInitialDialogShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showLanguageDialog(context, dismissible: false);
      });
    }
    AuthService.instance.addListener(_loadSession);
    _loadSession();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_loadSession);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final home = await FarmerProfileService.homeDashboard();
      if (!mounted) return;
      final nextCount =
          ((home['counts'] as Map?)?['unread_notifications'] as num? ?? 0)
              .toInt();
      final hasNew =
          _notificationCountLoaded && nextCount > _unreadNotifications;
      setState(() {
        _home = home;
        _unreadNotifications = nextCount;
        _notificationCountLoaded = true;
      });
      if (hasNew && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
            content: Text('New notification'),
          ));
      }
    } catch (_) {}
  }

  Future<void> _loadSession() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (!mounted) return;
    setState(() {
      _displayName = session?.user.fullName.isNotEmpty == true
          ? session!.user.fullName
          : (session?.user.email.split('@').first ?? 'Farmer');
    });
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 1:
        context.go('/farmer/cost-management');
      case 2:
        context.go('/farmer/disease-detection');
      case 3:
        // pushed (not go) so the shared community feed gets a back button
        // to return to the farmer dashboard.
        context.push('/community');
      case 4:
        context.go('/farmer/profile');
    }
  }

  Future<void> _showNotifications() async {
    try {
      final data = await FarmManagementService.get('notifications');
      final rows = List<Map<String, dynamic>>.from(
          (data['notifications'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e)));
      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (ctx) => Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 560, maxHeight: 680),
                  child: Column(children: [
                    ListTile(
                      title: const Text('Notifications',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      trailing: IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close)),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('No notifications yet.'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (_, index) {
                                final x = rows[index];
                                final refType =
                                    x['reference_type']?.toString() ?? '';
                                final consultationEvent = {
                                  'consultation',
                                  'prescription',
                                  'follow_up',
                                  'consultation_payment',
                                }.contains(refType);
                                final financeEvent = {
                                  'loan',
                                  'expense',
                                  'cashout',
                                }.contains(refType);
                                return ListTile(
                                  onTap: consultationEvent
                                      ? () {
                                          Navigator.pop(ctx);
                                          context.go('/farmer/consultations');
                                        }
                                      : financeEvent
                                          ? () {
                                              Navigator.pop(ctx);
                                              context.go(
                                                  '/farmer/cost-management');
                                            }
                                          : null,
                                  leading: Icon(
                                      consultationEvent
                                          ? Icons.medical_services_outlined
                                          : financeEvent
                                              ? Icons.payments_outlined
                                              : Icons.notifications_outlined,
                                      color: AppColors.secondary),
                                  title: Text('${x['title']}',
                                      style: TextStyle(
                                          fontWeight: x['is_read'] == true
                                              ? FontWeight.w500
                                              : FontWeight.w800)),
                                  subtitle: Text('${x['body']}\n${x['time']}'),
                                  isThreeLine: true,
                                  trailing: x['is_read'] == true
                                      ? null
                                      : const CircleAvatar(
                                          radius: 4,
                                          backgroundColor: AppColors.error),
                                );
                              },
                            ),
                    ),
                  ]),
                ),
              ));
      await FarmManagementService.patch('notifications', {});
      if (mounted) setState(() => _unreadNotifications = 0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isBn = LanguageNotifier.instance.isBengali;
    final farm = (_home?['farm'] as Map?) ?? const {};
    final finance = (_home?['finance'] as Map?) ?? const {};
    final counts = (_home?['counts'] as Map?) ?? const {};
    final alerts = (_home?['alerts'] as List?) ?? const [];
    final activity = (_home?['recent_activity'] as List?) ?? const [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text('Featherflow',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        actions: [
          GestureDetector(
            onTap: () => showLanguageDialog(context, dismissible: true),
            child: Container(
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: AppRadius.fullAll,
                border: Border.all(color: Colors.white38),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.language, color: Colors.white, size: 13),
                const SizedBox(width: 3),
                Text(isBn ? 'বাং' : 'EN',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          IconButton(
            onPressed: _showNotifications,
            icon: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 24),
              if (_unreadNotifications > 0)
                Positioned(
                  right: -7,
                  top: -7,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                        color: AppColors.error, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                        _unreadNotifications > 99
                            ? '99+'
                            : '$_unreadNotifications',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: GestureDetector(
              onTap: () => context.go('/farmer/profile'),
              child: CircleAvatar(
                radius: 18,
                // On the green app bar — white initial on a white-tinted disc.
                backgroundColor: AppColors.navigationHoverColor,
                child: Text(
                    _displayName.isNotEmpty
                        ? _displayName[0].toUpperCase()
                        : 'F',
                    style: const TextStyle(
                        color: AppColors.navigationForegroundColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _WelcomeCard(
                name: _displayName,
                farmName: farm['name']?.toString() ?? '',
                birds: (farm['total_birds'] as num?)?.toInt() ?? 0,
                batches: (farm['active_batches'] as num?)?.toInt() ?? 0,
                verified: farm['is_verified'] == true,
                isBn: isBn),
            const SizedBox(height: AppSpacing.md),
            _FinanceRow(finance: finance),
            const SizedBox(height: AppSpacing.md),
            _ProBannerCard(onTap: () => context.go('/subscription')),
            const SizedBox(height: AppSpacing.md),
            _QuickActionsGrid(
                counts: counts,
                onNavigate: (p) => p.startsWith('/farmer')
                    ? context.go(p)
                    : context.push(p)),
            const SizedBox(height: AppSpacing.lg),
            if (alerts.isNotEmpty) ...[
              _SectionTitle(text: l.recentAlerts),
              const SizedBox(height: AppSpacing.sm),
              for (final raw in alerts.take(4))
                _AlertCard(alert: Map<String, dynamic>.from(raw as Map)),
              const SizedBox(height: AppSpacing.lg),
            ],
            const _SectionTitle(text: 'Recent activity'),
            const SizedBox(height: AppSpacing.sm),
            if (activity.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing yet. Add an expense or revenue to begin.',
                    style: TextStyle(color: Colors.black54)),
              )
            else
              for (final raw in activity)
                _ActivityRow(row: Map<String, dynamic>.from(raw as Map)),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: const Color(0xFF999999),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        elevation: 8,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: l.home),
          BottomNavigationBarItem(
              icon: const Icon(Icons.attach_money), label: l.cost),
          BottomNavigationBarItem(
              icon: const Icon(Icons.coronavirus_outlined),
              activeIcon: const Icon(Icons.coronavirus),
              label: l.detect),
          BottomNavigationBarItem(
              icon: const Icon(Icons.people), label: l.community),
          BottomNavigationBarItem(
              icon: const Icon(Icons.person), label: l.profile),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String name;
  final String farmName;
  final int birds;
  final int batches;
  final bool verified;
  final bool isBn;

  const _WelcomeCard({
    required this.name,
    required this.farmName,
    required this.birds,
    required this.batches,
    required this.verified,
    required this.isBn,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l.welcomeBack}, $name!',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.xs),
        Row(children: [
          const Icon(Icons.agriculture,
              color: AppColors.onSecondaryContainer, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(farmName.isEmpty ? 'Your farm' : farmName,
                style: const TextStyle(
                    color: AppColors.onSecondaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ),
          if (verified)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.verified, color: Colors.white, size: 16),
            ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          const Icon(Icons.scatter_plot, color: AppColors.secondary, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text('$birds ${isBn ? 'পাখি' : 'Birds'}  •  $batches ${l.activeBatches}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  final Map finance;
  const _FinanceRow({required this.finance});

  num _n(String k) => (finance[k] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: () => context.go('/farmer/cost-management'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Revenue',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
            Text(taka(_n('total_revenue')),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              _mini('Expense', taka(_n('total_expense'))),
              _mini('Net Profit', taka(_n('net_profit')),
                  color: _n('net_profit') >= 0
                      ? AppColors.secondaryContainer
                      : AppColors.error),
              _mini('Cash', taka(_n('cash_balance'))),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _mini(String k, String v, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 10, color: Colors.black45)),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color ?? Colors.black87)),
        ]),
      );
}

class _ProBannerCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ProBannerCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00695C), AppColors.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: AppRadius.smAll,
            ),
            child: const Icon(Icons.workspace_premium,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.becomeProFarmer,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(l.proFarmerSubtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
        ]),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final Map counts;
  final void Function(String path) onNavigate;
  const _QuickActionsGrid({required this.counts, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = <_QuickActionItem>[
      _QuickActionItem(
          icon: Icons.attach_money,
          label: l.costManagementGrid,
          cardColor: const Color(0xFFF3E5F5),
          iconColor: const Color(0xFF6A1B9A),
          path: '/farmer/cost-management'),
      _QuickActionItem(
          icon: Icons.medical_services,
          label: l.findVetGrid,
          cardColor: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF2E7D32),
          path: '/farmer/vet-map'),
      _QuickActionItem(
          icon: Icons.event_note_outlined,
          label: 'My Consultations',
          cardColor: const Color(0xFFE0F7FA),
          iconColor: const Color(0xFF00796B),
          path: '/farmer/consultations',
          badge: (counts['upcoming_consultations'] as num?)?.toInt() ?? 0),
      _QuickActionItem(
          icon: Icons.local_pharmacy,
          label: l.pharmacyGrid,
          cardColor: const Color(0xFFFFEBEE),
          iconColor: const Color(0xFFC62828),
          path: '/farmer/pharmacy',
          badge: (counts['open_pharmacy_orders'] as num?)?.toInt() ?? 0),
      _QuickActionItem(
          icon: Icons.grass,
          label: l.feedManagementGrid,
          cardColor: const Color(0xFFE0F2F1),
          iconColor: const Color(0xFF00695C),
          path: '/farmer/feed-management'),
      const _QuickActionItem(
          icon: Icons.receipt_long,
          label: 'Tax & Estimates',
          cardColor: Color(0xFFEDE7F6),
          iconColor: Color(0xFF4527A0),
          path: '/farmer/tax'),
      _QuickActionItem(
          icon: Icons.people,
          label: l.laborManagementGrid,
          cardColor: const Color(0xFFE8EAF6),
          iconColor: const Color(0xFF283593),
          path: '/farmer/labor'),
      _QuickActionItem(
          icon: Icons.forum_outlined,
          label: l.communityGrid,
          cardColor: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFE65100),
          path: '/community'),
      _QuickActionItem(
          icon: Icons.article,
          label: l.articlesGrid,
          cardColor: const Color(0xFFFFF8E1),
          iconColor: const Color(0xFFF57F17),
          path: '/paper-portal'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.3,
      children: items
          .map((item) => _QuickActionCard(item: item, onNavigate: onNavigate))
          .toList(),
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final Color cardColor;
  final Color iconColor;
  final String path;
  final int badge;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.cardColor,
    required this.iconColor,
    required this.path,
    this.badge = 0,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickActionItem item;
  final void Function(String path) onNavigate;
  const _QuickActionCard({required this.item, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onNavigate(item.path),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: item.cardColor,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: item.iconColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(item.icon, color: item.iconColor, size: 32),
              const Spacer(),
              if (item.badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: item.iconColor, shape: BoxShape.rectangle,
                      borderRadius: AppRadius.fullAll),
                  child: Text('${item.badge}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text(item.label,
                style: TextStyle(
                    color: item.iconColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.primary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15));
}

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isError = alert['severity'] == 'error';
    final color = isError ? const Color(0xFFC62828) : const Color(0xFFF57C00);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded,
            color: color, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert['title']?.toString() ?? '',
                style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(alert['body']?.toString() ?? '',
                style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ActivityRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final isRevenue = row['kind'] == 'revenue';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(isRevenue ? Icons.south_west : Icons.north_east,
          size: 18,
          color:
              isRevenue ? AppColors.secondaryContainer : AppColors.error),
      title: Text(row['title']?.toString() ?? '',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
      subtitle: Text('${row['status']} • ${row['date']}',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(
          '${isRevenue ? '+' : '-'}${taka((row['amount'] as num?) ?? 0)}',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: isRevenue
                  ? AppColors.secondaryContainer
                  : Colors.black87)),
    );
  }
}
