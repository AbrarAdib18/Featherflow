// Renders the unified "Find Vet" feature (Discover Vets + My Consultations
// tabs, replacing the old separate Find Vet / vet-map and My Consultations
// screens) inside a minimal GoRouter and asserts the tree builds without
// throwing. With no session, the network calls in initState fail and each
// tab must fall back to its loading/error state instead of crashing —
// mirroring the existing convention in farmer_screens_smoke_test.dart.
//
// Discover Vets also makes a best-effort real platform-channel call
// (Geolocator) with its own internal timeout; on a platform with no
// registered mock handler that call can take real wall-clock time to settle
// (or to hit its own timeout) rather than resolving on a fake-time pump, so
// these tests run under `tester.runAsync` and poll with real delays instead
// of fixed fake-time pumps — the standard pattern for widgets that touch a
// real plugin channel in a widget test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/farmer/presentation/screens/find_vet_screen.dart';
import 'package:featherflow/features/farmer/presentation/widgets/discover_vets_tab.dart';
import 'package:featherflow/features/farmer/presentation/widgets/vet_booking_dialog.dart';
import 'package:featherflow/features/farmer/presentation/widgets/vet_detail_dialog.dart';

/// Pumps real time until [finder] appears (or [timeout] elapses), inside
/// `tester.runAsync` so real Futures/Timers (not just fake-clock ones) can
/// actually settle.
Future<void> _settleUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 5)}) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  });
  await tester.pump();
}

/// Unconditionally waits real time past Discover Vets' internal 3s location
/// timeout so its background `Geolocator` call's `Timer` actually fires and
/// clears before the test tears down (a screen just embedding Discover Vets,
/// with nothing distinctive yet on screen to settle on, needs this rather
/// than [_settleUntil]).
Future<void> _drainBackgroundTimers(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('FindVetScreen builds with both tabs, defaults to Discover Vets',
      (t) async {
    final router = GoRouter(
      initialLocation: '/farmer/find-vet',
      routes: [
        GoRoute(path: '/farmer/find-vet', builder: (_, __) => const FindVetScreen()),
        GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Find Vet'), findsOneWidget);
    expect(find.text('Discover Vets'), findsOneWidget);
    expect(find.text('My Consultations'), findsWidgets);
    await _drainBackgroundTimers(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('FindVetScreen can open directly on the My Consultations tab',
      (t) async {
    final router = GoRouter(
      initialLocation: '/farmer/find-vet',
      routes: [
        GoRoute(
            path: '/farmer/find-vet',
            builder: (_, __) => const FindVetScreen(initialTab: 1)),
        GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    // The embedded FarmerConsultationsScreen's own inner tab strip renders
    // (Consultations / Chats) alongside the outer Find Vet tabs.
    expect(find.text('Consultations'), findsWidgets);
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('FindVetScreen surfaces a disease-detection banner when provided',
      (t) async {
    final router = GoRouter(
      initialLocation: '/farmer/find-vet',
      routes: [
        GoRoute(
            path: '/farmer/find-vet',
            builder: (_, __) => const FindVetScreen(diseaseContext: 'Newcastle disease')),
        GoRoute(path: '/farmer', builder: (_, __) => const SizedBox()),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Newcastle disease'), findsOneWidget);
    await _drainBackgroundTimers(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('DiscoverVetsTab renders its filters without a session', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DiscoverVetsTab())));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Any mode'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('In-person'), findsOneWidget);
    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('Emergency support'), findsOneWidget);
    expect(find.text('Verified only'), findsOneWidget);
    // No session -> the discovery call fails -> a retryable error state, not
    // a crash or an infinite spinner. The list load itself is independent of
    // the (best-effort, non-blocking) location lookup.
    await _settleUntil(t, find.text('Retry'));
    expect(t.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('VetDetailDialog builds and shows a retry state without a session',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const VetDetailDialog(doctorId: 'doc-1'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Veterinarian profile'), findsOneWidget);
    await _settleUntil(t, find.text('Retry'));
    expect(t.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('VetBookingDialog builds and shows a retry state without a session',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const VetBookingDialog(doctor: {
                  'id': 'doc-1',
                  'name': 'Dr Test',
                  'mode': 'both',
                  'emergency': true,
                }),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Book Dr Test'), findsOneWidget);
    await _settleUntil(t, find.text('Retry'));
    expect(t.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });
}
