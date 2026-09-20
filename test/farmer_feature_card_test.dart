// FarmerFeatureCard — the reusable poultry-themed dashboard tile.
//
// Covers: correct illustration per card, title/subtitle top-right alignment,
// illustration bottom-left, tap navigation, no overflow at narrow widths, no
// opaque background painted behind the transparent illustration, long-title
// readability, badge visibility, and the accessibility label.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/features/farmer/presentation/widgets/farmer_feature_card.dart';
import 'package:featherflow/features/farmer/presentation/widgets/farmer_feature_illustrations.dart';

Widget _host(Widget child, {double width = 200, double height = 220}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders its title, subtitle and the correct illustration',
      (t) async {
    await t.pumpWidget(_host(FarmerFeatureCard(
      title: 'Cost Management',
      subtitle: 'Track expenses, revenue & profit',
      illustration: FeatureIllustrationKind.costManagement,
      onTap: () {},
    )));
    await t.pump();

    expect(find.text('Cost Management'), findsOneWidget);
    expect(find.text('Track expenses, revenue & profit'), findsOneWidget);
    expect(find.byType(FeatureIllustration), findsOneWidget);
    final illustration =
        t.widget<FeatureIllustration>(find.byType(FeatureIllustration));
    expect(illustration.kind, FeatureIllustrationKind.costManagement);
    expect(t.takeException(), isNull);
  });

  testWidgets('title sits top-right and the illustration sits bottom-left',
      (t) async {
    await t.pumpWidget(_host(FarmerFeatureCard(
      title: 'Find Vet',
      subtitle: 'Book trusted poultry vets nearby',
      illustration: FeatureIllustrationKind.findVet,
      onTap: () {},
    )));
    await t.pump();

    final cardTopLeft = t.getTopLeft(find.byType(FarmerFeatureCard));
    final cardBottomRight = t.getBottomRight(find.byType(FarmerFeatureCard));
    final titleCenter = t.getCenter(find.text('Find Vet'));
    final illustrationRect =
        t.getRect(find.byType(FeatureIllustration));

    final cardWidth = cardBottomRight.dx - cardTopLeft.dx;
    final cardHeight = cardBottomRight.dy - cardTopLeft.dy;

    // Title is in the right half and top half of the card.
    expect(titleCenter.dx, greaterThan(cardTopLeft.dx + cardWidth / 2));
    expect(titleCenter.dy, lessThan(cardTopLeft.dy + cardHeight / 2));

    // The illustration is anchored to the card's bottom-left.
    expect(illustrationRect.left, lessThan(cardTopLeft.dx + cardWidth * 0.3));
    expect(illustrationRect.bottom,
        greaterThan(cardTopLeft.dy + cardHeight * 0.85));

    // The illustration's top stays below the title/subtitle block — no
    // overlap.
    expect(illustrationRect.top, greaterThan(titleCenter.dy));
    expect(t.takeException(), isNull);
  });

  testWidgets('tap fires the onTap callback', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(FarmerFeatureCard(
      title: 'Community',
      subtitle: 'Connect with fellow poultry farmers',
      illustration: FeatureIllustrationKind.community,
      onTap: () => tapped = true,
    )));
    await t.pump();
    await t.tap(find.byType(FarmerFeatureCard));
    expect(tapped, isTrue);
  });

  testWidgets('no overflow at a narrow (compact) width with a long title',
      (t) async {
    await t.pumpWidget(_host(
      const FarmerFeatureCard(
        title: 'Labour Management & Payroll Overview',
        subtitle:
            'Manage workers, attendance and payroll with an even longer description line',
        illustration: FeatureIllustrationKind.laborManagement,
        onTap: _noop,
        compact: true,
      ),
      width: 140,
      height: 150,
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    // Long text is still present (clipped with ellipsis, not thrown away).
    expect(find.textContaining('Labour Management'), findsOneWidget);
  });

  testWidgets('notification badge is visible when badgeCount > 0', (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Find Vet',
      subtitle: 'Book trusted poultry vets nearby',
      illustration: FeatureIllustrationKind.findVet,
      onTap: _noop,
      badgeCount: 3,
    )));
    await t.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('badge caps display at 99+', (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Pharmacy',
      subtitle: 'Order medicine & farm supplies',
      illustration: FeatureIllustrationKind.pharmacy,
      onTap: _noop,
      badgeCount: 150,
    )));
    await t.pump();
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('no badge rendered when badgeCount is 0', (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Tax & Estimates',
      subtitle: 'Calculate your farm tax estimate',
      illustration: FeatureIllustrationKind.tax,
      onTap: _noop,
    )));
    await t.pump();
    expect(find.text('0'), findsNothing);
  });

  testWidgets('exposes an accessibility label combining title and subtitle',
      (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Feed Management',
      subtitle: 'Track feed stock & feeding schedules',
      illustration: FeatureIllustrationKind.feedManagement,
      onTap: _noop,
    )));
    await t.pump();
    final semantics = t.getSemantics(find.byType(FarmerFeatureCard));
    expect(semantics.label,
        'Feed Management. Track feed stock & feeding schedules');
    expect(semantics.flagsCollection.isButton, isTrue);
  }, semanticsEnabled: true);

  testWidgets('a custom semanticLabel overrides the default', (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Articles',
      subtitle: 'Poultry news, tips & research',
      illustration: FeatureIllustrationKind.articles,
      onTap: _noop,
      semanticLabel: 'Open poultry news and research articles',
    )));
    await t.pump();
    final semantics = t.getSemantics(find.byType(FarmerFeatureCard));
    expect(semantics.label, 'Open poultry news and research articles');
  }, semanticsEnabled: true);

  testWidgets('renders no opaque full-bleed background behind the '
      'illustration (the card stays white, not a colored/opaque tile)',
      (t) async {
    await t.pumpWidget(_host(const FarmerFeatureCard(
      title: 'Labour Management',
      subtitle: 'Manage workers & payroll with ease',
      illustration: FeatureIllustrationKind.laborManagement,
      onTap: _noop,
      backgroundColor: Colors.white,
    )));
    await t.pump();
    final container = t.widget<Container>(find
        .ancestor(
            of: find.text('Labour Management'), matching: find.byType(Container))
        .first);
    expect((container.decoration as BoxDecoration).color, Colors.white);
  });

  testWidgets('every dashboard illustration kind builds without an error',
      (t) async {
    for (final kind in FeatureIllustrationKind.values) {
      await t.pumpWidget(_host(FarmerFeatureCard(
        title: 'Feature',
        subtitle: 'Subtitle',
        illustration: kind,
        onTap: () {},
      )));
      await t.pump();
      expect(t.takeException(), isNull, reason: 'illustration failed: $kind');
    }
  });
}

void _noop() {}
