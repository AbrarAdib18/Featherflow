import 'package:flutter/material.dart';

/// Poultry-themed vector illustrations for the farmer dashboard's quick-action
/// cards, in the style of a stock "feature card" image (bold rounded shape +
/// a clear pictogram) — but hand-drawn rather than a photo, since neither
/// Material Icons nor the bundled Phosphor set include a chicken/hen glyph.
///
/// Each card shows the same hen silhouette (the poultry-farm "mascot"),
/// recolored to the card's accent, with a small circular badge icon layered
/// on top identifying the specific feature (wallet for Cost Management, a
/// medical cross for Find Vet, etc.) — so every card reads as "poultry farm"
/// at a glance while staying visually distinct from its neighbors.
class FarmTileIllustration extends StatelessWidget {
  const FarmTileIllustration({
    super.key,
    required this.badgeIcon,
    required this.accent,
    this.size = 92,
  });

  final IconData badgeIcon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Soft rounded backdrop, like the reference image's white card
          // with a cut-out photo — here a tinted blob behind the hen.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(size * 0.14),
              child: CustomPaint(painter: _HenPainter(color: accent)),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: EdgeInsets.all(size * 0.09),
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(badgeIcon, color: Colors.white, size: size * 0.22),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple, flat hen silhouette: rounded body, head, beak, comb and legs.
/// Deliberately simplified (no feather texture/shading) to read clearly at
/// small card sizes.
class _HenPainter extends CustomPainter {
  _HenPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;
    final comb = Paint()..color = color.withValues(alpha: 0.75);

    // Body: a rounded oval sitting in the lower-left two-thirds of the box.
    final bodyRect = Rect.fromLTWH(w * 0.02, h * 0.32, w * 0.72, h * 0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(bodyRect.height / 2)),
      body,
    );

    // Head: a circle at the upper-right of the body.
    final headCenter = Offset(w * 0.68, h * 0.28);
    final headRadius = w * 0.22;
    canvas.drawCircle(headCenter, headRadius, body);

    // Comb: three small bumps on top of the head.
    final combPath = Path();
    for (final dx in [-0.10, 0.0, 0.10]) {
      combPath.addOval(Rect.fromCircle(
        center: headCenter + Offset(w * dx, -headRadius * 0.85),
        radius: w * 0.045,
      ));
    }
    canvas.drawPath(combPath, comb);

    // Beak: a small triangle pointing right from the head.
    final beak = Path()
      ..moveTo(headCenter.dx + headRadius * 0.85, headCenter.dy - w * 0.02)
      ..lineTo(headCenter.dx + headRadius * 1.35, headCenter.dy + w * 0.03)
      ..lineTo(headCenter.dx + headRadius * 0.85, headCenter.dy + w * 0.09)
      ..close();
    canvas.drawPath(beak, Paint()..color = Colors.orange.shade700);

    // Eye.
    canvas.drawCircle(
      headCenter + Offset(w * 0.05, -w * 0.02),
      w * 0.02,
      Paint()..color = Colors.white,
    );

    // Legs: two short lines beneath the body.
    final legPaint = Paint()
      ..color = Colors.orange.shade700
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    final legY = bodyRect.bottom;
    canvas.drawLine(Offset(w * 0.24, legY - h * 0.03),
        Offset(w * 0.22, legY + h * 0.14), legPaint);
    canvas.drawLine(Offset(w * 0.42, legY - h * 0.03),
        Offset(w * 0.44, legY + h * 0.14), legPaint);

    // Tail feathers: a couple of soft curved strokes at the back-left.
    final tailPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.02, h * 0.42), radius: w * 0.16),
      3.6,
      1.4,
      false,
      tailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HenPainter oldDelegate) =>
      oldDelegate.color != color;
}
