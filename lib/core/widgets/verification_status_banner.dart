import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Renders the unified verification payload the backend now returns from
/// `GET /api/farmers/profile/` (`verification`) and `/api/me/updates/`
/// (`verification_status`) — see `backend/verification/status.py`.
///
/// Replaces ad-hoc single-flag checks ("is_verified == true" -> a generic
/// "not verified" label) with the three real, independent axes: contact
/// (email/phone), professional approval (role-specific, or not required),
/// and documents. Exactly one line per axis, in plain language, so a farmer
/// with an active account and a doctor mid-review never see the same vague
/// message.
class VerificationStatusBanner extends StatelessWidget {
  const VerificationStatusBanner({super.key, required this.status});

  /// The raw `verification` / `verification_status` map from the API.
  final Map<String, dynamic> status;

  static const _statusColors = {
    'approved': AppColors.secondary,
    'not_required': AppColors.secondary,
    'verified': AppColors.secondary,
    'pending': Colors.orange,
    'partial': Colors.orange,
    'rejected': AppColors.error,
    'suspended': AppColors.error,
    'not_applicable': AppColors.onSurfaceVariant,
  };

  static const _statusIcons = {
    'approved': Icons.verified,
    'not_required': Icons.verified,
    'verified': Icons.verified,
    'pending': Icons.hourglass_bottom,
    'partial': Icons.hourglass_bottom,
    'rejected': Icons.cancel,
    'suspended': Icons.block,
    'not_applicable': Icons.info_outline,
  };

  Color _colorFor(String key) => _statusColors[key] ?? AppColors.onSurfaceVariant;
  IconData _iconFor(String key) => _statusIcons[key] ?? Icons.info_outline;

  Widget _line(String label, bool ok, {String? okText, String? pendingText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16, color: ok ? AppColors.secondary : AppColors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok ? (okText ?? '$label verified.') : (pendingText ?? '$label verification pending.'),
            style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = (status['contact'] as Map?) ?? const {};
    final professional = (status['professional_approval'] as Map?) ?? const {};
    final documents = (status['documents'] as Map?) ?? const {};
    final professionalStatus = (professional['status'] ?? 'not_required').toString();
    final documentsStatus = (documents['status'] ?? 'not_applicable').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(professionalStatus), size: 18, color: _colorFor(professionalStatus)),
          const SizedBox(width: 8),
          const Text('Account status',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.onSurface)),
        ]),
        const SizedBox(height: 8),
        _line('Email', contact['email_verified'] == true),
        _line('Phone', contact['phone_verified'] == true),
        if (professionalStatus != 'not_required')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(_iconFor(professionalStatus), size: 16, color: _colorFor(professionalStatus)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (professional['message'] ?? '').toString(),
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                ),
              ),
            ]),
          ),
        if (documentsStatus != 'not_applicable')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(_iconFor(documentsStatus), size: 16, color: _colorFor(documentsStatus)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (documents['message'] ?? '').toString(),
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                ),
              ),
            ]),
          ),
        if (status['account_active'] == false) ...[
          const SizedBox(height: 4),
          Text(
            status['account_status'] == 'suspended'
                ? 'This account is suspended. Contact support.'
                : 'This account is pending activation.',
            style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    );
  }
}
