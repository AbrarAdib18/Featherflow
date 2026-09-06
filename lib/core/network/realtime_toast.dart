import 'package:flutter/material.dart';

import 'user_updates_service.dart';

/// Wraps every screen (via `MaterialApp.router`'s `builder`). Watches
/// [UserUpdatesService] and shows a SnackBar whenever an admin action produces
/// a notification for this user ("Your account has been verified by admin").
class RealtimeToastHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  const RealtimeToastHost({
    super.key,
    required this.child,
    required this.messengerKey,
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
      messenger.showSnackBar(SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
