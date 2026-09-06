import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import '../../research/data/services/research_api_service.dart';
import '../widgets/article_card.dart';
import '../widgets/featured_article_card.dart';
import '../widgets/team_post_banner.dart';
import 'article_detail_screen.dart';
import 'search_filter_screen.dart';

const _tabs = [
  'All',
  'Research Papers',
  'News',
  'Innovation',
  'Disease Studies',
  'Feed Studies',
  'Market Reports',
  'Team Featherflow',
];

const _tabCategories = <int, ArticleCategory>{
  1: ArticleCategory.researchPaper,
  2: ArticleCategory.news,
  3: ArticleCategory.innovation,
  4: ArticleCategory.diseaseStudy,
  5: ArticleCategory.feedStudy,
  6: ArticleCategory.marketReport,
  7: ArticleCategory.teamFeatherflow,
};

const _sortLabels = <SortOrder, String>{
  SortOrder.latest: 'Latest',
  SortOrder.mostRead: 'Most Read',
  SortOrder.mostCited: 'Most Cited',
  SortOrder.trending: 'Trending',
};

class PaperPortalScreen extends StatefulWidget {
  const PaperPortalScreen({super.key});

  @override
  State<PaperPortalScreen> createState() => _PaperPortalScreenState();
}

class _PaperPortalScreenState extends State<PaperPortalScreen> {
  int _selectedTab = 0;
  String _searchQuery = '';
  SortOrder _sortOrder = SortOrder.latest;
  Set<String> _selectedTopics = {};
  Set<String> _selectedAgeGroups = {};
  String _authorFilter = '';
  String _yearFilter = '';

  final _searchController = TextEditingController();
  List<Article> _articles = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Requirements §9 / §4: surface newly published research & news within ~4s.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ResearchApiService.instance.articleFeed();
      final results = (data['results'] as List)
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      final knownIds = _articles.map((a) => a.id).toSet();
      final fresh = results.where((a) => !knownIds.contains(a.id)).length;
      setState(() {
        _articles = results;
        _loading = false;
        _error = null;
      });
      if (silent && fresh > 0 && knownIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$fresh new article${fresh == 1 ? '' : 's'} published'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (error) {
      if (!mounted || silent) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleBookmark(Article article) async {
    try {
      await ResearchApiService.instance.toggleBookmark(article.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Article> get _teamArticles =>
      _articles.where((a) => a.isTeamFeatherflow).toList();

  List<Article> get _filteredArticles {
    var list = _articles.where((a) {
      if (_selectedTab != 7 && a.isTeamFeatherflow) return false;
      if (_selectedTab >= 1 && _selectedTab <= 6) {
        if (a.category != _tabCategories[_selectedTab]) return false;
      }
      if (_selectedTab == 7 && !a.isTeamFeatherflow) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!a.title.toLowerCase().contains(q) &&
            !a.tags.any((t) => t.toLowerCase().contains(q))) {
          return false;
        }
      }

      if (_selectedTopics.isNotEmpty) {
        if (!a.tags.any((t) => _selectedTopics.contains(t))) return false;
      }

      if (_authorFilter.isNotEmpty) {
        final q = _authorFilter.toLowerCase();
        if (!a.author.toLowerCase().contains(q) && !a.source.toLowerCase().contains(q)) {
          return false;
        }
      }

      if (_yearFilter.isNotEmpty) {
        final year = int.tryParse(_yearFilter);
        if (year != null && a.date.year != year) return false;
      }

      return true;
    }).toList();

    switch (_sortOrder) {
      case SortOrder.latest:
        list.sort((a, b) => b.date.compareTo(a.date));
      case SortOrder.mostRead:
        list.sort((a, b) => b.viewsCount.compareTo(a.viewsCount));
      case SortOrder.mostCited:
        list.sort((a, b) => b.bookmarksCount.compareTo(a.bookmarksCount));
      case SortOrder.trending:
        list.sort((a, b) => b.viewsCount.compareTo(a.viewsCount));
    }

    if (_selectedTab == 0 && list.isNotEmpty) {
      final featuredIdx = list.indexWhere((a) => a.isFeatured);
      if (featuredIdx > 0) {
        final featured = list.removeAt(featuredIdx);
        list.insert(0, featured);
      }
    }

    return list;
  }

  bool get _hasActiveFilters =>
      _selectedTopics.isNotEmpty ||
      _selectedAgeGroups.isNotEmpty ||
      _authorFilter.isNotEmpty ||
      _yearFilter.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _selectedTopics = {};
      _selectedAgeGroups = {};
      _sortOrder = SortOrder.latest;
      _searchQuery = '';
      _authorFilter = '';
      _yearFilter = '';
      _searchController.clear();
    });
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SearchFilterScreen(
        initialTopics: _selectedTopics,
        initialAgeGroups: _selectedAgeGroups,
        initialSort: _sortOrder,
        initialAuthor: _authorFilter,
        initialYear: _yearFilter,
        onApply: (topics, ageGroups, sort, author, year) {
          setState(() {
            _selectedTopics = topics;
            _selectedAgeGroups = ageGroups;
            _sortOrder = sort;
            _authorFilter = author;
            _yearFilter = year;
          });
        },
      ),
    );
  }

  void _navigateToDetail(Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articles = _filteredArticles;
    final showBanner = _selectedTab != 7 && _teamArticles.isNotEmpty;

    return Scaffold(
      backgroundColor: PPColors.surface2,
      appBar: AppBar(
        backgroundColor: PPColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: PhosphorIcon(PhosphorIcons.arrowLeft(), color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            PhosphorIcon(PhosphorIcons.feather(), color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Knowledge Portal',
                  style: ppLabel(size: 16, weight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  'Research, news & innovations in poultry',
                  style: ppLabel(size: 10, color: Colors.white60),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: (currentUserRole == UserRole.admin ||
              currentUserRole == UserRole.researcher)
          ? FloatingActionButton(
              backgroundColor: PPColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/research/new-paper'),
              child: PhosphorIcon(PhosphorIcons.plus(), size: 22),
            )
          : null,
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            hasActiveFilters: _hasActiveFilters,
            onChanged: (v) => setState(() => _searchQuery = v),
            onFilterTap: _openFilters,
          ),
          _TabRow(
            selectedIndex: _selectedTab,
            onTabSelected: (i) => setState(() => _selectedTab = i),
          ),
          _SortRow(
            count: articles.length,
            sortOrder: _sortOrder,
            onSortChanged: (s) => setState(() => _sortOrder = s),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: PPColors.primary))
                : _error != null
                    ? _ErrorState(message: _error!, onRetry: _load)
                    : articles.isEmpty && !showBanner
                        ? _EmptyState(onClear: _clearFilters)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(top: 6, bottom: 80),
                              itemCount: (showBanner ? 1 : 0) + articles.length,
                              itemBuilder: (_, i) {
                                if (showBanner && i == 0) {
                                  return TeamPostBanner(
                                    articles: _teamArticles,
                                    onTap: _navigateToDetail,
                                  );
                                }
                                final articleIndex = showBanner ? i - 1 : i;
                                final article = articles[articleIndex];
                                if (_selectedTab == 0 &&
                                    articleIndex == 0 &&
                                    article.isFeatured) {
                                  return FeaturedArticleCard(
                                    article: article,
                                    onTap: () => _navigateToDetail(article),
                                    onBookmarkToggle: _toggleBookmark,
                                  );
                                }
                                return ArticleCard(
                                  article: article,
                                  onTap: () => _navigateToDetail(article),
                                  onBookmarkToggle: _toggleBookmark,
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasActiveFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  const _SearchBar({
    required this.controller,
    required this.hasActiveFilters,
    required this.onChanged,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PPColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: ppBody(size: 14, color: PPColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search articles, tags…',
                  hintStyle: ppBody(size: 14, color: PPColors.textSecondary),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 6),
                    child: PhosphorIcon(PhosphorIcons.magnifyingGlass(),
                        size: 16, color: PPColors.textSecondary),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasActiveFilters ? PPColors.amber : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasActiveFilters ? PPColors.amber : Colors.white.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIcons.funnel(),
                  size: 18,
                  color: hasActiveFilters ? Colors.white : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _TabRow({required this.selectedIndex, required this.onTabSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PPColors.bg,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final isSelected = i == selectedIndex;
                return GestureDetector(
                  onTap: () => onTabSelected(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? PPColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      _tabs[i],
                      style: ppLabel(
                        size: 13,
                        weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSelected ? PPColors.primary : PPColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const Divider(height: 1, color: PPColors.border),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final int count;
  final SortOrder sortOrder;
  final ValueChanged<SortOrder> onSortChanged;

  const _SortRow({
    required this.count,
    required this.sortOrder,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PPColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$count article${count == 1 ? '' : 's'}',
            style: ppLabel(size: 12, color: PPColors.textSecondary),
          ),
          const Spacer(),
          PopupMenuButton<SortOrder>(
            onSelected: onSortChanged,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: PPColors.border),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(PhosphorIcons.arrowsDownUp(), size: 13, color: PPColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    _sortLabels[sortOrder]!,
                    style: ppLabel(size: 12, weight: FontWeight.w600, color: PPColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  PhosphorIcon(PhosphorIcons.caretDown(), size: 11, color: PPColors.textSecondary),
                ],
              ),
            ),
            itemBuilder: (_) => SortOrder.values
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Text(_sortLabels[s]!,
                          style: ppLabel(size: 13, color: PPColors.textPrimary)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhosphorIcon(PhosphorIcons.warning(), size: 48, color: PPColors.textSecondary),
            const SizedBox(height: 14),
            Text('Could not load the knowledge portal',
                style: ppTitle(size: 15, color: PPColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: ppBody(size: 12), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: ppLabel(size: 14, weight: FontWeight.w600, color: PPColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onClear;

  const _EmptyState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhosphorIcon(PhosphorIcons.article(), size: 56, color: PPColors.border),
          const SizedBox(height: 14),
          Text('No articles found', style: ppTitle(size: 16, color: PPColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your search or filters.',
            style: ppBody(size: 13, color: PPColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onClear,
            child: Text(
              'Clear filters',
              style: ppLabel(size: 14, weight: FontWeight.w600, color: PPColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
