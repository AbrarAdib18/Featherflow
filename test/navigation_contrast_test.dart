// Global navigation-contrast guarantee.
//
// Every green navigation surface in the app (app bars, green tab bars,
// sidebar / drawer headers, navigation rails, selected nav items) must render
// its text and icons in white / near-white. This test locks that in at the
// theme level and on a representative rendered green app bar + tab bar so a
// future change that drops `foregroundColor` (or adds a dark-tinted nav icon)
// fails CI instead of shipping an unreadable bar.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/core/theme/theme.dart';

/// The brand green every navigation surface is painted with.
const _greenSurface = AppColors.navigationSurface;

/// A colour is white-hued when every channel is high (opaque white, or white
/// with an alpha — hover / unselected / disabled tints are still white-hued).
bool _isWhiteHued(Color c) => c.r >= 0.90 && c.g >= 0.90 && c.b >= 0.90;

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Composited over the green nav surface, does the colour clear the WCAG
/// contrast bar? 4.5:1 for body text / icons, 3:1 for large or disabled.
bool _readsOnGreen(Color c, {double min = 4.5}) =>
    _contrastRatio(Color.alphaBlend(c, _greenSurface), _greenSurface) >= min;

void _expectNavForeground(Color? c, String label, {double min = 4.5}) {
  expect(c, isNotNull, reason: '$label has no colour');
  expect(_isWhiteHued(c!), isTrue,
      reason: '$label = $c is not white/near-white (dark-on-green is forbidden)');
  expect(_readsOnGreen(c, min: min), isTrue,
      reason: '$label = $c does not meet contrast on the green nav surface');
}

/// The colour of every glyph run actually rendered inside [root] (Flutter
/// paints both `Text` and `Icon` as `RichText`).
List<Color> _renderedGlyphColors(WidgetTester tester, Finder root) {
  final colors = <Color>[];
  for (final e
      in find.descendant(of: root, matching: find.byType(RichText)).evaluate()) {
    final span = (e.widget as RichText).text;
    if (span is TextSpan && span.style?.color != null) {
      colors.add(span.style!.color!);
    }
    span.visitChildren((s) {
      if (s is TextSpan && s.style?.color != null) colors.add(s.style!.color!);
      return true;
    });
  }
  return colors;
}

void main() {
  group('navigation-contrast tokens', () {
    test('the six shared nav tokens are white-hued', () {
      for (final entry in const {
        'navigationForegroundColor': AppColors.navigationForegroundColor,
        'navigationIconColor': AppColors.navigationIconColor,
        'navigationSelectedColor': AppColors.navigationSelectedColor,
        'navigationUnselectedColor': AppColors.navigationUnselectedColor,
        'navigationHoverColor': AppColors.navigationHoverColor,
        'navigationDisabledColor': AppColors.navigationDisabledColor,
      }.entries) {
        expect(_isWhiteHued(entry.value), isTrue,
            reason: '${entry.key} = ${entry.value} is not white-hued');
      }
    });

    test('foreground / selected / unselected read as body text on green', () {
      for (final c in const [
        AppColors.navigationForegroundColor,
        AppColors.navigationIconColor,
        AppColors.navigationSelectedColor,
        AppColors.navigationUnselectedColor,
      ]) {
        expect(_readsOnGreen(c), isTrue,
            reason: '$c fails 4.5:1 on the green nav surface');
      }
    });

    test('the disabled token is still readable (>= 3:1), never dark-on-green', () {
      expect(_isWhiteHued(AppColors.navigationDisabledColor), isTrue);
      expect(_readsOnGreen(AppColors.navigationDisabledColor, min: 3.0), isTrue);
    });

    test('selected-item indicator is a visible lighter green, not the surface', () {
      expect(AppColors.navigationIndicator, isNot(_greenSurface));
      expect(
          _contrastRatio(AppColors.navigationIndicator, _greenSurface),
          greaterThan(1.5));
    });
  });

  group('theme components', () {
    test('ColorScheme.onPrimary is white and primary is a dark green', () {
      final scheme = AppTheme.light.colorScheme;
      _expectNavForeground(scheme.onPrimary, 'colorScheme.onPrimary');
      expect(scheme.primary.computeLuminance(), lessThan(0.1));
    });

    test('AppBarTheme paints white on the green surface', () {
      final ab = AppTheme.light.appBarTheme;
      expect(ab.backgroundColor, _greenSurface);
      _expectNavForeground(ab.foregroundColor, 'appBarTheme.foregroundColor');
      _expectNavForeground(ab.iconTheme?.color, 'appBarTheme.iconTheme');
      _expectNavForeground(
          ab.actionsIconTheme?.color, 'appBarTheme.actionsIconTheme');
      _expectNavForeground(
          ab.titleTextStyle?.color, 'appBarTheme.titleTextStyle');
    });

    test('TabBarTheme labels are white on the green app bar', () {
      final tb = AppTheme.light.tabBarTheme;
      _expectNavForeground(tb.labelColor, 'tabBarTheme.labelColor');
      _expectNavForeground(tb.unselectedLabelColor,
          'tabBarTheme.unselectedLabelColor',
          min: 3.0);
      expect(tb.indicatorColor, isNot(_greenSurface));
    });

    test('NavigationRailTheme is white on green', () {
      final nr = AppTheme.light.navigationRailTheme;
      expect(nr.backgroundColor, _greenSurface);
      _expectNavForeground(
          nr.selectedIconTheme?.color, 'navRail.selectedIconTheme');
      _expectNavForeground(
          nr.unselectedIconTheme?.color, 'navRail.unselectedIconTheme',
          min: 3.0);
      _expectNavForeground(
          nr.selectedLabelTextStyle?.color, 'navRail.selectedLabel');
      _expectNavForeground(
          nr.unselectedLabelTextStyle?.color, 'navRail.unselectedLabel',
          min: 3.0);
    });
  });

  group('rendered green navigation surface', () {
    testWidgets('un-coloured title, action icons, back button and tab labels '
        'all render white on the green app bar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              leading:
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {}),
              title: const Text('Screen title'),
              actions: const [
                Icon(Icons.search),
                SizedBox(width: 8),
                Icon(Icons.notifications_outlined),
                SizedBox(width: 8),
              ],
              bottom: const TabBar(
                tabs: [Tab(text: 'One'), Tab(text: 'Two'), Tab(text: 'Three')],
              ),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // The bar really is the brand green.
      expect(AppTheme.light.appBarTheme.backgroundColor, _greenSurface);

      // Inherited defaults inside the app bar are near-white.
      final ctx = tester.element(find.text('Screen title'));
      _expectNavForeground(
          DefaultTextStyle.of(ctx).style.color, 'app-bar DefaultTextStyle');
      _expectNavForeground(IconTheme.of(ctx).color, 'app-bar IconTheme');

      // Every glyph actually painted in the app bar (title, icons, tab labels).
      final colors = _renderedGlyphColors(tester, find.byType(AppBar));
      expect(colors, isNotEmpty, reason: 'no glyphs found in the app bar');
      for (final c in colors) {
        expect(_isWhiteHued(c), isTrue,
            reason: 'app-bar glyph $c is not white/near-white');
        expect(_readsOnGreen(c, min: 3.0), isTrue,
            reason: 'app-bar glyph $c is too faint on green');
      }
    });
  });
}
