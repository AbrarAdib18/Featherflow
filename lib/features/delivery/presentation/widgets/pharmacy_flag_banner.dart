import 'package:flutter/material.dart';
import '../delivery_theme.dart';

class PharmacyFlagBanner extends StatelessWidget {
  const PharmacyFlagBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF3F51B5).withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.medical_services_outlined,
              color: Color(0xFF3F51B5), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medicine Delivery — Handle with care',
                  style: TextStyle(
                    color: Color(0xFF283593),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'OTP required at handover. Keep package upright.',
                  style: TextStyle(
                      color: DColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
