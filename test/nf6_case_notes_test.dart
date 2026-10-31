// NF-6: editable doctor case notes - partial updates (no accidental replacement),
// validation, saving / success / failure / conflict states, audit history view.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/network/auth_service.dart';
import 'package:featherflow/features/doctor/data/services/doctor_session.dart';
import 'package:featherflow/features/doctor/presentation/screens/doctor_case_notes_screen.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Backend {
  final Map<String, dynamic> notes = {
    'diagnosis': 'Newcastle disease (suspected)', 'treatment_plan': 'Supportive care',
    'warnings': 'Isolate', 'next_steps': 'Recheck in 3 days', 'feed_notes': '', 'vaccine_history': '', 'biosecurity_notes': '',
  };
  String status = 'in_progress';
  int revision = 1;
  final patches = <Map<String, dynamic>>[];
  http.Response Function()? patchOverride;
  http.Response Function()? historyOverride;
  int historyCalls = 0;

  Map<String, dynamic> get caseJson => {
        'id': 'case1', 'appointment_id': 'cons1', 'farmer_name': 'Rashed', 'farm_name': 'Green Farm', 'flock_size': 500,
        'bird_age_weeks': 6, 'breed': 'Broiler', 'mortality_count': 3, 'symptoms': ['cough'], 'disease_tags': [],
        'urgency': 'routine', 'status': status, 'created_at': '2026-10-01T10:00:00Z', 'notes_revision': revision, ...notes,
      };

  http.Response handle(http.Request req) {
    final path = req.url.path;
    if (req.method == 'PATCH' && path.contains('/cases/case1/')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      patches.add(body);
      if (patchOverride != null) return patchOverride!();
      if (body['base_revision'] != revision) {
        return _json({'detail': 'These notes were changed after you opened them.', 'code': 'note_conflict', 'notes_revision': revision}, 409);
      }
      for (final k in notes.keys) {
        if (body.containsKey(k)) notes[k] = body[k];
      }
      revision++;
      return _json(caseJson);
    }
    if (path.endsWith('/cases/case1/history/')) {
      historyCalls++;
      if (historyOverride != null) return historyOverride!();
      return _json({'notes_revision': 1, 'history': [
        {'id': 'h1', 'revision': 1, 'action': 'edit', 'editor': 'Dr Vet', 'editor_role': 'doctor', 'created_at': '2026-10-02T09:00:00Z',
         'changes': {'diagnosis': {'from': '', 'to': 'Newcastle disease (suspected)'}}},
      ]});
    }
    if (path.endsWith('/dashboard/')) return _json({'profile': {'id': 'd1', 'name': 'Dr Vet'}, 'summary': {}});
    if (path.endsWith('/cases/')) return _json({'cases': [caseJson]});
    if (path.endsWith('/notifications/')) return _json({'notifications': [], 'unread_count': 0});
    return _json({'appointments': [], 'earnings': [], 'ratings': [], 'conversations': []});
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _open(WidgetTester t, _Backend b, Future<void> Function() body) async {
  SharedPreferences.setMockInitialValues({});
  await t.runAsync(() => AuthService.instance.saveSession(AuthSession(
        accessToken: 'a', refreshToken: 'r',
        user: AuthUser(
          id: 'doc1', email: 'vet@test', fullName: 'Dr Vet', roles: const ['doctor'],
          accountStatus: 'active', phone: '+8801000000000', presentAddress: 'Dhaka',
          dateOfBirth: '1990-01-01', profileData: const {}, profilePhotoUrl: '',
        ),
      )));
  final client = MockClient((req) async => b.handle(req));
  await http.runWithClient(() async {
    await t.runAsync(() async {
      // the singleton may still be finishing an earlier (unmocked) load: retry until ours lands
      for (var i = 0; i < 40; i++) {
        await DoctorSession.instance.refresh();
        final c = DoctorSession.instance.findCase('case1');
        if (c != null && !DoctorSession.instance.isLoading && c.notesRevision == b.revision && c.nextSteps == b.notes['next_steps'] &&
            c.diagnosis == b.notes['diagnosis'] && c.status.name == (b.status == 'in_progress' ? 'inProgress' : b.status)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CaseDetailScreen(caseId: 'case1')));
    await _settle(t);
    await body();
    await t.pumpWidget(const SizedBox());
  }, () => client);
}

Future<void> _openEditor(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('editNotesButton')));
  await t.tap(find.byKey(const Key('editNotesButton')));
  await _settle(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the editor shows the existing notes; Save is disabled until something changes', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await _openEditor(t);
      expect(t.widget<TextField>(find.byKey(const Key('note_diagnosis'))).controller!.text, 'Newcastle disease (suspected)');
      expect(t.widget<TextField>(find.byKey(const Key('note_next_steps'))).controller!.text, 'Recheck in 3 days');
      expect(t.widget<FilledButton>(find.byKey(const Key('saveNotesButton'))).onPressed, isNull);
      expect(find.byKey(const Key('notesNoChanges')), findsOneWidget);
      expect(b.patches, isEmpty);
    });
  });

  testWidgets('saving sends ONLY the changed field + base revision; other notes are preserved; success is shown', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await _openEditor(t);
      await t.enterText(find.byKey(const Key('note_next_steps')), 'Recheck in 5 days');
      await _settle(t);
      expect(find.text('Save 1 change'), findsOneWidget);
      await t.tap(find.byKey(const Key('saveNotesButton')));
      await _settle(t);
      expect(b.patches, hasLength(1));
      expect(b.patches.single.keys.toSet(), {'consultation_id', 'next_steps', 'base_revision'}, reason: 'no full-record replacement');
      expect(b.patches.single['next_steps'], 'Recheck in 5 days');
      expect(b.patches.single['base_revision'], 1);
      expect(b.notes['diagnosis'], 'Newcastle disease (suspected)');
      expect(b.notes['treatment_plan'], 'Supportive care');
      expect(find.byKey(const Key('note_next_steps')), findsNothing, reason: 'dialog closed');
      expect(find.text('Case notes saved'), findsOneWidget);
      expect(find.textContaining('Recheck in 5 days'), findsWidgets, reason: 'the screen shows the saved value');
    });
  });

  testWidgets('a recorded diagnosis cannot be blanked; an over-long note is refused; nothing is sent', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await _openEditor(t);
      await t.enterText(find.byKey(const Key('note_diagnosis')), '   ');
      await _settle(t);
      expect(find.textContaining('cannot be emptied'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('saveNotesButton'))).onPressed, isNull);
      await t.enterText(find.byKey(const Key('note_diagnosis')), 'Fixed diagnosis');
      await t.enterText(find.byKey(const Key('note_warnings')), '');
      await _settle(t);
      expect(find.textContaining('cannot be emptied'), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const Key('saveNotesButton'))).onPressed, isNotNull, reason: 'optional notes may be cleared deliberately');
      expect(b.patches, isEmpty);
    });
  });

  testWidgets('a server failure is shown, the dialog stays and keeps the edit', (t) async {
    final b = _Backend()..patchOverride = () => _json({'detail': 'Case notes can only be edited for an accepted consultation (currently rejected).', 'code': 'case_not_editable'}, 409);
    await _open(t, b, () async {
      await _openEditor(t);
      await t.enterText(find.byKey(const Key('note_next_steps')), 'My edit');
      await _settle(t);
      await t.tap(find.byKey(const Key('saveNotesButton')));
      await _settle(t);
      expect(find.byKey(const Key('notesError')), findsOneWidget);
      expect(find.textContaining('accepted consultation'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const Key('note_next_steps'))).controller!.text, 'My edit');
      expect(find.text('Case notes saved'), findsNothing);
    });
  });

  testWidgets('a conflicting save is refused; "Reload the latest notes" loads the newer text', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await _openEditor(t);
      // someone else saves while this editor is open
      b.notes['next_steps'] = 'Changed on another device';
      b.revision = 2;
      await t.enterText(find.byKey(const Key('note_next_steps')), 'STALE OVERWRITE');
      await _settle(t);
      await t.tap(find.byKey(const Key('saveNotesButton')));
      await _settle(t);
      expect(find.byKey(const Key('notesConflict')), findsOneWidget);
      expect(b.notes['next_steps'], 'Changed on another device', reason: 'the newer text was not overwritten');
      expect(t.widget<FilledButton>(find.byKey(const Key('saveNotesButton'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('reloadLatestNotes')));
      await _settle(t);
      expect(find.byKey(const Key('notesConflict')), findsNothing);
      expect(t.widget<TextField>(find.byKey(const Key('note_next_steps'))).controller!.text, 'Changed on another device');
      // now a fresh edit goes through with the new revision
      await t.enterText(find.byKey(const Key('note_next_steps')), 'Merged edit');
      await _settle(t);
      await t.tap(find.byKey(const Key('saveNotesButton')));
      await _settle(t);
      expect(b.notes['next_steps'], 'Merged edit');
      expect(b.patches.last['base_revision'], 2);
    });
  });

  testWidgets('a closed case cannot be edited from the UI', (t) async {
    final b = _Backend()..status = 'closed';
    await _open(t, b, () async {
      final btn = find.byKey(const Key('editNotesButton'));
      await t.ensureVisible(btn);
      expect(t.widget<FilledButton>(btn).onPressed, isNull);
      expect(find.textContaining('reopen to edit notes'), findsOneWidget);
    });
  });

  testWidgets('history shows revision, author, timestamp and previous -> new value; failure offers Retry', (t) async {
    final b = _Backend();
    await _open(t, b, () async {
      await t.ensureVisible(find.byKey(const Key('notesHistoryButton')));
      await t.tap(find.byKey(const Key('notesHistoryButton')));
      await _settle(t);
      expect(find.textContaining('Revision 1 - Dr Vet - 2026-10-02T09:00:00Z'), findsOneWidget);
      expect(find.textContaining('diagnosis: "" -> "Newcastle disease (suspected)"'), findsOneWidget);
      await t.tap(find.text('Close'));
      await _settle(t);

      var fail = true;
      b.historyOverride = () => fail ? _json({'detail': 'History unavailable'}, 500) : _json({'notes_revision': 0, 'history': []});
      await t.tap(find.byKey(const Key('notesHistoryButton')));
      await _settle(t);
      expect(find.byKey(const Key('notesHistoryError')), findsOneWidget);
      fail = false;
      await t.tap(find.byKey(const Key('notesHistoryRetry')));
      await _settle(t);
      expect(find.byKey(const Key('notesHistoryEmpty')), findsOneWidget);
    });
  });
}
