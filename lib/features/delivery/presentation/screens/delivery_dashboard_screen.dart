import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/profile_photo_field.dart';
import '../../data/models/delivery_order.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';
import '../widgets/status_stepper.dart';
import 'delivery_orders_screen.dart';
import 'delivery_map_screen.dart';
import 'delivery_earnings_screen.dart';
import 'delivery_attendance_screen.dart';
import 'delivery_detail_screen.dart';
import 'delivery_performance_screen.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  int _currentIndex = 0;
  int _shiftSeconds = 0;
  Timer? _shiftTimer;
  DateTime? _shiftStartedAt;

  @override
  void initState() {
    super.initState();
    // A hard refresh / cold start lands here with the session restored from
    // storage but the AuthService login listener never fired — make sure the
    // delivery data actually loads instead of sitting on a spinner.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => DeliverySession.instance.ensureStarted());
    _shiftTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final online = DeliverySession.instance.isOnline;
      if (online) {
        _shiftStartedAt ??= DateTime.now();
        setState(() => _shiftSeconds =
            DateTime.now().difference(_shiftStartedAt!).inSeconds);
      } else {
        _shiftStartedAt = null;
        if (_shiftSeconds != 0) setState(() => _shiftSeconds = 0);
      }
    });
  }

  @override
  void dispose() {
    _shiftTimer?.cancel();
    super.dispose();
  }

  String get _shiftDuration {
    final h = _shiftSeconds ~/ 3600;
    final m = (_shiftSeconds % 3600) ~/ 60;
    final s = _shiftSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleOnline() async {
    try {
      await DeliverySession.instance.toggleOnline();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeliverySession.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: DColors.bg,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _DashboardTab(
                isOnline: DeliverySession.instance.isOnline,
                onToggleOnline: _toggleOnline,
                shiftDuration: _shiftDuration,
              ),
              const DeliveryOrdersScreen(),
              const DeliveryMapScreen(),
              const DeliveryEarningsScreen(),
              _ProfileTab(onNavigateTo: (i) => setState(() => _currentIndex = i)),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            backgroundColor: Colors.white,
            selectedItemColor: DColors.primary,
            unselectedItemColor: const Color(0xFF999999),
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            elevation: 8,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined),
                activeIcon: Icon(Icons.receipt_long),
                label: 'Orders',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet),
                label: 'Earnings',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Dashboard Tab ──────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onToggleOnline;
  final String shiftDuration;

  const _DashboardTab({
    required this.isOnline,
    required this.onToggleOnline,
    required this.shiftDuration,
  });

  Future<void> _refresh() => DeliverySession.instance.refresh();

  @override
  Widget build(BuildContext context) {
    final session = DeliverySession.instance;
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Featherflow',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3),
            ),
            Text(
              'Delivery',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: onToggleOnline,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white38),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color:
                          isOnline ? const Color(0xFF69F0AE) : Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (isOnline)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  shiftDuration,
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white38),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Color(0xFFFFD54F), size: 13),
                  const SizedBox(width: 3),
                  Text(session.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: session.isLoading && session.errorMessage == null && session.rating == 0 && session.activeOrder == null
            ? const Center(child: CircularProgressIndicator(color: DColors.primary))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (session.errorMessage != null) _buildError(session.errorMessage!),
                    _buildTodayOverview(context, session),
                    const SizedBox(height: 16),
                    if (session.activeOrder != null)
                      _buildActiveOrder(context, session.activeOrder!)
                    else
                      _buildNoActiveOrder(),
                    const SizedBox(height: 16),
                    _buildQuickActions(context),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildError(String message) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DColors.redLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DColors.red.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: DColors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(ErrorStateView.humanize(message),
                  style: const TextStyle(color: DColors.red, fontSize: 12))),
          TextButton(
            onPressed: _refresh,
            style: TextButton.styleFrom(
                foregroundColor: DColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _buildTodayOverview(BuildContext context, DeliverySession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Overview",
          style: TextStyle(
              color: DColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.inbox_outlined,
                color: DColors.accent,
                value: '${session.pendingRequestsCount}',
                label: 'New Requests',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.local_shipping_outlined,
                color: DColors.accentMid,
                value: '${session.completedTodayCount}',
                label: 'Completed',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFFFB300),
                value: '৳${session.todayEarnings.toStringAsFixed(0)}',
                label: 'Earnings',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DeliveryAttendanceScreen()),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: dCard(),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: DColors.accentMid,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Attendance Status:',
                  style: TextStyle(color: DColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  session.attendanceStatus.replaceAll('_', ' '),
                  style: const TextStyle(
                      color: DColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios,
                    color: DColors.grey, size: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: DColors.textSecondary, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveOrder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: dCard(),
      child: const Column(
        children: [
          Icon(Icons.local_shipping_outlined, color: DColors.grey, size: 32),
          SizedBox(height: 8),
          Text('No active delivery',
              style: TextStyle(color: DColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildActiveOrder(BuildContext context, DeliveryOrder order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Order',
          style: TextStyle(
              color: DColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: dCard(highlight: true),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                    style: const TextStyle(
                        color: DColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DColors.accentLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: DColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Accepted',
                        style: TextStyle(
                            color: DColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StatusStepper(currentStatus: order.status),
              const SizedBox(height: 14),
              _addrRow(Icons.radio_button_checked, DColors.accent,
                  order.pickupAddress),
              const SizedBox(height: 6),
              _addrRow(Icons.location_on, DColors.red, order.dropAddress),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.phone_outlined, size: 15),
                      label: const Text('Call'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DColors.primary,
                        side: BorderSide(
                            color: DColors.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeliveryDetailScreen(order: order),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 15),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _addrRow(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  const TextStyle(color: DColors.textSecondary, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
              color: DColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _quickAction(
              icon: Icons.how_to_reg_outlined,
              label: 'Attendance',
              color: DColors.accent,
              bgColor: DColors.accentLight,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DeliveryAttendanceScreen()),
              ),
            ),
            const SizedBox(width: 10),
            _quickAction(
              icon: Icons.bar_chart,
              label: 'Performance',
              color: const Color(0xFFFFB300),
              bgColor: const Color(0xFFFFF8E1),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DeliveryPerformanceScreen()),
              ),
            ),
            const SizedBox(width: 10),
            _quickAction(
              icon: Icons.support_agent_outlined,
              label: 'Support',
              color: DColors.orange,
              bgColor: DColors.orangeLight,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Profile Tab ────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final void Function(int) onNavigateTo;

  const _ProfileTab({required this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (context, _) {
              final user = AuthService.instance.currentSession?.user;
              final name = user?.fullName.isNotEmpty == true
                  ? user!.fullName
                  : 'Delivery Partner';
              final identifier =
                  user?.profileValue('license_number', user.id) ?? '-';
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: dCard(),
                child: Row(
                  children: [
                    ProfilePhotoField(
                      radius: 30,
                      onLightSurface: true,
                      currentUrl: user?.profilePhotoUrl ?? '',
                      fallbackInitial:
                          name.isNotEmpty ? name[0].toUpperCase() : 'D',
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  color: DColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('ID: $identifier',
                              style: const TextStyle(
                                  color: DColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<AuthSession?>(
            future: AuthService.instance.getStoredSession(),
            builder: (context, snapshot) {
              final user = snapshot.data?.user;
              if (user == null) return const SizedBox.shrink();
              final details = <String, dynamic>{
                'Email': user.email,
                'Phone': user.phone,
                'Address': user.presentAddress,
                'Date Of Birth': user.dateOfBirth,
                ...user.profileData
                    .map((key, value) => MapEntry(_profileLabel(key), value)),
              }..removeWhere((key, value) =>
                  value == null || value.toString().trim().isEmpty);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: dCard(),
                child: Column(
                  children: details.entries
                      .map((entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Expanded(
                                  child: Text(entry.key,
                                      style: const TextStyle(
                                          color: DColors.textSecondary,
                                          fontSize: 12))),
                              Expanded(
                                  child: Text(entry.value.toString(),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                          color: DColors.textPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))),
                            ]),
                          ))
                      .toList(),
                ),
              );
            },
          ),
          _profileMenu(
            icon: Icons.bar_chart,
            label: 'Performance',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DeliveryPerformanceScreen()),
            ),
          ),
          _profileMenu(
            icon: Icons.calendar_month_outlined,
            label: 'Attendance',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DeliveryAttendanceScreen()),
            ),
          ),
          _profileMenu(
            icon: Icons.help_outline,
            label: 'Help & Support',
            onTap: () {},
          ),
          _profileMenu(
            icon: Icons.logout,
            label: 'Log Out',
            color: DColors.red,
            onTap: () async {
              await AuthService.instance.clearSession();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
          ),
        ],
      ),
    );
  }

  String _profileLabel(String key) => key
      .split('_')
      .map((word) =>
          word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');

  Widget _profileMenu({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: dCard(),
        child: Row(
          children: [
            Icon(icon, color: color ?? DColors.primary, size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: color ?? DColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios,
                color: color ?? DColors.grey, size: 13),
          ],
        ),
      ),
    );
  }
}
