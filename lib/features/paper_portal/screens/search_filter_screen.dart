import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';
import '../widgets/filter_chip_group.dart';

const _topicOptions = [
  'Broiler', 'Layer', 'Turkey', 'Duck',
  'Feed Efficiency', 'Biosecurity', 'Vaccines',
  'Newcastle Disease', 'Avian Flu',
];

const _ageGroupOptions = ['Chick 0–4w', 'Grower 4–8w', 'Adult 8w+'];

const _sortLabels = {
  SortOrder.latest: 'Latest',
  SortOrder.mostRead: 'Most Read',
  SortOrder.mostCited: 'Most Cited',
  SortOrder.trending: 'Trending',
};

class SearchFilterScreen extends StatefulWidget {
  final Set<String> initialTopics;
  final Set<String> initialAgeGroups;
  final SortOrder initialSort;
  final void Function(Set<String> topics, Set<String> ageGroups, SortOrder sort) onApply;

  const SearchFilterScreen({
    super.key,
    required this.initialTopics,
    required this.initialAgeGroups,
    required this.initialSort,
    required this.onApply,
  });

  @override
  State<SearchFilterScreen> createState() => _SearchFilterScreenState();
}

class _SearchFilterScreenState extends State<SearchFilterScreen> {
  late Set<String> _topics;
  late Set<String> _ageGroups;
  late SortOrder _sort;

  @override
  void initState() {
    super.initState();
    _topics = Set.from(widget.initialTopics);
    _ageGroups = Set.from(widget.initialAgeGroups);
    _sort = widget.initialSort;
  }

  void _clearAll() {
    setState(() {
      _topics.clear();
      _ageGroups.clear();
      _sort = SortOrder.latest;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: PPColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: PPColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Filters',
                    style: ppTitle(size: 17, color: PPColors.textPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearAll,
                    child: Text(
                      'Clear all',
                      style: ppLabel(size: 13, color: PPColors.primary, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: PPColors.border),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilterChipGroup(
                      title: 'Topic',
                      options: _topicOptions,
                      selected: _topics,
                      onToggle: (item) => setState(() {
                        _topics.contains(item) ? _topics.remove(item) : _topics.add(item);
                      }),
                    ),
                    const SizedBox(height: 20),
                    FilterChipGroup(
                      title: 'Age Group',
                      options: _ageGroupOptions,
                      selected: _ageGroups,
                      onToggle: (item) => setState(() {
                        _ageGroups.contains(item)
                            ? _ageGroups.remove(item)
                            : _ageGroups.add(item);
                      }),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sort By',
                      style: ppLabel(size: 13, weight: FontWeight.w700, color: PPColors.textPrimary),
                    ),
                    const SizedBox(height: 10),
                    RadioGroup<SortOrder>(
                      groupValue: _sort,
                      onChanged: (v) => setState(() => _sort = v!),
                      child: Column(
                        children: SortOrder.values
                            .map((s) => RadioListTile<SortOrder>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: PPColors.primary,
                                  title: Text(
                                    _sortLabels[s]!,
                                    style: ppLabel(size: 14, color: PPColors.textPrimary),
                                  ),
                                  value: s,
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(_topics, _ageGroups, _sort);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PPColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: ppLabel(size: 15, weight: FontWeight.w700, color: Colors.white),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PhosphorIcon(PhosphorIcons.funnel(), size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('Apply Filters'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
