// F-005 regression (Flutter): delivery arrival + proof review lifecycle.
//
// Rider (DeliveryDetailScreen): Mark Arrived -> pick/preview photo -> multipart
// upload (with retry) -> "proof under review" (the rider can never mark
// delivered) -> rejection banner + resubmission.
// Admin (AdminDeliveryProofsScreen): review queue, approve, reject dialog with
// a required reason, rejected/approved views.
// Farmer: feed/pharmacy order cards show Arrived / Proof under review.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/admin/data/models/admin_role.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_delivery_proofs_screen.dart';
import 'package:featherflow/features/delivery/data/models/delivery_order.dart';
import 'package:featherflow/features/delivery/data/services/delivery_session.dart';
import 'package:featherflow/features/delivery/presentation/screens/delivery_detail_screen.dart';
import 'package:featherflow/features/farmer/presentation/screens/farmer_feed_marketplace_screen.dart';

final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='));

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

DeliveryOrder _order(OrderStatus status, {String? reason}) => DeliveryOrder(
      id: 'ORD1',
      pickupAddress: 'Warehouse',
      dropAddress: 'Farm',
      customerName: 'Farmer',
      customerPhone: '01710000000',
      distanceKm: 2.0,
      type: OrderType.regular,
      status: status,
      items: const [],
      earning: 60,
      createdAt: DateTime(2026, 1, 1),
      proofRejectionReason: reason,
    );

Map<String, Object?> _orderJson(String status, {String? reason}) => {
      'id': 'ORD1', 'pickup_address': 'Warehouse', 'delivery_address': 'Farm',
      'customer_name': 'Farmer', 'customer_phone': '01710000000', 'distance_km': 2,
      'order_type': 'regular', 'status': status, 'items': [], 'earning': 60,
      'created_at': '2026-01-01T00:00:00Z', 'proof_rejection_reason': reason,
    };

Future<void> _signIn(WidgetTester t, List<String> roles) async {
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'a', refreshToken: 'r',
        user: AuthUser(
          id: 'u1', email: 'u@test', fullName: 'Tester', roles: roles,
          accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
        ),
      )));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // Created outside the fake-async zone so its (non-delivery-role) listener
  // never starts a polling timer in these tests.
  final session = DeliverySession.instance;

  group('Rider: arrival + proof submission', () {
    Future<void> run(
      WidgetTester t,
      OrderStatus status,
      http.Response Function(http.Request) handler,
      Future<void> Function(DeliveryDetailScreen screen) body, {
      String? reason,
      Future<PickedProofPhoto?> Function()? picker,
    }) async {
      // A non-delivery role keeps DeliverySession from starting its poller;
      // DeliveryApiService only needs *a* session for the bearer token.
      await _signIn(t, const ['farmer']);
      session.debugSetActiveOrders([_order(status, reason: reason)]);
      final client = MockClient((req) async => handler(req));
      await http.runWithClient(() async {
        final screen = DeliveryDetailScreen(
          order: _order(status, reason: reason),
          photoPicker: picker ?? () async => (bytes: _png, name: 'proof.png'),
        );
        await t.pumpWidget(MaterialApp(home: screen));
        await t.pump(const Duration(milliseconds: 100));
        await body(screen);
        await t.pumpWidget(const SizedBox());
      }, () => client);
    }

    testWidgets('out for delivery shows Mark Arrived (never Mark Delivered) and PATCHes arrived',
        (t) async {
      String? sentStatus;
      await run(t, OrderStatus.onTheWay, (req) {
        if (req.method == 'PATCH' && req.url.path.endsWith('/status/')) {
          sentStatus = jsonDecode(req.body)['status'] as String;
          return _json(_orderJson('arrived'));
        }
        return _json({'results': [], 'records': []});
      }, (_) async {
        expect(find.text('Mark Delivered'), findsNothing);
        await t.ensureVisible(find.widgetWithText(ElevatedButton, 'Mark Arrived'));
        await t.tap(find.widgetWithText(ElevatedButton, 'Mark Arrived'));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(sentStatus, 'arrived');
        expect(find.byKey(const Key('submitProofButton')), findsOneWidget);
        expect(find.byKey(const Key('proofPickButton')), findsOneWidget);
      });
    });

    testWidgets('arrived: submit is disabled until a photo is picked; preview is shown',
        (t) async {
      await run(t, OrderStatus.arrived, (_) => _json({}), (_) async {
        var submit = t.widget<ElevatedButton>(find.byKey(const Key('submitProofButton')));
        expect(submit.onPressed, isNull);
        await t.ensureVisible(find.byKey(const Key('proofPickButton')));
        await t.tap(find.byKey(const Key('proofPickButton')));
        await t.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const Key('proofPreview')), findsOneWidget);
        submit = t.widget<ElevatedButton>(find.byKey(const Key('submitProofButton')));
        expect(submit.onPressed, isNotNull);
      });
    });

    testWidgets('submitting uploads multipart and lands on "proof under review"', (t) async {
      http.Request? upload;
      await run(t, OrderStatus.arrived, (req) {
        if (req.url.path.endsWith('/proof/')) {
          upload = req;
          return _json({'order': _orderJson('proof_submitted'), 'proof': {'id': 'P1'}}, 201);
        }
        return _json({'results': [], 'records': []});
      }, (_) async {
        await t.ensureVisible(find.byKey(const Key('proofPickButton')));
        await t.tap(find.byKey(const Key('proofPickButton')));
        await t.pump(const Duration(milliseconds: 200));
        await t.ensureVisible(find.byKey(const Key('submitProofButton')));
        await t.tap(find.byKey(const Key('submitProofButton')));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(upload, isNotNull);
        expect(upload!.headers['content-type'], startsWith('multipart/form-data'));
        expect(latin1.decode(upload!.bodyBytes), contains('name="file"'));
        expect(find.byKey(const Key('proofAwaitingReview')), findsOneWidget);
        expect(find.byKey(const Key('proofUnderReviewBanner')), findsOneWidget);
        expect(find.text('Mark Delivered'), findsNothing);
        expect(find.byKey(const Key('submitProofButton')), findsNothing);
      });
    });

    testWidgets('upload failure shows the error and Try again retries', (t) async {
      var calls = 0;
      await run(t, OrderStatus.arrived, (req) {
        if (req.url.path.endsWith('/proof/')) {
          calls++;
          if (calls == 1) return _json({'detail': 'Upload failed, try again.'}, 400);
          return _json({'order': _orderJson('proof_submitted'), 'proof': {'id': 'P1'}}, 201);
        }
        return _json({'results': [], 'records': []});
      }, (_) async {
        await t.ensureVisible(find.byKey(const Key('proofPickButton')));
        await t.tap(find.byKey(const Key('proofPickButton')));
        await t.pump(const Duration(milliseconds: 200));
        await t.ensureVisible(find.byKey(const Key('submitProofButton')));
        await t.tap(find.byKey(const Key('submitProofButton')));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Upload failed, try again.'), findsOneWidget);
        expect(find.byKey(const Key('proofPreview')), findsOneWidget,
            reason: 'the chosen photo is kept so the rider can retry');
        await t.ensureVisible(find.byKey(const Key('proofRetryButton')));
        await t.tap(find.byKey(const Key('proofRetryButton')));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(calls, 2);
        expect(find.byKey(const Key('proofAwaitingReview')), findsOneWidget);
      });
    });

    testWidgets('rejected proof shows the admin reason and allows resubmission', (t) async {
      await run(t, OrderStatus.proofRejected, (req) {
        if (req.url.path.endsWith('/proof/')) {
          return _json({'order': _orderJson('proof_submitted'), 'proof': {'id': 'P2'}}, 201);
        }
        return _json({'results': [], 'records': []});
      }, (_) async {
        expect(find.byKey(const Key('proofRejectedBanner')), findsOneWidget);
        expect(find.text('Photo is blurry'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Resubmit Delivery Proof'), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('proofPickButton')));
        await t.tap(find.byKey(const Key('proofPickButton')));
        await t.pump(const Duration(milliseconds: 200));
        await t.ensureVisible(find.byKey(const Key('submitProofButton')));
        await t.tap(find.byKey(const Key('submitProofButton')));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('proofAwaitingReview')), findsOneWidget);
      }, reason: 'Photo is blurry');
    });
  });

  group('Admin: proof review queue', () {
    Map<String, Object?> proof(String id, String status, {String reason = ''}) => {
          'id': id, 'attempt': 1, 'status': status, 'url': '', 'note': '',
          'review_reason': reason, 'order_id': 'o-$id', 'order_number': 'FEED-$id',
          'order_type': 'feed', 'customer': 'Farmer Fatema', 'destination': 'Savar',
          'rider': 'Rider Rafi', 'order_status': 'proof_submitted',
        };

    Future<void> open(
      WidgetTester t,
      http.Response Function(http.Request) handler,
      Future<void> Function() body,
    ) async {
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/admin-panel/me/')) {
          return _json({
            'name': 'Admin', 'email': 'a@test', 'role': 'admin_delivery', 'tier': 3,
            'permissions': {'delivery': ['view', 'approve', 'reject']},
          });
        }
        return handler(req);
      });
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({});
        await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
              accessToken: 'a', refreshToken: 'r',
              user: AuthUser(
                id: 'admin1', email: 'a@test', fullName: 'Admin', roles: const ['admin_delivery'],
                accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
                dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
              ),
            )));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        final router = GoRouter(initialLocation: '/admin/delivery-proofs', routes: [
          GoRoute(path: '/admin/delivery-proofs', builder: (_, __) => const AdminDeliveryProofsScreen()),
          GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
        ]);
        t.view.physicalSize = const Size(1200, 1800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp.router(routerConfig: router));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(seconds: 1));
        await body();
        await t.pumpWidget(const SizedBox());
      }, () => client);
    }

    testWidgets('pending proof is listed with order, rider and Approve/Reject', (t) async {
      await open(t, (_) => _json({'results': [proof('p1', 'submitted')]}), () async {
        expect(find.text('Order FEED-p1  ·  attempt 1'), findsOneWidget);
        expect(find.textContaining('Rider Rafi'), findsOneWidget);
        expect(find.byKey(const Key('approveButton_p1')), findsOneWidget);
        expect(find.byKey(const Key('rejectButton_p1')), findsOneWidget);
      });
    });

    testWidgets('approve confirms, POSTs approve, then reloads the queue', (t) async {
      var approved = false;
      await open(t, (req) {
        if (req.url.path.endsWith('/p1/approve/')) {
          approved = true;
          return _json(proof('p1', 'approved'));
        }
        return _json({'results': approved ? [] : [proof('p1', 'submitted')]});
      }, () async {
        await t.tap(find.byKey(const Key('approveButton_p1')));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const Key('confirmApproveButton')));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        expect(approved, isTrue);
        expect(find.byKey(const Key('proofsEmpty')), findsOneWidget);
      });
    });

    testWidgets('reject requires a reason, then POSTs it', (t) async {
      String? sentReason;
      await open(t, (req) {
        if (req.url.path.endsWith('/p1/reject/')) {
          sentReason = jsonDecode(req.body)['reason'] as String;
          return _json(proof('p1', 'rejected', reason: sentReason!));
        }
        return _json({'results': [proof('p1', 'submitted')]});
      }, () async {
        await t.tap(find.byKey(const Key('rejectButton_p1')));
        await t.pump(const Duration(milliseconds: 300));
        var confirm = t.widget<FilledButton>(find.byKey(const Key('confirmRejectButton')));
        expect(confirm.onPressed, isNull, reason: 'a rejection reason is mandatory');
        await t.enterText(find.byKey(const Key('rejectReasonField')), 'Photo is blurry');
        await t.pump(const Duration(milliseconds: 100));
        confirm = t.widget<FilledButton>(find.byKey(const Key('confirmRejectButton')));
        expect(confirm.onPressed, isNotNull);
        await t.tap(find.byKey(const Key('confirmRejectButton')));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        expect(sentReason, 'Photo is blurry');
      });
    });

    testWidgets('rejected view shows the reason and no review buttons', (t) async {
      await open(t, (req) {
        final status = req.url.queryParameters['status'];
        return _json({
          'results': [
            if (status == 'rejected') proof('p9', 'rejected', reason: 'Wrong house')
            else proof('p1', 'submitted')
          ]
        });
      }, () async {
        await t.tap(find.byKey(const Key('proofFilter_rejected')));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Rejection reason: Wrong house'), findsOneWidget);
        expect(find.byKey(const Key('approveButton_p9')), findsNothing);
        expect(find.byKey(const Key('rejectButton_p9')), findsNothing);
      });
    });

    testWidgets('server error is an error state with Retry, not an empty queue', (t) async {
      var fail = true;
      await open(t, (_) => fail
          ? _json({'detail': 'Server exploded'}, 500)
          : _json({'results': [proof('p1', 'submitted')]}), () async {
        expect(find.byKey(const Key('proofsError')), findsOneWidget);
        expect(find.byKey(const Key('proofsEmpty')), findsNothing);
        fail = false;
        await t.tap(find.text('Retry'));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('approveButton_p1')), findsOneWidget);
      });
    });

    testWidgets('permissions arriving AFTER the list still reveal Approve/Reject (fresh page load race)', (t) async {
      final meGate = Completer<void>();
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/admin-panel/me/')) {
          await meGate.future;
          return _json({
            'name': 'Admin', 'email': 'a@test', 'role': 'admin_pharmacy', 'tier': 3,
            'permissions': {'pharmacy': ['view', 'approve', 'reject']},
          });
        }
        return _json({'results': [proof('p1', 'submitted')]});
      });
      await http.runWithClient(() async {
        SharedPreferences.setMockInitialValues({});
        await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
              accessToken: 'a', refreshToken: 'r',
              user: AuthUser(
                id: 'admin1', email: 'a@test', fullName: 'Admin', roles: const ['admin_pharmacy'],
                accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
                dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
              ),
            )));
        final router = GoRouter(initialLocation: '/admin/delivery-proofs', routes: [
          GoRoute(path: '/admin/delivery-proofs', builder: (_, __) => const AdminDeliveryProofsScreen()),
          GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
        ]);
        t.view.physicalSize = const Size(1200, 1800);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp.router(routerConfig: router));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('proofCard_p1')), findsOneWidget);
        meGate.complete();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('approveButton_p1')), findsOneWidget);
        expect(find.byKey(const Key('rejectButton_p1')), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      }, () => client);
    });

    test('Feed Admin fallback permissions can approve/reject feed delivery proofs', () {
      final perms = kRolePermissions[AdminRole.feedAdmin]![AdminModule.feedDelivery]!;
      expect(perms, containsAll([AdminPermission.approve, AdminPermission.reject]));
    });
  });

  group('Farmer: order status display', () {
    Map<String, Object?> feedOrder(String status) => {
          'id': 'f1', 'order_number': 'FEED-1', 'status': status, 'items': [],
          'total_amount': 100, 'payment_status': 'pending', 'delivery_address': 'Farm',
          'can_cancel': false,
          'timeline': [
            for (final s in ['created', 'confirmed', 'preparing', 'ready_for_pickup', 'assigned',
              'picked_up', 'out_for_delivery', 'arrived', 'proof_under_review', 'delivered'])
              {'step': s, 'done': false}
          ],
        };

    for (final (status, label) in [('arrived', 'ARRIVED'), ('proof_under_review', 'PROOF UNDER REVIEW')]) {
      testWidgets('feed order card shows "$label"', (t) async {
        await _signIn(t, const ['farmer']);
        final client = MockClient((req) async {
          if (req.url.path.contains('feed-catalogue/orders')) {
            return _json({'results': [feedOrder(status)]});
          }
          return _json({'results': []});
        });
        await http.runWithClient(() async {
          t.view.physicalSize = const Size(1000, 1800);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(const MaterialApp(home: FarmerFeedMarketplaceScreen(initialTab: 2)));
          await t.pump(const Duration(milliseconds: 300));
          await t.pump(const Duration(seconds: 1));
          expect(find.text(label), findsOneWidget);
          await t.pumpWidget(const SizedBox());
        }, () => client);
      });
    }
  });
}
