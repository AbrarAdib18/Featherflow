import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';

import '../../data/community_api_service.dart';
import '../../data/community_session.dart';
import '../widgets/community_widgets.dart';
import '../widgets/post_card.dart';

const _tabs = <_Tab>[
  _Tab('latest', 'Latest', Icons.schedule),
  _Tab('trending', 'Trending', Icons.trending_up),
  _Tab('following', 'Following', Icons.people_outline),
];

class _Tab {
  const _Tab(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _session = CommunitySession.instance;
  final _api = CommunityApiService.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onChange);
    _session.attach();
  }

  @override
  void dispose() {
    _session.removeListener(_onChange);
    _session.release();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _session.refresh(silent: true);
    } on CommunityApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = _tabs.indexWhere((t) => t.key == _session.tab).clamp(0, _tabs.length - 1);
    final topics = _session.topics;
    final selectedTopic = _session.category;
    final posts = _session.posts;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Community', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/community/search'),
          ),
          _NotificationBell(
            count: _session.unreadCount,
            onTap: () async {
              await context.push('/community/notifications');
              _session.clearBadge();
              _session.refresh(silent: true);
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => _session.setView(tab: _tabs[i].key),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: i == selectedTab ? AppColors.secondary : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_tabs[i].icon,
                                size: 15, color: i == selectedTab ? Colors.white : Colors.white60),
                            const SizedBox(width: 5),
                            Text(_tabs[i].label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: i == selectedTab ? FontWeight.w700 : FontWeight.w400,
                                  color: i == selectedTab ? Colors.white : Colors.white60,
                                )),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: 44,
              color: Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                itemCount: topics.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (_, i) {
                  final t = topics[i];
                  final sel = t == selectedTopic;
                  return ChoiceChip(
                    label: Text(t, style: const TextStyle(fontSize: 11.5)),
                    selected: sel,
                    onSelected: (_) => _session.setView(category: t),
                    visualDensity: VisualDensity.compact,
                    selectedColor: AppColors.secondary.withValues(alpha: 0.18),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        onPressed: () async {
          final created = await context.push<bool>('/community/create');
          if (created == true) _session.refresh();
        },
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () => _session.refresh(),
        child: _body(posts),
      ),
    );
  }

  Widget _body(List<Map<String, dynamic>> posts) {
    if (_session.error != null && posts.isEmpty) {
      return ListView(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: CommunityStateView(
            icon: Icons.wifi_off,
            title: 'Could not load the community feed',
            subtitle: _session.error,
            onRetry: () => _session.refresh(),
          ),
        ),
      ]);
    }
    if (_session.loading && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return ListView(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: CommunityStateView(
            icon: _session.tab == 'following' ? Icons.people_outline : Icons.forum_outlined,
            title: _session.tab == 'following'
                ? 'Posts from people you follow will show here'
                : 'No posts yet — be the first to share',
            subtitle: _session.tab == 'following' ? 'Find farmers and experts to follow from Search.' : null,
          ),
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 96),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final post = posts[i];
        final id = post['id']?.toString() ?? '';
        return PostCard(
          post: post,
          dense: true,
          onTap: () async {
            await context.push('/community/post/$id');
            _session.refresh(silent: true);
          },
          onOpenAuthor: () {
            final authorId = (post['author'] as Map?)?['id']?.toString();
            if (authorId != null) context.push('/community/user/$authorId');
          },
          onOpenTag: (tag) => context.push('/community/search?tag=$tag'),
          onMuteAuthor: (authorId) => _guard(() async {
            await _api.blockUser(authorId);
            _toast('Muted — you will not see this member in your feed.');
          }),
          onReact: (type) => _guard(() => _api.react(id, type).then((_) {})),
          onBookmark: () => _guard(() => _api.toggleBookmark(id).then((_) {})),
          onRepost: () => _guard(() => _api.repost(id).then((_) {})),
          onReport: (reason) => _guard(() async {
            await _api.report(targetType: 'post', targetId: id, reason: reason);
            _toast('Report sent to moderators.');
          }),
          onVote: (indexes) => _guard(() => _api.votePoll(id, indexes).then((_) {})),
        );
      },
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications_none), onPressed: onTap),
      if (count > 0)
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.all(3),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
            child: Text('${count > 9 ? '9+' : count}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }
}
