import 'package:flutter/material.dart';
import '../models/article.dart';

/// Article thumbnail: a fixed-height, browser-cached network image that falls
/// back to the category gradient while loading or on error. Always occupies
/// exactly [height] so it is safe inside any flex layout.
class ArticleImage extends StatelessWidget {
  final Article article;
  final double height;
  final Widget? overlay;

  const ArticleImage({
    super.key,
    required this.article,
    this.height = 150,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _image(context),
          if (overlay != null) overlay!,
        ],
      ),
    );
  }

  Widget _image(BuildContext context) {
    final gradient = _GradientPlaceholder(category: article.category);
    final url = article.imageUrl;
    if (url == null || url.isEmpty) return gradient;
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 800,
      gaplessPlayback: true,
      frameBuilder: (ctx, child, frame, wasSync) =>
          (wasSync || frame != null) ? child : gradient,
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : gradient,
      errorBuilder: (ctx, error, stack) => gradient,
    );
  }
}

class _GradientPlaceholder extends StatelessWidget {
  final ArticleCategory category;

  const _GradientPlaceholder({required this.category});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: ppCategoryGradient(category)),
      child: Center(
        child: Icon(
          _categoryIcon(category),
          size: 48,
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

IconData _categoryIcon(ArticleCategory category) {
  switch (category) {
    case ArticleCategory.researchPaper:
      return Icons.science_outlined;
    case ArticleCategory.diseaseStudy:
      return Icons.medical_services_outlined;
    case ArticleCategory.news:
      return Icons.newspaper_outlined;
    case ArticleCategory.innovation:
      return Icons.lightbulb_outline;
    case ArticleCategory.feedStudy:
      return Icons.eco_outlined;
    case ArticleCategory.marketReport:
      return Icons.bar_chart_outlined;
    case ArticleCategory.teamFeatherflow:
      return Icons.verified_outlined;
  }
}
