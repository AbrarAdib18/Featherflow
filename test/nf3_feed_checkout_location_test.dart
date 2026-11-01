// NF-3: the farmer feed checkout must capture a valid delivery location before an
// order can be placed, show validation errors, and send the coordinates.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/location/delivery_location.dart';
import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_feed_marketplace_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _product = {
  'id': 'p1', 'company_id': 'c1', 'company_name': 'Acme Feeds', 'product_name': 'Layer Mash',
  'feed_type': 'layer', 'bird_type': 'layer', 'unit': 'bag', 'price': 1000, 'stock_quantity': 50,
  'min_order_quantity': 1, 'in_stock': true,
};

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
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openCheckout(WidgetTester t, LocationFetcher fetcher) async {
  await _signIn(t);
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: FarmerFeedMarketplaceScreen(locationFetcher: fetcher)));
  await _settle(t);
  await t.tap(find.text('Add to cart'));
  await _settle(t);
  await t.tap(find.textContaining('Cart'));
  await _settle(t);
  await t.tap(find.text('Proceed to checkout'));
  await _settle(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> posted;
  late MockClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    posted = [];
    client = MockClient((req) async {
      if (req.method == 'POST') {
        posted.add(jsonDecode(req.body) as Map<String, dynamic>);
        return _json({'id': 'FD-1', 'latitude': posted.last['latitude'], 'longitude': posted.last['longitude']}, 201);
      }
      if (req.url.path.contains('orders')) return _json({'results': []});
      return _json({'results': [_product]});
    });
  });

  Future<void> run(WidgetTester t, Future<void> Function() body) =>
      http.runWithClient(() async => body(), () => client);

  testWidgets('Place order stays disabled and no request is sent until a location is set', (t) async {
    await run(t, () async {
      await _openCheckout(t, () async => throw const LocationUnavailable('denied'));
      final place = find.byKey(const Key('placeOrderButton'));
      expect(place, findsOneWidget);
      expect(t.widget<ElevatedButton>(place).onPressed, isNull);
      expect(find.byKey(const Key('locationSet')), findsNothing);
      expect(posted, isEmpty);
    });
  });

  testWidgets('invalid manual coordinates show an error and keep the button disabled', (t) async {
    await run(t, () async {
      await _openCheckout(t, () async => throw const LocationUnavailable('denied'));
      await t.tap(find.byKey(const Key('manualLocationToggle')));
      await _settle(t);
      await t.enterText(find.byKey(const Key('latField')), '95');
      await t.enterText(find.byKey(const Key('lngField')), '90');
      await _settle(t);
      expect(find.byKey(const Key('locationError')), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const Key('placeOrderButton'))).onPressed, isNull);

      await t.enterText(find.byKey(const Key('latField')), '51.5');
      await t.enterText(find.byKey(const Key('lngField')), '-0.12');
      await _settle(t);
      expect(find.textContaining('outside the Bangladesh'), findsOneWidget);
      expect(posted, isEmpty);
    });
  });

  testWidgets('GPS denied falls back to manual entry with a message', (t) async {
    await run(t, () async {
      await _openCheckout(t, () async => throw const LocationUnavailable('Location permission was denied.'));
      await t.tap(find.byKey(const Key('useLocationButton')));
      await _settle(t);
      expect(find.text('Location permission was denied.'), findsOneWidget);
      expect(find.byKey(const Key('latField')), findsOneWidget);
    });
  });

  testWidgets('a valid location is shown in the summary and sent with the order', (t) async {
    await run(t, () async {
      await _openCheckout(t, () async => const DeliveryLocation(23.8103, 90.4125));
      await t.tap(find.byKey(const Key('useLocationButton')));
      await _settle(t);
      expect(find.byKey(const Key('locationSet')), findsOneWidget);
      expect(find.byKey(const Key('summaryLocation')), findsOneWidget);
      expect(find.textContaining('23.81030, 90.41250'), findsWidgets);

      await t.enterText(find.widgetWithText(TextField, 'Delivery address *'), 'Village Road 5');
      await t.ensureVisible(find.byKey(const Key('placeOrderButton')));
      await t.tap(find.byKey(const Key('placeOrderButton')));
      await _settle(t);
      expect(posted, hasLength(1));
      expect(posted.single['latitude'], 23.8103);
      expect(posted.single['longitude'], 90.4125);
      expect(posted.single['delivery_address'], contains('Village Road 5'));
    });
  });

  testWidgets('a server-side location rejection is shown to the farmer', (t) async {
    client = MockClient((req) async {
      if (req.method == 'POST') {
        return _json({'detail': 'Delivery location is outside the service area.', 'code': 'delivery_location_outside_service_area'}, 400);
      }
      if (req.url.path.contains('orders')) return _json({'results': []});
      return _json({'results': [_product]});
    });
    await run(t, () async {
      await _openCheckout(t, () async => const DeliveryLocation(23.8, 90.4));
      await t.tap(find.byKey(const Key('useLocationButton')));
      await _settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Delivery address *'), 'Village Road 5');
      await t.ensureVisible(find.byKey(const Key('placeOrderButton')));
      await t.tap(find.byKey(const Key('placeOrderButton')));
      await _settle(t);
      expect(find.textContaining('outside the service area'), findsWidgets);
    });
  });
}
