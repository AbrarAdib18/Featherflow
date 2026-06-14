import 'package:flutter/material.dart';

const double kSidebarWidth = 240.0;
const double kBreakpointWide = 900.0;

class AColors {
  AColors._();

  static const Color bg = Colors.white;
  static const Color appBar = Color(0xFF01291E);
  static const Color primary = Color(0xFF01291E);
  static const Color secondary = Color(0xFF1DB584);
  static const Color card = Colors.white;
  static const Color cardBorder = Color(0xFFE8E8E8);
  static const Color surface2 = Color(0xFFF5F5F5);
  static const Color divider = Color(0xFFEEEEEE);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color orange = Color(0xFFE65100);
  static const Color orangeLight = Color(0xFFFFF3E0);
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);
  static const Color green = Color(0xFF2E7D32);
  static const Color greenLight = Color(0xFFE8F5E9);
  static const Color amber = Color(0xFFF9A825);
  static const Color amberLight = Color(0xFFFFF8E1);
  static const Color blue = Color(0xFF1565C0);
  static const Color blueLight = Color(0xFFE3F2FD);
  static const Color purple = Color(0xFF6A1B9A);
  static const Color purpleLight = Color(0xFFF3E5F5);
}

BoxDecoration aCard({double radius = 12, bool highlight = false}) =>
    BoxDecoration(
      color: AColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: highlight
            ? AColors.secondary.withValues(alpha: 0.4)
            : AColors.cardBorder,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

Widget aChip(String label, Color bg, Color fg, {double fontSize = 11}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: fg, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
