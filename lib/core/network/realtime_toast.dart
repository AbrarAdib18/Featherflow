import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notification_navigator.dart';
import 'user_updates_service.dart';

/// Wraps every screen (via `MaterialApp.router`'s `builder`). Watches
/// [UserUpdatesService] and shows a SnackBar whenever an admin action produces
/// a notification for this user ("Your account has been verified by admin").
class RealtimeToastHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  /// This host sits *above* the router (MaterialApp.router's `builder`), so
  /// it can't look a GoRouter up from its own context — main.dart passes the
  /// app's router in so a toast's "Open" action can navigate.
  final GoRouter? router;
  const RealtimeToastHost({
    super.key,
    required this.child,
    required this.messengerKey,
    this.router,
  });

  @override
  State<RealtimeToastHost> createState() => _RealtimeToastHostState();
}

class _RealtimeToastHostState extends State<RealtimeToastHost> {
  @override
  void initState() {
    super.initState();
    UserUpdatesService.instance.addListener(_onUpdate);
  }

  @override
  void dispose() {
    UserUpdatesService.instance.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    Map<String, dynamic>? n;
    while ((n = UserUpdatesService.instance.consumeToast()) != null) {
      final title = (n!['title'] ?? '').toString();
      final body = (n['body'] ?? '').toString();
      final messenger = widget.messengerKey.currentState;
      if (messenger == null) return;
      final notification = n;
      final router = widget.router;
      final (outcome, _) = NotificationNavigator.resolve(notification);
      final canOpen = router != null && outcome == NotificationTapOutcome.navigated;
      messenger.showSnackBar(SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        // Toasts used to be display-only. Same NotificationNavigator as every
        // list, so the destination always matches the backend's mapping.
        action: canOpen
            ? SnackBarAction(
                label: 'Open',
                onPressed: () {
                  final navContext = router.routerDelegate.navigatorKey.currentContext;
                  if (navContext != null) {
                    NotificationNavigator.open(navContext, notification, router: router);
                  }
                },
              )
            : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
