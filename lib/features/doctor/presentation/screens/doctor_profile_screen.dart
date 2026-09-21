import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/profile_photo_field.dart';
import '../../data/models/doctor_models.dart';
import '../../data/services/doctor_session.dart';
import '../doctor_theme.dart';

/// The doctor's Profile screen — routed at `/doctor/profile`, opened from the
/// avatar button in the dashboard's top-right corner (matching the farmer
/// dashboard's profile button). This is the same content that previously
/// lived as the "Profile" tab inside Earnings & Profile; moved here verbatim
/// so it has its own back-navigable route instead of sharing Earnings'
/// AppBar/TabBar. See DOCTOR_DASHBOARD_PROFILE_AND_RATING.md.
class DoctorProfileScreen extends StatelessWidget {
  const DoctorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DoctorSession.instance,
      builder: (context, _) {
        final session = DoctorSession.instance;
        return Scaffold(
          backgroundColor: VetColors.bg,
          appBar: AppBar(
            backgroundColor: VetColors.appBar,
            foregroundColor: Colors.white,
            title: const Text(
              'Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          body: _ProfileBody(session: session),
        );
      },
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final DoctorSession session;
  const _ProfileBody({required this.session});

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
              // Tap the camera badge to change the photo — same upload
              // pipeline (pick → validate → upload → session refreshes
              // everywhere) already used on the dashboard's welcome header
              // and every other role's profile screen; not a new widget.
              ProfilePhotoField(
                radius: 32,
                onLightSurface: true,
                showLabel: false,
                currentUrl:
                    AuthService.instance.currentSession?.user.profilePhotoUrl ??
                        '',
                fallbackInitial: p.name.isNotEmpty ? p.name[0].toUpperCase() : 'D',
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
