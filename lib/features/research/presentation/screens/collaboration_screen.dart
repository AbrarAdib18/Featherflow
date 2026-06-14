import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class CollaborationScreen extends StatelessWidget {
  const CollaborationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Collaboration',
      module: ResearchModule.collaboration,
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        builder: (context, _) => _CollaborationBody(),
      ),
    );
  }
}

class _CollaborationBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = ResearchSession.instance;
    final coauthoredPapers = session.papers
        .where((p) => p.authors.length > 1)
        .toList();
    final papersWithComments = session.papers
        .where((p) => p.reviewComments.isNotEmpty)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationBanner(papersWithComments: papersWithComments),
          const SizedBox(height: 20),
          _CoAuthoredPapersCard(papers: coauthoredPapers),
          const SizedBox(height: 20),
          _ReviewThreadsCard(papers: papersWithComments),
          const SizedBox(height: 20),
          _JointProjectsCard(),
        ],
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  final List<ResearchPaper> papersWithComments;
  const _NotificationBanner({required this.papersWithComments});

  @override
  Widget build(BuildContext context) {
    if (papersWithComments.isEmpty) return const SizedBox.shrink();

    final unresolved = papersWithComments
        .expand((p) => p.reviewComments)
        .where((c) => !c.resolved)
        .length;

    if (unresolved == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RColors.underReviewLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: RColors.underReview.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined,
              color: RColors.underReview, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$unresolved unresolved reviewer comment${unresolved > 1 ? 's' : ''} across ${papersWithComments.length} paper${papersWithComments.length > 1 ? 's' : ''}.',
              style: const TextStyle(
                fontSize: 13,
                color: RColors.underReview,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/research/review'),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

class _CoAuthoredPapersCard extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _CoAuthoredPapersCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.group_outlined,
                    size: 18, color: RColors.secondary),
                const SizedBox(width: 8),
                const Text(
                  'Co-Authored Papers',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: RColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: RColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${papers.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: RColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          if (papers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No co-authored papers yet. Add co-authors when submitting a paper.',
                style: TextStyle(
                    color: RColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...papers.map((p) => _CoAuthoredRow(paper: p)),
        ],
      ),
    );
  }
}

class _CoAuthoredRow extends StatelessWidget {
  final ResearchPaper paper;
  const _CoAuthoredRow({required this.paper});

  @override
  Widget build(BuildContext context) {
    final coAuthors =
        paper.authors.where((a) => !a.isCorresponding).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 8),
          const Text(
            'Co-Authors:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: RColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: coAuthors.map((a) => _AuthorChip(author: a)).toList(),
          ),
          const Divider(height: 20, color: RColors.divider),
        ],
      ),
    );
  }
}

class _AuthorChip extends StatelessWidget {
  final dynamic author;
  const _AuthorChip({required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: RColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: const Border.fromBorderSide(
            BorderSide(color: RColors.cardBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: RColors.secondary.withValues(alpha: 0.15),
            child: Text(
              author.name.isNotEmpty
                  ? author.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: RColors.secondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            author.name,
            style: const TextStyle(
              fontSize: 12,
              color: RColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewThreadsCard extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _ReviewThreadsCard({required this.papers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.comment_outlined,
                    size: 18, color: RColors.underReview),
                const SizedBox(width: 8),
                const Text(
                  'Editor & Reviewer Comments',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: RColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/research/review'),
                  child: const Text('Full Review Area'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RColors.divider),
          if (papers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No reviewer comments on your papers yet.',
                style: TextStyle(
                    color: RColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...papers.take(3).map((p) {
              final unresolved =
                  p.reviewComments.where((c) => !c.resolved).length;
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: RColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (unresolved > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: RColors.needsRevisionLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unresolved open',
                              style: const TextStyle(
                                fontSize: 11,
                                color: RColors.needsRevision,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p.reviewComments.length} comment${p.reviewComments.length > 1 ? 's' : ''} total',
                      style: const TextStyle(
                        fontSize: 12,
                        color: RColors.textSecondary,
                      ),
                    ),
                    const Divider(height: 20, color: RColors.divider),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _JointProjectsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.folder_shared_outlined,
                  size: 18, color: RColors.accepted),
              SizedBox(width: 8),
              Text(
                'Joint Projects',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: RColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: const Border.fromBorderSide(
                  BorderSide(color: RColors.cardBorder)),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_shared_outlined,
                    size: 40,
                    color: RColors.grey.withValues(alpha: 0.6)),
                const SizedBox(height: 10),
                const Text(
                  'No joint projects yet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: RColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Joint projects with other researchers will appear here once initiated.',
                  style: TextStyle(
                      fontSize: 12, color: RColors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Start Joint Project'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RColors.secondary,
                    side: const BorderSide(color: RColors.secondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
