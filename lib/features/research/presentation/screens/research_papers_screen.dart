import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class ResearchPapersScreen extends StatefulWidget {
  const ResearchPapersScreen({super.key});

  @override
  State<ResearchPapersScreen> createState() => _ResearchPapersScreenState();
}

class _ResearchPapersScreenState extends State<ResearchPapersScreen> {
  PaperStatus? _filter;

  List<ResearchPaper> get _filtered {
    final papers = ResearchSession.instance.papers;
    if (_filter == null) return papers;
    return papers.where((p) => p.status == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'My Papers',
      module: ResearchModule.papers,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/research/new-paper'),
        backgroundColor: RColors.secondary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.post_add),
        label: const Text('New Paper'),
      ),
      child: ListenableBuilder(
        listenable: ResearchSession.instance,
        builder: (context, _) => Column(
          children: [
            _FilterBar(
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? _EmptyState(filter: _filter)
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _PaperCard(paper: _filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final PaperStatus? selected;
  final ValueChanged<PaperStatus?> onChanged;

  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final session = ResearchSession.instance;
    int countFor(PaperStatus? s) =>
        s == null ? session.papers.length : session.papersByStatus(s).length;

    return Container(
      decoration: const BoxDecoration(
        color: RColors.bg,
        border: Border(bottom: BorderSide(color: RColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _FilterChip(
              label: 'All',
              count: countFor(null),
              selected: selected == null,
              onTap: () => onChanged(null),
              color: RColors.textPrimary,
            ),
            const SizedBox(width: 8),
            ...PaperStatus.values.map((s) {
              final (_, fg, label) = paperStatusColors(s);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: label,
                  count: countFor(s),
                  selected: selected == s,
                  onTap: () => onChanged(s),
                  color: fg,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : RColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? color : RColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.15)
                    : RColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : RColors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  final ResearchPaper paper;
  const _PaperCard({required this.paper});

  @override
  Widget build(BuildContext context) {
    final (fieldBg, fieldFg) = researchFieldColors(paper.field);
    return Container(
      decoration: rCard(),
      child: InkWell(
        onTap: () => context.go(
          '/research/new-paper',
          extra: paper.id,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: RColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PaperStatusChip(status: paper.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                paper.abstract,
                style: const TextStyle(
                  fontSize: 12,
                  color: RColors.textSecondary,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      paper.field.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: fieldFg,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...paper.keywords.take(2).map(
                        (k) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: RColors.surface2,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              k,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: RColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                  if (paper.keywords.length > 2)
                    Text(
                      '+${paper.keywords.length - 2}',
                      style: const TextStyle(
                          fontSize: 10, color: RColors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: RColors.divider),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _formatDate(paper.updatedAt),
                    style: const TextStyle(
                        fontSize: 11, color: RColors.grey),
                  ),
                  if (paper.journal != null) ...[
                    const Text(' · ',
                        style: TextStyle(color: RColors.grey)),
                    Flexible(
                      child: Text(
                        paper.journal!,
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (paper.views > 0) ...[
                    const Icon(Icons.visibility_outlined,
                        size: 13, color: RColors.grey),
                    const SizedBox(width: 3),
                    Text('${paper.views}',
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey)),
                    const SizedBox(width: 10),
                  ],
                  if (paper.downloads > 0) ...[
                    const Icon(Icons.download_outlined,
                        size: 13, color: RColors.grey),
                    const SizedBox(width: 3),
                    Text('${paper.downloads}',
                        style: const TextStyle(
                            fontSize: 11, color: RColors.grey)),
                  ],
                  if (paper.reviewComments
                      .where((c) => !c.resolved)
                      .isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: RColors.needsRevisionLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.comment_outlined,
                              size: 11, color: RColors.needsRevision),
                          const SizedBox(width: 3),
                          Text(
                            '${paper.reviewComments.where((c) => !c.resolved).length} comments',
                            style: const TextStyle(
                              fontSize: 10,
                              color: RColors.needsRevision,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _PaperActions(paper: paper),
                ],
              ),
            ],
          ),
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

class _PaperActions extends StatelessWidget {
  final ResearchPaper paper;
  const _PaperActions({required this.paper});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) {
        switch (action) {
          case 'edit':
            context.go('/research/new-paper', extra: paper.id);
          case 'submit':
            ResearchSession.instance.submitForReview(paper.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Paper submitted for review.'),
                backgroundColor: RColors.underReview,
              ),
            );
          case 'delete':
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Paper'),
                content: const Text(
                    'Are you sure you want to delete this draft? This cannot be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      ResearchSession.instance.deletePaper(paper.id);
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                        foregroundColor: RColors.needsRevision),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: RColors.textSecondary),
              SizedBox(width: 8),
              Text('Edit'),
            ],
          ),
        ),
        if (paper.status == PaperStatus.draft ||
            paper.status == PaperStatus.needsRevision)
          const PopupMenuItem(
            value: 'submit',
            child: Row(
              children: [
                Icon(Icons.send_outlined, size: 16, color: RColors.secondary),
                SizedBox(width: 8),
                Text('Submit for Review',
                    style: TextStyle(color: RColors.secondary)),
              ],
            ),
          ),
        if (paper.status == PaperStatus.draft)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline,
                    size: 16, color: RColors.needsRevision),
                SizedBox(width: 8),
                Text('Delete Draft',
                    style: TextStyle(color: RColors.needsRevision)),
              ],
            ),
          ),
      ],
      icon: const Icon(Icons.more_vert,
          size: 18, color: RColors.textSecondary),
      tooltip: 'Options',
    );
  }
}

class _EmptyState extends StatelessWidget {
  final PaperStatus? filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 48,
            color: RColors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            filter == null
                ? 'No papers yet'
                : 'No ${filter!.label.toLowerCase()} papers',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: RColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (filter == null)
            const Text(
              'Start by submitting your first research paper.',
              style: TextStyle(fontSize: 13, color: RColors.grey),
            ),
          const SizedBox(height: 20),
          if (filter == null)
            ElevatedButton.icon(
              onPressed: () => context.go('/research/new-paper'),
              icon: const Icon(Icons.post_add),
              label: const Text('Submit Paper'),
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
