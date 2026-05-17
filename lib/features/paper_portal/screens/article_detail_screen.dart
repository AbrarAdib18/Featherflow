import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import '../data/demo_data.dart';
import '../widgets/category_badge.dart';
import '../widgets/author_avatar.dart';

const _dummyBody =
    'Poultry production continues to be a vital sector in South Asian agriculture, contributing significantly to protein security and rural livelihoods. This study presents findings from a comprehensive analysis conducted across multiple production systems in the region.\n\n'
    'Observations indicate that optimal environmental management, combined with evidence-based nutritional strategies, can significantly improve key performance indicators including feed conversion ratio, average daily gain, and mortality rate across different flock types.\n\n'
    'Data collected from participating farms over a 12-week period demonstrate consistent patterns in flock performance, with notable variations attributed to management practices, housing conditions, and input quality available to smallholder operators.\n\n'
    'Further research is recommended to validate these findings across a broader range of production environments and to identify context-specific recommendations for smallholder farmers operating under resource-constrained conditions.';

const _references = [
  '1. Ali, M.S. et al. (2024). Nutritional strategies for broiler performance in tropical climates. J. Poultry Sci. 61(2), 112–124.',
  '2. Rahman, A. & Hossain, F. (2025). Feed formulation and its impact on FCR in commercial flocks. Bangladesh J. Anim. Sci. 54(1), 33–41.',
  '3. FAO (2025). Livestock production systems in South Asia: Annual review. Food and Agriculture Organisation, Rome.',
  '4. WHO-FAO Joint Panel (2026). Biosecurity guidelines for commercial poultry: 2026 update. Technical Report Series No. 218.',
];

String _keyTakeaway(Article a) {
  switch (a.category) {
    case ArticleCategory.researchPaper:
      return 'Consider testing lysine supplementation during the starter phase to improve FCR on your farm.';
    case ArticleCategory.diseaseStudy:
      return 'Review your biosecurity plan and ensure all staff know the emergency culling protocol.';
    case ArticleCategory.innovation:
      return 'IoT ventilation control can meaningfully cut respiratory disease losses — worth piloting in one shed.';
    case ArticleCategory.marketReport:
      return 'Plan feed purchases ahead of Q3 to lock in current prices before projected increases.';
    case ArticleCategory.feedStudy:
      return 'A probiotic top-dress is low-cost and can improve egg quality scores in your layer flock.';
    case ArticleCategory.news:
      return 'Tighten entry biosecurity now — inspect all incoming stock documentation carefully.';
    case ArticleCategory.teamFeatherflow:
      return 'Update your Featherflow app to access the new batch tracking and feed cost tools.';
  }
}

PhosphorIconData _categoryIcon(ArticleCategory cat) {
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

String _categoryLabel(ArticleCategory cat) {
  switch (cat) {
    case ArticleCategory.researchPaper:
      return 'Research Paper';
    case ArticleCategory.news:
      return 'News';
    case ArticleCategory.innovation:
      return 'Innovation';
    case ArticleCategory.diseaseStudy:
      return 'Disease Study';
    case ArticleCategory.feedStudy:
      return 'Feed Study';
    case ArticleCategory.marketReport:
      return 'Market Report';
    case ArticleCategory.teamFeatherflow:
      return 'Team Featherflow';
  }
}

class ArticleDetailScreen extends StatefulWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool _bookmarked = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.article;

    return Scaffold(
      backgroundColor: PPColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: PPColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: PhosphorIcon(PhosphorIcons.arrowLeft(), color: Colors.white, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: PhosphorIcon(
                  _bookmarked
                      ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                      : PhosphorIcons.bookmarkSimple(),
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () => setState(() => _bookmarked = !_bookmarked),
              ),
              IconButton(
                icon: PhosphorIcon(PhosphorIcons.shareNetwork(), color: Colors.white, size: 22),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeroBackground(article: a),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorMetaStrip(article: a),
                const Divider(height: 1, color: PPColors.border),
                _AbstractBox(abstract: a.summary),
                _BodySection(body: a.body ?? _dummyBody),
                _KeyTakeawayCard(insight: _keyTakeaway(a)),
                const _ReferencesSection(),
                _RelatedArticlesRow(currentArticle: a),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  final Article article;

  const _HeroBackground({required this.article});

  @override
  Widget build(BuildContext context) {
    final a = article;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(gradient: ppCategoryGradient(a.category)),
        ),
        Center(
          child: PhosphorIcon(
            _categoryIcon(a.category),
            size: 130,
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _HeroChip(label: _categoryLabel(a.category)),
                    if (a.isVerified) ...[
                      const SizedBox(width: 6),
                      const _HeroChip(label: '✓  Verified'),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  a.title,
                  style: ppTitle(size: 20, color: Colors.white),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: ppLabel(size: 11, weight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

class _AuthorMetaStrip extends StatelessWidget {
  final Article article;

  const _AuthorMetaStrip({required this.article});

  @override
  Widget build(BuildContext context) {
    final a = article;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AuthorAvatar(name: a.author, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.author,
                  style: ppLabel(size: 13, weight: FontWeight.w600, color: PPColors.textPrimary),
                ),
                Text(a.source, style: ppLabel(size: 11, color: PPColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  PhosphorIcon(PhosphorIcons.calendarBlank(), size: 11, color: PPColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(ppFormatDate(a.date), style: ppLabel(size: 11, color: PPColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  PhosphorIcon(PhosphorIcons.clock(), size: 11, color: PPColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    '${a.readTimeMinutes} min read',
                    style: ppLabel(size: 11, color: PPColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AbstractBox extends StatelessWidget {
  final String abstract;

  const _AbstractBox({required this.abstract});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PPColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PPColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: PPColors.primary,
                margin: const EdgeInsets.only(right: 8),
              ),
              Text(
                'Abstract',
                style: ppLabel(size: 12, weight: FontWeight.w700, color: PPColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(abstract, style: ppBody(size: 14, color: PPColors.textPrimary)),
        ],
      ),
    );
  }
}

class _BodySection extends StatelessWidget {
  final String body;

  const _BodySection({required this.body});

  @override
  Widget build(BuildContext context) {
    final paragraphs = body.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paragraphs
            .map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(p.trim(), style: ppBody(size: 16, color: PPColors.textPrimary)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _KeyTakeawayCard extends StatelessWidget {
  final String insight;

  const _KeyTakeawayCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PPColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PPColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(PhosphorIcons.lightbulb(), color: PPColors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Key Takeaway for Farmers',
                  style: ppLabel(size: 12, weight: FontWeight.w700, color: PPColors.amberText),
                ),
                const SizedBox(height: 5),
                Text(insight, style: ppBody(size: 13, color: PPColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferencesSection extends StatelessWidget {
  const _ReferencesSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: PPColors.primary,
                margin: const EdgeInsets.only(right: 8),
              ),
              Text('References', style: ppTitle(size: 15, color: PPColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          ..._references.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(r, style: ppBody(size: 12, color: PPColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedArticlesRow extends StatelessWidget {
  final Article currentArticle;

  const _RelatedArticlesRow({required this.currentArticle});

  List<Article> get _articles {
    final same = demoArticles
        .where((a) => a.id != currentArticle.id && a.category == currentArticle.category)
        .take(3)
        .toList();
    if (same.length >= 3) return same;
    final others = demoArticles
        .where((a) => a.id != currentArticle.id && !same.any((s) => s.id == a.id))
        .take(3 - same.length)
        .toList();
    return [...same, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final articles = _articles;
    if (articles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Container(width: 3, height: 16, color: PPColors.primary),
              const SizedBox(width: 8),
              Text('Related Articles', style: ppTitle(size: 15, color: PPColors.textPrimary)),
            ],
          ),
        ),
        SizedBox(
          height: 252,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: articles.length,
            itemBuilder: (_, i) => _RelatedCard(
              article: articles[i],
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ArticleDetailScreen(article: articles[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;

  const _RelatedCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = article;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 195,
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: ppCardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 114,
              width: double.infinity,
              decoration: BoxDecoration(gradient: ppCategoryGradient(a.category)),
              child: Center(
                child: PhosphorIcon(
                  _categoryIcon(a.category),
                  size: 44,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryBadge(category: a.category),
                  const SizedBox(height: 6),
                  Text(
                    a.title,
                    style: ppTitle(size: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      PhosphorIcon(PhosphorIcons.clock(), size: 10, color: PPColors.textSecondary),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '${a.source} · ${ppTimeAgo(a.date)}',
                          style: ppLabel(size: 10, color: PPColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
