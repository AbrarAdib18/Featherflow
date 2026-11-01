// Renders the new Feed Inventory Owner + Feed Marketplace Admin chat screens
// (inside a minimal GoRouter/MaterialApp) and asserts they build without
// throwing. With no session, the API calls in initState fail and the screens
// fall back to their error/retry state — that path must not crash, matching
// admin_screens_smoke_test.dart's convention.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/admin/presentation/screens/admin_feed_chats_screen.dart';
import 'package:featherflow/features/feed_owner/presentation/screens/feed_owner_home_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (_, __) => screen),
      GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('FeedOwnerHomeScreen builds without throwing', (t) async {
    await _pump(t, const FeedOwnerHomeScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Feed Inventory Owner'), findsWidgets);
  });

  testWidgets('AdminFeedChatsScreen builds without throwing', (t) async {
    await _pump(t, const AdminFeedChatsScreen());
    expect(t.takeException(), isNull);
    expect(find.text('Feed Owner Chats'), findsWidgets);
  });
}
