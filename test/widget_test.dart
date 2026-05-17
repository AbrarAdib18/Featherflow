import 'package:flutter_test/flutter_test.dart';
import 'package:featherflow/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FeatherflowApp());
    expect(find.byType(FeatherflowApp), findsOneWidget);
  });
}
