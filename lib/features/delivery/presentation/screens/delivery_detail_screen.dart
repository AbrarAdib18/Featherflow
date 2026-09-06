import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/models/delivery_order.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';
import '../widgets/status_stepper.dart';
import '../widgets/pharmacy_flag_banner.dart';
import '../widgets/signature_pad.dart';
import 'delivery_map_screen.dart';

class DeliveryDetailScreen extends StatefulWidget {
  final DeliveryOrder order;

  const DeliveryDetailScreen({super.key, required this.order});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  late DeliveryOrder _order;
  final _otpController = TextEditingController();
  final _notesController = TextEditingController();
  String? _proofUrl;
  bool _uploadingProof = false;
  bool _recipientVerified = false;

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

  Future<void> _progressStatus() async {
    if (_order.status == OrderStatus.pending) {
      try {
        await DeliverySession.instance.respondToRequest(_order.id, true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(error.toString()), backgroundColor: DColors.red));
        }
        return;
      }
      if (mounted) {
        setState(() => _order = _order.copyWith(status: OrderStatus.accepted));
      }
      return;
    }
    final next = switch (_order.status) {
      OrderStatus.accepted => OrderStatus.pickedUp,
      OrderStatus.pickedUp => OrderStatus.onTheWay,
      OrderStatus.onTheWay => OrderStatus.delivered,
      _ => _order.status,
    };
    if (next == OrderStatus.delivered) {
      if (_order.requiresOtp && _otpController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter the delivery OTP first.'),
            backgroundColor: DColors.red));
        return;
      }
      if (_order.isPrescriptionRequired && !_recipientVerified) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Confirm you verified the recipient before delivering.'),
            backgroundColor: DColors.red));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.check_circle_outline, color: DColors.secondary),
            SizedBox(width: 10),
            Expanded(child: Text('Confirm Delivery')),
          ]),
          content: Text(
              'Are you sure you want to mark order #${_order.id} as delivered? The farmer and pharmacy will be notified immediately.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not Yet')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Yes, Delivered'),
              style: FilledButton.styleFrom(
                  backgroundColor: DColors.secondary,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await DeliverySession.instance.updateOrderStatus(
        _order.id, next,
        otpCode: next == OrderStatus.delivered && _order.requiresOtp
            ? _otpController.text.trim()
            : null,
        proofOfDeliveryUrl: next == OrderStatus.delivered ? _proofUrl : null,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
      return;
    }
    if (mounted) setState(() => _order = _order.copyWith(status: next));
  }

  Future<void> _reportFailed() async {
    final reason = _notesController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add a note describing the problem first.'),
          backgroundColor: DColors.red));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report Delivery Failed'),
        content: Text('Mark order #${_order.id} as failed with this note?\n\n"$reason"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style:
                FilledButton.styleFrom(backgroundColor: DColors.red, foregroundColor: Colors.white),
            child: const Text('Report Failed'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DeliverySession.instance.updateOrderStatus(
        _order.id, OrderStatus.failed,
        failureReason: reason,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
      return;
    }
    if (mounted) setState(() => _order = _order.copyWith(status: OrderStatus.failed));
  }

  Future<void> _uploadBytes(Uint8List bytes, String filename) async {
    setState(() => _uploadingProof = true);
    try {
      final url = await DeliverySession.instance.uploadProof(bytes, filename);
      if (mounted) setState(() { _proofUrl = url; _uploadingProof = false; });
    } catch (error) {
      if (mounted) {
        setState(() => _uploadingProof = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    await _uploadBytes(file.bytes!, file.name);
  }

  Future<void> _captureSignature() async {
    final bytes = await Navigator.push<Uint8List>(
        context, MaterialPageRoute(builder: (_) => const SignaturePadScreen()));
    if (bytes == null) return;
    await _uploadBytes(bytes, 'signature.png');
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
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
            if (_order.isColdChain || _order.isPrescriptionRequired) ...[
              _buildHandlingBadges(),
              const SizedBox(height: 14),
            ],
            _section('Delivery Status', _buildStepper()),
            _section('Customer Info', _buildCustomerInfo()),
            _section('Route', _buildRoute()),
            _section('Items', _buildItems()),
            if (_order.specialInstructions != null)
              _section('Special Instructions', _buildInstructions()),
            if (_order.requiresOtp) _section('OTP Handover', _buildOtpField()),
            if (_order.isPrescriptionRequired)
              _section('Recipient Verification', _buildRecipientVerification()),
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

  Widget _buildStepper() => StatusStepper(currentStatus: _order.status);

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
          child: _infoRow(Icons.phone_outlined, DColors.secondary, 'Phone',
              _order.customerPhone,
              valueColor: DColors.secondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
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
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DColors.primary,
                  side:
                      BorderSide(color: DColors.primary.withValues(alpha: 0.5)),
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
        _infoRow(Icons.radio_button_checked, DColors.accent, 'Pickup',
            _order.pickupAddress),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
          child: Container(width: 1, height: 16, color: DColors.cardBorder),
        ),
        _infoRow(Icons.location_on, DColors.red, 'Drop', _order.dropAddress),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.straighten, color: DColors.grey, size: 13),
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DeliveryMapScreen(order: _order)),
            ),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Open in Maps'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DColors.primary,
              side: BorderSide(color: DColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
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
                      child: const Icon(Icons.inventory_2_outlined,
                          color: DColors.accent, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.name,
                          style: const TextStyle(
                              color: DColors.textPrimary, fontSize: 13)),
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
            style: TextStyle(color: DColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(
              color: DColors.textPrimary, fontSize: 20, letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: '— — — — — —',
            hintStyle:
                const TextStyle(color: DColors.greyDark, letterSpacing: 4),
            filled: true,
            fillColor: DColors.surface2,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: DColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: DColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: DColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProofSection() {
    if (_uploadingProof) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(color: DColors.accent)),
      );
    }
    if (_proofUrl != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(_proofUrl!, height: 140, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: DColors.accentLight,
                      alignment: Alignment.center,
                      child: const Icon(Icons.check_circle, color: DColors.accent, size: 32),
                    )),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _proofUrl = null),
            icon: const Icon(Icons.refresh, size: 16, color: DColors.red),
            label: const Text('Retake', style: TextStyle(color: DColors.red)),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _captureSignature,
            icon: const Icon(Icons.draw_outlined, size: 16),
            label: const Text('Signature'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHandlingBadges() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_order.isColdChain)
          _badge(Icons.ac_unit, 'Cold Chain — keep refrigerated', DColors.secondary),
        if (_order.isPrescriptionRequired)
          _badge(Icons.medication_outlined, 'Prescription Required', DColors.orange),
      ],
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRecipientVerification() {
    return CheckboxListTile(
      value: _recipientVerified,
      onChanged: (v) => setState(() => _recipientVerified = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: DColors.primary,
      title: const Text("I verified the recipient's identity",
          style: TextStyle(color: DColors.textPrimary, fontSize: 13)),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      style: const TextStyle(color: DColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Add notes if delivery failed (optional)',
        hintStyle: const TextStyle(color: DColors.grey, fontSize: 13),
        filled: true,
        fillColor: DColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (const {
      OrderStatus.delivered,
      OrderStatus.cancelled,
      OrderStatus.failed,
      OrderStatus.rejected,
    }.contains(_order.status)) {
      final isGood = _order.status == OrderStatus.delivered;
      final color = isGood ? DColors.accent : DColors.red;
      final bg = isGood ? DColors.accentLight : DColors.redLight;
      final label = switch (_order.status) {
        OrderStatus.delivered => 'Order Completed',
        OrderStatus.failed => 'Delivery Failed',
        OrderStatus.rejected => 'Order Rejected',
        _ => 'Order Cancelled',
      };
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isGood ? Icons.check_circle : Icons.cancel, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final canReportFailed = {
      OrderStatus.accepted,
      OrderStatus.pickedUp,
      OrderStatus.onTheWay,
    }.contains(_order.status);
    return Column(
      children: [
        SizedBox(
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (canReportFailed) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _reportFailed,
              style: OutlinedButton.styleFrom(
                foregroundColor: DColors.red,
                side: BorderSide(color: DColors.red.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Report Delivery Failed',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
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
              style:
                  const TextStyle(color: DColors.textSecondary, fontSize: 12)),
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
      OrderStatus.delivered => (
          'Delivered',
          DColors.accentLight,
          DColors.accent
        ),
      OrderStatus.failed => ('Failed', DColors.redLight, DColors.red),
      OrderStatus.rejected => ('Rejected', DColors.redLight, DColors.red),
      OrderStatus.cancelled => ('Cancelled', DColors.surface2, DColors.grey),
      OrderStatus.pending => ('Pending', DColors.orangeLight, DColors.orange),
      OrderStatus.pickedUp => ('Picked Up', DColors.accentLight, DColors.accent),
      OrderStatus.onTheWay => (
          'On The Way',
          DColors.accentLight,
          DColors.accentMid
        ),
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
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _nextLabel(OrderStatus s) => switch (s) {
        OrderStatus.pending => 'Accept Order',
        OrderStatus.accepted => 'Mark as Picked Up',
        OrderStatus.pickedUp => 'On The Way',
        OrderStatus.onTheWay => 'Mark Delivered',
        _ => 'Update',
      };
}
