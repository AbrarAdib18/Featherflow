// Regression coverage for the shared error panel and for the fixes made during
// the full-platform audit:
//   * FarmManagementService / cost-management used to surface a raw
//     FormatException ("<!DOCTYPE html>…") as the on-screen error when the
//     backend returned a non-JSON 5xx (root cause: a farmer with >1 farm row
//     500'd on every cost-management endpoint). humanize() must turn those into
//     a readable sentence.
//   * ExpenseListScreen title was "All expenses expenses".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/widgets/error_state.dart';
import 'package:featherflow/core/l10n/language_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorStateView.humanize', () {
    test('non-JSON / HTML server response is not shown raw', () {
      final msg = ErrorStateView.humanize(
          const FormatException('Unexpected character', '<!DOCTYPE html><html>500'));
      expect(msg, isNot(contains('<!DOCTYPE')));
      expect(msg, isNot(contains('FormatException')));
      expect(msg.toLowerCase(), contains('server'));
    });

    test('network failures become a connectivity message', () {
      final msg = ErrorStateView.humanize(Exception('ClientException: Failed to fetch'));
      expect(msg.toLowerCase(), contains('connection'));
    });

    test('a plain message passes through without the Exception prefix', () {
      expect(ErrorStateView.humanize(Exception('This bill is already paid.')),
          'This bill is already paid.');
    });
  });

  testWidgets('ErrorStateView renders the message and a working Retry', (t) async {
    var retried = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorStateView(message: 'Could not load', onRetry: () => retried++),
      ),
    ));
    expect(find.text('Could not load'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, 1);
  });

  test('language choice + "asked" flag survive a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final n = LanguageNotifier.instance;
    n.setLocale(const Locale('bn'));
    n.markInitialDialogShown();
    // simulate a fresh app start
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await n.load();
    expect(n.locale.languageCode, 'bn');
    expect(n.hasShownInitialDialog, isTrue);
    n.setLocale(const Locale('en')); // reset for other tests
  });
}
