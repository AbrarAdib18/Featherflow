import 'package:flutter/material.dart';

/// Shared image treatment for marketplace/catalogue surfaces (feed products,
/// feed company logos/covers): consistent aspect ratio, a loading spinner
/// while the network image decodes, and an icon-based placeholder both
/// before any image exists and if loading fails — never a blank box.
class CatalogueImage extends StatelessWidget {
  const CatalogueImage({
    super.key,
    required this.url,
    this.fallbackIcon = Icons.grass,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.iconColor,
  });

  final String? url;
  final IconData fallbackIcon;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0xFFE8F0E9);
    final fg = iconColor ?? const Color(0xFF2E7D32);
    final radius = borderRadius ?? BorderRadius.circular(10);
    final hasUrl = url != null && url!.trim().isNotEmpty;

    Widget placeholder() => Container(
          color: bg,
          alignment: Alignment.center,
          child: Icon(fallbackIcon, color: fg, size: 32),
        );

    return ClipRRect(
      borderRadius: radius,
      child: hasUrl
          ? Image.network(
              url!,
              fit: fit,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: bg,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stack) => placeholder(),
            )
          : placeholder(),
    );
  }
}
