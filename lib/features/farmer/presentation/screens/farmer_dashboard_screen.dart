import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/l10n/language_dialog.dart';
import 'package:featherflow/core/network/auth_service.dart';
import '../../data/farm_management_service.dart';

class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({super.key});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  int _selectedIndex = 0;
  AuthSession? _session;
  String _displayName = 'Farmer';
  int _unreadNotifications = 0;
  Timer? _notificationTimer;

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
    _refreshNotificationCount();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshNotificationCount(),
    );
  }

  Future<void> _refreshNotificationCount() async {
    try {
      final data = await FarmManagementService.get('notifications');
      if (mounted) {
        setState(() => _unreadNotifications =
            (data['unread_count'] as num? ?? 0).toInt());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_loadSession);
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _displayName = session?.user.fullName.isNotEmpty == true
          ? session!.user.fullName
          : (session?.user.email.split('@').first ?? 'Farmer');
    });
  }

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 1:
        context.go('/farmer/disease-detection');
      case 2:
        context.go('/farmer/cost-management');
      case 3:
        context.go('/community');
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
          builder: (ctx) =>
              AlertDialog(
                  title: const Text('Notifications'),
                  content: SizedBox(
                      width: 380,
                      child: rows.isEmpty
                          ? const Text('No notifications yet.')
                          : ListView(
                              shrinkWrap: true,
                              children: rows
                                  .map((x) => ListTile(
                                      leading: const Icon(
                                          Icons.notifications_outlined,
                                          color: AppColors.secondary),
                                      title: Text(x['title']),
                                      subtitle:
                                          Text('${x['body']}\n${x['time']}'),
                                      trailing: x['is_read']
                                          ? null
                                          : const CircleAvatar(
                                              radius: 4,
                                              backgroundColor:
                                                  AppColors.error)))
                                  .toList())),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'))
                  ]));
      await FarmManagementService.patch('notifications', {});
      if (mounted) setState(() => _unreadNotifications = 0);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isBn = LanguageNotifier.instance.isBengali;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Featherflow',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          // language toggle chip
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, color: Colors.white, size: 13),
                  const SizedBox(width: 3),
                  Text(
                    isBn ? 'বাং' : 'EN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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
                          fontWeight: FontWeight.w800),
                    ),
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
                backgroundColor: AppColors.secondary,
                child: Text(
                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'F',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WelcomeCard(name: _displayName),
            const SizedBox(height: AppSpacing.md),
            _ProBannerCard(onTap: () => context.go('/subscription')),
            const SizedBox(height: AppSpacing.md),
            _QuickActionsGrid(onNavigate: (path) => context.go(path)),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle(text: l.recentAlerts),
            const SizedBox(height: AppSpacing.sm),
            const _RecentAlertsList(),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle(text: l.farmStats),
            const SizedBox(height: AppSpacing.sm),
            const _FarmStatsRow(),
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
              icon: const Icon(Icons.biotech), label: l.detect),
          BottomNavigationBarItem(
              icon: const Icon(Icons.attach_money), label: l.cost),
          BottomNavigationBarItem(
              icon: const Icon(Icons.people), label: l.community),
          BottomNavigationBarItem(
              icon: const Icon(Icons.person), label: l.profile),
        ],
      ),
    );
  }
}

// ── Welcome Card ─────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  final String name;

  const _WelcomeCard({required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isBn = l.locale.languageCode == 'bn';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l.welcomeBack}, $name!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Row(
            children: [
              Icon(Icons.agriculture,
                  color: AppColors.onSecondaryContainer, size: 16),
              SizedBox(width: AppSpacing.xs),
              Text(
                'Green Valley Farm',
                style: TextStyle(
                  color: AppColors.onSecondaryContainer,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.scatter_plot,
                  color: AppColors.secondary, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isBn ? '৪,৫০০ পাখি' : '4,500 Birds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pro Banner ────────────────────────────────────────────────────────────────

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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: AppRadius.smAll,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.becomeProFarmer,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.proFarmerSubtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  final void Function(String path) onNavigate;

  const _QuickActionsGrid({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      _QuickActionItem(
        icon: Icons.biotech,
        label: l.diseaseDetectionGrid,
        cardColor: const Color(0xFFE3F2FD),
        iconColor: const Color(0xFF1565C0),
        path: '/farmer/disease-detection',
      ),
      _QuickActionItem(
        icon: Icons.attach_money,
        label: l.costManagementGrid,
        cardColor: const Color(0xFFF3E5F5),
        iconColor: const Color(0xFF6A1B9A),
        path: '/farmer/cost-management',
      ),
      _QuickActionItem(
        icon: Icons.medical_services,
        label: l.findVetGrid,
        cardColor: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF2E7D32),
        path: '/farmer/vet-map',
      ),
      _QuickActionItem(
        icon: Icons.forum_outlined,
        label: l.communityGrid,
        cardColor: const Color(0xFFFFF3E0),
        iconColor: const Color(0xFFE65100),
        path: '/community',
      ),
      _QuickActionItem(
        icon: Icons.grass,
        label: l.feedManagementGrid,
        cardColor: const Color(0xFFE0F2F1),
        iconColor: const Color(0xFF00695C),
        path: '/farmer/feed-management',
      ),
      _QuickActionItem(
        icon: Icons.people,
        label: l.laborManagementGrid,
        cardColor: const Color(0xFFE8EAF6),
        iconColor: const Color(0xFF283593),
        path: '/farmer/labor',
      ),
      _QuickActionItem(
        icon: Icons.local_pharmacy,
        label: l.pharmacyGrid,
        cardColor: const Color(0xFFFFEBEE),
        iconColor: const Color(0xFFC62828),
        path: '/farmer/pharmacy',
      ),
      _QuickActionItem(
        icon: Icons.article,
        label: l.articlesGrid,
        cardColor: const Color(0xFFFFF8E1),
        iconColor: const Color(0xFFF57F17),
        path: '/paper-portal',
      ),
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

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.cardColor,
    required this.iconColor,
    required this.path,
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
          border: Border.all(
            color: item.iconColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: item.iconColor, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.label,
              style: TextStyle(
                color: item.iconColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
    );
  }
}

// ── Recent Alerts ─────────────────────────────────────────────────────────────

class _AlertData {
  final IconData icon;
  final Color iconColor;
  final Color cardColor;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;
  final String Function(AppLocalizations) time;

  const _AlertData({
    required this.icon,
    required this.iconColor,
    required this.cardColor,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

class _RecentAlertsList extends StatelessWidget {
  const _RecentAlertsList();

  static final _alerts = <_AlertData>[
    _AlertData(
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFF57C00),
      cardColor: const Color(0xFFFFF8E1),
      title: (l) => l.alertLowFeed,
      subtitle: (l) => l.alertLowFeedDesc,
      time: (l) => l.timeAgo2h,
    ),
    _AlertData(
      icon: Icons.health_and_safety,
      iconColor: const Color(0xFFC62828),
      cardColor: const Color(0xFFFFEBEE),
      title: (l) => l.alertHealth,
      subtitle: (l) => l.alertHealthDesc,
      time: (l) => l.timeAgo5h,
    ),
    _AlertData(
      icon: Icons.check_circle,
      iconColor: const Color(0xFF2E7D32),
      cardColor: const Color(0xFFE8F5E9),
      title: (l) => l.alertVaccination,
      subtitle: (l) => l.alertVaccinationDesc,
      time: (l) => l.timeAgo1d,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _alerts.map((a) => _AlertCard(alert: a)).toList(),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final _AlertData alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: alert.cardColor,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: alert.iconColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(alert.icon, color: alert.iconColor, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title(l),
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.subtitle(l),
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            alert.time(l),
            style: const TextStyle(color: Color(0xFF999999), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Farm Stats ────────────────────────────────────────────────────────────────

class _FarmStatsRow extends StatelessWidget {
  const _FarmStatsRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: l.totalBirds,
            value: l.locale.languageCode == 'bn' ? '৪,৫০০' : '4,500',
            icon: Icons.scatter_plot,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: l.activeBatches,
            value: l.locale.languageCode == 'bn' ? '৩' : '3',
            icon: Icons.layers,
            color: AppColors.secondaryContainer,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(
            label: l.healthStatus,
            value: l.good,
            icon: Icons.favorite,
            color: const Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
