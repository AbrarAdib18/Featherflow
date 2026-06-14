import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class ReviewAreaScreen extends StatefulWidget {
  const ReviewAreaScreen({super.key});

  @override
  State<ReviewAreaScreen> createState() => _ReviewAreaScreenState();
}

class _ReviewAreaScreenState extends State<ReviewAreaScreen> {
  String? _selectedPaperId;

  List<ResearchPaper> get _papersWithComments =>
      ResearchSession.instance.papers
          .where((p) => p.reviewComments.isNotEmpty)
          .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_papersWithComments.isNotEmpty) {
        setState(() => _selectedPaperId = _papersWithComments.first.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Review & Revision Area',
      module: ResearchModule.review,
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        builder: (context, _) {
          final papers = _papersWithComments;
          if (papers.isEmpty) {
            return _EmptyReview();
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 700) {
                return _WideReviewLayout(
                  papers: papers,
                  selectedId: _selectedPaperId,
                  onSelect: (id) =>
                      setState(() => _selectedPaperId = id),
                );
              }
              return _NarrowReviewLayout(papers: papers);
            },
          );
        },
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 56,
            color: RColors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No reviewer comments yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: RColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Reviewer and editor comments on your submitted papers\nwill appear here.',
            style: TextStyle(fontSize: 13, color: RColors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/research/papers'),
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('View My Papers'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RColors.secondary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideReviewLayout extends StatelessWidget {
  final List<ResearchPaper> papers;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _WideReviewLayout({
    required this.papers,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final selectedPaper = selectedId != null
        ? ResearchSession.instance.findPaper(selectedId!)
        : null;

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: RColors.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Papers Under Review',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: RColors.textSecondary,
                    ),
                  ),
                ),
                const Divider(height: 1, color: RColors.divider),
                Expanded(
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                    itemCount: papers.length,
                    itemBuilder: (context, i) {
                      final p = papers[i];
                      final unresolved = p.reviewComments
                          .where((c) => !c.resolved)
                          .length;
                      final isSelected = p.id == selectedId;
                      return Material(
                        color: isSelected
                            ? RColors.secondary.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => onSelect(p.id),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? RColors.secondary
                                        : RColors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    PaperStatusChip(status: p.status),
                                    const SizedBox(width: 8),
                                    if (unresolved > 0)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: RColors
                                              .needsRevisionLight,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10),
                                        ),
                                        child: Text(
                                          '$unresolved open',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color:
                                                RColors.needsRevision,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: selectedPaper != null
              ? _PaperReviewDetail(paper: selectedPaper)
              : const Center(
                  child: Text(
                    'Select a paper to view reviewer comments.',
                    style: TextStyle(color: RColors.textSecondary),
                  ),
                ),
        ),
      ],
    );
  }
}

class _NarrowReviewLayout extends StatelessWidget {
  final List<ResearchPaper> papers;
  const _NarrowReviewLayout({required this.papers});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: papers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = papers[i];
        return _CollapsedPaperReview(paper: p);
      },
    );
  }
}

class _CollapsedPaperReview extends StatefulWidget {
  final ResearchPaper paper;
  const _CollapsedPaperReview({required this.paper});

  @override
  State<_CollapsedPaperReview> createState() =>
      _CollapsedPaperReviewState();
}

class _CollapsedPaperReviewState extends State<_CollapsedPaperReview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: rCard(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.paper.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: RColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        PaperStatusChip(status: widget.paper.status),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: RColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: RColors.divider),
            _PaperReviewDetail(paper: widget.paper),
          ],
        ],
      ),
    );
  }
}

class _PaperReviewDetail extends StatelessWidget {
  final ResearchPaper paper;
  const _PaperReviewDetail({required this.paper});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VersionHistory(paper: paper),
          const SizedBox(height: 20),
          _ReviewComments(paper: paper),
          const SizedBox(height: 20),
          _RevisionActions(paper: paper),
        ],
      ),
    );
  }
}

class _VersionHistory extends StatelessWidget {
  final ResearchPaper paper;
  const _VersionHistory({required this.paper});

  @override
  Widget build(BuildContext context) {
    if (paper.versions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Version History',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: RColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        ...paper.versions.reversed.map(
          (v) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: const Border.fromBorderSide(
                  BorderSide(color: RColors.cardBorder)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: RColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      'v${v.versionNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: RColors.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.changeNotes,
                        style: const TextStyle(
                          fontSize: 12,
                          color: RColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatDate(v.submittedAt),
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _ReviewComments extends StatelessWidget {
  final ResearchPaper paper;
  const _ReviewComments({required this.paper});

  @override
  Widget build(BuildContext context) {
    final comments = paper.reviewComments;
    if (comments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Reviewer Comments',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: RColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: comments.any((c) => !c.resolved)
                    ? RColors.needsRevisionLight
                    : RColors.publishedLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${comments.where((c) => !c.resolved).length} open · ${comments.where((c) => c.resolved).length} resolved',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: comments.any((c) => !c.resolved)
                      ? RColors.needsRevision
                      : RColors.published,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...comments.map((c) => _CommentCard(paper: paper, comment: c)),
      ],
    );
  }
}

class _CommentCard extends StatelessWidget {
  final ResearchPaper paper;
  final ReviewComment comment;

  const _CommentCard({required this.paper, required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: comment.resolved
            ? RColors.publishedLight
            : RColors.needsRevisionLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: comment.resolved
              ? RColors.published.withValues(alpha: 0.3)
              : RColors.needsRevision.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    comment.reviewerName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: comment.resolved
                          ? RColors.published
                          : RColors.needsRevision,
                    ),
                  ),
                ),
                const Spacer(),
                if (comment.resolved)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: RColors.published),
                      SizedBox(width: 4),
                      Text(
                        'Resolved',
                        style: TextStyle(
                          fontSize: 11,
                          color: RColors.published,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  TextButton(
                    onPressed: () {
                      ResearchSession.instance
                          .resolveComment(paper.id, comment.id);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: RColors.published,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    child: const Text(
                      'Mark Resolved',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment.comment,
              style: TextStyle(
                fontSize: 13,
                color: comment.resolved
                    ? RColors.textSecondary
                    : RColors.textPrimary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatDate(comment.createdAt),
              style: const TextStyle(fontSize: 11, color: RColors.grey),
            ),
          ],
        ),
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

class _RevisionActions extends StatelessWidget {
  final ResearchPaper paper;
  const _RevisionActions({required this.paper});

  @override
  Widget build(BuildContext context) {
    final canEdit = paper.status == PaperStatus.needsRevision ||
        paper.status == PaperStatus.draft;

    if (!canEdit) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(
            BorderSide(color: RColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Respond to Revision',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: RColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Address all reviewer comments, then resubmit your revised paper.',
            style: TextStyle(fontSize: 12, color: RColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go(
                  '/research/new-paper',
                  extra: paper.id,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Paper'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  ResearchSession.instance.submitForReview(paper.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Revised paper submitted for review.'),
                      backgroundColor: RColors.underReview,
                    ),
                  );
                },
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Resubmit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RColors.underReview,
                  side: const BorderSide(color: RColors.underReview),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
