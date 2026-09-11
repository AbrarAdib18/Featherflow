import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/widgets/profile_photo_field.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';
import 'doctor_appointments_screen.dart';
import 'doctor_case_notes_screen.dart';
import 'doctor_messenger_screen.dart';
import 'doctor_earnings_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _workflowTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workflowTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => DoctorSession.instance.refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DoctorSession.instance.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workflowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final unread = DoctorSession.instance.unreadMessages;
        return Scaffold(
          backgroundColor: VetColors.bg,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              _HomeTab(onNavigateTo: (i) => setState(() => _currentIndex = i)),
              const DoctorAppointmentsScreen(),
              const DoctorCaseNotesScreen(),
              const DoctorMessengerScreen(),
              const DoctorEarningsScreen(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            backgroundColor: Colors.white,
            selectedItemColor: VetColors.primary,
            unselectedItemColor: const Color(0xFF999999),
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            elevation: 8,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard),
                label: 'Home',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.calendar_month_outlined),
                activeIcon: Icon(Icons.calendar_month),
                label: 'Schedule',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.folder_open_outlined),
                activeIcon: Icon(Icons.folder),
                label: 'Cases',
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                activeIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble),
                ),
                label: 'Chat',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet),
                label: 'Earnings',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Home Tab ──────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final void Function(int) onNavigateTo;
  const _HomeTab({required this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final s = DoctorSession.instance;
        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
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
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Vet Panel',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => _showNotifications(context),
                icon: Badge(
                  isLabelVisible: s.unreadNotifications > 0,
                  label: Text('${s.unreadNotifications}'),
                  child: const Icon(Icons.notifications_outlined,
                      color: Colors.white),
                ),
              ),
              _StatusPill(
                availability: s.profile.availability,
                onChanged: (v) => DoctorSession.instance.setAvailability(v),
              ),
              const SizedBox(width: 8),
              _RatingBadge(rating: s.profile.rating),
              const SizedBox(width: 12),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WelcomeHeader(profile: s.profile),
                const SizedBox(height: 16),
                _StatGrid(session: s, onNavigateTo: onNavigateTo),
                const SizedBox(height: 20),
                _TodayAppointments(
                  appointments: s.todayAppointments,
                  onSeeAll: () => onNavigateTo(1),
                ),
                const SizedBox(height: 20),
                if (s.pendingFollowUps.isNotEmpty) ...[
                  _PendingFollowUps(
                    cases: s.pendingFollowUps,
                    onSeeAll: () => onNavigateTo(2),
                  ),
                  const SizedBox(height: 20),
                ],
                _QuickActions(onNavigateTo: onNavigateTo),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNotifications(BuildContext context) async {
    final session = DoctorSession.instance;
    await session.refresh();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Column(children: [
            ListTile(
              title: const Text('Notifications',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              trailing: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close)),
            ),
            const Divider(height: 1),
            Expanded(
              child: session.notifications.isEmpty
                  ? const Center(child: Text('No notifications yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: session.notifications.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final item = session.notifications[index];
                        final isRating =
                            item['reference_type'] == 'consultation_rating';
                        return ListTile(
                          onTap: () {
                            Navigator.pop(dialogContext);
                            if (isRating) onNavigateTo(4);
                          },
                          leading: CircleAvatar(
                            backgroundColor: isRating
                                ? const Color(0xFFFFF4D6)
                                : VetColors.openLight,
                            child: Icon(
                              isRating
                                  ? Icons.star_rounded
                                  : Icons.notifications_outlined,
                              color: isRating
                                  ? const Color(0xFFFFB300)
                                  : VetColors.open,
                            ),
                          ),
                          title: Text('${item['title']}',
                              style: TextStyle(
                                  fontWeight: item['is_read'] == true
                                      ? FontWeight.w500
                                      : FontWeight.w800)),
                          subtitle:
                              Text('${item['body']}\n${item['time'] ?? ''}'),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
    try {
      await session.markNotificationsRead();
    } catch (_) {
      // Notifications remain visible even if marking them read must be retried.
    }
  }
}

// ── Status Pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final DoctorAvailability availability;
  final ValueChanged<DoctorAvailability> onChanged;
  const _StatusPill({required this.availability, required this.onChanged});

  (Color dot, String label) get _attrs => switch (availability) {
        DoctorAvailability.available => (const Color(0xFF69F0AE), 'Available'),
        DoctorAvailability.busy => (const Color(0xFFFFB74D), 'Busy'),
        DoctorAvailability.offline => (Colors.white38, 'Offline'),
      };

  @override
  Widget build(BuildContext context) {
    final (dot, label) = _attrs;
    return PopupMenuButton<DoctorAvailability>(
      onSelected: onChanged,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
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
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_drop_down, color: Colors.white60, size: 16),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _statusItem(
            DoctorAvailability.available, const Color(0xFF2E7D32), 'Available'),
        _statusItem(DoctorAvailability.busy, const Color(0xFFE65100), 'Busy'),
        _statusItem(
            DoctorAvailability.offline, const Color(0xFF757575), 'Offline'),
      ],
    );
  }

  PopupMenuItem<DoctorAvailability> _statusItem(
    DoctorAvailability value,
    Color color,
    String label,
  ) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Welcome Header ────────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  final DoctorProfile profile;
  const _WelcomeHeader({required this.profile});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProfilePhotoField(
          radius: 24,
          onLightSurface: true,
          showLabel: false,
          currentUrl:
              AuthService.instance.currentSession?.user.profilePhotoUrl ?? '',
          fallbackInitial:
              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'D',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$_greeting,',
                    style: const TextStyle(
                      color: VetColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      color: VetColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (profile.isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: VetColors.availableLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              color: VetColors.available, size: 11),
                          SizedBox(width: 3),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: VetColors.available,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Text(
                profile.specialty,
                style: const TextStyle(
                    color: VetColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Stat Grid ─────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  final DoctorSession session;
  final void Function(int) onNavigateTo;
  const _StatGrid({required this.session, required this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    final summary = session.dashboardSummary;
    final rt = summary['response_time'];
    final avgResponse = rt is Map ? (rt['avg_minutes'] as num?)?.toDouble() : null;
    final openDisputes = (summary['open_disputes'] as num?)?.toInt() ?? 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.people_alt_outlined,
                color: VetColors.secondary,
                bg: VetColors.availableLight,
                value: '${session.totalClients}',
                label: 'Total Clients',
                onTap: () => onNavigateTo(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.calendar_today_outlined,
                color: VetColors.online,
                bg: VetColors.onlineLight,
                value: '${session.todayAppointmentCount}',
                label: "Today's Appts",
                onTap: () => onNavigateTo(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.folder_open_outlined,
                color: VetColors.inProgress,
                bg: VetColors.inProgressLight,
                value: '${session.activeCases}',
                label: 'Active Cases',
                onTap: () => onNavigateTo(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.check_circle_outline,
                color: VetColors.available,
                bg: VetColors.closedLight,
                value: '${session.completedCases}',
                label: 'Completed',
                onTap: () => onNavigateTo(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.warning_amber_outlined,
                color: VetColors.emergency,
                bg: VetColors.emergencyLight,
                value: '${session.urgentRequests}',
                label: 'Urgent',
                onTap: () => onNavigateTo(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.chat_bubble_outline,
                color: VetColors.followUpColor,
                bg: VetColors.followUpLight,
                value: '${session.unreadMessages}',
                label: 'Unread',
                onTap: () => onNavigateTo(3),
              ),
            ),
          ],
        ),
        if (avgResponse != null || openDisputes > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _statCard(
                icon: Icons.timer_outlined,
                color: VetColors.online,
                bg: VetColors.onlineLight,
                value: avgResponse != null ? '~${avgResponse.round()}m' : '—',
                label: 'Avg response',
                onTap: () => onNavigateTo(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                icon: Icons.flag_outlined,
                color: openDisputes > 0 ? VetColors.red : VetColors.grey,
                bg: openDisputes > 0 ? VetColors.redLight : VetColors.surface2,
                value: '$openDisputes',
                label: 'Open disputes',
                onTap: () => onNavigateTo(1),
              ),
            ),
            const Spacer(),
          ]),
        ],
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                    color: VetColors.textSecondary, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

// ── Today's Appointments ──────────────────────────────────────────────────────

class _TodayAppointments extends StatelessWidget {
  final List<DoctorAppointment> appointments;
  final VoidCallback onSeeAll;
  const _TodayAppointments(
      {required this.appointments, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              "Today's Schedule",
              style: TextStyle(
                color: VetColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  color: VetColors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (appointments.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: vetCard(),
            child: const Center(
              child: Text(
                'No appointments today',
                style: TextStyle(color: VetColors.grey, fontSize: 13),
              ),
            ),
          )
        else
          ...appointments.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AppointmentTile(appointment: a),
              )),
      ],
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final DoctorAppointment appointment;
  const _AppointmentTile({required this.appointment});

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = appointment.isUrgent;
    return Container(
      decoration: vetCard(highlight: isUrgent),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isUrgent ? VetColors.emergencyLight : VetColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatTime(appointment.scheduledAt).split(' ')[0],
                  style: TextStyle(
                    color: isUrgent ? VetColors.emergency : VetColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _formatTime(appointment.scheduledAt).split(' ')[1],
                  style: TextStyle(
                    color: isUrgent
                        ? VetColors.emergency
                        : VetColors.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appointment.farmerName,
                        style: const TextStyle(
                          color: VetColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isUrgent) ...[
                      const SizedBox(width: 6),
                      vetChip(
                          'URGENT', VetColors.emergency, VetColors.emergency,
                          fontSize: 9),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  appointment.farmName,
                  style: const TextStyle(
                      color: VetColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _modeBadge(appointment.mode),
                    const SizedBox(width: 6),
                    _statusDot(appointment.status),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '৳${appointment.fee.toStringAsFixed(0)}',
            style: const TextStyle(
              color: VetColors.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBadge(AppointmentMode mode) {
    final (label, color) = switch (mode) {
      AppointmentMode.online => ('Online', VetColors.online),
      AppointmentMode.inPerson => ('In-Person', VetColors.inPerson),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statusDot(AppointmentStatus status) {
    final (color, label) = switch (status) {
      AppointmentStatus.pending => (VetColors.amber, 'Pending'),
      AppointmentStatus.accepted => (VetColors.available, 'Accepted'),
      AppointmentStatus.completed => (VetColors.secondary, 'Done'),
      AppointmentStatus.rejected => (VetColors.red, 'Rejected'),
      AppointmentStatus.rescheduled => (VetColors.moderate, 'Rescheduled'),
      AppointmentStatus.noShow => (VetColors.red, 'No-Show'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── Pending Follow-Ups ────────────────────────────────────────────────────────

class _PendingFollowUps extends StatelessWidget {
  final List<DoctorCase> cases;
  final VoidCallback onSeeAll;
  const _PendingFollowUps({required this.cases, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Pending Follow-Ups',
              style: TextStyle(
                color: VetColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: VetColors.followUpLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${cases.length}',
                style: const TextStyle(
                  color: VetColors.followUpColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                    color: VetColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...cases.take(2).map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FollowUpTile(doctorCase: c),
            )),
      ],
    );
  }
}

class _FollowUpTile extends StatelessWidget {
  final DoctorCase doctorCase;
  const _FollowUpTile({required this.doctorCase});

  String _formatDate(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  bool get _isOverdue =>
      doctorCase.followUpDate != null &&
      doctorCase.followUpDate!.isBefore(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final overdue = _isOverdue;
    return Container(
      decoration: vetCard(
          borderColor: overdue ? VetColors.red.withValues(alpha: 0.4) : null),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.event_repeat,
            color: overdue ? VetColors.red : VetColors.followUpColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctorCase.farmName,
                  style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  doctorCase.farmerName,
                  style: const TextStyle(
                      color: VetColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          if (doctorCase.followUpDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: overdue ? VetColors.redLight : VetColors.followUpLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                overdue ? 'Overdue' : _formatDate(doctorCase.followUpDate!),
                style: TextStyle(
                  color: overdue ? VetColors.red : VetColors.followUpColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final void Function(int) onNavigateTo;
  const _QuickActions({required this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: VetColors.primary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _action(
              icon: Icons.add_circle_outline,
              label: 'New Case',
              color: VetColors.secondary,
              bg: VetColors.availableLight,
              onTap: () => onNavigateTo(2),
            ),
            const SizedBox(width: 10),
            _action(
              icon: Icons.medication_outlined,
              label: 'Prescriptions',
              color: VetColors.open,
              bg: VetColors.openLight,
              onTap: () => context.go('/doctor/prescriptions'),
            ),
            const SizedBox(width: 10),
            _action(
              icon: Icons.event_repeat,
              label: 'Follow-Ups',
              color: VetColors.followUpColor,
              bg: VetColors.followUpLight,
              onTap: () => context.go('/doctor/followups'),
            ),
            const SizedBox(width: 10),
            _action(
              icon: Icons.videocam_outlined,
              label: 'Video Call',
              color: VetColors.inProgress,
              bg: VetColors.inProgressLight,
              onTap: () => context.go('/doctor/video'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}
