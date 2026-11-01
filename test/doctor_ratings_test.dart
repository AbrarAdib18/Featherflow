// Doctor ratings shown from real data only — see DOCTOR_RATINGS_FIX.md.
//
// The Ratings tab's headline used to read the stored profile rating, so it
// showed "0.0" above 7 real reviews; the session also started from a demo
// profile (4.7 from 128 ratings). These tests load real API payloads into
// DoctorSession and check the dashboard, profile and Ratings tab agree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_dashboard_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_earnings_screen.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_profile_screen.dart';

Map<String, dynamic> _rating(String id, num stars, {String? review}) => {
      'id': id,
      'farmer_name': 'Farmer $id',
      'rating': stars,
      'review': review,
      'date': '2026-10-0${id}T10:00:00Z',
    };

void _loadDashboard({required double rating, required int count}) =>
    DoctorSession.instance.debugLoadDashboardPayload({
      'profile': {
        'id': 'd1',
        'name': 'Dr. Real',
        'specialty': 'Poultry',
        'rating': rating,
        'total_ratings': count,
      },
      'summary': {'rating': rating, 'total_ratings': count},
    });

Future<void> _pump(WidgetTester t, Widget screen) async {
  // Same narrow filter as doctor_dashboard_profile_test.dart: the test font
  // makes unrelated rows overflow by a few pixels.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  await t.binding.setSurfaceSize(const Size(1000, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: screen));
  await t.pump(const Duration(milliseconds: 100));
}

Future<void> _openRatingsTab(WidgetTester t) async {
  await t.tap(find.widgetWithText(Tab, 'Ratings'));
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Ratings tab', () {
    testWidgets('average, stars and count come from the real ratings list',
        (t) async {
      // The stored profile copy says 0 — the summary must not use it.
      _loadDashboard(rating: 0, count: 0);
      DoctorSession.instance.debugLoadEarningsPayload({
        'earnings': [],
        'ratings': [
          _rating('1', 3),
          _rating('2', 4, review: 'Good advice'),
          _rating('3', 5),
        ],
      });
      await _pump(t, const DoctorEarningsScreen());
      await _openRatingsTab(t);

      expect(t.widget<Text>(find.byKey(const Key('ratingAverage'))).data, '4.0');
      expect(t.widget<Text>(find.byKey(const Key('ratingCount'))).data, '3 ratings');
      final summary =
          find.ancestor(of: find.byKey(const Key('ratingAverage')), matching: find.byType(Column)).first;
      expect(find.descendant(of: summary, matching: find.byIcon(Icons.star)), findsNWidgets(4));
      expect(find.text('Good advice'), findsOneWidget);
      expect(find.byKey(const Key('ratingsEmpty')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('half star and singular count', (t) async {
      DoctorSession.instance.debugLoadEarningsPayload({
        'earnings': [],
        'ratings': [_rating('1', 4), _rating('2', 5)],
      });
      await _pump(t, const DoctorEarningsScreen());
      await _openRatingsTab(t);
      expect(t.widget<Text>(find.byKey(const Key('ratingAverage'))).data, '4.5');
      final summary =
          find.ancestor(of: find.byKey(const Key('ratingAverage')), matching: find.byType(Column)).first;
      expect(find.descendant(of: summary, matching: find.byIcon(Icons.star_half)), findsOneWidget);
      expect(find.descendant(of: summary, matching: find.byIcon(Icons.star)), findsNWidgets(4));

      DoctorSession.instance.debugLoadEarningsPayload({
        'earnings': [],
        'ratings': [_rating('1', 5)],
      });
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('ratingCount'))).data, '1 rating');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('no ratings shows an empty state, not 0.0', (t) async {
      DoctorSession.instance.debugLoadEarningsPayload({'earnings': [], 'ratings': []});
      await _pump(t, const DoctorEarningsScreen());
      await _openRatingsTab(t);
      expect(t.widget<Text>(find.byKey(const Key('ratingAverage'))).data, '–');
      expect(t.widget<Text>(find.byKey(const Key('ratingCount'))).data, 'No ratings yet');
      expect(find.byKey(const Key('ratingsEmpty')), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Profile and dashboard', () {
    testWidgets('profile shows the live average to one decimal and the count',
        (t) async {
      _loadDashboard(rating: 4.14, count: 7);
      await _pump(t, const DoctorProfileScreen());
      expect(t.widget<Text>(find.byKey(const Key('profileRating'))).data, '4.1 (7)');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('profile with no ratings says so', (t) async {
      _loadDashboard(rating: 0, count: 0);
      await _pump(t, const DoctorProfileScreen());
      expect(t.widget<Text>(find.byKey(const Key('profileRating'))).data, 'No ratings yet');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('dashboard shows the live average beside the name', (t) async {
      _loadDashboard(rating: 4.14, count: 7);
      await _pump(t, const DoctorDashboardScreen());
      expect(find.text('4.1'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
