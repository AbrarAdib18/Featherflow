// F-003 regression (Flutter): rider route + ETA states.
// Route display, ETA, error states (config error / unavailable / no route),
// retry, missing location and the manual-address fallback — plus the mapping
// from the API's error codes to those states.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/delivery/data/models/delivery_order.dart';
import 'package:featherflow/features/delivery/data/models/route_info.dart';
import 'package:featherflow/features/delivery/presentation/widgets/route_summary_card.dart';

DeliveryOrder _order({double? lat = 23.8, double? lng = 90.4, String pickup = 'Warehouse', String drop = 'Village Road 5'}) =>
    DeliveryOrder(
      id: 'O1',
      pickupAddress: pickup,
      dropAddress: drop,
      pickupLat: lat,
      pickupLng: lng,
      dropLat: lat,
      dropLng: lng,
      customerName: 'Farmer',
      customerPhone: '017',
      distanceKm: 2.0,
      type: OrderType.regular,
      status: OrderStatus.onTheWay,
      items: const [],
      earning: 60,
      createdAt: DateTime(2026, 1, 1),
    );

const _info = RouteInfo(polyline: '_p~iF~ps|U', distanceKm: 5.26, durationMin: 20, provider: 'google_routes');

Future<void> _pump(WidgetTester t, DeliveryOrder order, RouteLoader loader,
    {VoidCallback? onOpen, ValueChanged<RouteInfo>? onRoute}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: RouteSummaryCard(
            order: order, loader: loader, onOpenMaps: onOpen ?? () {}, onRoute: onRoute),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteSummaryCard', () {
    testWidgets('route available: distance, ETA, and the route is handed to the map', (t) async {
      RouteInfo? drawn;
      await _pump(t, _order(), (_) async => _info, onRoute: (i) => drawn = i);
      expect(find.text('5.3 km'), findsOneWidget);
      expect(find.text('ETA ~20 min'), findsOneWidget);
      expect(find.byKey(const Key('routeError')), findsNothing);
      expect(find.text('Open in Google Maps'), findsOneWidget);
      expect(drawn?.polyline, _info.polyline);
    });

    testWidgets('shows a loading state while the route is fetched', (t) async {
      final gate = Future<RouteInfo>.delayed(const Duration(seconds: 1), () => _info);
      await _pump(t, _order(), (_) => gate);
      expect(find.byKey(const Key('routeLoading')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('routeLoading')), findsNothing);
      expect(find.text('ETA ~20 min'), findsOneWidget);
    });

    testWidgets('route unavailable: error + labelled estimate + Retry; retry recovers', (t) async {
      var calls = 0;
      await _pump(t, _order(), (_) async {
        calls++;
        if (calls == 1) {
          throw const RouteLoadException(RouteFailure.unreachable, 'Could not reach the routing service.');
        }
        return _info;
      });
      expect(find.byKey(const Key('routeErrorTitle_unreachable')), findsOneWidget);
      expect(find.text('Route unavailable'), findsOneWidget);
      expect(find.text('Est. ~6 min'), findsOneWidget, reason: 'straight-line estimate is labelled Est.');
      expect(find.byKey(const Key('routeRetry')), findsOneWidget);
      await t.tap(find.byKey(const Key('routeRetry')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(find.byKey(const Key('routeError')), findsNothing);
      expect(find.text('ETA ~20 min'), findsOneWidget);
    });

    testWidgets('API configuration error is distinct from "unavailable"', (t) async {
      await _pump(t, _order(), (_) async {
        throw const RouteLoadException(RouteFailure.configuration, 'not configured');
      });
      expect(find.byKey(const Key('routeErrorTitle_configuration')), findsOneWidget);
      expect(find.text('Route service configuration error'), findsOneWidget);
      expect(find.textContaining('tell an admin'), findsOneWidget);
      expect(find.byKey(const Key('routeRetry')), findsOneWidget);
    });

    testWidgets('no drivable route shows "No route found"', (t) async {
      await _pump(t, _order(), (_) async {
        throw const RouteLoadException(RouteFailure.noRoute, 'none');
      });
      expect(find.text('No route found'), findsOneWidget);
    });

    testWidgets('no coordinates but addresses: routed by address, not reported as missing', (t) async {
      var calls = 0;
      await _pump(t, _order(lat: null, lng: null), (_) async {
        calls++;
        return _info;
      });
      expect(calls, 1);
      expect(find.byKey(const Key('routeErrorTitle_locationMissing')), findsNothing,
          reason: 'addresses exist, so this is not "missing" - routing happens by address');
    });

    testWidgets('no coordinates AND no addresses: Location missing, no Retry, no provider call', (t) async {
      var calls = 0;
      await _pump(t, _order(lat: null, lng: null, pickup: ' ', drop: ''), (_) async {
        calls++;
        return _info;
      });
      expect(calls, 0);
      expect(find.byKey(const Key('routeErrorTitle_locationMissing')), findsOneWidget);
      expect(find.text('Location missing'), findsOneWidget);
      expect(find.byKey(const Key('routeRetry')), findsNothing);
    });

    testWidgets('manual address fallback: addresses listed and "Navigate by address" works', (t) async {
      var opened = 0;
      await _pump(t, _order(), (_) async {
        throw const RouteLoadException(RouteFailure.timeout, 'slow');
      }, onOpen: () => opened++);
      expect(find.text('Pickup: Warehouse'), findsOneWidget);
      expect(find.text('Drop: Village Road 5'), findsOneWidget);
      await t.tap(find.byKey(const Key('routeOpenMaps')));
      expect(opened, 1);
      expect(find.text('Navigate by address'), findsOneWidget);
    });
  });

  group('loadRouteInfo maps API errors to route states', () {
    Future<void> expectFailure(WidgetTester t, int status, Map<String, Object?> body, RouteFailure want) async {
      SharedPreferences.setMockInitialValues({});
      await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
            accessToken: 'a', refreshToken: 'r',
            user: AuthUser(
              id: 'u1', email: 'u@test', fullName: 'Rider', roles: const ['farmer'],
              accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
              dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
            ),
          )));
      final client = MockClient((_) async => _json(body, status));
      await http.runWithClient(() async {
        await t.runAsync(() async {
          try {
            await loadRouteInfo('O1');
            fail('expected a RouteLoadException');
          } on RouteLoadException catch (e) {
            expect(e.failure, want);
          }
        });
      }, () => client);
    }

    testWidgets('503 routing_configuration_error -> configuration', (t) async =>
        expectFailure(t, 503, {'detail': 'x', 'code': 'routing_configuration_error'}, RouteFailure.configuration));
    testWidgets('503 routing_not_configured -> configuration', (t) async =>
        expectFailure(t, 503, {'detail': 'x', 'code': 'routing_not_configured'}, RouteFailure.configuration));
    testWidgets('503 routing_quota_exceeded -> quota', (t) async =>
        expectFailure(t, 503, {'detail': 'x', 'code': 'routing_quota_exceeded'}, RouteFailure.quota));
    testWidgets('502 routing_unreachable -> unreachable', (t) async =>
        expectFailure(t, 502, {'detail': 'x', 'code': 'routing_unreachable'}, RouteFailure.unreachable));
    testWidgets('504 routing_timeout -> timeout', (t) async =>
        expectFailure(t, 504, {'detail': 'x', 'code': 'routing_timeout'}, RouteFailure.timeout));
    testWidgets('422 no_route -> noRoute', (t) async =>
        expectFailure(t, 422, {'detail': 'x', 'code': 'no_route'}, RouteFailure.noRoute));
    testWidgets('422 location_missing -> locationMissing', (t) async =>
        expectFailure(t, 422, {'detail': 'x', 'code': 'location_missing'}, RouteFailure.locationMissing));
    testWidgets('success parses polyline, distance, ETA', (t) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((_) async => _json(
          {'polyline': 'abc', 'distance_km': 5.26, 'duration_min': 20, 'provider': 'google_routes'}, 200));
      await http.runWithClient(() async {
        await t.runAsync(() async {
          final r = await loadRouteInfo('O1');
          expect(r.durationMin, 20);
          expect(r.distanceKm, 5.26);
        });
      }, () => client);
    });
  });
}
