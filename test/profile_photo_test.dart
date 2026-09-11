// Smoke + validation tests for the shared ProfilePhotoField.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:featherflow/core/widgets/profile_photo_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows initials when there is no photo', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.green,
        body: Center(
          child: ProfilePhotoField(currentUrl: '', fallbackInitial: 'K'),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('K'), findsOneWidget);
    expect(find.text('Add profile photo'), findsOneWidget);
  });

  testWidgets('shows "Change profile photo" when a url is set', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProfilePhotoField(
            currentUrl: 'http://127.0.0.1:8000/api/auth/registration-documents/x/',
            fallbackInitial: 'K',
            onLightSurface: true,
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Change profile photo'), findsOneWidget);
  });

  testWidgets('non-editable hides the change controls', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProfilePhotoField(
              currentUrl: '', fallbackInitial: 'K', editable: false),
        ),
      ),
    ));
    expect(find.text('Add profile photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
  });

  testWidgets('showLabel:false keeps only the camera badge', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProfilePhotoField(
              currentUrl: '', fallbackInitial: 'K', showLabel: false),
        ),
      ),
    ));
    expect(find.text('Add profile photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });
}
