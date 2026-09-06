import 'package:flutter/material.dart';

import '../admin_theme.dart';

/// Shared loading / empty / error placeholders for admin list screens.
class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: CircularProgressIndicator(color: AColors.secondary));
}

class AdminEmpty extends StatelessWidget {
  final String message;
  final IconData icon;
  const AdminEmpty(this.message, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AColors.grey),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AColors.textSecondary)),
          ],
        ),
      );
}

class AdminError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const AdminError(this.message, this.onRetry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AColors.red),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AColors.textSecondary)),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
