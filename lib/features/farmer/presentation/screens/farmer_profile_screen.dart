import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/l10n/app_localizations.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';
import 'package:featherflow/core/l10n/language_dialog.dart';

class FarmerProfileScreen extends StatelessWidget {
  const FarmerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
      body: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(),
            _InfoSection(),
            _SettingsList(),
            SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

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
          const Text(
            'Ahmed Rahman',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _RoleBadge(),
          const SizedBox(height: AppSpacing.md),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.agriculture, color: Colors.white70, size: 16),
              SizedBox(width: AppSpacing.xs),
              Text(
                'Green Valley Farm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, color: Colors.white54, size: 14),
              SizedBox(width: AppSpacing.xs),
              Text(
                'Dhaka, Bangladesh',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge();

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
        l.farmer,
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
  const _InfoSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FarmDetailsCard(),
          SizedBox(height: AppSpacing.md),
          _AccountDetailsCard(),
          SizedBox(height: AppSpacing.md),
          _SubscriptionCard(),
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
  const _FarmDetailsCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.agriculture,
      title: l.farmDetails,
      children: [
        _InfoRow(label: l.farmType, value: l.farmTypeValue),
        _InfoRow(
            label: l.totalBirds,
            value: l.locale.languageCode == 'bn' ? '৪,৫০০' : '4,500'),
        _InfoRow(
            label: l.workers,
            value: l.locale.languageCode == 'bn' ? '১২' : '12'),
        _InfoRow(label: l.experience, value: l.experienceValue, isLast: true),
      ],
    );
  }
}

class _AccountDetailsCard extends StatelessWidget {
  const _AccountDetailsCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.manage_accounts_outlined,
      title: l.accountDetails,
      children: [
        _InfoRow(label: l.email, value: 'ahmed@greenvalley.bd'),
        _InfoRow(label: l.phone, value: '+880 1711-234567'),
        _InfoRow(
            label: l.memberSince,
            value: l.locale.languageCode == 'bn' ? 'জানুয়ারি ২০২৩' : 'Jan 2023',
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
  const _SettingsList();

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
              onPressed: () {},
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
