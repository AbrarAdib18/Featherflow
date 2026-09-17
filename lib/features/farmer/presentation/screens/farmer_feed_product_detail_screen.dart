import 'package:flutter/material.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/widgets/catalogue_image.dart';
import '../../data/feed_marketplace_service.dart';

/// Full feed-product detail — image/gallery, company, bird/feed stage,
/// nutrition/ingredients, package size, price, stock, minimum order
/// quantity, description, and an add-to-cart control. Reached only by
/// tapping an approved product card in the marketplace; never a route a
/// farmer can navigate to directly with an arbitrary/unapproved id.
class FarmerFeedProductDetailScreen extends StatefulWidget {
  const FarmerFeedProductDetailScreen({super.key, required this.product, required this.onAddToCart});
  final FeedMarketProduct product;
  final void Function(FeedMarketProduct product, int quantity) onAddToCart;

  @override
  State<FarmerFeedProductDetailScreen> createState() => _FarmerFeedProductDetailScreenState();
}

class _FarmerFeedProductDetailScreenState extends State<FarmerFeedProductDetailScreen> {
  late int _quantity = widget.product.minOrderQuantity;
  int _galleryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final images = [if (p.imageUrl.isNotEmpty) p.imageUrl, ...p.galleryUrls];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Product details', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: images.isEmpty
              ? const CatalogueImage(url: null)
              : CatalogueImage(url: images[_galleryIndex]),
        ),
        if (images.length > 1)
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => setState(() => _galleryIndex = i),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: i == _galleryIndex ? AppColors.primary : Colors.transparent, width: 2),
                  ),
                  child: CatalogueImage(url: images[i], borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 4),
            Row(children: [
              if (p.companyLogoUrl.isNotEmpty) ...[
                SizedBox(width: 20, height: 20, child: CatalogueImage(url: p.companyLogoUrl, borderRadius: BorderRadius.circular(10))),
                const SizedBox(width: 6),
              ],
              Text(p.companyName, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('Bird: ${p.birdType}'),
              _chip('Stage: ${p.feedType}'),
              _chip('Unit: ${p.unit.replaceAll('_', ' ')}'),
              if (!p.inStock) _chip('Out of stock', color: AppColors.error),
            ]),
            const SizedBox(height: 12),
            Text('৳${p.price.toStringAsFixed(0)} / ${p.unit.replaceAll('_', ' ')}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 22)),
            Text('${p.stockQuantity} in stock · min order ${p.minOrderQuantity}',
                style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(p.description),
            ],
            if (p.ingredients.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Ingredients', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(p.ingredients),
            ],
            if (p.nutritionalInfo.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Nutritional information', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final entry in p.nutritionalInfo.entries)
                if (entry.value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${_labelize(entry.key)}: ${entry.value}', style: const TextStyle(fontSize: 13)),
                  ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _quantity > p.minOrderQuantity ? () => setState(() => _quantity--) : null,
                  ),
                  Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _quantity < p.stockQuantity ? () => setState(() => _quantity++) : null,
                  ),
                ]),
              ),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: p.inStock
                      ? () {
                          widget.onAddToCart(p, _quantity);
                          Navigator.pop(context);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(p.inStock ? 'Add to cart' : 'Out of stock'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  String _labelize(String key) => key.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  Widget _chip(String label, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? AppColors.secondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (color ?? AppColors.secondary).withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color ?? AppColors.secondary, fontWeight: FontWeight.w600)),
      );
}
