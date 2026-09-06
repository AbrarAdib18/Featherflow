import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import 'category_badge.dart';
import 'verified_badge.dart';
import 'author_avatar.dart';

PhosphorIconData _featuredCategoryIcon(ArticleCategory cat) {
  switch (cat) {
    case ArticleCategory.researchPaper:
      return PhosphorIcons.microscope();
    case ArticleCategory.diseaseStudy:
      return PhosphorIcons.firstAid();
    case ArticleCategory.news:
      return PhosphorIcons.newspaper();
    case ArticleCategory.innovation:
      return PhosphorIcons.lightbulb();
    case ArticleCategory.feedStudy:
      return PhosphorIcons.leaf();
    case ArticleCategory.marketReport:
      return PhosphorIcons.chartBar();
    case ArticleCategory.teamFeatherflow:
      return PhosphorIcons.feather();
  }
}

class FeaturedArticleCard extends StatefulWidget {
  final Article article;
  final VoidCallback onTap;
  final ValueChanged<Article>? onBookmarkToggle;

  const FeaturedArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.onBookmarkToggle,
  });

  @override
  State<FeaturedArticleCard> createState() => _FeaturedArticleCardState();
}

class _FeaturedArticleCardState extends State<FeaturedArticleCard> {
  late bool _bookmarked = widget.article.bookmarked;

  @override
  void didUpdateWidget(covariant FeaturedArticleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.id != widget.article.id) {
      _bookmarked = widget.article.bookmarked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: PPColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: PPColors.bg,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: PPColors.border, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImagePlaceholder(category: a.category),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CategoryBadge(category: a.category),
                              if (a.isVerified) ...[
                                const SizedBox(width: 6),
                                const VerifiedBadge(),
                              ],
                              const Spacer(),
                              PhosphorIcon(PhosphorIcons.clock(), size: 11, color: PPColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                '${a.readTimeMinutes} min read',
                                style: ppLabel(size: 11, color: PPColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            a.title,
                            style: ppTitle(size: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            a.summary,
                            style: ppBody(size: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              AuthorAvatar(name: a.author, radius: 13),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.author,
                                      style: ppLabel(size: 11, weight: FontWeight.w600, color: PPColors.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${a.source} · ${ppTimeAgo(a.date)}',
                                      style: ppLabel(size: 10, color: PPColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _bookmarked = !_bookmarked);
                                  widget.onBookmarkToggle?.call(a);
                                },
                                child: PhosphorIcon(
                                  _bookmarked
                                      ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                                      : PhosphorIcons.bookmarkSimple(),
                                  size: 18,
                                  color: _bookmarked ? PPColors.primary : PPColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              PhosphorIcon(
                                PhosphorIcons.shareNetwork(),
                                size: 18,
                                color: PPColors.textSecondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final ArticleCategory category;

  const _ImagePlaceholder({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(gradient: ppCategoryGradient(category)),
      child: Stack(
        children: [
          Center(
            child: PhosphorIcon(
              _featuredCategoryIcon(category),
              size: 56,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PPColors.amber,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Featured',
                style: ppLabel(size: 11, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
