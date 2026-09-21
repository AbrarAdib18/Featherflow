import 'package:flutter/material.dart';

import '../format/currency.dart';
import '../theme/theme.dart';

/// Shared marketplace/catalogue product card — used by both the pharmacy
/// staff catalogue and the farmer-facing marketplace so both surfaces render
/// the exact same visual structure (image on top with optional badges,
/// delivery estimate, name, price row, unit/min-qty, bottom-aligned action
/// button) instead of two divergent one-off layouts.
///
/// Fixed height (via [ResponsiveProductGrid]'s `mainAxisExtent`) regardless
/// of which optional fields are present — badges overlay the image instead
/// of pushing layout down, and the action button is pinned to the bottom via
/// a trailing [Spacer], so cards never overflow and always line up.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.unit,
    required this.actionLabel,
    this.imageUrl,
    this.fallbackIcon = Icons.inventory_2_outlined,
    this.discountLabel,
    this.mostPicked = false,
    this.topSeller = false,
    this.deliveryText,
    this.subtitle,
    this.previousPrice,
    this.minQuantity = 1,
    this.stockLabel,
    this.inStock = true,
    this.quantitySelector,
    this.onAction,
    this.actionColor = AppColors.error,
    this.onTap,
    this.trailingActions = const [],
    this.extra,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final String? discountLabel;
  final bool mostPicked;
  final bool topSeller;
  final String? deliveryText;
  final String name;
  final String? subtitle;
  final double price;
  final double? previousPrice;
  final String unit;
  final int minQuantity;
  final String? stockLabel;
  final bool inStock;
  final Widget? quantitySelector;
  final VoidCallback? onAction;
  final String actionLabel;
  // Red (the default) is the "Add to Bag" call-to-action color in the
  // farmer marketplace, matching the reference design. It is NOT
  // appropriate for a neutral action like the pharmacy staff catalogue's
  // "Edit" button — callers there should pass the app's normal accent color
  // instead, or a red-looking "Edit" reads as a destructive/alarming action.
  final Color actionColor;
  final VoidCallback? onTap;
  final List<Widget> trailingActions;
  /// Extra compact content (e.g. status chips) shown right after the
  /// name/subtitle, before the price row. Optional so most callers don't pay
  /// for layout they don't use.
  final Widget? extra;

  static const double imageHeight = 110;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = previousPrice != null && previousPrice! > price;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.expand(
                        child: (imageUrl != null && imageUrl!.isNotEmpty)
                            ? Image.network(imageUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _fallback())
                            : _fallback(),
                      ),
                    ),
                    if (discountLabel != null)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _ribbon(discountLabel!, AppColors.error),
                      ),
                    if (mostPicked)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _pill('Most Picked', AppColors.secondary),
                      ),
                    if (topSeller)
                      Positioned(
                        right: 6,
                        top: mostPicked ? 30 : 6,
                        child: _pill('Top Seller', AppColors.primary),
                      ),
                    // Exactly one "Out of stock" label, unconditionally on
                    // top of whatever's underneath (real photo, plain
                    // fallback icon, or a broken/unreachable image URL that
                    // fell through to the fallback via errorBuilder) — never
                    // gated on whether an imageUrl string happens to be set,
                    // or a failed image would show this AND the fallback's
                    // own label both, doubled.
                    if (!inStock)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Out of stock',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (deliveryText != null)
                Text(deliveryText!,
                    style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
              ],
              if (extra != null) ...[
                const SizedBox(height: 3),
                extra!,
              ],
              const SizedBox(height: 4),
              Row(children: [
                Text(taka(price), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.error)),
                if (hasDiscount) ...[
                  const SizedBox(width: 6),
                  Text(taka(previousPrice!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
                ],
              ]),
              Text('per $unit${minQuantity > 1 ? ' · min $minQuantity' : ''}',
                  style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
              if (stockLabel != null) ...[
                const SizedBox(height: 2),
                Text(stockLabel!,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: inStock ? AppColors.secondary : AppColors.error)),
              ],
              if (quantitySelector != null) ...[
                const SizedBox(height: 4),
                quantitySelector!,
              ],
              const Spacer(),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: FilledButton(
                      onPressed: inStock ? onAction : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: actionColor,
                        disabledBackgroundColor: AppColors.disabled,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      child: Text(actionLabel),
                    ),
                  ),
                ),
                ...trailingActions,
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // Icon only — the "Out of stock" label (when applicable) is always drawn
  // by the single overlay above instead, so there is never more than one
  // label regardless of whether this renders because there's no photo at
  // all, or because a real photo URL failed to load.
  Widget _fallback() => Container(
        color: AppColors.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(fallbackIcon, size: 30, color: AppColors.onSurfaceVariant),
      );

  Widget _ribbon(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomRight: Radius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w700)),
      );
}

/// Responsive product grid — as many columns as fit at [maxCardWidth] each,
/// so it's naturally multi-column on desktop, fewer on tablet, one or two on
/// a narrow phone/320px width, with no manual breakpoint list to maintain.
/// [cardHeight] is fixed regardless of column width, which is what keeps
/// every [ProductCard] the same height without per-card aspect-ratio math.
class ResponsiveProductGrid extends StatelessWidget {
  const ResponsiveProductGrid({
    super.key,
    required this.children,
    this.maxCardWidth = 200,
    this.cardHeight = 300,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(12),
  });

  final List<Widget> children;
  final double maxCardWidth;
  final double cardHeight;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCardWidth,
        mainAxisExtent: cardHeight,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
    );
  }
}
