import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/article.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: PPColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PPColors.primary, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIcons.checkCircle(),
            size: 10,
            color: PPColors.primary,
          ),
          const SizedBox(width: 3),
          Text(
            'Verified',
            style: ppLabel(size: 10, weight: FontWeight.w600, color: PPColors.primary),
          ),
        ],
      ),
    );
  }
}
