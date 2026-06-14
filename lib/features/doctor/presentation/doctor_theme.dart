import 'package:flutter/material.dart';

class VetColors {
  VetColors._();

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
  static const Color greyDark = Color(0xFFBDBDBD);

  // Doctor availability
  static const Color available = Color(0xFF2E7D32);
  static const Color availableLight = Color(0xFFE8F5E9);
  static const Color busy = Color(0xFFE65100);
  static const Color busyLight = Color(0xFFFFF3E0);
  static const Color offline = Color(0xFF757575);
  static const Color offlineLight = Color(0xFFF5F5F5);

  // Case urgency
  static const Color routine = Color(0xFF1565C0);
  static const Color routineLight = Color(0xFFE3F2FD);
  static const Color moderate = Color(0xFFF57C00);
  static const Color moderateLight = Color(0xFFFFF8E1);
  static const Color urgent = Color(0xFFE65100);
  static const Color urgentLight = Color(0xFFFFF3E0);
  static const Color emergency = Color(0xFFB71C1C);
  static const Color emergencyLight = Color(0xFFFFEBEE);

  // Case status
  static const Color open = Color(0xFF1565C0);
  static const Color openLight = Color(0xFFE3F2FD);
  static const Color inProgress = Color(0xFFF57C00);
  static const Color inProgressLight = Color(0xFFFFF8E1);
  static const Color followUpColor = Color(0xFF6A1B9A);
  static const Color followUpLight = Color(0xFFF3E5F5);
  static const Color closed = Color(0xFF2E7D32);
  static const Color closedLight = Color(0xFFE8F5E9);

  // Appointment mode
  static const Color online = Color(0xFF0277BD);
  static const Color onlineLight = Color(0xFFE1F5FE);
  static const Color inPerson = Color(0xFF2E7D32);
  static const Color inPersonLight = Color(0xFFE8F5E9);

  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);
  static const Color amber = Color(0xFFF9A825);
  static const Color amberLight = Color(0xFFFFF8E1);
}

BoxDecoration vetCard({
  double radius = 12,
  bool highlight = false,
  Color? borderColor,
}) =>
    BoxDecoration(
      color: VetColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            (highlight
                ? VetColors.secondary.withValues(alpha: 0.4)
                : VetColors.cardBorder),
        width: highlight ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

Widget vetChip(
  String label,
  Color bg,
  Color fg, {
  double fontSize = 11,
}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
