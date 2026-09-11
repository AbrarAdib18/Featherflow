import 'package:flutter/material.dart';

import 'package:featherflow/core/theme/theme.dart';

/// The four reaction types the backend accepts, in display order.
const communityReactions = <String, String>{
  'like': 'Like',
  'love': 'Love',
  'helpful': 'Helpful',
  'insightful': 'Insightful',
};

IconData reactionIcon(String type, {bool filled = false}) => switch (type) {
      'like' => filled ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
      'love' => filled ? Icons.favorite : Icons.favorite_border,
      'helpful' => filled ? Icons.check_circle : Icons.check_circle_outline,
      _ => filled ? Icons.lightbulb : Icons.lightbulb_outline,
    };

Color badgeColor(String? type) => switch (type) {
      'team' => const Color(0xFF2563EB),
      'researcher' => const Color(0xFF7C3AED),
      'doctor' => AppColors.secondary,
      'pharmacy' => const Color(0xFF0E9F6E),
      _ => AppColors.secondary,
    };

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.badge, this.compact = true});
  final Map<String, dynamic>? badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (badge == null) return const SizedBox.shrink();
    final color = badgeColor(badge!['type']?.toString());
    final label = badge!['label']?.toString() ?? 'Verified';
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xxs),
        child: Tooltip(message: label, child: Icon(Icons.verified, size: 14, color: color)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.fullAll,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class AuthorRow extends StatelessWidget {
  const AuthorRow({super.key, required this.author, required this.time, this.trailing, this.onTapAuthor});
  final Map<String, dynamic> author;
  final String time;
  final Widget? trailing;
  final VoidCallback? onTapAuthor;

  @override
  Widget build(BuildContext context) {
    final anon = author['anonymous'] == true;
    final name = author['name']?.toString() ?? 'Community member';
    final initial = (author['initial']?.toString().trim().isNotEmpty ?? false)
        ? author['initial'].toString()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    final role = author['role']?.toString() ?? 'Community member';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: anon ? null : onTapAuthor,
        child: CircleAvatar(
          radius: 18,
          backgroundColor: anon ? Colors.grey.shade300 : AppColors.secondary.withValues(alpha: 0.18),
          child: anon
              ? Icon(Icons.person_off_outlined, size: 16, color: Colors.grey.shade700)
              : Text(initial,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: GestureDetector(
                onTap: anon ? null : onTapAuthor,
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ),
            VerifiedBadge(badge: author['badge'] as Map<String, dynamic>?),
          ]),
          Text('$role · $time', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class ReactionBar extends StatelessWidget {
  const ReactionBar({super.key, required this.reactions, required this.onReact});
  final Map<String, dynamic> reactions;
  final void Function(String type) onReact;

  @override
  Widget build(BuildContext context) {
    final mine = reactions['my_reaction']?.toString();
    final total = (reactions['total'] as num?)?.toInt() ?? 0;
    return PopupMenuButton<String>(
      tooltip: 'React',
      onSelected: onReact,
      itemBuilder: (_) => communityReactions.entries
          .map((e) => PopupMenuItem<String>(
                value: e.key,
                child: Row(children: [
                  Icon(reactionIcon(e.key), size: 16, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Text(e.value),
                ]),
              ))
          .toList(),
      child: communityPill(
        icon: reactionIcon(mine ?? 'like', filled: mine != null),
        label: mine == null ? 'React${total > 0 ? ' ($total)' : ''}' : '${communityReactions[mine]} ($total)',
        active: mine != null,
      ),
    );
  }
}

Widget communityPill({required IconData icon, required String label, bool active = false}) {
  final color = active ? AppColors.secondary : Colors.grey.shade600;
  return Container(
    padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : AppSpacing.sm, vertical: 5),
    decoration: BoxDecoration(
      color: active ? AppColors.secondary.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: AppRadius.fullAll,
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: color),
      if (label.isNotEmpty) ...[
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    ]),
  );
}

class CommunityActionButton extends StatelessWidget {
  const CommunityActionButton(
      {super.key, required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: AppRadius.fullAll,
        onTap: onTap,
        child: communityPill(icon: icon, label: label, active: active),
      );
}

class PollView extends StatelessWidget {
  const PollView({super.key, required this.poll, required this.onVote});
  final Map<String, dynamic> poll;
  final void Function(List<int> indexes) onVote;

  @override
  Widget build(BuildContext context) {
    final options = List<Map<String, dynamic>>.from(
        (poll['options'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final total = (poll['total_votes'] as num?)?.toInt() ?? 0;
    final myVote = (poll['my_vote'] as List?)?.map((e) => (e as num).toInt()).toSet() ?? <int>{};
    final voted = myVote.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: _PollOption(
            text: o['text']?.toString() ?? '',
            votes: (o['votes'] as num?)?.toInt() ?? 0,
            total: total,
            selected: myVote.contains(o['index']),
            showResults: voted,
            onTap: voted ? null : () => onVote([(o['index'] as num).toInt()]),
          ),
        ),
      Text('$total vote${total == 1 ? '' : 's'}${voted ? ' · you voted' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ]);
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.text,
    required this.votes,
    required this.total,
    required this.selected,
    required this.showResults,
    this.onTap,
  });
  final String text;
  final int votes;
  final int total;
  final bool selected;
  final bool showResults;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : votes / total;
    return InkWell(
      borderRadius: AppRadius.smAll,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.smAll,
          border: Border.all(color: selected ? AppColors.secondary : Colors.grey.shade300),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (showResults)
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(height: 34, color: AppColors.secondary.withValues(alpha: 0.14)),
            ),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (showResults)
                Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Renders images / video links / documents attached to a post or comment.
class MediaStrip extends StatelessWidget {
  const MediaStrip({super.key, required this.urls});
  final List<String> urls;

  static bool isImage(String u) {
    final l = u.toLowerCase();
    return l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.png') ||
        l.endsWith('.webp') || l.endsWith('.gif');
  }

  void _openViewer(BuildContext context, List<String> images) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            PageView(
              children: [
                for (final url in images)
                  InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54, size: 48)),
                    ),
                  ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final images = urls.where(isImage).toList();
    final others = urls.where((u) => !isImage(u)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (images.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onTap: () => _openViewer(context, images),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network(images.first,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: const Color(0xFFF3F3F3),
                        child: const Center(
                            child: Icon(Icons.broken_image_outlined)))),
              ),
              if (images.length > 1)
                Container(
                  margin: const EdgeInsets.all(6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('1/${images.length}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11)),
                ),
            ],
          ),
        ),
      ],
      for (final url in others)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(url.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.attachment,
                size: 15, color: AppColors.secondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(url.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
    ]);
  }
}

class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, required this.child, this.highlight = false, this.onTap});
  final Widget child;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: highlight ? AppColors.secondary.withValues(alpha: 0.05) : Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: highlight ? AppColors.secondary.withValues(alpha: 0.3) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
        ),
      ),
    );
  }
}

/// Shared empty / error / loading state, matching the other panels' feel.
class CommunityStateView extends StatelessWidget {
  const CommunityStateView({super.key, required this.icon, required this.title, this.subtitle, this.onRetry});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: AppSpacing.sm),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}
