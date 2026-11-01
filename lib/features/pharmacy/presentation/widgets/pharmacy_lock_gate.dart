import 'package:flutter/material.dart';

import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import '../screens/pharmacy_appeal_screen.dart';
import '../screens/pharmacy_support_chat_screen.dart';
import 'pharmacy_locked_banner.dart';

/// Wraps an operational pharmacy section (catalogue, inventory, orders,
/// suppliers, analytics). While the account is pending / rejected / suspended
/// (`GET /api/pharmacy/permissions/` -> not ACTIVE) the section is replaced by
/// a locked panel — status, reason, and the always-on actions (Pharmacy Admin
/// chat, appeal) — instead of an empty list with working "Add" buttons. The
/// backend enforces the same lock (those endpoints 403 for a non-active
/// pharmacy); this just stops the UI from pretending the data is empty.
class PharmacyLockGate extends StatelessWidget {
  const PharmacyLockGate({super.key, required this.child, this.section = 'This section'});

  final Widget child;
  final String section;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        // Lock state not known yet (first permissions call in flight): don't build the
        // operational screen — it would fire its (401/403) data calls and flash an
        // empty list for an account that is about to be shown as locked.
        if (s.permissions == null && !s.ready) {
          return const Center(child: CircularProgressIndicator(color: PhColors.secondary));
        }
        // (If the permissions call failed but the session finished loading, fall through to the
        // screen's own error handling rather than spinning forever.)
        if (!s.isLocked) return child;
        return Container(
          color: PhColors.bg,
          child: ListView(
            key: const ValueKey('pharmacy-locked-panel'),
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.lock_outline, size: 44, color: PhColors.grey),
              const SizedBox(height: 10),
              Text('$section is locked',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                  'Operational features unlock again once your account is active. '
                  'Your profile, earnings, Pharmacy Admin chat and appeal stay available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: PhColors.textSecondary)),
              const SizedBox(height: 16),
              PharmacyLockedBanner(
                permissions: s.permissions!,
                onRefresh: s.refreshPermissions,
                onContactAdmin: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PharmacySupportChatScreen())),
                onOpenAppeal: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PharmacyAppealScreen())),
              ),
            ],
          ),
        );
      },
    );
  }
}
