import 'package:flutter/material.dart';
import '../../data/models/innovation_post.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';

class InnovationScreen extends StatefulWidget {
  const InnovationScreen({super.key});

  @override
  State<InnovationScreen> createState() => _InnovationScreenState();
}

class _InnovationScreenState extends State<InnovationScreen> {
  InnovationCategory? _filter;
  String? _expandedId;

  List<InnovationPost> get _filtered {
    final all = ResearchSession.instance.innovations;
    if (_filter == null) return all;
    return all.where((i) => i.category == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Innovations',
      module: ResearchModule.innovations,
      child: Column(
        children: [
          _CategoryFilterBar(
            selected: _filter,
            onChanged: (c) => setState(() => _filter = c),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: ResearchSession.instance,
              builder: (context, _) => _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No innovations found for this category.',
                        style: TextStyle(color: RColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final post = _filtered[i];
                        return _InnovationCard(
                          post: post,
                          expanded: _expandedId == post.id,
                          onToggle: () => setState(() {
                            _expandedId =
                                _expandedId == post.id ? null : post.id;
                          }),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final InnovationCategory? selected;
  final ValueChanged<InnovationCategory?> onChanged;

  const _CategoryFilterBar(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: RColors.bg,
        border: Border(bottom: BorderSide(color: RColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _CatChip(
              label: 'All',
              selected: selected == null,
              color: RColors.textPrimary,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            ...InnovationCategory.values.map((c) {
              final (_, fg) = innovationCategoryColors(c);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _CatChip(
                  label: c.label,
                  selected: selected == c,
                  color: fg,
                  onTap: () => onChanged(c),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CatChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : RColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : RColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _InnovationCard extends StatelessWidget {
  final InnovationPost post;
  final bool expanded;
  final VoidCallback onToggle;

  const _InnovationCard({
    required this.post,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final (catBg, catFg) = innovationCategoryColors(post.category);
    return Container(
      decoration: rCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: catBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          post.category.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: catFg,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.visibility_outlined,
                              size: 13, color: RColors.grey),
                          const SizedBox(width: 3),
                          Text(
                            '${post.views}',
                            style: const TextStyle(
                                fontSize: 12, color: RColors.grey),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.bookmark_outline,
                              size: 13, color: RColors.grey),
                          const SizedBox(width: 3),
                          Text(
                            '${post.bookmarks}',
                            style: const TextStyle(
                                fontSize: 12, color: RColors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: RColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.summary,
                    style: const TextStyle(
                      fontSize: 13,
                      color: RColors.textSecondary,
                      height: 1.5,
                    ),
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: RColors.textSecondary,
                        ),
                      ),
                      const Text(' · ',
                          style: TextStyle(color: RColors.grey)),
                      Text(
                        _formatDate(post.publishedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: RColors.grey,
                        ),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: RColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: RColors.divider),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Full Details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: RColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: RColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      post.details,
                      style: const TextStyle(
                        fontSize: 13,
                        color: RColors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: catBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.source_outlined,
                            size: 14, color: catFg),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            post.sourceDetails,
                            style: TextStyle(
                              fontSize: 12,
                              color: catFg,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: post.tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: RColors.surface2,
                              borderRadius: BorderRadius.circular(4),
                              border: const Border.fromBorderSide(
                                  BorderSide(color: RColors.cardBorder)),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 11,
                                color: RColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
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
