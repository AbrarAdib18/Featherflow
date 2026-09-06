import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import '../../research/data/services/research_api_service.dart';
import '../widgets/category_badge.dart';
import '../widgets/author_avatar.dart';

/// Falls back to a generic category-based prompt only when the author did
/// not write a farmer_summary for this article.
String _genericTakeaway(Article a) {
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
  late Article _article = widget.article;
  late bool _bookmarked = widget.article.bookmarked;
  List<Article> _related = [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await ResearchApiService.instance.articleDetail(
          articleCategoryToApi(_article.category), _article.id);
      if (!mounted) return;
      setState(() {
        _article = Article.fromJson(data);
        _bookmarked = _article.bookmarked;
      });
    } catch (_) {
      // Keep showing the summary passed in from the feed if the refetch fails.
    }
    try {
      final feed = await ResearchApiService.instance
          .articleFeed(type: articleCategoryToApi(_article.category));
      final same = (feed['results'] as List)
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((a) => a.id != _article.id)
          .take(3)
          .toList();
      if (!mounted) return;
      setState(() => _related = same);
    } catch (_) {
      // Related articles are a nice-to-have; ignore failures silently here.
    }
  }

  Future<void> _openReportDialog() async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ReportContentDialog(articleId: _article.id),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.')));
    }
  }

  Future<void> _toggleBookmark() async {
    setState(() => _bookmarked = !_bookmarked);
    try {
      await ResearchApiService.instance.toggleBookmark(_article.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _bookmarked = !_bookmarked);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;

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
                onPressed: _toggleBookmark,
              ),
              IconButton(
                icon: PhosphorIcon(PhosphorIcons.shareNetwork(), color: Colors.white, size: 22),
                onPressed: () {},
              ),
              PopupMenuButton<String>(
                icon: PhosphorIcon(PhosphorIcons.dotsThree(), color: Colors.white, size: 22),
                onSelected: (value) {
                  if (value == 'report') _openReportDialog();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'report', child: Text('Report content')),
                ],
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
                if ((a.body ?? '').trim().isNotEmpty) _BodySection(body: a.body!),
                _KeyTakeawayCard(insight: a.farmerSummary ?? _genericTakeaway(a)),
                if (a.references.isNotEmpty) _ReferencesSection(references: a.references),
                if (_related.isNotEmpty)
                  _RelatedArticlesRow(currentArticle: a, related: _related),
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
  final List<String> references;

  const _ReferencesSection({required this.references});

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
          ...references.map(
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
  final List<Article> related;

  const _RelatedArticlesRow({required this.currentArticle, required this.related});

  @override
  Widget build(BuildContext context) {
    final articles = related;
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

class _ReportContentDialog extends StatefulWidget {
  final String articleId;
  const _ReportContentDialog({required this.articleId});

  @override
  State<_ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends State<_ReportContentDialog> {
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'A reason is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ResearchApiService.instance.reportContent(widget.articleId, _reasonCtrl.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report this content'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Why are you reporting this?',
                hintText: 'e.g. spam, misinformation, harmful advice',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}
