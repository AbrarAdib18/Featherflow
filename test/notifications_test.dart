// Notification timing + tap navigation — see
// NOTIFICATION_TIMING_AND_NAVIGATION_AUDIT.md / NOTIFICATION_NAVIGATION_MATRIX.md.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/notifications/notification_navigator.dart';
import 'package:featherflow/core/notifications/notification_time.dart';
import 'package:featherflow/core/notifications/notification_widgets.dart';

Map<String, dynamic> _n({
  String id = '1',
  String? createdAt,
  Map<String, dynamic>? navigation,
  String title = 'Title',
  String body = 'Body',
}) =>
    {
      'id': id,
      'title': title,
      'body': body,
      'is_read': false,
      'created_at': createdAt,
      'navigation': navigation,
    };

Map<String, dynamic> _nav(String? route, {bool available = true}) => {
      'route': route,
      'target_type': 'x',
      'target_id': null,
      'available': available,
    };

void main() {
  setUp(NotificationNavigator.resetDebounce);

  group('formatNotificationTime', () {
    final now = DateTime.utc(2026, 10, 30, 2, 0, 0);
    String fmt(Duration ago) => formatNotificationTime(now.subtract(ago), now: now);

    test('just created -> Just now', () => expect(fmt(Duration.zero), 'Just now'));
    test('59s -> Just now', () => expect(fmt(const Duration(seconds: 59)), 'Just now'));
    test('1 minute -> 1 min ago', () => expect(fmt(const Duration(minutes: 1)), '1 min ago'));
    test('30 minutes -> 30 mins ago', () => expect(fmt(const Duration(minutes: 30)), '30 mins ago'));
    test('1 hour -> 1 hour ago', () => expect(fmt(const Duration(hours: 1)), '1 hour ago'));
    test('6 hours -> 6 hours ago', () => expect(fmt(const Duration(hours: 6)), '6 hours ago'));
    test('1 day -> 1 day ago', () => expect(fmt(const Duration(days: 1)), '1 day ago'));
    test('3 days -> 3 days ago', () => expect(fmt(const Duration(days: 3)), '3 days ago'));
    test('7+ days -> a calendar date', () {
      expect(fmt(const Duration(days: 9)), matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}$')));
    });
    test('future timestamp (clock skew) -> Just now, never negative', () {
      expect(formatNotificationTime(now.add(const Duration(minutes: 3)), now: now), 'Just now');
    });
  });

  group('parseNotificationTimestamp', () {
    test('offset-aware ISO parses to the right UTC instant', () {
      final t = parseNotificationTimestamp('2026-10-30T01:57:00+06:00')!;
      expect(t.isUtc, isTrue);
      expect(t, DateTime.utc(2026, 10, 29, 19, 57));
    });
    test('Z suffix parses as UTC', () {
      expect(parseNotificationTimestamp('2026-10-29T20:07:02.948234Z'),
          DateTime.utc(2026, 10, 29, 20, 7, 2, 948, 234));
    });
    test('an offset-less string is UTC, NOT device-local (the 6-hour bug)', () {
      final t = parseNotificationTimestamp('2026-10-29T20:07:02')!;
      expect(t, DateTime.utc(2026, 10, 29, 20, 7, 2));
    });
    test('null / empty / garbage -> null, no crash', () {
      expect(parseNotificationTimestamp(null), isNull);
      expect(parseNotificationTimestamp(''), isNull);
      expect(parseNotificationTimestamp('not a date'), isNull);
    });
    test('UTC <-> local conversion keeps the same instant', () {
      final t = parseNotificationTimestamp('2026-10-29T20:00:00+00:00')!;
      expect(t.toLocal().toUtc(), t);
    });
  });

  group('the reported bug, end to end through the label', () {
    test('a just-created notification never reads "6 hours ago"', () {
      final now = DateTime.now().toUtc();
      final label = notificationTimeLabel(
          _n(createdAt: now.toIso8601String()), now: now.add(const Duration(seconds: 2)));
      expect(label, 'Just now');
      expect(label, isNot(contains('hour')));
    });
    test('label prefers created_at over a stale server "time" string', () {
      final now = DateTime.now().toUtc();
      final n = _n(createdAt: now.toIso8601String())..['time'] = '6 hours ago';
      expect(notificationTimeLabel(n, now: now), 'Just now');
    });
    test('falls back to server "time" only when created_at is absent', () {
      final n = _n()..['time'] = '5 mins ago';
      expect(notificationTimeLabel(n), '5 mins ago');
    });
  });

  group('NotificationTimeLabel recalculates', () {
    testWidgets('on refresh (clock tick) the label advances', (t) async {
      final created = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: NotificationTimeLabel(_n(createdAt: created.toIso8601String())))));
      expect(find.text('Just now'), findsOneWidget);
      // Simulate a refresh happening ~2 minutes later.
      NotificationClock.instance.value = DateTime.now().add(const Duration(minutes: 2));
      await t.pump();
      expect(find.text('2 mins ago'), findsOneWidget);
    });

    testWidgets('on app foreground return', (t) async {
      final created = DateTime.now().toUtc().subtract(const Duration(minutes: 30, seconds: 5));
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: NotificationTimeLabel(_n(createdAt: created.toIso8601String())))));
      NotificationClock.instance.value = DateTime(2000); // stale clock
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('30 mins ago'), findsOneWidget);
    });
  });

  group('NotificationNavigator.resolve', () {
    test('a valid backend route navigates', () {
      expect(NotificationNavigator.resolve(_n(navigation: _nav('/doctor/appointments'))),
          (NotificationTapOutcome.navigated, '/doctor/appointments'));
    });
    test('unavailable target -> unavailable (no navigation)', () {
      expect(NotificationNavigator.resolve(_n(navigation: _nav(null, available: false))).$1,
          NotificationTapOutcome.unavailable);
    });
    test('no navigation metadata / unknown type -> noDestination, no crash', () {
      expect(NotificationNavigator.resolve(_n()).$1, NotificationTapOutcome.noDestination);
      expect(NotificationNavigator.resolve({'navigation': 'garbage'}).$1,
          NotificationTapOutcome.noDestination);
    });
    test('routes outside the app sections are refused', () {
      for (final bad in [
        'https://evil.example', '/login', '/admin/../login', '//evil', 'admin',
        '/community/post/:postId', '', '/farmerx',
      ]) {
        expect(NotificationNavigator.isAllowedRoute(bad), isFalse, reason: bad);
      }
    });
  });

  group('tap navigation (real GoRouter)', () {
    // Every destination a notification can open — see the matrix doc.
    const destinations = [
      '/farmer/find-vet/consultations', '/farmer/find-vet/chats',
      '/farmer/cost-management/loans', '/farmer/feed-management/marketplace',
      '/farmer/pharmacy', '/doctor/appointments', '/doctor/messenger',
      '/doctor/earnings', '/doctor/followups', '/pharmacy/orders',
      '/delivery/orders', '/delivery/earnings', '/research/papers',
      '/admin/approvals', '/admin/cashouts/pending', '/admin/delivery',
      '/admin/payroll', '/community/post/abc', '/subscription',
    ];

    Future<GoRouter> pumpList(WidgetTester t, List<Map<String, dynamic>> items,
        {bool push = false}) async {
      final router = GoRouter(initialLocation: '/list', routes: [
        GoRoute(
          path: '/list',
          builder: (_, __) => Scaffold(
            body: ListView(children: [
              for (final n in items)
                Builder(builder: (ctx) => NotificationTile(
                      key: Key('tile-${n['id']}'),
                      notification: n,
                      onTap: () => NotificationNavigator.open(ctx, n, push: push),
                    )),
            ]),
          ),
        ),
        for (final d in destinations)
          GoRoute(path: d, builder: (_, __) => Scaffold(body: Text('DEST $d'))),
      ]);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      return router;
    }

    for (final d in destinations) {
      testWidgets('tap -> $d', (t) async {
        final router = await pumpList(t, [_n(id: 'a', navigation: _nav(d))]);
        await t.tap(find.byKey(const Key('tile-a')));
        await t.pumpAndSettle();
        expect(router.routerDelegate.currentConfiguration.uri.path, d);
        expect(find.text('DEST $d'), findsOneWidget);
      });
    }

    testWidgets('double tap navigates only once', (t) async {
      final router = await pumpList(t, [_n(id: 'a', navigation: _nav('/doctor/appointments'))],
          push: true);
      await t.tap(find.byKey(const Key('tile-a')));
      await t.tap(find.byKey(const Key('tile-a')), warnIfMissed: false);
      await t.pumpAndSettle();
      // One push on top of /list, so a single pop returns to the list.
      router.pop();
      await t.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/list');
    });

    testWidgets('back from the destination returns to the list (push mode)', (t) async {
      final router = await pumpList(t, [_n(id: 'a', navigation: _nav('/doctor/messenger'))],
          push: true);
      await t.tap(find.byKey(const Key('tile-a')));
      await t.pumpAndSettle();
      expect(find.text('DEST /doctor/messenger'), findsOneWidget);
      router.pop();
      await t.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/list');
    });

    testWidgets('deleted/inaccessible target shows "no longer available"', (t) async {
      final router = await pumpList(t, [_n(id: 'a', navigation: _nav(null, available: false))]);
      await t.tap(find.byKey(const Key('tile-a')));
      await t.pumpAndSettle();
      expect(find.text('This item is no longer available.'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/list');
    });

    testWidgets('no destination keeps the user here and shows the full text', (t) async {
      final router = await pumpList(t, [_n(id: 'a', body: 'Full message text')]);
      await t.tap(find.byKey(const Key('tile-a')));
      await t.pumpAndSettle();
      expect(find.text('Full message text'), findsWidgets);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/list');
    });
  });

  group('every notification surface uses the shared components', () {
    // A per-row `x['time']` here is exactly what rendered the server's frozen,
    // 6-hours-off label; each surface must go through the shared widgets.
    const surfaces = {
      'lib/features/farmer/presentation/screens/farmer_dashboard_screen.dart': 'showNotificationCenter',
      'lib/features/farmer/presentation/screens/feed_management_screen.dart': 'showNotificationCenter',
      'lib/features/doctor/presentation/screens/doctor_dashboard_screen.dart': 'showNotificationCenter',
      'lib/features/community/presentation/screens/community_notifications_screen.dart': 'NotificationNavigator.open',
      'lib/features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart': 'NotificationBellButton',
      'lib/features/delivery/presentation/screens/delivery_dashboard_screen.dart': 'NotificationBellButton',
      'lib/features/research/presentation/widgets/research_scaffold.dart': 'NotificationBellButton',
      'lib/features/admin/presentation/widgets/admin_scaffold.dart': 'NotificationBellButton',
      'lib/core/network/realtime_toast.dart': 'NotificationNavigator',
    };
    surfaces.forEach((path, marker) {
      test('$path uses $marker and never renders a raw time string', () {
        final src = File(path).readAsStringSync();
        expect(src, contains(marker));
        expect(src, isNot(contains("x['time']")));
        expect(src, isNot(contains("item['time']")));
        expect(src, isNot(contains("n['time']")));
      });
    });
  });
}
