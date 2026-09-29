// Regression test for "RIGHT OVERFLOWED BY 27 PIXELS" on the Urgency dropdown
// in the Book-a-vet dialog (lib/features/farmer/presentation/widgets/vet_booking_dialog.dart).
//
// Why this is a mechanism test rather than a test of VetBookingDialog itself:
// the dialog only renders its form after `_loadOptions()` succeeds against the
// backend, and there is no injectable seam for that. Pumping the real dialog
// with no session leaves it on its spinner/error branch, so the overflowing
// Row never builds and any "no overflow" assertion against it would pass
// vacuously — which is precisely the kind of green-but-meaningless test that
// let an earlier bug hide (see FARMER_DOCTOR_END_TO_END_AUDIT.md).
//
// So this reproduces the exact structure that overflowed — two Expanded
// dropdowns sharing a Row inside the dialog's 560px max-width, with the real
// item lists — and asserts the fix (`isExpanded: true`) holds. The negative
// control below documents that without it, this same harness overflows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the Consultation-mode / Urgency Row in `VetBookingDialog._form()`.
Widget _modeAndUrgencyRow({required bool isExpanded, required bool supportsEmergency}) {
  return MaterialApp(
    home: Scaffold(
      body: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          // Same constraint the real dialog uses.
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: 'online',
                  isExpanded: isExpanded,
                  items: const [
                    DropdownMenuItem(value: 'online', child: Text('Online')),
                    DropdownMenuItem(value: 'offline', child: Text('In-person')),
                  ],
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: 'routine',
                  isExpanded: isExpanded,
                  items: [
                    const DropdownMenuItem(value: 'routine', child: Text('Routine')),
                    const DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                    const DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                    DropdownMenuItem(
                      value: 'emergency',
                      enabled: supportsEmergency,
                      // The widest item — this is what drove the overflow.
                      child: Text(
                        supportsEmergency ? 'Emergency' : 'Emergency (not offered)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester t, Size size, Widget w) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(w);
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Consultation mode / Urgency row', () {
    testWidgets('NEGATIVE CONTROL: without isExpanded the row overflows '
        'when the doctor does not offer emergency', (t) async {
      await _pump(t, const Size(556, 1000),
          _modeAndUrgencyRow(isExpanded: false, supportsEmergency: false));
      final err = t.takeException();
      // This is the bug being guarded against. If this ever stops overflowing,
      // Flutter's dropdown sizing changed and the guard below is moot.
      expect(err, isA<FlutterError>());
      expect(err.toString(), contains('overflowed'));
    });

    testWidgets('with isExpanded there is no overflow (the fix)', (t) async {
      await _pump(t, const Size(556, 1000),
          _modeAndUrgencyRow(isExpanded: true, supportsEmergency: false));
      expect(t.takeException(), isNull);
    });

    testWidgets('no overflow at a narrow phone width', (t) async {
      await _pump(t, const Size(390, 1000),
          _modeAndUrgencyRow(isExpanded: true, supportsEmergency: false));
      expect(t.takeException(), isNull);
    });

    testWidgets('no overflow when the doctor DOES offer emergency', (t) async {
      await _pump(t, const Size(556, 1000),
          _modeAndUrgencyRow(isExpanded: true, supportsEmergency: true));
      expect(t.takeException(), isNull);
    });

    testWidgets('no overflow on a wide layout', (t) async {
      await _pump(t, const Size(1200, 1000),
          _modeAndUrgencyRow(isExpanded: true, supportsEmergency: false));
      expect(t.takeException(), isNull);
    });
  });
}
