import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/network/auth_service.dart';

import '../../data/community_api_service.dart';
import '../widgets/community_widgets.dart';
import '../widgets/post_card.dart';

class CommunityProfileScreen extends StatefulWidget {
  const CommunityProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  final _api = CommunityApiService.instance;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _posts = const [];
  String? _error;
  bool _busy = false;

  bool get _isMe => AuthService.instance.currentSession?.user.id == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.userStats(widget.userId),
        _api.userPosts(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _posts = List<Map<String, dynamic>>.from(results[1] as List);
          _error = null;
        });
      }
    } on CommunityApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleFollow() async {
    final stats = _stats;
    if (stats == null) return;
    setState(() => _busy = true);
    try {
      if (stats['is_following'] == true) {
        await _api.unfollowUser(widget.userId);
      } else {
        await _api.followUser(widget.userId);
      }
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    final stats = _stats;
    if (stats == null) return;
    setState(() => _busy = true);
    try {
      if (stats['is_blocked'] == true) {
        await _api.unblockUser(widget.userId);
      } else {
        await _api.blockUser(widget.userId);
      }
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(stats?['name']?.toString() ?? 'Profile'),
        actions: [
          if (stats != null && !_isMe)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'block') _toggleBlock();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Text(stats['is_blocked'] == true ? 'Unmute this member' : 'Mute this member'),
                ),
              ],
            ),
        ],
      ),
      body: stats == null
          ? (_error != null
              ? CommunityStateView(icon: Icons.error_outline, title: 'Could not load profile', subtitle: _error, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(children: [
                _header(stats),
                if (_posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: Text('No public posts yet.', style: TextStyle(color: Colors.grey))),
                  ),
                for (final post in _posts)
                  PostCard(
                    post: post,
                    dense: true,
                    onTap: () => context.push('/community/post/${post['id']}'),
                    onOpenTag: (t) => context.push('/community/search?tag=$t'),
                    onReact: (t) => _api.react(post['id'].toString(), t).then((_) => _load()),
                    onBookmark: () => _api.toggleBookmark(post['id'].toString()).then((_) => _load()),
                    onRepost: () => _api.repost(post['id'].toString()).then((_) => _load()),
                    onReport: (r) => _api.report(targetType: 'post', targetId: post['id'].toString(), reason: r),
                  ),
              ]),
            ),
    );
  }

  Widget _header(Map<String, dynamic> stats) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.18),
            child: Text(stats['initial']?.toString() ?? '?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(stats['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                VerifiedBadge(badge: stats['badge'] as Map<String, dynamic>?, compact: false),
              ]),
              Text(stats['role']?.toString() ?? 'Community member',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
          if (!_isMe && stats['is_blocked'] != true)
            OutlinedButton(
              onPressed: _busy ? null : _toggleFollow,
              child: Text(stats['is_following'] == true ? 'Following' : 'Follow'),
            ),
          if (!_isMe && stats['is_blocked'] == true)
            const Chip(label: Text('Muted'), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: AppSpacing.md),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Posts', stats['posts_count']),
          _stat('Followers', stats['followers_count']),
          _stat('Following', stats['following_count']),
        ]),
      ]),
    );
  }

  Widget _stat(String label, Object? value) => Column(children: [
        Text('${value ?? 0}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]);
}
