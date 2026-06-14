import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../delivery_theme.dart';
import '../widgets/status_stepper.dart';
import '../widgets/pharmacy_flag_banner.dart';

class DeliveryDetailScreen extends StatefulWidget {
  final DeliveryOrder order;

  const DeliveryDetailScreen({super.key, required this.order});

  @override
  State<DeliveryDetailScreen> createState() =>
      _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  late DeliveryOrder _order;
  final _otpController = TextEditingController();
  final _notesController = TextEditingController();
  bool _photoCaptured = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  @override
  void dispose() {
    _otpController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _progressStatus() {
    final next = switch (_order.status) {
      OrderStatus.accepted => OrderStatus.pickedUp,
      OrderStatus.pickedUp => OrderStatus.onTheWay,
      OrderStatus.onTheWay => OrderStatus.delivered,
      _ => _order.status,
    };
    setState(() => _order = _order.copyWith(status: next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DColors.bg,
      appBar: AppBar(
        backgroundColor: DColors.appBar,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '#${_order.id}',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _statusChipAppBar(_order.status),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_order.type == OrderType.pharmacy) ...[
              const PharmacyFlagBanner(),
              const SizedBox(height: 14),
            ],
            _section('Delivery Status', _buildStepper()),
            _section('Customer Info', _buildCustomerInfo()),
            _section('Route', _buildRoute()),
            _section('Items', _buildItems()),
            if (_order.specialInstructions != null)
              _section(
                  'Special Instructions', _buildInstructions()),
            if (_order.requiresOtp)
              _section('OTP Handover', _buildOtpField()),
            _section('Proof of Delivery', _buildProofSection()),
            _section('Failed Delivery Notes', _buildNotesField()),
            const SizedBox(height: 20),
            _buildActionButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: DColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: dCard(),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() =>
      StatusStepper(currentStatus: _order.status);

  Widget _buildCustomerInfo() {
    return Column(
      children: [
        _infoRow(Icons.person_outline, DColors.primary, 'Customer',
            _order.customerName),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calling ${_order.customerPhone}…'),
              backgroundColor: DColors.secondary,
              behavior: SnackBarBehavior.floating,
            ),
          ),
          child: _infoRow(Icons.phone_outlined, DColors.secondary,
              'Phone', _order.customerPhone,
              valueColor: DColors.secondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening dialer…'),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                icon: const Icon(Icons.phone, size: 16),
                label: const Text('Call Customer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(
                    Icons.chat_bubble_outline, size: 16),
                label: const Text('Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DColors.primary,
                  side: BorderSide(
                      color: DColors.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoute() {
    return Column(
      children: [
        _infoRow(Icons.radio_button_checked, DColors.accent,
            'Pickup', _order.pickupAddress),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
          child: Container(
              width: 1, height: 16, color: DColors.cardBorder),
        ),
        _infoRow(Icons.location_on, DColors.red, 'Drop',
            _order.dropAddress),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.straighten,
                color: DColors.grey, size: 13),
            const SizedBox(width: 6),
            Text('${_order.distanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                    color: DColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 16),
            const Icon(Icons.account_balance_wallet_outlined,
                color: DColors.accent, size: 13),
            const SizedBox(width: 6),
            Text('৳${_order.earning.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: DColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _buildItems() {
    return Column(
      children: _order.items
          .map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: DColors.accentLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                          Icons.inventory_2_outlined,
                          color: DColors.accent,
                          size: 14),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.name,
                          style: const TextStyle(
                              color: DColors.textPrimary,
                              fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('×${item.quantity}',
                          style: const TextStyle(
                              color: DColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildInstructions() {
    return Text(
      _order.specialInstructions!,
      style: const TextStyle(
          color: DColors.textSecondary, fontSize: 13, height: 1.5),
    );
  }

  Widget _buildOtpField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Enter OTP provided by customer',
            style: TextStyle(
                color: DColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(
              color: DColors.textPrimary,
              fontSize: 20,
              letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '— — — — — —',
            hintStyle: const TextStyle(
                color: DColors.greyDark, letterSpacing: 4),
            filled: true,
            fillColor: DColors.surface2,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: DColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: DColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: DColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProofSection() {
    return GestureDetector(
      onTap: () =>
          setState(() => _photoCaptured = !_photoCaptured),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: _photoCaptured
              ? DColors.accentLight
              : DColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _photoCaptured
                ? DColors.accent.withValues(alpha: 0.5)
                : DColors.cardBorder,
          ),
        ),
        child: _photoCaptured
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle,
                      color: DColors.accent, size: 32),
                  SizedBox(height: 6),
                  Text('Photo captured (mock)',
                      style: TextStyle(
                          color: DColors.accent, fontSize: 12)),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      color: DColors.grey, size: 28),
                  SizedBox(height: 6),
                  Text('Tap to capture proof photo',
                      style: TextStyle(
                          color: DColors.textSecondary,
                          fontSize: 12)),
                ],
              ),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      style: const TextStyle(
          color: DColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Add notes if delivery failed (optional)',
        hintStyle: const TextStyle(
            color: DColors.grey, fontSize: 13),
        filled: true,
        fillColor: DColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: DColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: DColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: DColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_order.status == OrderStatus.delivered ||
        _order.status == OrderStatus.cancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: DColors.accentLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: DColors.accent.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: DColors.accent, size: 18),
            SizedBox(width: 8),
            Text('Order Completed',
                style: TextStyle(
                    color: DColors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _progressStatus,
        style: ElevatedButton.styleFrom(
          backgroundColor: DColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          _nextLabel(_order.status),
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    Color iconColor,
    String label,
    String value, {
    Color valueColor = DColors.textPrimary,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(
                  color: DColors.textSecondary, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _statusChipAppBar(OrderStatus s) {
    final (label, bg, fg) = switch (s) {
      OrderStatus.delivered =>
        ('Delivered', DColors.accentLight, DColors.accent),
      OrderStatus.failed =>
        ('Failed', DColors.redLight, DColors.red),
      OrderStatus.cancelled =>
        ('Cancelled', DColors.surface2, DColors.grey),
      OrderStatus.onTheWay =>
        ('On The Way', DColors.accentLight, DColors.accentMid),
      _ => ('Accepted', DColors.accentLight, DColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _nextLabel(OrderStatus s) => switch (s) {
        OrderStatus.accepted => 'Mark as Picked Up',
        OrderStatus.pickedUp => 'On The Way',
        OrderStatus.onTheWay => 'Mark Delivered',
        _ => 'Update',
      };
}
