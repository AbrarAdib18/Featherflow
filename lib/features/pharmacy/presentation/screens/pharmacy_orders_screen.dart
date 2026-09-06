import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/medicine_models.dart';
import '../../data/services/pharmacy_session.dart';
import '../pharmacy_theme.dart';
import 'pharmacy_dashboard_screen.dart' show orderStatusColors;

class PharmacyOrdersScreen extends StatefulWidget {
  const PharmacyOrdersScreen({super.key});

  @override
  State<PharmacyOrdersScreen> createState() => _PharmacyOrdersScreenState();
}

class _PharmacyOrdersScreenState extends State<PharmacyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  static const _tabs2 = [
    (label: 'Incoming', filter: [PharmacyOrderStatus.pending]),
    (label: 'Preparing', filter: [PharmacyOrderStatus.preparing]),
    (
      label: 'Delivery',
      filter: [PharmacyOrderStatus.readyForDelivery, PharmacyOrderStatus.outForDelivery]
    ),
    (label: 'Completed', filter: [PharmacyOrderStatus.delivered]),
    (
      label: 'Cancelled',
      filter: [
        PharmacyOrderStatus.cancelled,
        PharmacyOrderStatus.refunded,
        PharmacyOrderStatus.deliveryFailed
      ]
    ),
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PharmacySession.instance,
      builder: (context, _) {
        final s = PharmacySession.instance;
        return Scaffold(
          backgroundColor: PhColors.bg,
          appBar: AppBar(
            backgroundColor: PhColors.appBar,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Row(children: [
              const Text('Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (s.incomingOrderCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: PhColors.pending, borderRadius: BorderRadius.circular(10)),
                  child: Text('${s.incomingOrderCount}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ]),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: PhColors.secondary,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: _tabs2.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: _tabs2.map((t) {
              final orders = s.recentOrders.where((o) => t.filter.contains(o.status)).toList();
              if (orders.isEmpty) {
                return const _Empty();
              }
              return RefreshIndicator(
                onRefresh: s.refresh,
                color: PhColors.secondary,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OrderCard(order: orders[i]),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final CatalogueOrder order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = orderStatusColors(order.status);
    return Container(
      decoration: phCard(
          borderColor: order.status == PharmacyOrderStatus.pending
              ? PhColors.pending.withValues(alpha: .35)
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: fg.withValues(alpha: .05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(children: [
              Text(order.orderNumber,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
              const Spacer(),
              phChip(order.status.label, bg, fg),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.person_outline, size: 14, color: PhColors.textSecondary),
                const SizedBox(width: 6),
                Text(order.farmerName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PhColors.textPrimary)),
                const Spacer(),
                if (order.farmerPhone.isNotEmpty)
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse('tel:${order.farmerPhone}')),
                    child: const Icon(Icons.call, size: 16, color: PhColors.secondary),
                  ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: PhColors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      order.deliveryMethod == 'pickup'
                          ? 'Pickup at pharmacy'
                          : order.deliveryAddress,
                      style: const TextStyle(fontSize: 12, color: PhColors.textSecondary)),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                phChip('${order.itemsCount} item(s)', PhColors.surface2, PhColors.textSecondary, fontSize: 10),
                phChip(order.paymentMethod.toUpperCase(), PhColors.surface2, PhColors.textSecondary, fontSize: 10),
                phChip('Pay: ${order.paymentStatus}',
                    order.paymentStatus == 'paid' ? PhColors.deliveredLight : PhColors.pendingLight,
                    order.paymentStatus == 'paid' ? PhColors.delivered : PhColors.pending, fontSize: 10),
                if (order.requiresColdChain)
                  phChip('🧊 Cold chain', PhColors.processingLight, PhColors.processing, fontSize: 10),
                if (order.requiresPrescription)
                  phChip('Rx required', PhColors.pendingLight, PhColors.amber, fontSize: 10),
              ]),
              if (order.prescriptionImage != null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _viewImage(context, order.prescriptionImage!),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(order.prescriptionImage!, width: 44, height: 44, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 44, height: 44, color: PhColors.surface2,
                              child: const Icon(Icons.receipt_long, size: 18, color: PhColors.grey))),
                    ),
                    const SizedBox(width: 8),
                    const Text('View prescription',
                        style: TextStyle(fontSize: 12, color: PhColors.secondary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              ...order.items.map((it) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 5, color: PhColors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(it.name,
                            style: const TextStyle(fontSize: 12, color: PhColors.textSecondary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text('${it.quantity} × ৳${it.unitPrice.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 11, color: PhColors.grey)),
                    ]),
                  )),
              const Divider(color: PhColors.divider, height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    'Subtotal ৳${order.subtotal.toStringAsFixed(0)}'
                    '${order.deliveryFee > 0 ? '  +  delivery ৳${order.deliveryFee.toStringAsFixed(0)}' : ''}',
                    style: const TextStyle(fontSize: 11, color: PhColors.grey)),
                Text('৳${order.totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: PhColors.textPrimary)),
              ]),
              if (order.rider != null) ...[
                const SizedBox(height: 10),
                _RiderBox(rider: order.rider!),
              ],
              const SizedBox(height: 12),
              _Actions(order: order),
            ]),
          ),
        ],
      ),
    );
  }

  void _viewImage(BuildContext context, String url) => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          child: InteractiveViewer(child: Image.network(url)),
        ),
      );
}

class _RiderBox extends StatelessWidget {
  final RiderInfo rider;
  const _RiderBox({required this.rider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: PhColors.shippedLight, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const CircleAvatar(radius: 16, backgroundColor: PhColors.shipped, child: Icon(Icons.two_wheeler, size: 16, color: Colors.white)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rider.name.isEmpty ? 'Rider assigned' : rider.name,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: PhColors.textPrimary)),
            Text('Delivery: ${rider.deliveryStatus.replaceAll('_', ' ')}  ·  OTP ${rider.otpCode}',
                style: const TextStyle(fontSize: 11, color: PhColors.textSecondary)),
          ]),
        ),
        if (rider.phone.isNotEmpty)
          IconButton(
            onPressed: () => launchUrl(Uri.parse('tel:${rider.phone}')),
            icon: const Icon(Icons.call, size: 17, color: PhColors.shipped),
            visualDensity: VisualDensity.compact,
          ),
      ]),
    );
  }
}

class _Actions extends StatelessWidget {
  final CatalogueOrder order;
  const _Actions({required this.order});

  @override
  Widget build(BuildContext context) {
    switch (order.status) {
      case PharmacyOrderStatus.pending:
        return Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _cancel(context),
              style: OutlinedButton.styleFrom(
                  foregroundColor: PhColors.cancelled,
                  side: BorderSide(color: PhColors.cancelled.withValues(alpha: .5))),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () => _run(context, () => PharmacySession.instance.confirmOrder(order.id), 'Order confirmed.'),
              style: FilledButton.styleFrom(backgroundColor: PhColors.processing),
              child: const Text('Confirm order', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]);
      case PharmacyOrderStatus.preparing:
        return Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _cancel(context),
              style: OutlinedButton.styleFrom(
                  foregroundColor: PhColors.cancelled,
                  side: BorderSide(color: PhColors.cancelled.withValues(alpha: .5))),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => _run(context, () => PharmacySession.instance.readyForDelivery(order.id),
                  order.deliveryMethod == 'pickup' ? 'Marked ready for pickup.' : 'Queued for a delivery rider.'),
              style: FilledButton.styleFrom(backgroundColor: PhColors.shipped),
              icon: const Icon(Icons.local_shipping_outlined, size: 15),
              label: Text(order.deliveryMethod == 'pickup' ? 'Ready for pickup' : 'Request delivery',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ]);
      case PharmacyOrderStatus.readyForDelivery:
      case PharmacyOrderStatus.outForDelivery:
        if (order.deliveryMethod == 'pickup' || order.rider == null) {
          return FilledButton.icon(
            onPressed: () => _markDelivered(context),
            style: FilledButton.styleFrom(backgroundColor: PhColors.delivered),
            icon: const Icon(Icons.check_circle_outline, size: 15),
            label: const Text('Mark handed over', style: TextStyle(fontSize: 12)),
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: PhColors.shippedLight, borderRadius: BorderRadius.circular(8)),
          child: const Text('Rider handling delivery — track above',
              style: TextStyle(fontSize: 11, color: PhColors.shipped, fontWeight: FontWeight.w600)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String ok) async {
    try {
      await action();
      if (context.mounted) showPharmacyNotice(context, ok, PhColors.green, Icons.check_circle_outline);
    } catch (e) {
      if (context.mounted) showPharmacyNotice(context, e.toString(), PhColors.red, Icons.error_outline);
    }
  }

  Future<void> _markDelivered(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PhColors.bg,
        title: const Text('Confirm hand-over'),
        content: Text('Confirm the farmer received order ${order.orderNumber}? This completes the order.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PhColors.delivered),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => PharmacySession.instance.markDelivered(order.id, 'Handed over by pharmacy.'),
        'Order completed.');
  }

  Future<void> _cancel(BuildContext context) async {
    const reasons = ['Out of stock', 'Medicine expired', 'Farmer unreachable', 'Other'];
    var reason = reasons.first;
    final custom = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: PhColors.bg,
          title: const Text('Cancel order'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: reason,
              dropdownColor: PhColors.bg,
              decoration: phInput('Reason', Icons.help_outline),
              items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setLocal(() => reason = v ?? reason),
            ),
            if (reason == 'Other') ...[
              const SizedBox(height: 10),
              TextField(controller: custom, style: phFieldText, decoration: phInput('Details', Icons.edit_outlined)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep order')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PhColors.cancelled),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel order'),
            ),
          ],
        ),
      ),
    );
    final finalReason = reason == 'Other' && custom.text.trim().isNotEmpty ? custom.text.trim() : reason;
    custom.dispose();
    if (confirmed != true || !context.mounted) return;
    await _run(context, () => PharmacySession.instance.cancelOrder(order.id, finalReason), 'Order cancelled.');
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: PhColors.grey.withValues(alpha: .4)),
          const SizedBox(height: 12),
          const Text('No orders here', style: TextStyle(fontSize: 14, color: PhColors.textSecondary)),
        ]),
      );
}
