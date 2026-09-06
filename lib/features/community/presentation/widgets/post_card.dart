import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:featherflow/core/theme/theme.dart';

import 'community_widgets.dart';

const communityReportReasons = <String, String>{
  'spam': 'Spam or advertising',
  'false_advice': 'False or misleading advice',
  'harmful_treatment': 'Harmful treatment claim',
  'abusive': 'Abusive or hateful',
  'harassment': 'Harassment',
  'other': 'Something else',
};

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onTap,
    required this.onReact,
    required this.onBookmark,
    required this.onRepost,
    required this.onReport,
    this.onVote,
    this.onOpenAuthor,
    this.onOpenTag,
    this.onMuteAuthor,
    this.dense = false,
  });

  final Map<String, dynamic> post;
  final VoidCallback onTap;
  final void Function(String type) onReact;
  final VoidCallback onBookmark;
  final VoidCallback onRepost;
  final void Function(String reason) onReport;
  final void Function(List<int> indexes)? onVote;
  final VoidCallback? onOpenAuthor;
  final void Function(String tag)? onOpenTag;
  final void Function(String authorId)? onMuteAuthor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(post['author'] as Map? ?? const {});
    final type = post['post_type']?.toString() ?? 'text';
    final official = post['is_official'] == true;
    final pinned = post['is_pinned'] == true;
    final trending = post['is_trending'] == true;
    final tags = List<String>.from(post['tags'] as List? ?? const []);
    final media = List<String>.from(post['media_urls'] as List? ?? const []);
    final reactions = Map<String, dynamic>.from(post['reactions'] as Map? ?? const {});
    final comments = (post['comments_count'] as num?)?.toInt() ?? 0;
    final reposts = (post['reposts_count'] as num?)?.toInt() ?? 0;
    final bookmarked = post['bookmarked'] == true;
    final status = post['status']?.toString() ?? 'active';

    return CommunityCard(
      highlight: official || pinned,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AuthorRow(
          author: author,
          time: post['time']?.toString() ?? '',
          onTapAuthor: onOpenAuthor,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (pinned) Icon(Icons.push_pin, size: 13, color: Colors.grey.shade500),
            if (trending) ...[
              const SizedBox(width: 4),
              const Icon(Icons.trending_up, size: 15, color: AppColors.secondary),
            ],
            _overflow(context),
          ]),
        ),
        if (status != 'active')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _StatusChip(status: status, reason: post['hidden_reason']?.toString()),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (type == 'question' && (post['title']?.toString().isNotEmpty ?? false)) ...[
          Row(children: [
            const _Kind(icon: Icons.help_outline, label: 'Question', color: Color(0xFF7C3AED)),
            if (post['best_answer_id'] != null) ...[
              const SizedBox(width: AppSpacing.xs),
              const _Kind(icon: Icons.check_circle, label: 'Answered', color: AppColors.secondary),
            ],
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text(post['title'].toString(),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary, height: 1.35)),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (type == 'poll')
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: _Kind(icon: Icons.bar_chart, label: 'Poll', color: Color(0xFF2563EB)),
          ),
        if ((post['content']?.toString() ?? '').isNotEmpty)
          Text(post['content'].toString(),
              maxLines: dense ? 4 : 10,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.grey.shade800)),
        if (type == 'poll' && post['poll'] != null && onVote != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PollView(poll: Map<String, dynamic>.from(post['poll'] as Map), onVote: onVote!),
        ],
        MediaStrip(urls: media),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            for (final t in tags)
              GestureDetector(
                onTap: onOpenTag == null ? null : () => onOpenTag!('#$t'),
                child: Text('#$t',
                    style: const TextStyle(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.xs),
        Row(children: [
          ReactionBar(reactions: reactions, onReact: onReact),
          const SizedBox(width: AppSpacing.xs),
          CommunityActionButton(icon: Icons.chat_bubble_outline, label: '$comments', onTap: onTap),
          const SizedBox(width: AppSpacing.xs),
          CommunityActionButton(
              icon: Icons.repeat, label: '$reposts', active: post['reposted'] == true, onTap: onRepost),
          const Spacer(),
          CommunityActionButton(
              icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
              label: '',
              active: bookmarked,
              onTap: onBookmark),
        ]),
      ]),
    );
  }

  Widget _overflow(BuildContext context) {
    final authorId = (post['author'] as Map?)?['id']?.toString();
    final canMute = onMuteAuthor != null && authorId != null && post['author']?['anonymous'] != true;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade500),
      onSelected: (v) async {
        if (v == 'share') {
          await Clipboard.setData(ClipboardData(text: post['content']?.toString() ?? ''));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Post copied for sharing.')));
          }
        } else if (v == 'report') {
          final reason = await pickReportReason(context);
          if (reason != null) onReport(reason);
        } else if (v == 'mute') {
          onMuteAuthor!(authorId!);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'share',
            child: Row(children: [Icon(Icons.share, size: 16), SizedBox(width: 8), Text('Share')])),
        const PopupMenuItem(
            value: 'report',
            child: Row(children: [
              Icon(Icons.flag_outlined, size: 16, color: AppColors.error),
              SizedBox(width: 8),
              Text('Report'),
            ])),
        if (canMute)
          const PopupMenuItem(
              value: 'mute',
              child: Row(children: [
                Icon(Icons.volume_off_outlined, size: 16),
                SizedBox(width: 8),
                Text('Mute this user'),
              ])),
      ],
    );
  }
}

Future<String?> pickReportReason(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text('Why are you reporting this?', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final e in communityReportReasons.entries)
          ListTile(dense: true, title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
      ]),
    ),
  );
}

class _Kind extends StatelessWidget {
  const _Kind({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.smAll),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.reason});
  final String status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'flagged' => 'Auto-hidden — under review',
      'hidden' => 'Hidden by a moderator',
      'removed' => 'Removed',
      _ => status,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: AppRadius.smAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.visibility_off_outlined, size: 13, color: AppColors.error),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
        ]),
        if (reason != null && reason!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(reason!, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ),
      ]),
    );
  }
}
