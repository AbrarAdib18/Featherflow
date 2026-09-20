import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import 'farmer_feature_illustrations.dart';

/// A poultry-themed feature card for the farmer dashboard's quick-action
/// grid: title/subtitle anchored top-right, a vector illustration anchored
/// bottom-left, on a white card. Each card gets its own hand-drawn pictogram
/// (`farmer_feature_illustrations.dart`) matching its feature — a wallet for
/// Cost Management, a stethoscope for Find Vet, and so on — recolored to the
/// card's accent, rather than a shared generic icon or an imported photo.
class FarmerFeatureCard extends StatelessWidget {
  const FarmerFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.onTap,
    this.backgroundColor = Colors.white,
    this.accent = AppColors.primary,
    this.badgeCount = 0,
    this.compact = false,
    this.semanticLabel,
  });

  final String title;
  final String subtitle;

  /// Which pictogram this card shows, e.g. [FeatureIllustrationKind.pharmacy].
  final FeatureIllustrationKind illustration;

  final VoidCallback onTap;
  final Color backgroundColor;

  /// Used for the notification badge and to recolor the illustration.
  final Color accent;

  final int badgeCount;

  /// Compact mode: smaller illustration/text for narrow layouts (e.g. a 3+
  /// column grid on a wide desktop, or an embedded card list) without
  /// duplicating this widget.
  final bool compact;

  /// Falls back to "$title. $subtitle" when omitted.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: const Color(0xFF0B1F17),
      fontSize: compact ? 14 : 16,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: 0.1,
    );
    final subtitleStyle = TextStyle(
      color: Colors.black54,
      fontSize: compact ? 10 : 11,
      height: 1.25,
    );

    return Semantics(
      button: true,
      // A semantics boundary: without it, the descendant Text widgets' own
      // semantics nodes merge into this label, duplicating the title and
      // subtitle after it instead of exposing exactly one clean label.
      container: true,
      excludeSemantics: true,
      label: semanticLabel ?? '$title. $subtitle',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: compact ? 160 : 190,
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.sm : AppSpacing.sm,
            compact ? AppSpacing.sm : AppSpacing.sm,
            compact ? AppSpacing.sm : AppSpacing.sm,
            0,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: const Color(0xFFEAEFED)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          // Column, not Stack: title/subtitle occupy their own top strip so
          // they never compete for space with the image, which then owns the
          // full-width bottom strip — matches the reference layout exactly
          // (text block above, image anchored bottom-left of its own row)
          // without needing to guess how much horizontal room the image
          // needs next to variable-length text.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (badgeCount > 0) ...[
                    _Badge(count: badgeCount, color: accent),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(title,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle),
              // The illustration sits in the remaining space, anchored
              // bottom-left, but drawn at a fraction of that space rather
              // than filling it — a full-bleed pictogram read as oversized
              // for a small dashboard tile.
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.maxWidth < constraints.maxHeight
                          ? constraints.maxWidth
                          : constraints.maxHeight;
                      return FeatureIllustration(
                        kind: illustration,
                        accent: accent,
                        size: side * 0.68,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.fullAll),
      child: Text(count > 99 ? '99+' : '$count',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}
