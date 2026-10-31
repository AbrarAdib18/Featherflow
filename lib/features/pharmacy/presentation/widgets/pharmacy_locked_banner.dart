import 'package:flutter/material.dart';

import '../../data/services/pharmacy_permissions_service.dart';
import '../pharmacy_theme.dart';

/// The single "why is this locked" treatment every pharmacy screen should
/// show instead of a bespoke per-screen message — reads directly from
/// `GET /api/pharmacy/permissions/` (PharmacyPermissions), the backend's own
/// source of truth for lock state, per spec §7.
class PharmacyLockedBanner extends StatelessWidget {
  const PharmacyLockedBanner({
    super.key,
    required this.permissions,
    this.onContactAdmin,
    this.onOpenAppeal,
    this.onRefresh,
  });

  final PharmacyPermissions permissions;
  final VoidCallback? onContactAdmin;
  final VoidCallback? onOpenAppeal;
  final VoidCallback? onRefresh;

  static const _statusColors = {
    'PENDING_REVIEW': PhColors.pending,
    'NEEDS_MORE_INFORMATION': PhColors.pending,
    'REJECTED': PhColors.red,
    'SUSPENDED': PhColors.red,
    'APPEAL_PENDING': PhColors.red,
    'CLOSED': PhColors.grey,
    'ACTIVE': PhColors.secondary,
  };

  static const _statusIcons = {
    'PENDING_REVIEW': Icons.hourglass_bottom,
    'NEEDS_MORE_INFORMATION': Icons.info_outline,
    'REJECTED': Icons.cancel,
    'SUSPENDED': Icons.block,
    'APPEAL_PENDING': Icons.gavel,
    'CLOSED': Icons.lock,
    'ACTIVE': Icons.verified,
  };

  static const _statusLabels = {
    'PENDING_REVIEW': 'Verification pending',
    'NEEDS_MORE_INFORMATION': 'More information needed',
    'REJECTED': 'Application rejected',
    'SUSPENDED': 'Account suspended',
    'APPEAL_PENDING': 'Appeal under review',
    'CLOSED': 'Account closed',
    'ACTIVE': 'Account active',
  };

  @override
  Widget build(BuildContext context) {
    if (permissions.isActive) return const SizedBox.shrink();
    final status = permissions.status;
    final color = _statusColors[status] ?? PhColors.grey;
    final icon = _statusIcons[status] ?? Icons.info_outline;
    final label = _statusLabels[status] ?? status;
    final reason = permissions.rejectionReason ??
        permissions.moreInformationReason ??
        '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: phCard(color: color.withValues(alpha: 0.06), borderColor: color.withValues(alpha: 0.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
          ),
          if (onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Refresh status',
              onPressed: onRefresh,
            ),
        ]),
        if (permissions.lockedReason != null) ...[
          const SizedBox(height: 6),
          Text(permissions.lockedReason!, style: phFieldText),
        ],
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Reason: $reason',
              style: const TextStyle(fontSize: 13, color: PhColors.textPrimary, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (permissions.canDo('chat') && onContactAdmin != null)
            OutlinedButton.icon(
              onPressed: onContactAdmin,
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Contact Pharmacy Admin'),
            ),
          if (permissions.canDo('appeal') && onOpenAppeal != null)
            OutlinedButton.icon(
              onPressed: onOpenAppeal,
              icon: const Icon(Icons.gavel_outlined, size: 16),
              label: Text(permissions.openAppealId != null ? 'View appeal' : 'Submit appeal'),
            ),
        ]),
      ]),
    );
  }
}

/// A small overlay for an individual locked feature card/tile — shows a lock
/// icon + short explanation instead of a dead button that silently fails.
class PharmacyLockedOverlay extends StatelessWidget {
  const PharmacyLockedOverlay({super.key, required this.child, required this.locked, this.message});

  final Widget child;
  final bool locked;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(children: [
      Opacity(opacity: 0.4, child: IgnorePointer(child: child)),
      Positioned.fill(
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Tooltip(
            message: message ?? 'Locked until your account is approved.',
            child: const Icon(Icons.lock_outline, color: PhColors.grey),
          ),
        ),
      ),
    ]);
  }
}
