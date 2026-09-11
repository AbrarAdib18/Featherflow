import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';

import '../../data/community_api_service.dart';
import '../widgets/community_widgets.dart';
import '../widgets/post_card.dart';

class CommunitySearchScreen extends StatefulWidget {
  const CommunitySearchScreen({super.key, this.initialTag});
  final String? initialTag;

  @override
  State<CommunitySearchScreen> createState() => _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends State<CommunitySearchScreen> {
  final _api = CommunityApiService.instance;
  final _controller = TextEditingController();
  Timer? _debounce;

  String _sort = 'latest';
  bool _verifiedOnly = false;
  String? _tag;
  List<Map<String, dynamic>> _results = const [];
  List<Map<String, dynamic>> _trending = const [];
  List<Map<String, dynamic>> _suggestions = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    _api.hashtags().then((r) => mounted ? setState(() => _trending = r) : null).catchError((_) {});
    _api.followSuggestions().then((r) => mounted ? setState(() => _suggestions = r) : null).catchError((_) {});
    if (_tag != null) {
      _run();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _run);
  }

  Future<void> _run() async {
    final q = _controller.text.trim();
    if (q.isEmpty && _tag == null && !_verifiedOnly) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _api.search(query: q, tag: _tag, verifiedOnly: _verifiedOnly, sort: _sort);
      final rows = List<Map<String, dynamic>>.from(
          (data['results'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      if (mounted) setState(() => _results = rows);
    } catch (_) {
      // keep previous results
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasQuery => _controller.text.trim().isNotEmpty || _tag != null || _verifiedOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: TextField(
          controller: _controller,
          autofocus: widget.initialTag == null,
          onChanged: _onQueryChanged,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search posts, prices, topics…',
            hintStyle: TextStyle(color: Colors.white60),
            border: InputBorder.none,
          ),
        ),
      ),
      body: Column(children: [
        _filters(),
        if (_tag != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: InputChip(
                label: Text(_tag!),
                onDeleted: () {
                  setState(() => _tag = null);
                  _run();
                },
              ),
            ),
          ),
        Expanded(child: _hasQuery ? _resultsView() : _discoverView()),
      ]),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(children: [
        FilterChip(
          label: const Text('Verified experts'),
          selected: _verifiedOnly,
          onSelected: (v) {
            setState(() => _verifiedOnly = v);
            _run();
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        DropdownButton<String>(
          value: _sort,
          underline: const SizedBox.shrink(),
          dropdownColor: Colors.white,
          style: const TextStyle(
              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500),
          iconEnabledColor: AppColors.primary,
          items: const [
            DropdownMenuItem(value: 'latest', child: Text('Latest')),
            DropdownMenuItem(value: 'popular', child: Text('Most popular')),
          ],
          onChanged: (v) {
            setState(() => _sort = v ?? 'latest');
            _run();
          },
        ),
      ]),
    );
  }

  Widget _resultsView() {
    if (_loading && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return const CommunityStateView(icon: Icons.search_off, title: 'No matching posts');
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final post = _results[i];
        final id = post['id'].toString();
        return PostCard(
          post: post,
          dense: true,
          onTap: () => context.push('/community/post/$id'),
          onOpenAuthor: () {
            final aid = (post['author'] as Map?)?['id']?.toString();
            if (aid != null) context.push('/community/user/$aid');
          },
          onOpenTag: (t) => setState(() {
            _tag = t;
            _run();
          }),
          onReact: (t) => _api.react(id, t).then((_) => _run()),
          onBookmark: () => _api.toggleBookmark(id).then((_) => _run()),
          onRepost: () => _api.repost(id).then((_) => _run()),
          onReport: (r) => _api.report(targetType: 'post', targetId: id, reason: r),
        );
      },
    );
  }

  Widget _discoverView() {
    return ListView(padding: const EdgeInsets.all(AppSpacing.md), children: [
      const Text('Trending hashtags', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: _trending
            .map((h) => ActionChip(
                  label: Text('${h['tag']}  ·  ${h['count']}'),
                  onPressed: () {
                    setState(() => _tag = h['tag']?.toString());
                    _run();
                  },
                ))
            .toList(),
      ),
      const SizedBox(height: AppSpacing.lg),
      const Text('Suggested to follow', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpacing.xs),
      if (_suggestions.isEmpty)
        Text('No suggestions right now.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      for (final u in _suggestions)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.secondary.withValues(alpha: 0.18),
            child: Text(u['initial']?.toString() ?? '?', style: const TextStyle(color: AppColors.primary)),
          ),
          title: Row(children: [
            Flexible(child: Text(u['name']?.toString() ?? '', overflow: TextOverflow.ellipsis)),
            VerifiedBadge(badge: u['badge'] as Map<String, dynamic>?),
          ]),
          subtitle: Text('${u['role']} · ${u['followers']} followers', style: const TextStyle(fontSize: 11)),
          trailing: _FollowButton(userId: u['id'].toString(), api: _api),
          onTap: () => context.push('/community/user/${u['id']}'),
        ),
    ]);
  }
}

class _FollowButton extends StatefulWidget {
  const _FollowButton({required this.userId, required this.api});
  final String userId;
  final CommunityApiService api;

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _following = false;
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_following) {
        await widget.api.unfollowUser(widget.userId);
        setState(() => _following = false);
      } else {
        final now = await widget.api.followUser(widget.userId);
        setState(() => _following = now);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _busy ? null : _toggle,
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      child: Text(_following ? 'Following' : 'Follow', style: const TextStyle(fontSize: 12)),
    );
  }
}
