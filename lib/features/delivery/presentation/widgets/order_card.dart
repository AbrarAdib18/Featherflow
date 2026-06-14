import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../delivery_theme.dart';

class OrderCard extends StatelessWidget {
  final DeliveryOrder order;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onTap;
  final bool showActions;

  const OrderCard({
    super.key,
    required this.order,
    this.onAccept,
    this.onReject,
    this.onTap,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: dCard(highlight: order.type == OrderType.pharmacy),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${order.id}',
                    style: const TextStyle(
                      color: DColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (order.type == OrderType.pharmacy)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EAF6),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFF3F51B5)
                                .withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.medical_services_outlined,
                              color: Color(0xFF3F51B5), size: 11),
                          SizedBox(width: 3),
                          Text('Medicine',
                              style: TextStyle(
                                  color: Color(0xFF3F51B5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  _statusChip(order.status),
                ],
              ),
              const SizedBox(height: 10),
              _addressRow(Icons.radio_button_checked, DColors.accent,
                  order.pickupAddress),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                    width: 1, height: 14, color: DColors.cardBorder),
              ),
              _addressRow(
                  Icons.location_on, DColors.red, order.dropAddress),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.straighten, color: DColors.grey, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '${order.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: DColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: DColors.accent, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '৳${order.earning.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: DColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (showActions) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DColors.red,
                          side: BorderSide(
                              color: DColors.red.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Reject',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Accept',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow(IconData icon, Color iconColor, String address) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
                color: DColors.textSecondary, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _statusChip(OrderStatus status) {
    final (label, bg, fg) = switch (status) {
      OrderStatus.pending =>
        ('Pending', DColors.orangeLight, DColors.orange),
      OrderStatus.accepted =>
        ('Accepted', DColors.accentLight, DColors.accent),
      OrderStatus.pickedUp =>
        ('Picked Up', DColors.accentLight, DColors.accent),
      OrderStatus.onTheWay =>
        ('On The Way', DColors.accentLight, DColors.accentMid),
      OrderStatus.delivered =>
        ('Delivered', DColors.accentLight, DColors.accent),
      OrderStatus.failed =>
        ('Failed', DColors.redLight, DColors.red),
      OrderStatus.cancelled =>
        ('Cancelled', DColors.surface2, DColors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
