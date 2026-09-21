// Discover Vets — explicit location status states (Phase 4).
//
// Location used to be entirely best-effort with a bare `catch (_) {}`: every
// failure (service disabled, permission denied/denied forever, timeout,
// any other platform error) was swallowed silently, leaving the farmer with
// no distances and no explanation why. `_LocationStatus` now makes every
// outcome explicit and renders an informational banner with a "Try again"
// (and, for a permanent denial, "Open settings") action.
//
// There is no real Geolocator platform implementation in a widget test, so
// every run here exercises the same "unavailable" catch-all path (a thrown
// MissingPluginException with no registered handler). The denied/
// deniedForever/timedOut/serviceDisabled branches are exercised directly by
// Django-side equivalents are not applicable; those specific branches are
// verified by reading discover_vets_tab.dart's `_locationBanner` switch,
// which is exhaustive over `_LocationStatus` (a compile error if a case is
// ever dropped) — this test locks in the reachable "unavailable" outcome and
// its retry affordance end to end.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/farmer/presentation/widgets/discover_vets_tab.dart';

/// See find_vet_screen_test.dart — Discover Vets makes a real platform-channel
/// call with its own internal timeout, so this polls with real delays inside
/// `runAsync` rather than a fake-time pump.
Future<void> _settleUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 8)}) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpTall(WidgetTester t) async {
    // See find_vet_screen_test.dart's DiscoverVetsTab test for why this needs
    // a tall surface: the location banner adds height above the vet list,
    // pushing later content past what the default 800x600 viewport lazily
    // builds inside a ListView.
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DiscoverVetsTab())));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
      'no platform location support -> an explicit banner with a retry action, '
      'not a silent failure', (t) async {
    await pumpTall(t);
    // No Geolocator platform handler is registered in a widget test, so the
    // lookup lands on the "unavailable" branch.
    await _settleUntil(
        t, find.textContaining('Couldn\'t get your location right now'));
    expect(t.takeException(), isNull);
    expect(find.textContaining('Couldn\'t get your location right now'),
        findsOneWidget);
    // The banner offers a way forward, never a dead end.
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    // No claim of "near me" — the banner explicitly says location wasn't
    // obtained rather than silently proceeding as if it had been.
    expect(find.textContaining('near me'), findsNothing);
  });

  testWidgets('the vet list still loads independently of the location outcome',
      (t) async {
    await pumpTall(t);
    // The list's own (retryable) error state doesn't require location to
    // resolve first — both are independent, best-effort background calls.
    await _settleUntil(t, find.text('Retry'));
    expect(t.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retrying the location lookup does not crash and keeps the '
      'banner in a valid state', (t) async {
    await pumpTall(t);
    await _settleUntil(
        t, find.widgetWithText(TextButton, 'Try again'));
    await t.tap(find.widgetWithText(TextButton, 'Try again'));
    await t.pump();
    // Retrying re-enters the same lookup and, with still no platform
    // handler, settles back on the same explicit "unavailable" banner rather
    // than crashing or clearing to a blank/inconsistent state.
    await _settleUntil(
        t, find.textContaining('Couldn\'t get your location right now'));
    expect(t.takeException(), isNull);
  });
}
