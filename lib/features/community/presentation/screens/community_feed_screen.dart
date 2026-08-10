import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:featherflow/core/theme/theme.dart';
import '../../../farmer/data/farm_management_service.dart';

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  int _selectedTopic = 0;
  int _selectedTab = 0;
  Map<String, dynamic>? _data;
  Map<String, dynamic> _notifications = {
    'notifications': <dynamic>[],
    'unread_count': 0
  };
  String? _error;
  Timer? _notificationTimer;
  @override
  void initState() {
    super.initState();
    _load();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshNotifications(),
    );
  }

  Future<void> _refreshNotifications() async {
    try {
      final value = await FarmManagementService.get('notifications');
      if (mounted) setState(() => _notifications = value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        FarmManagementService.get('community'),
        FarmManagementService.get('notifications')
      ]);
      final value = values[0];
      if (mounted) {
        setState(() {
          _data = value;
          _notifications = values[1];
          _error = null;
          if (_selectedTopic > List.from(value['topics']).length - 1) {
            _selectedTopic = 0;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;
    if (_data == null) {
      return Scaffold(
          backgroundColor: Colors.white,
          appBar: _buildAppBar(),
          body: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!)));
    }
    final topics = List<String>.from(_data!['topics'] ?? const ['All Posts']);
    final allPosts = List<Map<String, dynamic>>.from(
        (_data!['posts'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e)));
    final trending = List<String>.from(_data!['trending'] ?? const []);
    final selectedTopic = topics[_selectedTopic];
    final posts = allPosts
        .where((p) =>
            (selectedTopic == 'All Posts' || p['category'] == selectedTopic) &&
            (_selectedTab == 0 ||
                _selectedTab == 1 && p['category'] == 'Feed Prices' ||
                _selectedTab == 2 && p['category'] == 'Disease Help' ||
                _selectedTab == 3 && p['official'] == true))
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isWide)
            SizedBox(
              width: 200,
              child: _SidebarTopics(
                topics: topics,
                selected: _selectedTopic,
                onSelect: (i) => setState(() => _selectedTopic = i),
              ),
            ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isWide)
                        _TopicChips(
                          topics: topics,
                          selected: _selectedTopic,
                          onSelect: (i) => setState(() => _selectedTopic = i),
                        ),
                      _ComposeBox(onCompose: _compose),
                      const _SectionHeader(),
                    ],
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index < posts.length) {
                        return _FeedPost(
                            post: posts[index],
                            onAction: (action, content, parent) => _postAction(
                                posts[index], action,
                                content: content, parentId: parent));
                      }
                      return const _Footer();
                    },
                    childCount: posts.length + 1,
                  ),
                ),
              ],
            ),
          ),
          if (isWide)
            SizedBox(
              width: 220,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    _TrendingBox(
                        tags: trending, onTap: (tag) => _compose(tag: tag)),
                    const SizedBox(height: AppSpacing.md),
                    const _CommunityToolsBox(),
                    const SizedBox(height: AppSpacing.md),
                    const _WhyBox(),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        icon: PhosphorIcon(PhosphorIcons.pencilSimple(), size: 20),
        label: const Text(
          'Post',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  Future<void> _compose({String? tag}) async {
    final content = TextEditingController();
    String category = (tag ?? '').replaceFirst('#', '');
    bool anonymous = false;
    String? imageUrl;
    final topics = List<String>.from(_data!['topics'] ?? [])
        .where((x) => x != 'All Posts')
        .toList();
    if (category.isEmpty && topics.isNotEmpty) category = topics.first;
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Create Community Post'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: content,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              labelText: 'What would you like to share? *')),
                      DropdownButtonFormField<String>(
                          initialValue: category.isEmpty ? null : category,
                          items: topics
                              .map((x) =>
                                  DropdownMenuItem(value: x, child: Text(x)))
                              .toList(),
                          onChanged: (v) => setLocal(() => category = v ?? ''),
                          decoration:
                              const InputDecoration(labelText: 'Topic')),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                                type: FileType.image, withData: true);
                            if (picked != null &&
                                picked.files.single.bytes != null) {
                              final result = await FarmManagementService.upload(
                                  'community/upload',
                                  picked.files.single.bytes!,
                                  picked.files.single.name);
                              setLocal(() => imageUrl = result['url']);
                            }
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: Text(imageUrl == null
                              ? 'Choose image from device'
                              : 'Image selected')),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Anonymous Question'),
                          value: anonymous,
                          onChanged: (v) => setLocal(() => anonymous = v))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Post'))
                    ])));
    if (save == true) {
      await FarmManagementService.post('community', {
        'content': content.text,
        'category': category,
        'is_anonymous': anonymous,
        'media_urls': imageUrl == null ? [] : [imageUrl]
      });
      await _load();
    }
  }

  Future<void> _postAction(Map<String, dynamic> post, String action,
      {String? content, String? parentId}) async {
    try {
      if (action == 'Helpful' || action == 'React') {
        await FarmManagementService.post('community/react',
            {'post_id': post['id'], 'reaction_type': 'helpful'});
      } else if (action == 'Follow') {
        await FarmManagementService.post(
            'community/follow', {'post_id': post['id']});
      } else if ((action == 'Reply' || action == 'Ask Vet') &&
          content == null) {
        final c = TextEditingController();
        final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text(action == 'Ask Vet'
                        ? 'Ask the community veterinarian'
                        : 'Reply'),
                    content: TextField(
                        controller: c,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Comment *')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Send'))
                    ]));
        if (ok == true) {
          await FarmManagementService.post(
              'community/comment', {'post_id': post['id'], 'content': c.text});
        }
      } else if ((action == 'Reply' || action == 'Ask Vet') &&
          content != null) {
        await FarmManagementService.post('community/comment', {
          'post_id': post['id'],
          'content': content,
          'parent_comment_id': parentId
        });
      } else if (action == 'Save' || action == 'Solved later') {
        await FarmManagementService.post(
            'community/bookmark', {'post_id': post['id']});
      } else if (action == 'Share') {
        await Clipboard.setData(ClipboardData(text: post['body']));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Post copied for sharing.')));
        }
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showNotifications() async {
    final rows = List<Map<String, dynamic>>.from(
        (_notifications['notifications'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e)));
    await showDialog(
        context: context,
        builder: (ctx) =>
            AlertDialog(
                title: const Text('Community Activity'),
                content: SizedBox(
                    width: 380,
                    child: rows.isEmpty
                        ? const Text('No community activity yet.')
                        : ListView(
                            shrinkWrap: true,
                            children: rows
                                .map((x) => ListTile(
                                    leading: Icon(x['type'] == 'message'
                                        ? Icons.message_outlined
                                        : Icons.notifications_outlined),
                                    title: Text(x['title']),
                                    subtitle:
                                        Text('${x['body']}\n${x['time']}'),
                                    trailing: x['is_read']
                                        ? null
                                        : const CircleAvatar(
                                            radius: 4,
                                            backgroundColor:
                                                AppColors.secondary)))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'))
                ]));
    await FarmManagementService.patch('notifications', {});
    await _load();
  }

  PreferredSizeWidget _buildAppBar() {
    final tabs = ['Feed', 'Prices', 'Questions', 'Updates'];
    return PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: Container(
        color: AppColors.primary,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.feather(),
                  color: AppColors.secondary,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Featherflow Community',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        'Farmer posts, prices, questions, and Team Featherflow updates',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(tabs.length, (i) {
                      final selected = _selectedTab == i;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTab = i),
                        child: Container(
                          margin: const EdgeInsets.only(left: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: selected
                              ? const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.secondary,
                                      width: 2,
                                    ),
                                  ),
                                )
                              : null,
                          child: Text(
                            tabs[i],
                            style: TextStyle(
                              color: selected
                                  ? AppColors.secondary
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Stack(
                  children: [
                    IconButton(
                      onPressed: _showNotifications,
                      icon: PhosphorIcon(
                        PhosphorIcons.bell(),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if ((_notifications['unread_count'] as num? ?? 0) > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${_notifications['unread_count']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTopics extends StatelessWidget {
  final List<String> topics;
  final int selected;
  final void Function(int) onSelect;

  const _SidebarTopics({
    required this.topics,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F7F7),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(topics.length, (i) {
          final sel = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: sel
                  ? AppColors.secondary.withValues(alpha: 0.1)
                  : Colors.transparent,
              child: Row(
                children: [
                  if (sel)
                    Container(
                      width: 3,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: AppRadius.fullAll,
                      ),
                    ),
                  if (sel) const SizedBox(width: AppSpacing.sm),
                  PhosphorIcon(
                    PhosphorIcons.hash(),
                    size: 14,
                    color: sel ? AppColors.secondary : Colors.grey,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      topics[i],
                      style: TextStyle(
                        color: sel ? AppColors.primary : Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TopicChips extends StatelessWidget {
  final List<String> topics;
  final int selected;
  final void Function(int) onSelect;

  const _TopicChips({
    required this.topics,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F7F7),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: List.generate(topics.length, (i) {
            final sel = i == selected;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.secondary : Colors.white,
                    border: Border.all(
                      color: sel ? AppColors.secondary : Colors.grey.shade300,
                      width: 1,
                    ),
                    borderRadius: AppRadius.fullAll,
                  ),
                  child: Text(
                    topics[i],
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ComposeBox extends StatelessWidget {
  final void Function({String? tag}) onCompose;
  const _ComposeBox({required this.onCompose});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.secondary,
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: () => onCompose(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      'Ask the community, share a price, or post an update...',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _QuickTag(
                    label: '#FeedPrice',
                    onTap: () => onCompose(tag: '#FeedPrice')),
                _QuickTag(
                    label: '#DiseaseHelp',
                    onTap: () => onCompose(tag: '#DiseaseHelp')),
                _QuickTag(
                    label: '#Broiler', onTap: () => onCompose(tag: '#Broiler')),
                _QuickTag(
                    label: '#Layer', onTap: () => onCompose(tag: '#Layer')),
                _QuickTag(
                  label: 'Upload Photo',
                  icon: PhosphorIcons.image(),
                  onTap: () => onCompose(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          GestureDetector(
            onTap: () => onCompose(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: AppRadius.fullAll,
              ),
              child: Text(
                'Anonymous Question',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _QuickTag({required this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.08),
          borderRadius: AppRadius.fullAll,
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              PhosphorIcon(icon!, size: 12, color: AppColors.secondary),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Latest Feed',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Minimal social timeline',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _FeedPost extends StatefulWidget {
  final Map<String, dynamic> post;
  final Future<void> Function(String, String?, String?) onAction;

  const _FeedPost({required this.post, required this.onAction});
  @override
  State<_FeedPost> createState() => _FeedPostState();
}

class _FeedPostState extends State<_FeedPost> {
  bool expanded = false;
  final reply = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final bool official = post['official'] as bool;
    final bool pinned = post['pinned'] as bool;
    final bool verified = post['verified'] as bool;
    final bool hasImage = post['hasImage'] as bool;
    final String tag = post['tag'] as String;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: official
            ? AppColors.secondary.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: official
              ? AppColors.secondary.withValues(alpha: 0.2)
              : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: official
                    ? AppColors.secondary
                    : AppColors.secondary.withValues(alpha: 0.15),
                child: Text(
                  post['initial'] as String,
                  style: TextStyle(
                    color: official ? Colors.white : AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          post['author'] as String,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          PhosphorIcon(
                            PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                            size: 14,
                            color: Colors.green,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${post['role']} • ${post['time']}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (tag.isNotEmpty)
                Text(
                  tag,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (official && tag.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 1),
                    borderRadius: AppRadius.fullAll,
                  ),
                  child: const Text(
                    'Verified',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            post['body'] as String,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (hasImage) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network((post['media_urls'] as List).first,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        height: 100,
                        color: const Color(0xFFF5F5F5),
                        child: const Center(
                            child: Icon(Icons.broken_image_outlined))))),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (official) ...[
                _ActionBtn(
                    label:
                        '${post['reacted'] ? 'Reacted' : 'React'} (${post['helpful_count']})',
                    onPressed: () => widget.onAction('React', null, null)),
                _ActionBtn(
                    label: 'Share',
                    onPressed: () => widget.onAction('Share', null, null)),
                _ActionBtn(
                    label: post['following'] ? 'Following' : 'Follow',
                    onPressed: () => widget.onAction('Follow', null, null)),
                const Spacer(),
                if (pinned)
                  Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.pushPin(),
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'Pinned',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ] else ...[
                _ActionBtn(
                    label:
                        '${post['reacted'] ? 'Helpful ✓' : 'Helpful'} (${post['helpful_count']})',
                    onPressed: () => widget.onAction('Helpful', null, null)),
                _ActionBtn(
                    label: 'Reply (${post['comment_count']})',
                    onPressed: () => setState(() => expanded = !expanded)),
                _ActionBtn(
                    label: 'Ask Vet',
                    onPressed: () => setState(() => expanded = true)),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onAction('Solved later', null, null),
                  child: Text(
                    'Solved later',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (expanded) ...[
            const Divider(),
            ...(post['comments'] as List? ?? const []).map((raw) {
              final c = Map<String, dynamic>.from(raw);
              return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: c['is_vet'] == true
                          ? AppColors.secondary.withValues(alpha: .06)
                          : const Color(0xFFF7F7F7),
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                          color: c['is_vet'] == true
                              ? AppColors.secondary.withValues(alpha: .3)
                              : Colors.grey.shade200)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                            radius: 14,
                            child: Text(c['initial'],
                                style: const TextStyle(fontSize: 10))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Text(c['author'],
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                if (c['is_vet'] == true)
                                  const Padding(
                                      padding: EdgeInsets.only(left: 5),
                                      child: Text('VET',
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: AppColors.secondary,
                                              fontWeight: FontWeight.w800)))
                              ]),
                              Text('${c['role']} · ${c['time']}',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey.shade500)),
                              Text(c['content'],
                                  style: const TextStyle(fontSize: 12))
                            ]))
                      ]));
            }),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: reply,
                      decoration: const InputDecoration(
                          hintText: 'Write a reply...', isDense: true))),
              IconButton(
                  tooltip: 'Send reply',
                  icon: const Icon(Icons.send, color: AppColors.secondary),
                  onPressed: () async {
                    if (reply.text.trim().isNotEmpty) {
                      await widget.onAction('Reply', reply.text, null);
                      reply.clear();
                    }
                  })
            ])
          ],
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ActionBtn({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: Colors.grey.shade600,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

class _TrendingBox extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String> onTap;

  const _TrendingBox({required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trending',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: tags.map((tag) {
              return GestureDetector(
                onTap: () => onTap(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    borderRadius: AppRadius.fullAll,
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.hash(),
                        size: 10,
                        color: AppColors.secondary,
                      ),
                      Text(
                        tag.replaceFirst('#', ''),
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CommunityToolsBox extends StatelessWidget {
  const _CommunityToolsBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Community Tools',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ask anonymously, bookmark posts, report spam, and mark best answers to keep discussions useful and safe.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _WhyBox extends StatelessWidget {
  const _WhyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Why this matters',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This space helps farmers share prices, solve problems, and stay updated with Team Featherflow.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.md,
      ),
      child: Center(
        child: Text(
          'Featherflow • minimal community blog for farmers and official updates',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
