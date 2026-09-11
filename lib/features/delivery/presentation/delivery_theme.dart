import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart' show AppColors;

// Delivery panel color tokens — mirrors the user panel design system.
// AppColors.primary = 0xFF01291E, AppColors.secondary = 0xFF1DB584
class DColors {
  DColors._();

  // Scaffold / surface (white — matches user panel)
  static const Color bg = Colors.white;
  static const Color card = Colors.white;
  static const Color cardBorder = Color(0xFFE8E8E8);
  static const Color surface2 = Color(0xFFF5F5F5);
  static const Color divider = Color(0xFFEEEEEE);

  // Primary palette (AppColors.primary / secondary from user panel)
  static const Color primary = Color(0xFF01291E);
  static const Color secondary = Color(0xFF1DB584);
  static const Color secondaryContainer = Color(0xFF00896A);

  // Green accent variants (visible on white backgrounds)
  static const Color accent = Color(0xFF2E7D32);
  static const Color accentMid = Color(0xFF4CAF50);
  static const Color accentLight = Color(0xFFE8F5E9);

  // Status colors
  static const Color orange = Color(0xFFE65100);
  static const Color orangeLight = Color(0xFFFFF3E0);
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);

  // Text (dark on white backgrounds)
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color grey = Color(0xFF999999);
  static const Color greyDark = Color(0xFFBDBDBD);

  // App bar (always dark green, white text over it)
  static const Color appBar = Color(0xFF01291E);

  // Navigation-contrast tokens — shared via [AppColors]. Anything on a
  // green nav surface (app bar, green TabBar) uses these; never dark on green.
  static const Color navigationSurface = AppColors.navigationSurface;
  static const Color navigationForegroundColor =
      AppColors.navigationForegroundColor;
  static const Color navigationIconColor = AppColors.navigationIconColor;
  static const Color navigationSelectedColor =
      AppColors.navigationSelectedColor;
  static const Color navigationUnselectedColor =
      AppColors.navigationUnselectedColor;
  static const Color navigationHoverColor = AppColors.navigationHoverColor;
  static const Color navigationDisabledColor =
      AppColors.navigationDisabledColor;
}

BoxDecoration dCard({
  double radius = 12,
  Color? color,
  bool highlight = false,
}) =>
    BoxDecoration(
      color: color ?? DColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: highlight
            ? DColors.accent.withValues(alpha: 0.35)
            : DColors.cardBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

Widget dChip(String label, Color bg, Color fg, {double fontSize = 11}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: fg, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
