import 'package:flutter/material.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class ResearchAnalyticsScreen extends StatelessWidget {
  const ResearchAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Analytics & Records',
      module: ResearchModule.analytics,
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        // NOT const — see research_dashboard_screen: a const child never rebuilds.
        // ignore: prefer_const_constructors
        builder: (context, _) => _AnalyticsBody(),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody();

  @override
  Widget build(BuildContext context) {
    final session = ResearchSession.instance;
    final papers = session.papers;
    final published =
        papers.where((p) => p.status == PaperStatus.published).toList()
          ..sort((a, b) => b.views.compareTo(a.views));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OverviewGrid(
            totalPublished:
                papers.where((p) => p.status == PaperStatus.published).length,
            totalViews: session.totalViews,
            totalDownloads: session.totalDownloads,
            totalBookmarks: session.totalBookmarks,
          ),
          const SizedBox(height: 18),
          _PerPaperStatsCard(papers: papers),
          const SizedBox(height: 18),
          _TopPapersCard(published: published),
          const SizedBox(height: 18),
          _PublicationTimelineCard(papers: papers),
          const SizedBox(height: 18),
          _ExportCard(),
        ],
      ),
    );
  }
}

// ── Responsive overview grid ──────────────────────────────────────────────────

class _OverviewGrid extends StatelessWidget {
  final int totalPublished;
  final int totalViews;
  final int totalDownloads;
  final int totalBookmarks;

  const _OverviewGrid({
    required this.totalPublished,
    required this.totalViews,
    required this.totalDownloads,
    required this.totalBookmarks,
  });

  String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final profile = ResearchSession.instance.profile;

    final items = [
      _StatItem(
          value: '$totalPublished',
          label: 'Published',
          icon: Icons.check_circle_outline,
          color: RColors.published),
      _StatItem(
          value: _fmt(totalViews),
          label: 'Total Views',
          icon: Icons.visibility_outlined,
          color: RColors.accepted),
      _StatItem(
          value: _fmt(totalDownloads),
          label: 'Downloads',
          icon: Icons.download_outlined,
          color: RColors.secondary),
      _StatItem(
          value: '${profile.pendingReviewCount}',
          label: 'Pending Review',
          icon: Icons.hourglass_empty,
          color: RColors.underReview),
      _StatItem(
          value: '$totalBookmarks',
          label: 'Bookmarks',
          icon: Icons.bookmark_outline,
          color: RColors.draft),
      _StatItem(
          value: '${profile.needsRevisionCount}',
          label: 'Needs Revision',
          icon: Icons.rate_review_outlined,
          color: RColors.needsRevision),
      _StatItem(
          value: '${profile.totalPublications}',
          label: 'All Publications',
          icon: Icons.article_outlined,
          color: RColors.textSecondary),
      _StatItem(
          value: '${profile.yearsExperience}y',
          label: 'Years Active',
          icon: Icons.history_edu_outlined,
          color: RColors.textSecondary),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth < 480
            ? 2
            : constraints.maxWidth < 760
                ? 3
                : 4;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _StatCard(item: items[i]),
        );
      },
    );
  }
}

class _StatItem {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final _StatItem item;
  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(item.icon, color: item.color, size: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: item.color,
                ),
              ),
              Text(
                item.label,
                style: const TextStyle(
                    fontSize: 11, color: RColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Per-paper stats (scrollable table) ────────────────────────────────────────

class _PerPaperStatsCard extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _PerPaperStatsCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    final withStats =
        papers.where((p) => p.views > 0 || p.downloads > 0).toList()
          ..sort((a, b) => b.views.compareTo(a.views));

    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'Per-Paper Statistics',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          if (withStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Statistics will appear once papers receive views.',
                style:
                    TextStyle(color: RColors.textSecondary, fontSize: 13),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 240,
                            child: Text(
                              'Title',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: RColors.textSecondary,
                              ),
                            ),
                          ),
                          _TableHeader('Views', 70),
                          _TableHeader('Downloads', 90),
                          _TableHeader('Bookmarks', 90),
                          _TableHeader('Status', 110),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: RColors.divider),
                    ...withStats.map((p) => _PaperStatRow(paper: p)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String label;
  final double width;
  // ignore: prefer_const_constructors_in_immutables
  const _TableHeader(this.label, this.width);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: RColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _PaperStatRow extends StatelessWidget {
  final ResearchPaper paper;
  const _PaperStatRow({required this.paper});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: RColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Text(
              paper.title,
              style: const TextStyle(
                fontSize: 12,
                color: RColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _TableCell('${paper.views}', 70, RColors.accepted),
          _TableCell('${paper.downloads}', 90, RColors.secondary),
          _TableCell('${paper.bookmarks}', 90, RColors.underReview),
          SizedBox(
            width: 110,
            child: Center(child: PaperStatusChip(status: paper.status)),
          ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String value;
  final double width;
  final Color color;
  const _TableCell(this.value, this.width, this.color);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Top papers ────────────────────────────────────────────────────────────────

class _TopPapersCard extends StatelessWidget {
  final List<ResearchPaper> published;
  const _TopPapersCard({required this.published});

  @override
  Widget build(BuildContext context) {
    if (published.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star_outline, size: 17, color: Color(0xFFFFC107)),
              SizedBox(width: 8),
              Text(
                'Most-Read Published Papers',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: RColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...published
              .take(3)
              .toList()
              .asMap()
              .entries
              .map((e) => _TopPaperRow(paper: e.value, rank: e.key + 1)),
        ],
      ),
    );
  }
}

class _TopPaperRow extends StatelessWidget {
  final ResearchPaper paper;
  final int rank;
  const _TopPaperRow({required this.paper, required this.rank});

  @override
  Widget build(BuildContext context) {
    final rankColor = rank == 1
        ? const Color(0xFFFFC107)
        : rank == 2
            ? const Color(0xFF9E9E9E)
            : const Color(0xFFCD7F32);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RColors.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: rankColor, shape: BoxShape.circle),
            child: Center(
              child: Text(
                '#$rank',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paper.title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (paper.journal != null)
                  Text(
                    paper.journal!,
                    style: const TextStyle(
                        fontSize: 11,
                        color: RColors.textSecondary,
                        fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${paper.views} views',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RColors.accepted)),
              Text('${paper.downloads} dl',
                  style:
                      const TextStyle(fontSize: 11, color: RColors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Publication timeline ──────────────────────────────────────────────────────

class _PublicationTimelineCard extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _PublicationTimelineCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    final sorted = papers.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'Publication Timeline',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: sorted
                  .take(5)
                  .map((p) => _TimelineRow(paper: p))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final ResearchPaper paper;
  const _TimelineRow({required this.paper});

  @override
  Widget build(BuildContext context) {
    final (_, fg, _) = paperStatusColors(paper.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
              Container(width: 2, height: 28, color: RColors.divider),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paper.title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _formatDate(paper.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Text(' · ',
                        style: TextStyle(color: RColors.grey)),
                    Text(
                      paper.status.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: fg,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

// ── Export card ───────────────────────────────────────────────────────────────

class _ExportCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export & Citation',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                _ExportBtn(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF Report',
                  color: RColors.needsRevision,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'PDF export requires the pdf package. Add it to pubspec.yaml.')),
                  ),
                ),
                _ExportBtn(
                  icon: Icons.format_quote_outlined,
                  label: 'Citations',
                  color: RColors.accepted,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Citation export coming soon.')),
                  ),
                ),
                _ExportBtn(
                  icon: Icons.table_chart_outlined,
                  label: 'CSV Export',
                  color: RColors.secondary,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV export coming soon.')),
                  ),
                ),
              ];

              if (constraints.maxWidth < 420) {
                return Column(
                  children: buttons
                      .map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(width: double.infinity, child: b)))
                      .toList(),
                );
              }
              return Row(
                children: buttons
                    .expand((b) => [Expanded(child: b), const SizedBox(width: 10)])
                    .take(buttons.length * 2 - 1)
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ExportBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
