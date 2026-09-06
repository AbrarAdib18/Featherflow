import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class ResearchDashboardScreen extends StatelessWidget {
  const ResearchDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Dashboard',
      module: ResearchModule.dashboard,
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        builder: (context, _) => const _DashboardBody(),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    final session = ResearchSession.instance;
    final profile = session.profile;
    final papers = session.papers;
    final recentPapers = papers.take(3).toList();
    final publishedCount =
        papers.where((p) => p.status == PaperStatus.published).length;
    final pendingCount = papers
        .where((p) =>
            p.status == PaperStatus.underReview ||
            p.status == PaperStatus.accepted)
        .length;
    final needsRevisionCount =
        papers.where((p) => p.status == PaperStatus.needsRevision).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeCard(profile: profile),
          const SizedBox(height: 16),
          if (needsRevisionCount > 0) ...[
            _AlertBanner(
              message:
                  '$needsRevisionCount paper${needsRevisionCount > 1 ? 's' : ''} need revision — check reviewer comments.',
              onTap: () => context.go('/research/review'),
            ),
            const SizedBox(height: 14),
          ],
          _ResponsiveStatGrid(
            published: publishedCount,
            pending: pendingCount,
            totalViews: session.totalViews,
            totalDownloads: session.totalDownloads,
          ),
          const SizedBox(height: 20),
          _ResponsiveMainPanel(recentPapers: recentPapers),
          const SizedBox(height: 20),
          _TrendingSection(),
        ],
      ),
    );
  }
}

// ── Welcome card ─────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  final dynamic profile;
  const _WelcomeCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: rCard(highlight: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: RColors.secondary.withValues(alpha: 0.15),
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'R',
                  style: const TextStyle(
                    color: RColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: RColors.textPrimary,
                          ),
                        ),
                        if (profile.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: RColors.verifiedLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: RColors.secondary
                                      .withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified,
                                    size: 11, color: RColors.secondary),
                                SizedBox(width: 3),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: RColors.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.institution,
                      style: const TextStyle(
                        fontSize: 12,
                        color: RColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.go('/research/profile'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                ),
                child: const Text('Profile', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${profile.yearsExperience} yrs exp · ${profile.totalPublications} publications · ${profile.totalViews} views',
            style: const TextStyle(fontSize: 12, color: RColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Alert banner ──────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final String message;
  final VoidCallback onTap;
  const _AlertBanner({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: RColors.needsRevisionLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: RColors.needsRevision.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: RColors.needsRevision, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: RColors.needsRevision,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 12, color: RColors.needsRevision),
          ],
        ),
      ),
    );
  }
}

// ── Responsive 2x2 / 1x4 stat grid ──────────────────────────────────────────

class _ResponsiveStatGrid extends StatelessWidget {
  final int published;
  final int pending;
  final int totalViews;
  final int totalDownloads;

  const _ResponsiveStatGrid({
    required this.published,
    required this.pending,
    required this.totalViews,
    required this.totalDownloads,
  });

  String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        label: 'Published',
        value: '$published',
        icon: Icons.check_circle_outline,
        color: RColors.published,
      ),
      _StatCard(
        label: 'In Progress',
        value: '$pending',
        icon: Icons.hourglass_empty_outlined,
        color: RColors.underReview,
      ),
      _StatCard(
        label: 'Total Views',
        value: _fmt(totalViews),
        icon: Icons.visibility_outlined,
        color: RColors.accepted,
      ),
      _StatCard(
        label: 'Downloads',
        value: _fmt(totalDownloads),
        icon: Icons.download_outlined,
        color: RColors.secondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          // 2 × 2 grid on small screens
          return Column(
            children: [
              Row(children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 10),
                Expanded(child: cards[3]),
              ]),
            ],
          );
        }
        // 1 × 4 row on wider screens
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
            const SizedBox(width: 10),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: RColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Responsive main panel (recent papers + quick actions) ─────────────────────

class _ResponsiveMainPanel extends StatelessWidget {
  final List<ResearchPaper> recentPapers;
  const _ResponsiveMainPanel({required this.recentPapers});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              _RecentPapersCard(papers: recentPapers),
              const SizedBox(height: 16),
              _QuickActionsCard(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _RecentPapersCard(papers: recentPapers)),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: _QuickActionsCard()),
          ],
        );
      },
    );
  }
}

class _RecentPapersCard extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _RecentPapersCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Text(
                  'Recent Papers',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: RColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/research/papers'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('View All', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          if (papers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No papers yet.',
                  style: TextStyle(
                      color: RColors.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            ...papers.map((p) => _PaperListItem(paper: p)),
        ],
      ),
    );
  }
}

class _PaperListItem extends StatelessWidget {
  final ResearchPaper paper;
  const _PaperListItem({required this.paper});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/research/papers'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    paper.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: RColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                PaperStatusChip(status: paper.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  paper.field.label,
                  style: const TextStyle(
                      fontSize: 11, color: RColors.textSecondary),
                ),
                if (paper.views > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.visibility_outlined,
                      size: 11, color: RColors.grey),
                  const SizedBox(width: 2),
                  Text('${paper.views}',
                      style:
                          const TextStyle(fontSize: 11, color: RColors.grey)),
                ],
              ],
            ),
            const Divider(height: 14, color: RColors.divider),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.post_add_outlined,
            label: 'Submit New Paper',
            color: RColors.secondary,
            onTap: () => context.go('/research/new-paper'),
          ),
          const SizedBox(height: 6),
          _ActionButton(
            icon: Icons.health_and_safety_outlined,
            label: 'Disease Updates',
            color: RColors.needsRevision,
            onTap: () => context.go('/research/diseases'),
          ),
          const SizedBox(height: 6),
          _ActionButton(
            icon: Icons.lightbulb_outlined,
            label: 'Innovations',
            color: RColors.accepted,
            onTap: () => context.go('/research/innovations'),
          ),
          const SizedBox(height: 6),
          _ActionButton(
            icon: Icons.search,
            label: 'Search Papers',
            color: RColors.draft,
            onTap: () => context.go('/research/search'),
          ),
          const SizedBox(height: 6),
          _ActionButton(
            icon: Icons.rate_review_outlined,
            label: 'Review Area',
            color: RColors.underReview,
            onTap: () => context.go('/research/review'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 11, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trending section ──────────────────────────────────────────────────────────

class _TrendingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final published = ResearchSession.instance.papers
        .where((p) => p.status == PaperStatus.published)
        .toList()
      ..sort((a, b) => b.views.compareTo(a.views));
    final top = published.take(3).toList();

    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Most Viewed Papers',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: RColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              // Stack cards vertically on mobile
              return Column(
                children: top
                    .asMap()
                    .entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TrendingCard(
                              paper: e.value, rank: e.key + 1),
                        ))
                    .toList(),
              );
            }
            // Horizontal row on wider screens
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: top
                  .asMap()
                  .entries
                  .expand((e) => [
                        Expanded(
                          child: _TrendingCard(
                              paper: e.value, rank: e.key + 1),
                        ),
                        if (e.key < top.length - 1)
                          const SizedBox(width: 10),
                      ])
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final ResearchPaper paper;
  final int rank;
  const _TrendingCard({required this.paper, required this.rank});

  @override
  Widget build(BuildContext context) {
    final rankColor = rank == 1
        ? const Color(0xFFFFC107)
        : rank == 2
            ? const Color(0xFF9E9E9E)
            : const Color(0xFFCD7F32);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration:
                    BoxDecoration(color: rankColor, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (paper.journal != null)
                Flexible(
                  child: Text(
                    paper.journal!,
                    style: const TextStyle(
                        fontSize: 10, color: RColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            paper.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RColors.textPrimary,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 12, color: RColors.grey),
              const SizedBox(width: 3),
              Text('${paper.views}',
                  style:
                      const TextStyle(fontSize: 11, color: RColors.textSecondary)),
              const SizedBox(width: 10),
              const Icon(Icons.download_outlined,
                  size: 12, color: RColors.grey),
              const SizedBox(width: 3),
              Text('${paper.downloads}',
                  style:
                      const TextStyle(fontSize: 11, color: RColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
