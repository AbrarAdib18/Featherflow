import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../delivery_theme.dart';

class StatusStepper extends StatelessWidget {
  final OrderStatus currentStatus;

  const StatusStepper({super.key, required this.currentStatus});

  static const _steps = [
    (OrderStatus.accepted, 'Accepted', Icons.check_circle_outline),
    (OrderStatus.pickedUp, 'Picked Up', Icons.inventory_2_outlined),
    (OrderStatus.onTheWay, 'Out for delivery', Icons.directions_bike_outlined),
    (OrderStatus.arrived, 'Arrived', Icons.location_on_outlined),
    (OrderStatus.proofSubmitted, 'Proof review', Icons.fact_check_outlined),
    (OrderStatus.delivered, 'Completed', Icons.where_to_vote_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIdx = _stepIndex(currentStatus);
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIdx = i ~/ 2;
          final done = stepIdx < currentIdx;
          return Expanded(
            child: Container(
              height: 2,
              color: done ? DColors.accent : DColors.cardBorder,
            ),
          );
        }
        final stepIdx = i ~/ 2;
        final (_, label, icon) = _steps[stepIdx];
        final done = stepIdx < currentIdx;
        final active = stepIdx == currentIdx;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: done
                    ? DColors.accentLight
                    : active
                        ? DColors.accentLight
                        : DColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done
                      ? DColors.accent
                      : active
                          ? DColors.primary
                          : DColors.cardBorder,
                  width: 1.5,
                ),
              ),
              child: Icon(
                done ? Icons.check : icon,
                color: done
                    ? DColors.accent
                    : active
                        ? DColors.primary
                        : DColors.grey,
                size: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? DColors.primary : DColors.grey,
                fontSize: 8,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        );
      }),
    );
  }

  int _stepIndex(OrderStatus status) => switch (status) {
        OrderStatus.accepted => 0,
        OrderStatus.pickedUp => 1,
        OrderStatus.onTheWay => 2,
        OrderStatus.arrived => 3,
        OrderStatus.proofSubmitted || OrderStatus.proofRejected => 4,
        OrderStatus.delivered => 5,
        _ => 0,
      };
}
