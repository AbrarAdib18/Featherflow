import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';

class TeamPostBanner extends StatelessWidget {
  final List<Article> articles;
  final void Function(Article) onTap;

  const TeamPostBanner({super.key, required this.articles, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: PPColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
                    size: 13, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  'FROM TEAM FEATHERFLOW',
                  style: ppLabel(
                    size: 10,
                    weight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          ...articles.map((a) => _BannerItem(article: a, onTap: () => onTap(a))),
        ],
      ),
    );
  }
}

class _BannerItem extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;

  const _BannerItem({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.title,
              style: ppTitle(size: 14, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              article.summary,
              style: ppBody(size: 12, color: Colors.white70),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  ppTimeAgo(article.date),
                  style: ppLabel(size: 11, color: Colors.white54),
                ),
                const SizedBox(width: 8),
                Text(
                  '${article.readTimeMinutes} min read',
                  style: ppLabel(size: 11, color: Colors.white54),
                ),
                const Spacer(),
                Text(
                  'Read more',
                  style: ppLabel(
                    size: 12,
                    weight: FontWeight.w600,
                    color: PPColors.accent,
                  ),
                ),
                const SizedBox(width: 3),
                PhosphorIcon(PhosphorIcons.arrowRight(), size: 12, color: PPColors.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
