import 'package:flutter/material.dart';
import '../models/article.dart';

class FilterChipGroup extends StatelessWidget {
  final String title;
  final List<String> options;
  final Set<String> selected;
  final void Function(String item) onToggle;

  const FilterChipGroup({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ppLabel(size: 13, weight: FontWeight.w700, color: PPColors.textPrimary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected = selected.contains(opt);
            return GestureDetector(
              onTap: () => onToggle(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? PPColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? PPColors.primary : PPColors.border,
                  ),
                ),
                child: Text(
                  opt,
                  style: ppLabel(
                    size: 13,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.white : PPColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
