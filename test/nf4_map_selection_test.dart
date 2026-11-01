// NF-4: the rider Map tab is bound to the delivery the rider selected - never
// the first / oldest / cached active order. With several active deliveries and
// no selection it shows a chooser instead of an arbitrary map.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/delivery/data/models/delivery_order.dart';
import 'package:featherflow/features/delivery/data/services/delivery_session.dart';
import 'package:featherflow/features/delivery/presentation/screens/delivery_map_screen.dart';

// No coordinates on purpose: the route card still loads by order id, but the
// native GoogleMap view (not available in widget tests) is not built.
DeliveryOrder _order(String id, {OrderStatus status = OrderStatus.accepted}) => DeliveryOrder(
      id: id,
      pickupAddress: 'Pickup of $id',
      dropAddress: 'Drop of $id',
      customerName: 'Farmer $id',
      customerPhone: '01710000000',
      distanceKm: 2.0,
      type: OrderType.regular,
      status: status,
      items: const [],
      earning: 60,
      createdAt: DateTime(2026, 1, 1),
    );

http.Response _route() => http.Response(
    jsonEncode({'polyline': '_p~iF~ps|U', 'distance_km': 3.2, 'duration_min': 11, 'provider': 'google_routes'}), 200,
    headers: {'content-type': 'application/json'});

Future<void> _signIn(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'a', refreshToken: 'r',
        user: AuthUser(
          id: 'u1', email: 'u@test', fullName: 'Tester', roles: const ['farmer'],
          accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
        ),
      )));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final session = DeliverySession.instance;
  late List<String> routeRequests;
  late MockClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    routeRequests = [];
    client = MockClient((req) async {
      routeRequests.add(req.url.path);
      return _route();
    });
    session.debugSetActiveOrders(const []);
    session.selectOrder(null);
    session.debugSetError(null);
    session.debugSetLoading(false);
  });

  Future<void> run(WidgetTester t, Future<void> Function() body) =>
      http.runWithClient(() async => body(), () => client);

  Future<void> pumpMap(WidgetTester t) async {
    await _signIn(t);
    await t.pumpWidget(const MaterialApp(home: DeliveryMapScreen()));
    await _settle(t);
  }

  testWidgets('several active deliveries and none selected -> chooser, no route is requested', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    await run(t, () async {
      await pumpMap(t);
      expect(find.byKey(const Key('mapChooser')), findsOneWidget);
      expect(find.byKey(const Key('mapChoose_AAAA1111')), findsOneWidget);
      expect(find.byKey(const Key('mapChoose_BBBB2222')), findsOneWidget);
      expect(routeRequests, isEmpty, reason: 'must not guess a delivery to route');
    });
  });

  testWidgets('choosing the SECOND delivery routes that id, not the first', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    await run(t, () async {
      await pumpMap(t);
      await t.tap(find.byKey(const Key('mapChoose_BBBB2222')));
      await _settle(t);
      expect(session.selectedOrderId, 'BBBB2222');
      expect(routeRequests, isNotEmpty);
      expect(routeRequests.every((p) => p.contains('BBBB2222')), isTrue, reason: '$routeRequests');
      expect(find.text('Pickup of BBBB2222'), findsWidgets);
      expect(find.text('Pickup of AAAA1111'), findsNothing);
      expect(find.text('ETA ~11 min'), findsOneWidget);
    });
  });

  testWidgets('change delivery returns to the chooser and the next pick uses the new id', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    session.selectOrder('AAAA1111');
    await run(t, () async {
      await pumpMap(t);
      expect(routeRequests.single, contains('AAAA1111'));
      await t.tap(find.byKey(const Key('mapChangeDelivery')));
      await _settle(t);
      expect(find.byKey(const Key('mapChooser')), findsOneWidget);
      routeRequests.clear();
      await t.tap(find.byKey(const Key('mapChoose_BBBB2222')));
      await _settle(t);
      expect(routeRequests, isNotEmpty);
      expect(routeRequests.every((p) => p.contains('BBBB2222')), isTrue, reason: '$routeRequests');
    });
  });

  testWidgets('refresh: a selected delivery that is no longer active is dropped, not kept', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    session.selectOrder('BBBB2222');
    await run(t, () async {
      await pumpMap(t);
      expect(routeRequests.every((p) => p.contains('BBBB2222')), isTrue);
      // BBBB2222 is delivered / reassigned; a refresh leaves two others
      session.debugSetActiveOrders([_order('AAAA1111'), _order('CCCC3333')]);
      await _settle(t);
      expect(find.byKey(const Key('mapChooser')), findsOneWidget, reason: 'no stale map for BBBB2222');
      expect(find.text('Pickup of BBBB2222'), findsNothing);
    });
  });

  testWidgets('refresh keeps the selected delivery when it is still active (status changes)', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    session.selectOrder('BBBB2222');
    await run(t, () async {
      await pumpMap(t);
      session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222', status: OrderStatus.pickedUp)]);
      await _settle(t);
      expect(find.byKey(const Key('mapChooser')), findsNothing);
      expect(find.text('Picked Up'), findsWidgets);
      expect(find.text('Pickup of BBBB2222'), findsWidgets);
    });
  });

  testWidgets('exactly one active delivery is unambiguous and used automatically', (t) async {
    session.debugSetActiveOrders([_order('ONLY0001')]);
    await run(t, () async {
      await pumpMap(t);
      expect(find.byKey(const Key('mapChooser')), findsNothing);
      expect(routeRequests.single, contains('ONLY0001'));
    });
  });

  testWidgets('an explicit order passed through navigation wins over the session selection', (t) async {
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    session.selectOrder('AAAA1111');
    await run(t, () async {
      await t.pumpWidget(MaterialApp(home: DeliveryMapScreen(order: _order('BBBB2222'))));
      await _settle(t);
      expect(routeRequests.every((p) => p.contains('BBBB2222')), isTrue, reason: '$routeRequests');
    });
  });

  testWidgets('no active delivery -> "No active delivery" message, no route request', (t) async {
    await run(t, () async {
      await pumpMap(t);
      expect(find.text('No active delivery to navigate'), findsOneWidget);
      expect(routeRequests, isEmpty);
    });
  });

  testWidgets('the selection is persisted per rider and cleared with "Change delivery"', (t) async {
    await _signIn(t);
    session.debugSetActiveOrders([_order('AAAA1111'), _order('BBBB2222')]);
    await t.runAsync(() async {
      session.selectOrder('BBBB2222');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('delivery_selected_order_u1'), 'BBBB2222');
      session.selectOrder(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('delivery_selected_order_u1'), isNull);
    });
  });
}
