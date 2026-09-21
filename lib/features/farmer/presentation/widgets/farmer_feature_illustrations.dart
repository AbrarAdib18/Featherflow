import 'package:flutter/material.dart';

/// A distinct flat-vector illustration per farmer dashboard feature card —
/// one pictogram per [FeatureIllustrationKind], recolored to the card's
/// accent. Replaces the earlier repeated hen-silhouette-plus-badge treatment
/// (every card looked the same) and the imported PNG photos (inconsistent
/// scale/crop across assets) with a lightweight, crisp-at-any-size painter
/// per feature.
enum FeatureIllustrationKind {
  costManagement,
  findVet,
  pharmacy,
  feedManagement,
  tax,
  laborManagement,
  community,
  articles,
}

class FeatureIllustration extends StatelessWidget {
  const FeatureIllustration({
    super.key,
    required this.kind,
    required this.accent,
    this.size = 120,
  });

  final FeatureIllustrationKind kind;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _painterFor(kind, accent),
      ),
    );
  }

  CustomPainter _painterFor(FeatureIllustrationKind kind, Color accent) {
    switch (kind) {
      case FeatureIllustrationKind.costManagement:
        return _WalletPainter(accent: accent);
      case FeatureIllustrationKind.findVet:
        return _VetPainter(accent: accent);
      case FeatureIllustrationKind.pharmacy:
        return _PharmacyPainter(accent: accent);
      case FeatureIllustrationKind.feedManagement:
        return _FeedBowlPainter(accent: accent);
      case FeatureIllustrationKind.tax:
        return _TaxDocPainter(accent: accent);
      case FeatureIllustrationKind.laborManagement:
        return _WorkerPainter(accent: accent);
      case FeatureIllustrationKind.community:
        return _CommunityPainter(accent: accent);
      case FeatureIllustrationKind.articles:
        return _ArticlePainter(accent: accent);
    }
  }
}

/// Shared helpers so every painter reads the same two-tone flat style:
/// a mid-tone accent shape and a darker accent for outlines/detail strokes,
/// with no backdrop shape behind the pictogram itself.
mixin _IllustrationStyle {
  Paint fill(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.fill;

  Paint stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

// ---------------------------------------------------------------------------
// Cost Management — a wallet with a coin, cash poking out the top.
// ---------------------------------------------------------------------------
class _WalletPainter extends CustomPainter with _IllustrationStyle {
  _WalletPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // A banknote peeking out from behind the wallet.
    final note = Rect.fromLTWH(w * 0.30, h * 0.18, w * 0.42, h * 0.28);
    canvas.save();
    canvas.translate(note.center.dx, note.center.dy);
    canvas.rotate(-0.18);
    canvas.translate(-note.center.dx, -note.center.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(note, const Radius.circular(4)),
      fill(accent.withValues(alpha: 0.55)),
    );
    canvas.restore();

    // Wallet body.
    final body = Rect.fromLTWH(w * 0.16, h * 0.40, w * 0.68, h * 0.46);
    final rBody = RRect.fromRectAndRadius(body, const Radius.circular(14));
    canvas.drawRRect(rBody, fill(accent));

    // Flap fold line.
    canvas.drawLine(
      Offset(body.left, body.top + h * 0.09),
      Offset(body.right, body.top + h * 0.09),
      stroke(dark.withValues(alpha: 0.35), 2),
    );

    // Coin clasp / button.
    final coinCenter = Offset(body.right - w * 0.16, body.top + h * 0.23);
    canvas.drawCircle(coinCenter, w * 0.085, fill(Colors.white));
    canvas.drawCircle(coinCenter, w * 0.085, stroke(dark, 2));
    canvas.drawCircle(coinCenter, w * 0.03, fill(dark));

    // A loose coin sitting beside the wallet.
    final loose = Offset(w * 0.20, h * 0.80);
    canvas.drawCircle(loose, w * 0.11, fill(Colors.white));
    canvas.drawCircle(loose, w * 0.11, stroke(dark, 2));
    canvas.drawCircle(loose, w * 0.04, fill(dark.withValues(alpha: 0.6)));
  }

  @override
  bool shouldRepaint(covariant _WalletPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Find Vet — a rounded medical badge with a cross and a heartbeat pulse line.
// ---------------------------------------------------------------------------
class _VetPainter extends CustomPainter with _IllustrationStyle {
  _VetPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // Rounded shield/badge body.
    final badge = Rect.fromLTWH(w * 0.14, h * 0.10, w * 0.72, h * 0.72);
    final badgePath = Path()
      ..moveTo(badge.left, badge.top + badge.height * 0.18)
      ..lineTo(badge.left, badge.bottom - badge.height * 0.28)
      ..cubicTo(badge.left, badge.bottom, badge.center.dx, badge.bottom,
          badge.center.dx, badge.bottom)
      ..cubicTo(badge.right, badge.bottom, badge.right,
          badge.bottom - badge.height * 0.28, badge.right,
          badge.bottom - badge.height * 0.28)
      ..lineTo(badge.right, badge.top + badge.height * 0.18)
      ..cubicTo(badge.right, badge.top, badge.center.dx, badge.top,
          badge.center.dx, badge.top)
      ..cubicTo(badge.left, badge.top, badge.left, badge.top + badge.height * 0.18,
          badge.left, badge.top + badge.height * 0.18)
      ..close();
    canvas.drawPath(badgePath, fill(accent));

    // Inset white panel carrying the pulse line.
    final panel = Rect.fromLTWH(
        badge.left + w * 0.08, badge.top + h * 0.30, badge.width - w * 0.16, h * 0.18);
    canvas.drawRRect(
        RRect.fromRectAndRadius(panel, const Radius.circular(6)), fill(Colors.white));
    final pulse = Path()
      ..moveTo(panel.left + w * 0.02, panel.center.dy)
      ..lineTo(panel.left + w * 0.14, panel.center.dy)
      ..lineTo(panel.left + w * 0.19, panel.top + h * 0.02)
      ..lineTo(panel.left + w * 0.25, panel.bottom - h * 0.02)
      ..lineTo(panel.left + w * 0.30, panel.center.dy)
      ..lineTo(panel.right - w * 0.02, panel.center.dy);
    canvas.drawPath(pulse, stroke(accent, w * 0.028));

    // Medical cross above the panel.
    final crossCenter = Offset(badge.center.dx, badge.top + h * 0.16);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: crossCenter, width: w * 0.07, height: h * 0.20),
            const Radius.circular(2)),
        fill(Colors.white));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: crossCenter, width: w * 0.20, height: h * 0.07),
            const Radius.circular(2)),
        fill(Colors.white));

    // A small paw print low on the badge — ties the medical mark back to an
    // animal patient without redrawing a full hen.
    final pawCenter = Offset(badge.center.dx, badge.bottom - h * 0.13);
    canvas.drawOval(
        Rect.fromCenter(center: pawCenter, width: w * 0.10, height: h * 0.08),
        fill(dark.withValues(alpha: 0.55)));
    for (final dx in [-0.07, -0.025, 0.025, 0.07]) {
      canvas.drawCircle(pawCenter + Offset(w * dx, -h * 0.06), w * 0.022,
          fill(dark.withValues(alpha: 0.55)));
    }
  }

  @override
  bool shouldRepaint(covariant _VetPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Pharmacy — a medicine bottle with a cross label, plus a capsule.
// ---------------------------------------------------------------------------
class _PharmacyPainter extends CustomPainter with _IllustrationStyle {
  _PharmacyPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // Bottle: neck + body.
    final neck = Rect.fromLTWH(w * 0.40, h * 0.14, w * 0.20, h * 0.12);
    canvas.drawRRect(
        RRect.fromRectAndRadius(neck, const Radius.circular(3)), fill(dark));
    final cap = Rect.fromLTWH(w * 0.37, h * 0.08, w * 0.26, h * 0.08);
    canvas.drawRRect(
        RRect.fromRectAndRadius(cap, const Radius.circular(3)), fill(dark));

    final body = Rect.fromLTWH(w * 0.22, h * 0.24, w * 0.56, h * 0.58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(16)),
      fill(accent),
    );

    // Label band + cross.
    final label = Rect.fromLTWH(w * 0.28, h * 0.44, w * 0.44, h * 0.28);
    canvas.drawRRect(
      RRect.fromRectAndRadius(label, const Radius.circular(6)),
      fill(Colors.white),
    );
    final crossCenter = label.center;
    final crossPaint = fill(accent);
    canvas.drawRect(
        Rect.fromCenter(center: crossCenter, width: w * 0.05, height: h * 0.16),
        crossPaint);
    canvas.drawRect(
        Rect.fromCenter(center: crossCenter, width: w * 0.16, height: h * 0.05),
        crossPaint);

    // A capsule leaning beside the bottle.
    final capsuleRect = Rect.fromCenter(
        center: Offset(w * 0.84, h * 0.78), width: w * 0.22, height: h * 0.11);
    canvas.save();
    canvas.translate(capsuleRect.center.dx, capsuleRect.center.dy);
    canvas.rotate(-0.55);
    canvas.translate(-capsuleRect.center.dx, -capsuleRect.center.dy);
    final capsuleRRect =
        RRect.fromRectAndRadius(capsuleRect, Radius.circular(capsuleRect.height / 2));
    canvas.drawRRect(capsuleRRect, fill(Colors.white));
    canvas.save();
    canvas.clipRRect(capsuleRRect);
    canvas.drawRect(
        Rect.fromLTWH(capsuleRect.left, capsuleRect.top, capsuleRect.width / 2,
            capsuleRect.height),
        fill(dark.withValues(alpha: 0.7)));
    canvas.restore();
    canvas.drawRRect(capsuleRRect, stroke(dark.withValues(alpha: 0.4), 1.5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PharmacyPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Feed Management — a feed bowl with grain, wheat stalks above.
// ---------------------------------------------------------------------------
class _FeedBowlPainter extends CustomPainter with _IllustrationStyle {
  _FeedBowlPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // Two wheat stalks above the bowl.
    for (final dx in [-0.14, 0.14]) {
      final baseX = w * (0.5 + dx);
      final stalk = Path()
        ..moveTo(baseX, h * 0.50)
        ..lineTo(baseX + w * dx * 0.3, h * 0.14);
      canvas.drawPath(stalk, stroke(dark.withValues(alpha: 0.55), 2.5));
      for (double t = 0.2; t <= 0.9; t += 0.18) {
        final p = Offset(baseX + w * dx * 0.3 * t, h * (0.50 - 0.36 * t));
        canvas.drawOval(
            Rect.fromCenter(center: p + Offset(w * 0.03, 0), width: w * 0.05, height: h * 0.03),
            fill(accent.withValues(alpha: 0.7)));
        canvas.drawOval(
            Rect.fromCenter(center: p - Offset(w * 0.03, 0), width: w * 0.05, height: h * 0.03),
            fill(accent.withValues(alpha: 0.7)));
      }
    }

    // Bowl.
    final bowlRect = Rect.fromLTWH(w * 0.14, h * 0.56, w * 0.72, h * 0.30);
    final bowlPath = Path()
      ..moveTo(bowlRect.left, bowlRect.top)
      ..quadraticBezierTo(bowlRect.left, bowlRect.bottom, bowlRect.center.dx,
          bowlRect.bottom)
      ..quadraticBezierTo(
          bowlRect.right, bowlRect.bottom, bowlRect.right, bowlRect.top)
      ..close();
    canvas.drawPath(bowlPath, fill(accent));

    // Rim ellipse.
    final rim = Rect.fromCenter(
        center: Offset(bowlRect.center.dx, bowlRect.top),
        width: bowlRect.width,
        height: h * 0.09);
    canvas.drawOval(rim, fill(dark));

    // Grain scatter inside the rim.
    for (final p in [
      Offset(rim.center.dx - w * 0.12, rim.center.dy),
      Offset(rim.center.dx, rim.center.dy - h * 0.01),
      Offset(rim.center.dx + w * 0.12, rim.center.dy),
      Offset(rim.center.dx - w * 0.04, rim.center.dy + h * 0.015),
      Offset(rim.center.dx + w * 0.05, rim.center.dy + h * 0.015),
    ]) {
      canvas.drawCircle(p, w * 0.018, fill(Colors.white));
    }
  }

  @override
  bool shouldRepaint(covariant _FeedBowlPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Tax & Estimates — a receipt/document with a percent badge.
// ---------------------------------------------------------------------------
class _TaxDocPainter extends CustomPainter with _IllustrationStyle {
  _TaxDocPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // Receipt with a zigzag bottom edge.
    final left = w * 0.24, right = w * 0.72, top = h * 0.12, bottom = h * 0.82;
    final receipt = Path()..moveTo(left, top);
    receipt.lineTo(right, top);
    receipt.lineTo(right, bottom);
    const teeth = 6;
    final toothW = (right - left) / teeth;
    for (int i = teeth; i >= 1; i--) {
      final x1 = left + i * toothW;
      final x0 = left + (i - 1) * toothW;
      receipt.lineTo(x1 - toothW / 2, bottom + h * 0.03);
      receipt.lineTo(x0, bottom);
    }
    receipt.close();
    canvas.drawPath(receipt, fill(Colors.white));
    canvas.drawPath(receipt, stroke(dark.withValues(alpha: 0.25), 1.5));

    // Text lines.
    for (int i = 0; i < 4; i++) {
      final y = top + h * 0.14 + i * h * 0.09;
      canvas.drawLine(
        Offset(left + w * 0.06, y),
        Offset(right - w * (i.isEven ? 0.06 : 0.16), y),
        stroke(accent.withValues(alpha: 0.45), 3),
      );
    }

    // Percent badge overlapping the corner.
    final badgeCenter = Offset(right - w * 0.02, top + h * 0.06);
    canvas.drawCircle(badgeCenter, w * 0.17, fill(accent));
    canvas.drawCircle(badgeCenter, w * 0.17, stroke(Colors.white, 2.5));
    final tp = TextPainter(
      text: TextSpan(
        text: '%',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.18,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        badgeCenter - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TaxDocPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Labour Management — a worker ID card on a lanyard, with an attendance
// checklist beneath the photo.
// ---------------------------------------------------------------------------
class _WorkerPainter extends CustomPainter with _IllustrationStyle {
  _WorkerPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    // Lanyard strap running up into the card.
    final card = Rect.fromLTWH(w * 0.18, h * 0.22, w * 0.64, h * 0.66);
    canvas.drawLine(Offset(card.center.dx - w * 0.05, h * 0.02),
        Offset(card.left + w * 0.08, card.top), stroke(dark.withValues(alpha: 0.5), w * 0.045));
    canvas.drawLine(Offset(card.center.dx + w * 0.05, h * 0.02),
        Offset(card.right - w * 0.08, card.top), stroke(dark.withValues(alpha: 0.5), w * 0.045));

    // Card body.
    canvas.drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(12)), fill(Colors.white));
    canvas.drawRRect(
        RRect.fromRectAndRadius(card, const Radius.circular(12)),
        stroke(dark.withValues(alpha: 0.2), 1.5));

    // Punch-hole at the top of the card.
    canvas.drawCircle(Offset(card.center.dx, card.top + h * 0.04), w * 0.02,
        fill(dark.withValues(alpha: 0.3)));

    // Header strip.
    final header = Rect.fromLTWH(card.left, card.top + h * 0.07, card.width, h * 0.10);
    canvas.drawRRect(
        RRect.fromRectAndCorners(header,
            topLeft: const Radius.circular(11), topRight: const Radius.circular(11)),
        fill(accent));

    // Photo circle + name/id lines.
    final photoCenter = Offset(card.left + w * 0.17, card.top + h * 0.32);
    canvas.drawCircle(photoCenter, w * 0.10, fill(accent.withValues(alpha: 0.55)));
    canvas.drawCircle(photoCenter - Offset(0, h * 0.02), w * 0.045,
        fill(Colors.white));
    canvas.drawArc(
        Rect.fromCenter(center: photoCenter + Offset(0, h * 0.045), width: w * 0.13, height: h * 0.09),
        3.4, 2.7, false, fill(Colors.white));
    canvas.drawLine(
        Offset(card.left + w * 0.30, card.top + h * 0.28),
        Offset(card.right - w * 0.08, card.top + h * 0.28),
        stroke(dark.withValues(alpha: 0.55), 3));
    canvas.drawLine(
        Offset(card.left + w * 0.30, card.top + h * 0.37),
        Offset(card.right - w * 0.16, card.top + h * 0.37),
        stroke(dark.withValues(alpha: 0.3), 2.5));

    // Attendance checklist rows in the lower half of the card.
    for (int i = 0; i < 3; i++) {
      final y = card.top + h * 0.50 + i * h * 0.10;
      final boxCenter = Offset(card.left + w * 0.10, y);
      final box = Rect.fromCenter(center: boxCenter, width: w * 0.06, height: w * 0.06);
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(2)),
          fill(i < 2 ? accent : Colors.white));
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(2)),
          stroke(dark.withValues(alpha: 0.35), 1.5));
      if (i < 2) {
        final check = Path()
          ..moveTo(box.left + box.width * 0.2, box.center.dy)
          ..lineTo(box.left + box.width * 0.45, box.bottom - box.height * 0.2)
          ..lineTo(box.right - box.width * 0.15, box.top + box.height * 0.2);
        canvas.drawPath(check, stroke(Colors.white, 1.8));
      }
      canvas.drawLine(Offset(card.left + w * 0.18, y), Offset(card.right - w * 0.10, y),
          stroke(dark.withValues(alpha: 0.22), 2.5));
    }
  }

  @override
  bool shouldRepaint(covariant _WorkerPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Community — two overlapping people with a chat bubble.
// ---------------------------------------------------------------------------
class _CommunityPainter extends CustomPainter with _IllustrationStyle {
  _CommunityPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    void person(Offset headCenter, double scale, Color c) {
      canvas.drawCircle(headCenter, w * 0.14 * scale, fill(c));
      final body = Rect.fromCenter(
          center: headCenter + Offset(0, h * 0.28 * scale),
          width: w * 0.42 * scale,
          height: h * 0.30 * scale);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(w * 0.14 * scale)),
          fill(c));
    }

    // Back person (smaller, offset right).
    person(Offset(w * 0.64, h * 0.42), 0.85, accent.withValues(alpha: 0.5));
    // Front person.
    person(Offset(w * 0.38, h * 0.50), 1.0, accent);

    // Chat bubble with dots, floating top-right.
    final bubble = Rect.fromLTWH(w * 0.56, h * 0.08, w * 0.36, h * 0.22);
    final bubbleRRect =
        RRect.fromRectAndRadius(bubble, const Radius.circular(10));
    canvas.drawRRect(bubbleRRect, fill(Colors.white));
    canvas.drawRRect(bubbleRRect, stroke(dark.withValues(alpha: 0.25), 1.5));
    final tail = Path()
      ..moveTo(bubble.left + w * 0.06, bubble.bottom)
      ..lineTo(bubble.left + w * 0.02, bubble.bottom + h * 0.05)
      ..lineTo(bubble.left + w * 0.12, bubble.bottom)
      ..close();
    canvas.drawPath(tail, fill(Colors.white));
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(bubble.left + w * (0.10 + i * 0.09), bubble.center.dy),
          w * 0.02,
          fill(dark));
    }
  }

  @override
  bool shouldRepaint(covariant _CommunityPainter old) => old.accent != accent;
}

// ---------------------------------------------------------------------------
// Articles — a folded newspaper: masthead bar, byline rule, text columns and
// a dog-eared corner.
// ---------------------------------------------------------------------------
class _ArticlePainter extends CustomPainter with _IllustrationStyle {
  _ArticlePainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(accent, Colors.black, 0.22)!;

    final page = Rect.fromLTWH(w * 0.14, h * 0.10, w * 0.72, h * 0.80);
    const fold = 0.16; // fraction of the page cut off for the dog-ear.

    final paper = Path()
      ..moveTo(page.left, page.top)
      ..lineTo(page.right - page.width * fold, page.top)
      ..lineTo(page.right, page.top + page.height * fold)
      ..lineTo(page.right, page.bottom)
      ..lineTo(page.left, page.bottom)
      ..close();
    canvas.drawPath(paper, fill(Colors.white));
    canvas.drawPath(paper, stroke(dark.withValues(alpha: 0.25), 1.5));

    // The folded-back corner triangle.
    final corner = Path()
      ..moveTo(page.right - page.width * fold, page.top)
      ..lineTo(page.right - page.width * fold, page.top + page.height * fold)
      ..lineTo(page.right, page.top + page.height * fold)
      ..close();
    canvas.drawPath(corner, fill(dark.withValues(alpha: 0.18)));
    canvas.drawPath(corner, stroke(dark.withValues(alpha: 0.25), 1.5));

    // Masthead bar (the newspaper's title strip).
    final masthead = Rect.fromLTWH(
        page.left + w * 0.06, page.top + h * 0.07, page.width - w * 0.12, h * 0.09);
    canvas.drawRRect(
        RRect.fromRectAndRadius(masthead, const Radius.circular(2)), fill(accent));

    // A rule under the masthead.
    canvas.drawLine(
        Offset(page.left + w * 0.06, masthead.bottom + h * 0.03),
        Offset(page.right - w * 0.06, masthead.bottom + h * 0.03),
        stroke(dark.withValues(alpha: 0.35), 1.5));

    // Two text columns below.
    final colTop = masthead.bottom + h * 0.09;
    final colLeft = Rect.fromLTWH(
        page.left + w * 0.06, colTop, (page.width - w * 0.16) / 2, h * 0.02);
    final colRight = Rect.fromLTWH(
        colLeft.right + w * 0.04, colTop, colLeft.width, h * 0.02);
    for (int i = 0; i < 5; i++) {
      final dy = i * h * 0.075;
      final shrinkLeft = i == 4 ? colLeft.width * 0.4 : 0.0;
      final shrinkRight = i == 3 ? colRight.width * 0.5 : 0.0;
      canvas.drawLine(
          Offset(colLeft.left, colLeft.top + dy),
          Offset(colLeft.right - shrinkLeft, colLeft.top + dy),
          stroke(accent.withValues(alpha: 0.5), 2.5));
      if (colTop + dy < page.bottom - h * 0.05) {
        canvas.drawLine(
            Offset(colRight.left, colRight.top + dy),
            Offset(colRight.right - shrinkRight, colRight.top + dy),
            stroke(accent.withValues(alpha: 0.5), 2.5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArticlePainter old) => old.accent != accent;
}
