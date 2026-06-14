import 'package:flutter/material.dart';

class PhColors {
  PhColors._();

  static const Color bg = Colors.white;
  static const Color card = Colors.white;
  static const Color cardBorder = Color(0xFFE8E8E8);
  static const Color surface2 = Color(0xFFF7F8F9);
  static const Color divider = Color(0xFFEEEEEE);

  static const Color primary = Color(0xFF01291E);
  static const Color secondary = Color(0xFF1DB584);
  static const Color appBar = Color(0xFF01291E);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color grey = Color(0xFF9E9E9E);

  // Stock status
  static const Color inStock = Color(0xFF1DB584);
  static const Color inStockLight = Color(0xFFE8F8F2);
  static const Color lowStock = Color(0xFFF59E0B);
  static const Color lowStockLight = Color(0xFFFEF3C7);
  static const Color outOfStock = Color(0xFFEF4444);
  static const Color outOfStockLight = Color(0xFFFEE2E2);

  // Order status
  static const Color pending = Color(0xFFF59E0B);
  static const Color pendingLight = Color(0xFFFEF3C7);
  static const Color processing = Color(0xFF3B82F6);
  static const Color processingLight = Color(0xFFEFF6FF);
  static const Color shipped = Color(0xFF8B5CF6);
  static const Color shippedLight = Color(0xFFF5F3FF);
  static const Color delivered = Color(0xFF1DB584);
  static const Color deliveredLight = Color(0xFFE8F8F2);
  static const Color cancelled = Color(0xFFEF4444);
  static const Color cancelledLight = Color(0xFFFEE2E2);

  // Category
  static const Color medicines = Color(0xFF3B82F6);
  static const Color medicinesLight = Color(0xFFEFF6FF);
  static const Color vaccines = Color(0xFF1DB584);
  static const Color vaccinesLight = Color(0xFFE8F8F2);
  static const Color supplements = Color(0xFF8B5CF6);
  static const Color supplementsLight = Color(0xFFF5F3FF);
  static const Color equipment = Color(0xFFF59E0B);
  static const Color equipmentLight = Color(0xFFFEF3C7);

  static const Color red = Color(0xFFEF4444);
  static const Color amber = Color(0xFFF59E0B);
  static const Color green = Color(0xFF1DB584);
}

BoxDecoration phCard({
  double radius = 12,
  Color? color,
  bool highlight = false,
  Color? borderColor,
}) =>
    BoxDecoration(
      color: color ?? PhColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            (highlight
                ? PhColors.secondary.withValues(alpha: 0.4)
                : PhColors.cardBorder),
        width: highlight ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

Widget phChip(String label, Color bg, Color fg, {double fontSize = 11}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: fg, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
