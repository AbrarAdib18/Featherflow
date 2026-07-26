import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/l10n/language_dialog.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/core/router/app_router.dart';

class FarmerProfileScreen extends StatefulWidget {
  const FarmerProfileScreen({super.key});

  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen> {
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await AuthService.instance.getStoredSession();
    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _signOut(BuildContext context) async {
    await AuthService.instance.clearSession();
    if (!mounted) return;
    if (context.mounted) {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = _session?.user.fullName.isNotEmpty == true
        ? _session!.user.fullName
        : (_session?.user.email.split('@').first ?? 'Farmer');
    final role = (_session?.user.roles.isNotEmpty == true ? _session!.user.roles.first : 'farmer').toUpperCase();
    final email = _session?.user.email ?? '—';
    final accountStatus = _session?.user.accountStatus ?? 'pending';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l.myProfile,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () => context.go('/farmer'),
            tooltip: 'Home',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(name: name, role: role, email: email, accountStatus: accountStatus),
            _InfoSection(session: _session),
            _SettingsList(onSignOut: () => _signOut(context)),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String role;
  final String email;
  final String accountStatus;

  const _ProfileHeader({required this.name, required this.role, required this.email, required this.accountStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl,
      ),
      child: Column(
        children: [
          Stack(
            children: [
              const CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.primaryContainer,
                child: CircleAvatar(
                  radius: 45,
                  backgroundColor: AppColors.secondaryContainer,
                  child: Icon(Icons.person, size: 52, color: Colors.white70),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _RoleBadge(role: role),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text(
                email,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.white54, size: 14),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Status: ${accountStatus.toUpperCase()}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: AppRadius.fullAll,
      ),
      child: Text(
        role,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Info Section ──────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final AuthSession? session;

  const _InfoSection({required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FarmDetailsCard(session: session),
          const SizedBox(height: AppSpacing.md),
          _AccountDetailsCard(session: session),
          const SizedBox(height: AppSpacing.md),
          const _SubscriptionCard(),
        ],
      ),
    );
  }
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFDEEAE5)),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF0F7F4)),
      ],
    );
  }
}

class _FarmDetailsCard extends StatelessWidget {
  final AuthSession? session;

  const _FarmDetailsCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final email = session?.user.email ?? 'No email';
    return _SectionCard(
      icon: Icons.agriculture,
      title: l.farmDetails,
      children: [
        _InfoRow(label: l.farmType, value: l.farmTypeValue),
        _InfoRow(label: l.email, value: email),
        _InfoRow(
            label: l.totalBirds,
            value: l.locale.languageCode == 'bn' ? '৪,৫০০' : '4,500'),
        _InfoRow(label: l.experience, value: l.experienceValue, isLast: true),
      ],
    );
  }
}

class _AccountDetailsCard extends StatelessWidget {
  final AuthSession? session;

  const _AccountDetailsCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fullName = session?.user.fullName.isNotEmpty == true ? session!.user.fullName : 'Farmer';
    final email = session?.user.email ?? 'No email';
    final status = session?.user.accountStatus ?? 'pending';
    return _SectionCard(
      icon: Icons.manage_accounts_outlined,
      title: l.accountDetails,
      children: [
        _InfoRow(label: l.email, value: email),
        _InfoRow(label: l.phone, value: status.toUpperCase()),
        _InfoRow(
            label: l.memberSince,
            value: fullName,
            isLast: true),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: const Color(0xFFDEEAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: const Icon(Icons.workspace_premium_outlined,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  l.subscription,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFDEEAE5)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color:
                              AppColors.secondary.withValues(alpha: 0.15),
                          borderRadius: AppRadius.smAll,
                          border: Border.all(
                            color:
                                AppColors.secondary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          l.proPlan,
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l.expires,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => context.go('/subscription'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Text(l.upgrade),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings List ─────────────────────────────────────────────────────────────

class _SettingsList extends StatelessWidget {
  final VoidCallback onSignOut;

  const _SettingsList({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currentLangName = LanguageNotifier.instance.isBengali
        ? 'বাংলা'
        : 'English';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFFDEEAE5)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.settings,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: const Color(0xFFDEEAE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _SettingsItem(
                  icon: Icons.edit_outlined,
                  label: l.editProfile,
                  onTap: () {},
                ),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                _SettingsItem(
                  icon: Icons.lock_outline,
                  label: l.changePassword,
                  onTap: () {},
                ),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                _SettingsItem(
                  icon: Icons.notifications_outlined,
                  label: l.notificationSettings,
                  onTap: () {},
                ),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                _SettingsItem(
                  icon: Icons.language_outlined,
                  label: l.languagePreference,
                  onTap: () => showLanguageDialog(context, dismissible: true),
                  trailing: Text(
                    currentLangName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                _SettingsItem(
                  icon: Icons.privacy_tip_outlined,
                  label: l.privacyPolicy,
                  onTap: () {},
                ),
                const Divider(height: 1, color: Color(0xFFDEEAE5)),
                _SettingsItem(
                  icon: Icons.description_outlined,
                  label: l.termsOfService,
                  onTap: () {},
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(l.logout),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1.5),
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.mdAll),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool isLast;

  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: AppSpacing.xs),
            ],
            const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }
}
