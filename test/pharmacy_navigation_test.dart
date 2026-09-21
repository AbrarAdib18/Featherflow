// Pharmacy back-button + photo-gating regression tests.
//
// Covers two concrete defects fixed in this pass:
//   1. `phBackLeading` — standalone pharmacy routes must show a real,
//      working back button; tab-embedded ones must not (the shell's own
//      TabBar is the navigation there, a duplicate back arrow would be
//      redundant/confusing).
//   2. `AddMedicineDialog` — a new (unsaved) medicine now shows a "save
//      first" placeholder instead of the photo picker, and the primary
//      action reads "Add Medicine"; nothing to test at the widget level for
//      *after* saving since that requires a real network round trip
//      (covered by backend/scripts/test_pharmacy_medicine_images.py and by
//      the live-browser verification in the fix report instead).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/features/pharmacy/data/models/medicine_models.dart';
import 'package:featherflow/features/pharmacy/presentation/pharmacy_theme.dart';
import 'package:featherflow/features/pharmacy/presentation/widgets/add_medicine_dialog.dart';

void main() {
  group('phBackLeading', () {
    Widget hostFor(bool embedded) => MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/pharmacy/catalogue',
            routes: [
              GoRoute(path: '/pharmacy', builder: (_, __) => const SizedBox()),
              GoRoute(
                path: '/pharmacy/catalogue',
                builder: (context, __) => Scaffold(
                  appBar: AppBar(leading: phBackLeading(context, embedded: embedded)),
                ),
              ),
            ],
          ),
        );

    testWidgets('embedded (tab) mode shows no back button', (tester) async {
      await tester.pumpWidget(hostFor(true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('standalone route shows a visible, tappable back button with a tooltip',
        (tester) async {
      await tester.pumpWidget(hostFor(false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.tooltip, 'Back');
    });

    testWidgets('root fallback (nothing to pop) does not crash when tapped',
        (tester) async {
      // Single-route router: canPop() is false, so this exercises the
      // context.go(AppRoutes.pharmacyDashboard) fallback branch instead of
      // context.pop() — must not throw.
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/pharmacy/catalogue',
          routes: [
            GoRoute(path: '/pharmacy', builder: (_, __) => const Text('Pharmacy home')),
            GoRoute(
              path: '/pharmacy/catalogue',
              builder: (context, __) => Scaffold(
                appBar: AppBar(leading: phBackLeading(context, embedded: false)),
              ),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Pharmacy home'), findsOneWidget);
    });
  });

  group('AddMedicineDialog photo gating', () {
    testWidgets('a brand-new (unsaved) medicine shows the "save first" placeholder, not the picker',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AddMedicineDialog()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Add Medicine'), findsWidgets);
      expect(find.text('Save the medicine to add a photo.'), findsOneWidget);
      expect(find.text('Add product photo'), findsNothing);
    });

    testWidgets('editing an existing medicine (with a real id) shows the photo picker immediately',
        (tester) async {
      final existing = Medicine.fromJson({
        'id': 'existing-id',
        'name': 'Test Medicine',
        'category': 'antibiotic',
        'unit': 'bottle',
        'price': 100,
        'stock_quantity': 10,
        'expiry_date': '2099-01-01',
        'images': [],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AddMedicineDialog(existing: existing)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edit Medicine'), findsOneWidget);
      expect(find.text('Save the medicine to add a photo.'), findsNothing);
      // CatalogueImagePicker's own upload/replace label is present immediately
      // since a real id already exists.
      expect(find.text('Add product photo'), findsOneWidget);
    });
  });
}
