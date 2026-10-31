// NF-5: Research Admin "Request revision" - shown only for revision-eligible
// (Pending) submissions and only with the `reject` permission, reason required,
// current status + history visible, server refusals shown without losing the reason.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/admin/data/services/admin_session.dart';
import 'package:featherflow/features/admin/presentation/screens/admin_content_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _article(String id, String status, {String notes = ''}) => {
      'id': id, 'title': 'Paper $id', 'author': 'Dr Author', 'type': 'Research', 'status': status,
      'date': 'Oct 02, 2026', 'summary': 'summary $id', 'featured': false, 'review_notes': notes,
    };

class _Backend {
  _Backend({this.perms = const ['view', 'approve', 'reject', 'edit', 'create', 'delete']});
  final List<String> perms;
  final List<Map<String, Object?>> articles = [
    _article('pend', 'Pending'),
    _article('pub', 'Published'),
    _article('rev', 'Needs Revision', notes: 'Cite sources.'),
    _article('arch', 'Archived'),
  ];
  final patches = <Map<String, dynamic>>[];
  int historyCalls = 0;
  http.Response Function(http.Request)? patchOverride;
  http.Response Function()? historyOverride;

  http.Response handle(http.Request req) {
    final path = req.url.path;
    if (path.endsWith('/me/')) {
      return _json({'name': 'Research Admin', 'email': 'ra@test', 'role': 'admin_research', 'tier': 3,
        'permissions': {'articles': perms, 'research': perms}});
    }
    if (path.endsWith('/revision-history/')) {
      historyCalls++;
      if (historyOverride != null) return historyOverride!();
      return _json({'id': 'rev', 'title': 'Paper rev', 'status': 'Needs Revision', 'review_notes': 'Cite sources.',
        'can_request_revision': false, 'history': [
          {'id': 'h1', 'version': 1, 'note': 'Revision requested: Cite sources.', 'by': 'Research Admin', 'at': '2026-10-02T10:00:00Z', 'reason': 'Cite sources.', 'kind': 'revision_requested'},
        ]});
    }
    if (req.method == 'PATCH' && path.contains('/articles/')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      patches.add(body);
      if (patchOverride != null) return patchOverride!(req);
      final id = path.split('/').where((p) => p.isNotEmpty).last;
      final a = articles.firstWhere((x) => x['id'] == id);
      a['status'] = 'Needs Revision';
      a['review_notes'] = body['review_notes'];
      return _json(a);
    }
    if (path.endsWith('/articles/')) return _json({'results': articles});
    return _json({'results': []});
  }
}

Future<void> _open(WidgetTester t, _Backend b, Future<void> Function() body) async {
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'a', refreshToken: 'r',
        user: AuthUser(
          id: 'admin1', email: 'ra@test', fullName: 'Research Admin', roles: const ['admin_research'],
          accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
        ),
      )));
  final client = MockClient((req) async => b.handle(req));
  await http.runWithClient(() async {
    await t.runAsync(() => AdminSession.instance.refresh());
    final router = GoRouter(initialLocation: '/admin/content', routes: [
      GoRoute(path: '/admin/content', builder: (_, __) => const AdminContentScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const SizedBox()),
    ]);
    t.view.physicalSize = const Size(1200, 1800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await body();
    await t.pumpWidget(const SizedBox());
  }, () => client);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Request revision is offered only for the Pending submission', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      expect(find.byKey(const Key('revisionButton_pend')), findsOneWidget);
      expect(find.byKey(const Key('revisionButton_pub')), findsNothing, reason: 'published is not revision-eligible');
      expect(find.byKey(const Key('revisionButton_rev')), findsNothing, reason: 'already needs revision');
      expect(find.byKey(const Key('revisionButton_arch')), findsNothing);
      expect(find.byKey(const Key('revisionNotes_rev')), findsOneWidget, reason: 'the open request is visible');
      expect(find.text('Revision requested: Cite sources.'), findsOneWidget);
      expect(find.byKey(const Key('historyButton_pub')), findsOneWidget, reason: 'status/history for every item');
    });
  });

  testWidgets('without the reject permission the action is hidden (history stays with view)', (t) async {
    final b = _Backend(perms: const ['view', 'approve', 'edit']);
    await _open(t, b, () async {
      expect(find.byKey(const Key('revisionButton_pend')), findsNothing);
      expect(find.byKey(const Key('historyButton_pend')), findsOneWidget);
      expect(find.text('Approve'), findsWidgets);
    });
  });

  testWidgets('a reason is required; the request carries action + reason; the card updates', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await t.tap(find.byKey(const Key('revisionButton_pend')));
      await _settle(t);
      final confirm = find.byKey(const Key('confirmRevisionButton'));
      expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'disabled with no reason');
      await t.enterText(find.byKey(const Key('revisionNotesField')), 'ab');
      await _settle(t);
      expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'too short');
      expect(find.textContaining('Give the author a reason'), findsOneWidget);
      expect(b.patches, isEmpty);
      await t.enterText(find.byKey(const Key('revisionNotesField')), '   ');
      await _settle(t);
      expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'whitespace is not a reason');

      await t.enterText(find.byKey(const Key('revisionNotesField')), 'Add the sample size.');
      await _settle(t);
      await t.tap(confirm);
      await _settle(t);
      expect(b.patches, hasLength(1));
      expect(b.patches.single['action'], 'request_revision');
      expect(b.patches.single['review_notes'], 'Add the sample size.');
      expect(find.byKey(const Key('revisionNotesField')), findsNothing, reason: 'dialog closed');
      expect(find.textContaining('author was notified'), findsOneWidget);
      expect(find.byKey(const Key('revisionButton_pend')), findsNothing, reason: 'no longer eligible');
      expect(find.text('Revision requested: Add the sample size.'), findsOneWidget);
    });
  });

  testWidgets('a server refusal is shown in the dialog and the typed reason is kept', (t) async {
    final b = _Backend()
      ..patchOverride = (_) => _json({'detail': 'Revision can only be requested for content that is pending review.', 'code': 'not_revision_eligible'}, 409);
    await _open(t, b, () async {
      await t.tap(find.byKey(const Key('revisionButton_pend')));
      await _settle(t);
      await t.enterText(find.byKey(const Key('revisionNotesField')), 'Please fix the abstract.');
      await _settle(t);
      await t.tap(find.byKey(const Key('confirmRevisionButton')));
      await _settle(t);
      expect(find.byKey(const Key('revisionError')), findsOneWidget);
      expect(find.textContaining('pending review'), findsWidgets);
      expect(find.byKey(const Key('revisionNotesField')), findsOneWidget, reason: 'dialog stays open');
      expect(t.widget<TextField>(find.byKey(const Key('revisionNotesField'))).controller!.text, 'Please fix the abstract.');
      expect(find.byKey(const Key('revisionButton_pend')), findsOneWidget, reason: 'card unchanged');
    });
  });

  testWidgets('Cancel sends nothing', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await t.tap(find.byKey(const Key('revisionButton_pend')));
      await _settle(t);
      await t.enterText(find.byKey(const Key('revisionNotesField')), 'Some reason');
      await t.tap(find.text('Cancel'));
      await _settle(t);
      expect(b.patches, isEmpty);
    });
  });

  testWidgets('History shows the current status and revision history; failure offers Retry', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await t.tap(find.byKey(const Key('historyButton_rev')));
      await _settle(t);
      expect(find.byKey(const Key('historyStatus')), findsOneWidget);
      expect(find.text('Current status: Needs Revision'), findsOneWidget);
      expect(find.text('Revision requested: Cite sources.'), findsWidgets);
      expect(find.textContaining('Research Admin - 2026-10-02'), findsOneWidget);
      await t.tap(find.text('Close'));
      await _settle(t);

      var fail = true;
      b.historyOverride = () => fail ? _json({'detail': 'boom'}, 500) : _json({'status': 'Pending', 'review_notes': '', 'can_request_revision': true, 'history': []});
      await t.tap(find.byKey(const Key('historyButton_pend')));
      await _settle(t);
      expect(find.byKey(const Key('historyError')), findsOneWidget);
      fail = false;
      await t.tap(find.byKey(const Key('historyRetry')));
      await _settle(t);
      expect(find.text('Current status: Pending'), findsOneWidget);
      expect(find.byKey(const Key('historyEmpty')), findsOneWidget);
      expect(find.textContaining('a revision can be requested'), findsOneWidget);
    });
  });
}
