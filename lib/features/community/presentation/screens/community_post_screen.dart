import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:featherflow/core/theme/theme.dart';
import 'package:featherflow/core/network/auth_service.dart';

import '../../data/community_api_service.dart';
import '../widgets/community_widgets.dart';
import '../widgets/post_card.dart';

class CommunityPostScreen extends StatefulWidget {
  const CommunityPostScreen({super.key, required this.postId});
  final String postId;

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final _api = CommunityApiService.instance;
  final _commentController = TextEditingController();

  Map<String, dynamic>? _post;
  String? _error;
  bool _anonymousComment = false;
  bool _sending = false;
  Map<String, dynamic>? _replyingTo;
  Timer? _poll;

  String get _myId => AuthService.instance.currentSession?.user.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final data = await _api.post(widget.postId);
      if (mounted) {
        setState(() {
          _post = data;
          _error = null;
        });
      }
    } on CommunityApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && !silent) setState(() => _error = e.toString());
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load(silent: true);
    } on CommunityApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.comment(widget.postId, text,
          parentId: _replyingTo?['id']?.toString(), anonymous: _anonymousComment);
      _commentController.clear();
      setState(() => _replyingTo = null);
      await _load(silent: true);
    } on CommunityApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(post?['post_type'] == 'question' ? 'Question' : 'Post'),
        actions: [
          if (post != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'bookmark') {
                  await _guard(() => _api.toggleBookmark(widget.postId).then((_) {}));
                } else if (v == 'share') {
                  await Clipboard.setData(ClipboardData(text: post['content']?.toString() ?? ''));
                  _toast('Post copied for sharing.');
                } else if (v == 'report') {
                  final reason = await pickReportReason(context);
                  if (reason != null) {
                    await _guard(() async {
                      await _api.report(targetType: 'post', targetId: widget.postId, reason: reason);
                      _toast('Report sent to moderators.');
                    });
                  }
                } else if (v == 'delete') {
                  final router = GoRouter.of(context);
                  await _guard(() async {
                    await _api.deletePost(widget.postId);
                    if (mounted) router.pop();
                  });
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'bookmark',
                    child: Text(post['bookmarked'] == true ? 'Remove bookmark' : 'Bookmark')),
                const PopupMenuItem(value: 'share', child: Text('Share')),
                const PopupMenuItem(value: 'report', child: Text('Report')),
                if ((post['author'] as Map?)?['id']?.toString() == _myId)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: post == null
          ? (_error != null
              ? CommunityStateView(icon: Icons.error_outline, title: 'Could not open this post', subtitle: _error, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : _content(post),
      bottomNavigationBar: post == null ? null : _composer(),
    );
  }

  Widget _content(Map<String, dynamic> post) {
    final comments = List<Map<String, dynamic>>.from(
        (post['comments'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final roots = comments.where((c) => c['parent_comment_id'] == null).toList();
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final c in comments) {
      final pid = c['parent_comment_id']?.toString();
      if (pid != null) byParent.putIfAbsent(pid, () => []).add(c);
    }
    final isQuestion = post['post_type'] == 'question';
    final canMarkBest = post['can_mark_best_answer'] == true;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          PostCard(
            post: post,
            onTap: () {},
            onOpenAuthor: () {
              final id = (post['author'] as Map?)?['id']?.toString();
              if (id != null) context.push('/community/user/$id');
            },
            onOpenTag: (tag) => context.push('/community/search?tag=$tag'),
            onMuteAuthor: (authorId) => _guard(() async {
              await _api.blockUser(authorId);
              _toast('Muted from your feed.');
            }),
            onReact: (type) => _guard(() => _api.react(widget.postId, type).then((_) {})),
            onBookmark: () => _guard(() => _api.toggleBookmark(widget.postId).then((_) {})),
            onRepost: () => _guard(() => _api.repost(widget.postId).then((_) {})),
            onReport: (reason) => _guard(() async {
              await _api.report(targetType: 'post', targetId: widget.postId, reason: reason);
              _toast('Report sent to moderators.');
            }),
            onVote: (indexes) => _guard(() => _api.votePoll(widget.postId, indexes).then((_) {})),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Text('${comments.length} ${comments.length == 1 ? 'reply' : 'replies'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (roots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: Text('No replies yet. Start the conversation.', style: TextStyle(color: Colors.grey))),
            ),
          for (final c in roots) ...[
            _CommentTile(
              comment: c,
              isQuestion: isQuestion,
              canMarkBest: canMarkBest,
              onReply: () => setState(() => _replyingTo = c),
              onReact: (t) => _guard(() => _api.reactToComment(c['id'].toString(), t).then((_) {})),
              onReport: () => _reportComment(c),
              onMarkBest: () => _guard(() =>
                  _api.markBestAnswer(c['id'].toString(), value: c['is_best_answer'] != true).then((_) {})),
            ),
            for (final r in byParent[c['id'].toString()] ?? const <Map<String, dynamic>>[])
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: _CommentTile(
                  comment: r,
                  isQuestion: isQuestion,
                  canMarkBest: canMarkBest,
                  onReply: () => setState(() => _replyingTo = c),
                  onReact: (t) => _guard(() => _api.reactToComment(r['id'].toString(), t).then((_) {})),
                  onReport: () => _reportComment(r),
                  onMarkBest: () => _guard(() =>
                      _api.markBestAnswer(r['id'].toString(), value: r['is_best_answer'] != true).then((_) {})),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _reportComment(Map<String, dynamic> c) async {
    final reason = await pickReportReason(context);
    if (reason == null) return;
    await _guard(() async {
      await _api.report(targetType: 'comment', targetId: c['id'].toString(), reason: reason);
      _toast('Report sent to moderators.');
    });
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyingTo != null)
            Row(children: [
              Expanded(
                child: Text('Replying to ${(_replyingTo!['author'] as Map?)?['name'] ?? 'comment'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
              GestureDetector(
                onTap: () => setState(() => _replyingTo = null),
                child: const Icon(Icons.close, size: 14),
              ),
            ]),
          Row(children: [
            IconButton(
              tooltip: _anonymousComment ? 'Posting anonymously' : 'Post as yourself',
              icon: Icon(_anonymousComment ? Icons.person_off : Icons.person_outline,
                  color: _anonymousComment ? AppColors.secondary : Colors.grey),
              onPressed: () => setState(() => _anonymousComment = !_anonymousComment),
            ),
            Expanded(
              child: TextField(
                controller: _commentController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Write a reply…', isDense: true, border: InputBorder.none),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, color: AppColors.secondary),
              onPressed: _sending ? null : _sendComment,
            ),
          ]),
        ]),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isQuestion,
    required this.canMarkBest,
    required this.onReply,
    required this.onReact,
    required this.onReport,
    required this.onMarkBest,
  });

  final Map<String, dynamic> comment;
  final bool isQuestion;
  final bool canMarkBest;
  final VoidCallback onReply;
  final void Function(String type) onReact;
  final VoidCallback onReport;
  final VoidCallback onMarkBest;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(comment['author'] as Map? ?? const {});
    final best = comment['is_best_answer'] == true;
    final reactions = Map<String, dynamic>.from(comment['reactions'] as Map? ?? const {});
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: best ? AppColors.secondary.withValues(alpha: 0.06) : Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: best ? AppColors.secondary.withValues(alpha: 0.4) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (best)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.verified, size: 13, color: AppColors.secondary),
              SizedBox(width: 4),
              Text('Best answer', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.secondary)),
            ]),
          ),
        AuthorRow(author: author, time: comment['time']?.toString() ?? ''),
        const SizedBox(height: 6),
        Text(comment['content']?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.45)),
        const SizedBox(height: 4),
        Row(children: [
          ReactionBar(reactions: reactions, onReact: onReact),
          TextButton(onPressed: onReply, child: const Text('Reply', style: TextStyle(fontSize: 12))),
          if (isQuestion && canMarkBest)
            TextButton(
              onPressed: onMarkBest,
              child: Text(best ? 'Unmark' : 'Mark best', style: const TextStyle(fontSize: 12)),
            ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.flag_outlined, size: 15, color: Colors.grey.shade400),
            onPressed: onReport,
          ),
        ]),
      ]),
    );
  }
}
