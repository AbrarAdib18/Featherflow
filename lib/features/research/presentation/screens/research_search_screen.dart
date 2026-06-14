import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/research_paper.dart';
import '../../data/services/research_session.dart';
import '../research_theme.dart';
import '../widgets/research_scaffold.dart';
import '../widgets/research_sidebar.dart';
import '../widgets/paper_status_chip.dart';

class ResearchSearchScreen extends StatefulWidget {
  const ResearchSearchScreen({super.key});

  @override
  State<ResearchSearchScreen> createState() =>
      _ResearchSearchScreenState();
}

class _ResearchSearchScreenState
    extends State<ResearchSearchScreen> {
  final _searchCtrl = TextEditingController();
  ResearchField? _fieldFilter;
  List<ResearchPaper> _results = [];
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    var results = ResearchSession.instance.searchPapers(q);
    if (_fieldFilter != null) {
      results =
          results.where((p) => p.field == _fieldFilter).toList();
    }

    setState(() {
      _results = results;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResearchScaffold(
      title: 'Search & Discovery',
      module: ResearchModule.search,
      child: Column(
        children: [
          _SearchBar(
            controller: _searchCtrl,
            onSearch: _search,
            fieldFilter: _fieldFilter,
            onFieldChanged: (f) {
              setState(() => _fieldFilter = f);
              if (_hasSearched) _search();
            },
          ),
          Expanded(
            child: _hasSearched
                ? _SearchResults(results: _results, query: _searchCtrl.text)
                : _DiscoveryHome(),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ResearchField? fieldFilter;
  final ValueChanged<ResearchField?> onFieldChanged;

  const _SearchBar({
    required this.controller,
    required this.onSearch,
    required this.fieldFilter,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: RColors.bg,
        border: Border(bottom: BorderSide(color: RColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSearch(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: RColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Search by title, author, keyword, or year...',
                    hintStyle: const TextStyle(
                        color: RColors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: RColors.grey, size: 20),
                    filled: true,
                    fillColor: RColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: RColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: RColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: RColors.secondary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: RColors.grey),
                            onPressed: () {
                              controller.clear();
                              onSearch();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: RColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  'Field: ',
                  style: TextStyle(
                      fontSize: 12, color: RColors.textSecondary),
                ),
                _FieldFilterChip(
                  label: 'All Fields',
                  selected: fieldFilter == null,
                  onTap: () => onFieldChanged(null),
                ),
                ...ResearchField.values.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FieldFilterChip(
                      label: f.label,
                      selected: fieldFilter == f,
                      onTap: () => onFieldChanged(f),
                    ),
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

class _FieldFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FieldFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? RColors.secondary.withValues(alpha: 0.1)
              : RColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? RColors.secondary : RColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
            color:
                selected ? RColors.secondary : RColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<ResearchPaper> results;
  final String query;

  const _SearchResults(
      {required this.results, required this.query});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 48,
                color: RColors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No results for "$query"',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: RColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try different keywords or broaden your filters.',
              style: TextStyle(fontSize: 13, color: RColors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            '${results.length} result${results.length > 1 ? 's' : ''} for "$query"',
            style: const TextStyle(
              fontSize: 13,
              color: RColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _SearchResultCard(paper: results[i], query: query),
          ),
        ),
      ],
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final ResearchPaper paper;
  final String query;

  const _SearchResultCard(
      {required this.paper, required this.query});

  @override
  Widget build(BuildContext context) {
    final (fieldBg, fieldFg) = researchFieldColors(paper.field);
    return Container(
      decoration: rCard(),
      child: InkWell(
        onTap: () => context.go('/research/papers'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                  const SizedBox(width: 8),
                  PaperStatusChip(status: paper.status),
                ],
              ),
              const SizedBox(height: 6),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      paper.field.label,
                      style: TextStyle(
                          fontSize: 10,
                          color: fieldFg,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    paper.authors.first.name,
                    style: const TextStyle(
                        fontSize: 11, color: RColors.grey),
                  ),
                  if (paper.publishedAt != null) ...[
                    const Text(' · ',
                        style: TextStyle(color: RColors.grey)),
                    Text(
                      '${paper.publishedAt!.year}',
                      style: const TextStyle(
                          fontSize: 11, color: RColors.grey),
                    ),
                  ],
                  const Spacer(),
                  const Icon(Icons.visibility_outlined,
                      size: 12, color: RColors.grey),
                  const SizedBox(width: 3),
                  Text(
                    '${paper.views}',
                    style: const TextStyle(
                        fontSize: 11, color: RColors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = ResearchSession.instance;
    final trending = session.papers
        .where((p) => p.status == PaperStatus.published)
        .toList()
      ..sort((a, b) => b.views.compareTo(a.views));
    final recent = session.papers.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _DiscoverySection(
          title: 'Trending Research',
          icon: Icons.trending_up,
          color: RColors.secondary,
          papers: trending.take(3).toList(),
        ),
        const SizedBox(height: 20),
        _DiscoverySection(
          title: 'Recent Papers',
          icon: Icons.schedule,
          color: RColors.accepted,
          papers: recent.take(3).toList(),
        ),
        const SizedBox(height: 20),
        _BookmarkedSection(),
      ],
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<ResearchPaper> papers;

  const _DiscoverySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.papers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...papers.map((p) => _CompactPaperRow(paper: p)),
      ],
    );
  }
}

class _CompactPaperRow extends StatelessWidget {
  final ResearchPaper paper;
  const _CompactPaperRow({required this.paper});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: rCard(),
      child: InkWell(
        onTap: () => context.go('/research/papers'),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paper.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: RColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    paper.field.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: RColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (paper.views > 0) ...[
              const Icon(Icons.visibility_outlined,
                  size: 12, color: RColors.grey),
              const SizedBox(width: 3),
              Text(
                '${paper.views}',
                style: const TextStyle(
                    fontSize: 11, color: RColors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookmarkedSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.bookmark_outline, size: 16, color: RColors.underReview),
            SizedBox(width: 6),
            Text(
              'Bookmarked Papers',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: RColors.underReview,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: rCard(),
          child: const Center(
            child: Column(
              children: [
                Icon(Icons.bookmark_border,
                    size: 32, color: RColors.grey),
                SizedBox(height: 8),
                Text(
                  'No bookmarked papers yet.',
                  style: TextStyle(
                    color: RColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Bookmark papers from the My Papers screen.',
                  style: TextStyle(
                    color: RColors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
