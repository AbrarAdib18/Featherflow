import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Shared "something went wrong" panel for async screens: a readable message
/// (never a raw exception / stack trace) plus a Retry action. Use this instead
/// of `Center(child: Text(error.toString()))` so every failed load looks the
/// same and always offers a way forward.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final bool compact;

  /// Turn common low-level failures into something a farmer can act on.
  static String humanize(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('clientexception') ||
        lower.contains('xmlhttprequest')) {
      return 'Can’t reach the server. Check your connection and try again.';
    }
    if (lower.contains('formatexception') || lower.contains('<!doctype')) {
      return 'The server sent an unexpected response. Please try again.';
    }
    if (lower.contains('please sign in')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (raw.isEmpty) return 'Something went wrong. Please try again.';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 32 : 44, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.onSurface, fontSize: 14, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
