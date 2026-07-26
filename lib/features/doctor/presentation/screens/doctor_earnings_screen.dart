import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';

class DoctorEarningsScreen extends StatefulWidget {
  const DoctorEarningsScreen({super.key});

  @override
  State<DoctorEarningsScreen> createState() => _DoctorEarningsScreenState();
}

class _DoctorEarningsScreenState extends State<DoctorEarningsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

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
            automaticallyImplyLeading: false,
            title: const Text(
              'Earnings & Profile',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            bottom: TabBar(
              controller: _tab,
              indicatorColor: VetColors.secondary,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: 'Earnings'),
                Tab(text: 'Ratings'),
                Tab(text: 'Profile'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              _EarningsTab(session: s),
              _RatingsTab(session: s),
              _ProfileTab(session: s),
            ],
          ),
        );
      },
    );
  }
}

// ── Earnings Tab ──────────────────────────────────────────────────────────────

class _EarningsTab extends StatelessWidget {
  final DoctorSession session;
  const _EarningsTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final records = session.earnings.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary cards
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                label: 'Total Earned',
                value: '৳${session.totalEarned.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet_outlined,
                color: VetColors.secondary,
                bg: VetColors.availableLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                label: 'This Month',
                value: '৳${session.thisMonthEarned.toStringAsFixed(0)}',
                icon: Icons.calendar_month_outlined,
                color: VetColors.open,
                bg: VetColors.openLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                label: 'Pending',
                value: '৳${session.pendingAmount.toStringAsFixed(0)}',
                icon: Icons.pending_outlined,
                color: VetColors.amber,
                bg: VetColors.amberLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                label: 'Consultations',
                value:
                    '${session.appointments.where((a) => a.status == AppointmentStatus.completed).length}',
                icon: Icons.medical_services_outlined,
                color: VetColors.followUpColor,
                bg: VetColors.followUpLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Payout button
        ElevatedButton.icon(
          onPressed: () => _showPayoutDialog(context),
          icon: const Icon(Icons.payment_outlined, size: 18),
          label: const Text('Request Payout'),
          style: ElevatedButton.styleFrom(
            backgroundColor: VetColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Payment History',
          style: TextStyle(
            color: VetColors.primary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...records.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EarningsRow(record: r),
            )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                        color: VetColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  void _showPayoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Payout'),
        content: Text(
          'Available balance: ৳${DoctorSession.instance.pendingAmount.toStringAsFixed(0)}\n\nPayouts are processed within 3–5 business days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payout request submitted!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: VetColors.primary),
            child: const Text('Request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  final EarningsRecord record;
  const _EarningsRow({required this.record});

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

  @override
  Widget build(BuildContext context) {
    final r = record;
    final isPaid = r.isPaid;
    final isZero = r.amount == 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: vetCard(),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isZero
                  ? VetColors.redLight
                  : isPaid
                      ? VetColors.availableLight
                      : VetColors.amberLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isZero
                  ? Icons.person_off_outlined
                  : isPaid
                      ? Icons.check_circle_outline
                      : Icons.schedule_outlined,
              color: isZero
                  ? VetColors.red
                  : isPaid
                      ? VetColors.available
                      : VetColors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.farmerName,
                  style: const TextStyle(
                    color: VetColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  r.description,
                  style: const TextStyle(
                      color: VetColors.textSecondary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isZero ? 'No-Show' : '৳${r.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  color: isZero
                      ? VetColors.red
                      : isPaid
                          ? VetColors.available
                          : VetColors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _formatDate(r.date),
                style: const TextStyle(color: VetColors.grey, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Ratings Tab ───────────────────────────────────────────────────────────────

class _RatingsTab extends StatelessWidget {
  final DoctorSession session;
  const _RatingsTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final ratings = session.ratings.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RatingSummary(ratings: ratings, profile: session.profile),
        const SizedBox(height: 20),
        const Text(
          'Recent Reviews',
          style: TextStyle(
              color: VetColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...ratings.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReviewCard(rating: r),
            )),
      ],
    );
  }
}

class _RatingSummary extends StatelessWidget {
  final List<FarmerRating> ratings;
  final DoctorProfile profile;
  const _RatingSummary({required this.ratings, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: vetCard(),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                profile.rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: VetColors.primary,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < profile.rating.floor() ? Icons.star : Icons.star_border,
                    color: const Color(0xFFFFB300),
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${profile.totalRatings} reviews',
                style: const TextStyle(color: VetColors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 20),
          const VerticalDivider(width: 1, color: VetColors.divider),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final count =
                    ratings.where((r) => r.rating.round() == star).length;
                final pct = ratings.isEmpty ? 0.0 : count / ratings.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star',
                          style: const TextStyle(
                              color: VetColors.textSecondary, fontSize: 11)),
                      const SizedBox(width: 4),
                      const Icon(Icons.star,
                          size: 10, color: Color(0xFFFFB300)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: VetColors.surface2,
                            color: const Color(0xFFFFB300),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              color: VetColors.grey, fontSize: 11),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final FarmerRating rating;
  const _ReviewCard({required this.rating});

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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: VetColors.secondary.withValues(alpha: 0.12),
                child: Text(
                  rating.farmerName.isNotEmpty ? rating.farmerName[0] : 'F',
                  style: const TextStyle(
                    color: VetColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rating.farmerName,
                      style: const TextStyle(
                        color: VetColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatDate(rating.date),
                      style:
                          const TextStyle(color: VetColors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating.rating ? Icons.star : Icons.star_border,
                    color: const Color(0xFFFFB300),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          if (rating.review != null && rating.review!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              rating.review!,
              style: const TextStyle(
                color: VetColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Profile Tab ───────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final DoctorSession session;
  const _ProfileTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final p = session.profile;
    final user = session.registeredUser;
    final registrationDetails = <String, dynamic>{
      if (user != null) ...{
        'Full Name': user.fullName,
        'Email': user.email,
        'Phone': user.phone,
        'Address': user.presentAddress,
        'Date Of Birth': user.dateOfBirth,
        ...user.profileData
            .map((key, value) => MapEntry(_profileLabel(key), value)),
      },
    }..removeWhere(
        (key, value) => value == null || value.toString().trim().isEmpty);
    final (statusColor, statusLabel) = switch (p.availability) {
      DoctorAvailability.available => (VetColors.available, 'Available'),
      DoctorAvailability.busy => (VetColors.busy, 'Busy'),
      DoctorAvailability.offline => (VetColors.offline, 'Offline'),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: vetCard(),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: VetColors.secondary.withValues(alpha: 0.15),
                child: Text(
                  p.name.isNotEmpty ? p.name[0] : 'D',
                  style: const TextStyle(
                    color: VetColors.secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              color: VetColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (p.isVerified)
                          const Icon(Icons.verified,
                              color: VetColors.secondary, size: 16),
                      ],
                    ),
                    Text(p.specialty,
                        style: const TextStyle(
                            color: VetColors.textSecondary, fontSize: 13)),
                    Text('Lic: ${p.licenseNo}',
                        style: const TextStyle(
                            color: VetColors.grey, fontSize: 11)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: statusColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star,
                            color: Color(0xFFFFB300), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          '${p.rating} (${p.totalRatings})',
                          style: const TextStyle(
                              color: VetColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (registrationDetails.isNotEmpty) ...[
          _sectionTitle('Registration Details'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: vetCard(),
            child: Column(
              children: registrationDetails.entries
                  .map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Text(entry.key,
                                    style: const TextStyle(
                                        color: VetColors.textSecondary,
                                        fontSize: 12))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(entry.value.toString(),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                        color: VetColors.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Status change
        _sectionTitle('Status'),
        const SizedBox(height: 8),
        ...[
          DoctorAvailability.available,
          DoctorAvailability.busy,
          DoctorAvailability.offline
        ].map((av) {
          final (col, lbl) = switch (av) {
            DoctorAvailability.available => (
                VetColors.available,
                'Available — Accepting consultations'
              ),
            DoctorAvailability.busy => (
                VetColors.busy,
                'Busy — Not available right now'
              ),
            DoctorAvailability.offline => (
                VetColors.offline,
                'Offline — Hidden from farmer search'
              ),
          };
          final isSelected = p.availability == av;
          return GestureDetector(
            onTap: () => DoctorSession.instance.setAvailability(av),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: vetCard(
                borderColor: isSelected ? col.withValues(alpha: 0.5) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: col, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lbl,
                      style: TextStyle(
                        color: isSelected ? col : VetColors.textPrimary,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: col, size: 18),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        _sectionTitle('Account'),
        const SizedBox(height: 8),
        _menuItem(
          icon: Icons.email_outlined,
          label: p.email,
          onTap: () {},
        ),
        _menuItem(
          icon: Icons.phone_outlined,
          label: p.phone,
          onTap: () {},
        ),
        _menuItem(
          icon: Icons.help_outline,
          label: 'Help & Support',
          onTap: () {},
        ),
        _menuItem(
          icon: Icons.logout,
          label: 'Log Out',
          color: VetColors.red,
          onTap: () async {
            await AuthService.instance.clearSession();
            if (context.mounted) {
              context.go(AppRoutes.login);
            }
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _profileLabel(String key) => key
      .split('_')
      .map((word) =>
          word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          color: VetColors.primary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: vetCard(),
          child: Row(
            children: [
              Icon(icon, color: color ?? VetColors.primary, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color ?? VetColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  color: color ?? VetColors.grey, size: 13),
            ],
          ),
        ),
      );
}
