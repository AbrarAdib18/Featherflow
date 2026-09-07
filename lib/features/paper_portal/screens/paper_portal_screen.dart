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

/// tab index -> API content_type ("All" fetches every type).
const _tabTypes = <int, String>{
  1: 'research_paper',
  2: 'news',
  3: 'innovation',
  4: 'disease_study',
  5: 'feed_study',
  6: 'market_report',
  7: 'team_update',
};

const _sortLabels = <SortOrder, String>{
  SortOrder.latest: 'Latest',
  SortOrder.mostRead: 'Most Read',
  SortOrder.mostCited: 'Most Cited',
  SortOrder.trending: 'Trending',
};

const _pageSize = 20;

/// One tab's paginated, cached result set. Switching back to a visited tab
/// reuses this instead of re-fetching.
class _TabState {
  List<Article> articles = [];
  int page = 1;
  bool hasNext = true;
  bool loaded = false;
}

class PaperPortalScreen extends StatefulWidget {
  const PaperPortalScreen({super.key});

  @override
  State<PaperPortalScreen> createState() => _PaperPortalScreenState();
}

class _PaperPortalScreenState extends State<PaperPortalScreen> {
  int _selectedTab = 0;
  SortOrder _sortOrder = SortOrder.latest;
  String _searchQuery = '';
  Set<String> _selectedTopics = {};
  Set<String> _selectedAgeGroups = {};
  String _authorFilter = '';
  String _yearFilter = '';

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  final Map<int, _TabState> _cache = {};
  List<Article> _teamArticles = [];

  bool _loading = true; // first load of the current tab
  bool _loadingMore = false;
  String? _error;

  _TabState get _tab => _cache.putIfAbsent(_selectedTab, () => _TabState());

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadTeamBanner();
    _loadTab();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _sortApi => switch (_sortOrder) {
        SortOrder.latest => 'latest',
        SortOrder.mostRead => 'most_read',
        SortOrder.mostCited => 'most_bookmarked',
        SortOrder.trending => 'trending',
      };

  Future<void> _loadTeamBanner() async {
    try {
      final data = await ResearchApiService.instance
          .articleFeed(type: 'team_update', pageSize: 5);
      final list = (data['results'] as List? ?? const [])
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) setState(() => _teamArticles = list);
    } catch (_) {
      // Banner is a nice-to-have; ignore failures.
    }
  }

  /// On the "All" tab, Team Featherflow updates appear in the pinned banner
  /// only — keep them out of the main list to avoid showing them twice.
  bool _keep(Article a) => _selectedTab != 0 || !a.isTeamFeatherflow;

  /// (Re)load page 1 for the current tab. Uses the cache when already loaded
  /// unless [force] is set (pull-to-refresh, search/sort change).
  Future<void> _loadTab({bool force = false}) async {
    final tab = _tab;
    if (tab.loaded && !force) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ResearchApiService.instance.articleFeed(
        type: _tabTypes[_selectedTab],
        sort: _sortApi,
        search: _searchQuery,
        page: 1,
        pageSize: _pageSize,
      );
      final list = (data['results'] as List? ?? const [])
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .where(_keep)
          .toList();
      if (!mounted) return;
      setState(() {
        tab
          ..articles = list
          ..page = 1
          ..hasNext = data['has_next'] == true
          ..loaded = true;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    final tab = _tab;
    if (_loadingMore || !tab.hasNext || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ResearchApiService.instance.articleFeed(
        type: _tabTypes[_selectedTab],
        sort: _sortApi,
        search: _searchQuery,
        page: tab.page + 1,
        pageSize: _pageSize,
      );
      final more = (data['results'] as List? ?? const [])
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .where(_keep)
          .toList();
      if (!mounted) return;
      setState(() {
        final seen = tab.articles.map((a) => a.id).toSet();
        tab
          ..articles = [...tab.articles, ...more.where((a) => !seen.contains(a.id))]
          ..page += 1
          ..hasNext = data['has_next'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  void _selectTab(int index) {
    if (index == _selectedTab) return;
    setState(() {
      _selectedTab = index;
      _error = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadTab();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (value.trim() == _searchQuery) return;
      _searchQuery = value.trim();
      _cache.clear(); // search is global — every tab must re-query
      _loadTab(force: true);
    });
  }

  void _onSortChanged(SortOrder order) {
    if (order == _sortOrder) return;
    setState(() => _sortOrder = order);
    _cache.clear();
    _loadTab(force: true);
  }

  Future<void> _refresh() async {
    _cache.remove(_selectedTab);
    await Future.wait([_loadTab(force: true), _loadTeamBanner()]);
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

  /// Local-only refinements over the current page (topic / author / year).
  /// The tab + search + sort already happened on the server.
  List<Article> get _visibleArticles {
    var list = _tab.articles;
    if (_selectedTopics.isNotEmpty) {
      list = list
          .where((a) => a.tags.any((t) => _selectedTopics.contains(t)))
          .toList();
    }
    if (_authorFilter.isNotEmpty) {
      final q = _authorFilter.toLowerCase();
      list = list
          .where((a) =>
              a.author.toLowerCase().contains(q) ||
              a.source.toLowerCase().contains(q))
          .toList();
    }
    if (_yearFilter.isNotEmpty) {
      final year = int.tryParse(_yearFilter);
      if (year != null) list = list.where((a) => a.date.year == year).toList();
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
      _authorFilter = '';
      _yearFilter = '';
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
            _authorFilter = author;
            _yearFilter = year;
          });
          if (sort != _sortOrder) _onSortChanged(sort);
        },
      ),
    );
  }

  void _openDetail(Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final articles = _visibleArticles;
    final showBanner =
        _selectedTab != 7 && _teamArticles.isNotEmpty && _searchQuery.isEmpty;

    return Scaffold(
      backgroundColor: PPColors.surface2,
      appBar: AppBar(
        backgroundColor: PPColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: PhosphorIcon(PhosphorIcons.arrowLeft(), color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/farmer'),
        ),
        title: Row(
          children: [
            PhosphorIcon(PhosphorIcons.feather(), color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Knowledge Portal',
                      style: ppLabel(size: 16, weight: FontWeight.w700, color: Colors.white)),
                  Text('Research, news & innovations in poultry',
                      style: ppLabel(size: 10, color: Colors.white60)),
                ],
              ),
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
            onChanged: _onSearchChanged,
            onFilterTap: _openFilters,
          ),
          _TabRow(selectedIndex: _selectedTab, onTabSelected: _selectTab),
          _SortRow(
            count: articles.length,
            sortOrder: _sortOrder,
            onSortChanged: _onSortChanged,
          ),
          Expanded(child: _body(articles, showBanner)),
        ],
      ),
    );
  }

  Widget _body(List<Article> articles, bool showBanner) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: PPColors.primary));
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: () => _loadTab(force: true));
    }
    if (articles.isEmpty && !showBanner) {
      return _EmptyState(
        filtered: _hasActiveFilters || _searchQuery.isNotEmpty,
        onClear: () {
          _searchController.clear();
          _searchQuery = '';
          _clearFilters();
          _loadTab(force: true);
        },
      );
    }

    final tab = _tab;
    final bannerCount = showBanner ? 1 : 0;
    final footerCount = tab.hasNext ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 6, bottom: 80),
        itemCount: bannerCount + articles.length + footerCount,
        itemBuilder: (_, i) {
          if (showBanner && i == 0) {
            return TeamPostBanner(articles: _teamArticles, onTap: _openDetail);
          }
          final index = i - bannerCount;
          if (index >= articles.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: PPColors.primary),
                ),
              ),
            );
          }
          final article = articles[index];
          if (_selectedTab == 0 && index == 0 && article.isFeatured) {
            return FeaturedArticleCard(
              article: article,
              onTap: () => _openDetail(article),
              onBookmarkToggle: _toggleBookmark,
            );
          }
          return ArticleCard(
            article: article,
            onTap: () => _openDetail(article),
            onBookmarkToggle: _toggleBookmark,
          );
        },
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
              child: const Center(
                child: Icon(Icons.tune, size: 18, color: Colors.white),
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
  final VoidCallback onRetry;

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
            Text('Failed to load articles',
                style: ppTitle(size: 15, color: PPColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: ppBody(size: 12), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: PPColors.primary),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  final VoidCallback onClear;

  const _EmptyState({required this.filtered, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhosphorIcon(PhosphorIcons.article(), size: 56, color: PPColors.border),
          const SizedBox(height: 14),
          Text(
            filtered ? 'No articles match your search' : 'No articles available yet',
            style: ppTitle(size: 16, color: PPColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Try a different search or clear your filters.'
                : 'Check back soon — new research and news are added regularly.',
            style: ppBody(size: 13, color: PPColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (filtered) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onClear,
              child: Text('Clear search & filters',
                  style: ppLabel(size: 14, weight: FontWeight.w600, color: PPColors.primary)),
            ),
          ],
        ],
      ),
    );
  }
}
