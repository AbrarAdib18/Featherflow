import 'package:flutter/material.dart';
import '../../data/services/research_api_service.dart';
import '../research_theme.dart';

const int kMaxResearchTags = 8;

const Map<String, String> kTagCategoryLabels = {
  'disease': 'Disease', 'breed': 'Breed', 'age_group': 'Age group',
  'nutrition': 'Nutrition', 'research_field': 'Research field',
  'market': 'Market', 'other': 'Other',
};

/// Multi-select picker over the backend's constrained ResearchTag catalog.
/// Loads options once, groups them by category, and reports the selected
/// tag ids back to the caller for inclusion as `tag_ids` on submit.
class TagPicker extends StatefulWidget {
  final List<Map<String, dynamic>> initialTags;
  final ValueChanged<List<String>> onChanged;

  const TagPicker({super.key, this.initialTags = const [], required this.onChanged});

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  List<Map<String, dynamic>> _options = [];
  bool _loading = true;
  String? _error;
  late final Set<String> _selected =
      widget.initialTags.map((t) => t['id'].toString()).toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await ResearchApiService.instance.tagOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (_selected.length >= kMaxResearchTags) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can select up to $kMaxResearchTags tags.')),
          );
          return;
        }
        _selected.add(id);
      }
    });
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Text('Could not load tags: $_error',
          style: const TextStyle(color: RColors.needsRevision, fontSize: 12));
    }
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final tag in _options) {
      byCategory.putIfAbsent(tag['category'] as String, () => []).add(tag);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_selected.length}/$kMaxResearchTags tags selected',
            style: const TextStyle(fontSize: 11, color: RColors.textSecondary)),
        const SizedBox(height: 6),
        ...byCategory.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kTagCategoryLabels[entry.key] ?? entry.key,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: RColors.textSecondary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.value.map((tag) {
                      final id = tag['id'].toString();
                      final selected = _selected.contains(id);
                      return FilterChip(
                        label: Text(tag['name'] as String, style: const TextStyle(fontSize: 12)),
                        selected: selected,
                        onSelected: (_) => _toggle(id),
                        selectedColor: RColors.secondary.withValues(alpha: 0.2),
                        checkmarkColor: RColors.secondary,
                      );
                    }).toList(),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
