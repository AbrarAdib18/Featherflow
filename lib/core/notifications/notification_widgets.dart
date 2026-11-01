import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../network/auth_service.dart';
import '../network/user_updates_service.dart';
import 'notification_navigator.dart';
import 'notification_time.dart';

/// One app-wide clock that relative-time labels listen to. It ticks every 30s
/// and on app resume — repainting labels locally from each notification's
/// persisted `created_at`; it never calls the API. The timer only runs while
/// at least one label is on screen.
class NotificationClock extends ValueNotifier<DateTime> with WidgetsBindingObserver {
  NotificationClock._() : super(DateTime.now());
  static final NotificationClock instance = NotificationClock._();

  static const tick = Duration(seconds: 30);
  Timer? _timer;
  int _listeners = 0;

  void refresh() => value = DateTime.now();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_listeners++ == 0) {
      _timer = Timer.periodic(tick, (_) => refresh());
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (--_listeners == 0) {
      _timer?.cancel();
      _timer = null;
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}

/// "Just now" / "5 mins ago" … recomputed from `created_at` on every tick,
/// refresh and app resume. Never mutates the notification's own timestamp.
class NotificationTimeLabel extends StatelessWidget {
  const NotificationTimeLabel(this.notification, {super.key, this.style});
  final Map<String, dynamic> notification;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: NotificationClock.instance,
      builder: (_, now, __) => Text(
        notificationTimeLabel(notification, now: now),
        key: const Key('notificationTimeLabel'),
        style: style ?? const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
      ),
    );
  }
}

/// The single notification row used by every role's list/sheet.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    this.leading,
  });

  final Map<String, dynamic> notification;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final read = notification['is_read'] == true;
    final body = (notification['body'] ?? notification['message'] ?? '').toString();
    return ListTile(
      onTap: onTap,
      leading: leading ?? const Icon(Icons.notifications_outlined, color: Color(0xFF1DB584)),
      title: Text('${notification['title'] ?? ''}',
          style: TextStyle(fontWeight: read ? FontWeight.w500 : FontWeight.w800)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body.isNotEmpty) Text(body),
          NotificationTimeLabel(notification),
        ],
      ),
      isThreeLine: body.isNotEmpty,
      trailing: read
          ? null
          : const CircleAvatar(radius: 4, backgroundColor: Color(0xFFC62828)),
    );
  }
}

/// Role-agnostic access to `/api/notifications/`.
class NotificationApi {
  NotificationApi._();

  static Future<Map<String, String>> _headers() async {
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session == null || session.accessToken.isEmpty) {
      throw Exception('Please sign in to see notifications.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  static Uri get _uri => Uri.parse('${AuthService.instance.baseUrl}/api/notifications/');

  static Future<List<Map<String, dynamic>>> fetch() async {
    final res = await http.get(_uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw Exception('Could not load notifications (${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['notifications'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> markAllRead() async {
    await http.patch(_uri, headers: await _headers(), body: '{}');
  }
}

/// The shared notification center (a dialog). Existing product rule kept:
/// everything is marked read when the center closes.
///
/// [fetch]/[markRead] default to `/api/notifications/`; a role session that
/// already owns these calls (e.g. DoctorSession) passes its own so its badge
/// stays in sync.
Future<void> showNotificationCenter(
  BuildContext context, {
  String title = 'Notifications',
  Future<List<Map<String, dynamic>>> Function()? fetch,
  Future<void> Function()? markRead,
  Widget Function(Map<String, dynamic> n)? leadingBuilder,
}) async {
  final router = GoRouter.maybeOf(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => _NotificationCenter(
      title: title,
      fetch: fetch ?? NotificationApi.fetch,
      router: router,
      leadingBuilder: leadingBuilder,
    ),
  );
  try {
    await (markRead ?? NotificationApi.markAllRead)();
  } catch (_) {
    // Stays unread; retried next time the center closes.
  }
  unawaited(UserUpdatesService.instance.poll()); // refresh every badge
}

class _NotificationCenter extends StatefulWidget {
  const _NotificationCenter({
    required this.title,
    required this.fetch,
    required this.router,
    this.leadingBuilder,
  });

  final String title;
  final Future<List<Map<String, dynamic>>> Function() fetch;
  final GoRouter? router;
  final Widget Function(Map<String, dynamic> n)? leadingBuilder;

  @override
  State<_NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<_NotificationCenter> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.fetch();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
      NotificationClock.instance.refresh(); // labels recomputed on every fetch
    } catch (e) {
      if (!mounted) return;
      // A failed refresh keeps whatever was already showing.
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(children: [
          ListTile(
            title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    if (_rows.isEmpty) return const Center(child: Text('No notifications yet.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final n = _rows[i];
          return NotificationTile(
            notification: n,
            leading: widget.leadingBuilder?.call(n),
            onTap: () => NotificationNavigator.open(
              context, n,
              router: widget.router,
              beforeNavigate: () => Navigator.pop(context),
            ),
          );
        },
      ),
    );
  }
}

/// Bell + unread badge for app bars that had no notification entry point.
/// The count comes from the app-wide `/api/me/updates/` poller, which already
/// runs for every signed-in role.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key, this.color = Colors.white});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserUpdatesService.instance,
      builder: (context, _) {
        final unread = UserUpdatesService.instance.unreadCount;
        return IconButton(
          key: const Key('notificationBell'),
          tooltip: 'Notifications',
          onPressed: () => showNotificationCenter(context),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(Icons.notifications_outlined, color: color),
          ),
        );
      },
    );
  }
}
