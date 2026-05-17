import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:featherflow/core/theme/theme.dart';

final _mockPosts = [
  {
    'id': '1',
    'author': 'Md. Hasan',
    'initial': 'M',
    'role': 'Broiler farmer',
    'time': '12 min ago',
    'tag': '#FeedPrice',
    'body':
        'Anyone know the current starter feed price in Dhaka area? My supplier raised the price again this week. Looking for a better rate and reliable contact.',
    'hasImage': true,
    'pinned': false,
    'verified': false,
    'official': false,
  },
  {
    'id': '2',
    'author': 'Team Featherflow',
    'initial': 'T',
    'role': 'Official update',
    'time': '1 hour ago',
    'tag': '',
    'body':
        "We've added the disease detection upgrade and vet map support. Next update will improve doctor matching and appointment requests. Thanks for being part of Featherflow.",
    'hasImage': true,
    'pinned': true,
    'verified': true,
    'official': true,
  },
  {
    'id': '3',
    'author': 'Shila Akter',
    'initial': 'S',
    'role': 'Layer farm',
    'time': '3 hours ago',
    'tag': '#DiseaseHelp',
    'body':
        'My birds are sneezing and not eating much. I posted a photo earlier but want to know what others did before calling the vet. Any quick advice from experienced farmers?',
    'hasImage': false,
    'pinned': false,
    'verified': false,
    'official': false,
  },
  {
    'id': '4',
    'author': 'Shila Akter',
    'initial': 'S',
    'role': 'Layer farm',
    'time': '5 hours ago',
    'tag': '#DiseaseHelp',
    'body':
        'My birds are sneezing and not eating much. I posted a photo earlier but want to know what others did before calling the vet. Any quick advice from experienced farmers?',
    'hasImage': false,
    'pinned': true,
    'verified': false,
    'official': true,
  },
];

final _mockTrending = [
  '#FeedPrice',
  '#Broiler',
  '#EggMarket',
  '#Vaccination',
  '#TaxHelp',
];

final _mockTopics = [
  'All Posts',
  'Feed Prices',
  'Disease Help',
  'Market News',
  'Success Stories',
  'Team Featherflow',
];

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  int _selectedTopic = 0;
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

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
                topics: _mockTopics,
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
                          topics: _mockTopics,
                          selected: _selectedTopic,
                          onSelect: (i) => setState(() => _selectedTopic = i),
                        ),
                      const _ComposeBox(),
                      const _SectionHeader(),
                    ],
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index < _mockPosts.length) {
                        return _FeedPost(post: _mockPosts[index]);
                      }
                      return const _Footer();
                    },
                    childCount: _mockPosts.length + 1,
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
                    _TrendingBox(tags: _mockTrending),
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
        onPressed: () {},
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
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
                              color: selected ? AppColors.secondary : Colors.white60,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
                      onPressed: () {},
                      icon: PhosphorIcon(
                        PhosphorIcons.bell(),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
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
                        child: const Center(
                          child: Text(
                            '3',
                            style: TextStyle(
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
  const _ComposeBox();

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
                  onTap: () {},
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
                _QuickTag(label: '#FeedPrice'),
                _QuickTag(label: '#DiseaseHelp'),
                _QuickTag(label: '#Broiler'),
                _QuickTag(label: '#Layer'),
                _QuickTag(
                  label: 'Upload Photo',
                  icon: PhosphorIcons.image(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          GestureDetector(
            onTap: () {},
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

  const _QuickTag({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
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

class _FeedPost extends StatelessWidget {
  final Map<String, dynamic> post;

  const _FeedPost({required this.post});

  @override
  Widget build(BuildContext context) {
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
                            PhosphorIcons.checkCircle(
                                PhosphorIconsStyle.fill),
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
            Container(
              width: double.infinity,
              height: official ? 110 : 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  official
                      ? 'Software update banner'
                      : 'Image / chart preview area',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (official) ...[
                _ActionBtn(label: 'React'),
                _ActionBtn(label: 'Share'),
                _ActionBtn(label: 'Follow'),
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
                _ActionBtn(label: 'Helpful'),
                _ActionBtn(label: 'Reply'),
                _ActionBtn(label: 'Ask Vet'),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
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
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;

  const _ActionBtn({required this.label});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {},
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

  const _TrendingBox({required this.tags});

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
                onTap: () {},
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
