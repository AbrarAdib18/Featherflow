import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The backend-provided tap target of a notification (`navigation` in the
/// API). See NOTIFICATION_NAVIGATION_MATRIX.md.
class NotificationTarget {
  const NotificationTarget({
    required this.route,
    required this.targetType,
    required this.targetId,
    required this.available,
  });

  final String? route;
  final String? targetType;
  final String? targetId;
  final bool available;

  static NotificationTarget? fromNotification(Map<String, dynamic> n) {
    final raw = n['navigation'];
    if (raw is! Map) return null;
    return NotificationTarget(
      route: raw['route']?.toString(),
      targetType: raw['target_type']?.toString(),
      targetId: raw['target_id']?.toString(),
      available: raw['available'] != false,
    );
  }
}

enum NotificationTapOutcome { navigated, unavailable, noDestination, ignored }

/// The one place a notification tap is turned into navigation. Every
/// notification list, sheet and toast in the app goes through [open], so no
/// card carries its own routing table.
class NotificationNavigator {
  NotificationNavigator._();

  /// Route prefixes a notification may open. The backend chooses the route,
  /// but the client still refuses anything outside the app's own sections —
  /// a malformed or unexpected payload can never drive navigation anywhere
  /// else. Every one of these destinations is also guarded server-side (each
  /// screen's API only returns the caller's own data / enforces admin RBAC).
  static const allowedPrefixes = <String>[
    '/farmer', '/doctor', '/pharmacy', '/delivery', '/research',
    '/admin', '/community', '/subscription',
  ];

  static const debounce = Duration(milliseconds: 800);
  static DateTime? _lastTap;

  static bool isAllowedRoute(String? route) {
    if (route == null || route.isEmpty || !route.startsWith('/')) return false;
    if (route.contains('//') || route.contains('..') || route.contains(':')) return false;
    return allowedPrefixes.any((p) => route == p || route.startsWith('$p/'));
  }

  /// Pure decision, separated from the side effects so it can be unit-tested.
  static (NotificationTapOutcome, String?) resolve(Map<String, dynamic> n) {
    final target = NotificationTarget.fromNotification(n);
    if (target == null) return (NotificationTapOutcome.noDestination, null);
    if (!target.available) return (NotificationTapOutcome.unavailable, null);
    if (!isAllowedRoute(target.route)) return (NotificationTapOutcome.noDestination, null);
    return (NotificationTapOutcome.navigated, target.route);
  }

  /// [push] keeps the caller on the back stack (use from a full-screen list);
  /// otherwise the app `go`es to the route, whose parent is then the natural
  /// back destination (use from a dialog/sheet, which [beforeNavigate] closes).
  static Future<NotificationTapOutcome> open(
    BuildContext context,
    Map<String, dynamic> notification, {
    GoRouter? router,
    bool push = false,
    VoidCallback? beforeNavigate,
  }) async {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < debounce) {
      return NotificationTapOutcome.ignored; // double tap
    }
    _lastTap = now;

    final (outcome, route) = resolve(notification);
    switch (outcome) {
      case NotificationTapOutcome.navigated:
        final goRouter = router ?? GoRouter.of(context);
        beforeNavigate?.call();
        if (push) {
          goRouter.push(route!);
        } else {
          goRouter.go(route!);
        }
      case NotificationTapOutcome.unavailable:
        await _info(context, notification['title']?.toString() ?? 'Notification',
            'This item is no longer available.');
      case NotificationTapOutcome.noDestination:
        // No meaningful screen for this type — stay here and show the full
        // text rather than doing nothing on tap.
        await _info(context, notification['title']?.toString() ?? 'Notification',
            (notification['body'] ?? notification['message'] ?? '').toString());
      case NotificationTapOutcome.ignored:
        break;
    }
    return outcome;
  }

  static Future<void> _info(BuildContext context, String title, String body) {
    if (!context.mounted) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @visibleForTesting
  static void resetDebounce() => _lastTap = null;
}
