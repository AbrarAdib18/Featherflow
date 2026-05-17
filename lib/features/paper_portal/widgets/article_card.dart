import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import 'category_badge.dart';
import 'verified_badge.dart';
import 'author_avatar.dart';

PhosphorIconData _cardCategoryIcon(ArticleCategory cat) {
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

class ArticleCard extends StatefulWidget {
  final Article article;
  final VoidCallback onTap;
  final bool compact;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  bool _bookmarked = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: ppCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.compact) _CardImagePlaceholder(category: a.category),
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
                      if (currentUserRole == UserRole.admin ||
                          currentUserRole == UserRole.researcher)
                        _CardMenu(article: a),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    a.title,
                    style: ppTitle(size: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(height: 6),
                    Text(
                      a.summary,
                      style: ppBody(size: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _bookmarked = !_bookmarked),
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
    );
  }
}

class _CardImagePlaceholder extends StatelessWidget {
  final ArticleCategory category;

  const _CardImagePlaceholder({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(gradient: ppCategoryGradient(category)),
      child: Center(
        child: PhosphorIcon(
          _cardCategoryIcon(category),
          size: 56,
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  final Article article;

  const _CardMenu({required this.article});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: PhosphorIcon(PhosphorIcons.dotsThree(), size: 18, color: PPColors.textSecondary),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Text('Edit', style: ppLabel(size: 13, color: PPColors.textPrimary)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: ppLabel(size: 13, color: Colors.red)),
        ),
      ],
    );
  }
}
