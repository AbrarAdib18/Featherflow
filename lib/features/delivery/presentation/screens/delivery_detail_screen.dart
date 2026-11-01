import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/authed_image.dart';
import '../../data/models/delivery_order.dart';
import '../../data/services/delivery_session.dart';
import '../delivery_theme.dart';
import '../widgets/status_stepper.dart';
import '../widgets/pharmacy_flag_banner.dart';
import '../widgets/signature_pad.dart';
import 'delivery_map_screen.dart';

/// A photo chosen by the rider (kept in memory until it is submitted).
typedef PickedProofPhoto = ({Uint8List bytes, String name});

/// Picks the proof photo. Overridable so widget tests can supply a fixed
/// image without a native file dialog.
typedef ProofPhotoPicker = Future<PickedProofPhoto?> Function();

Future<PickedProofPhoto?> _defaultPhotoPicker() async {
  final result =
      await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes == null) return null;
  return (bytes: file.bytes!, name: file.name);
}

class DeliveryDetailScreen extends StatefulWidget {
  final DeliveryOrder order;
  final ProofPhotoPicker? photoPicker;

  const DeliveryDetailScreen({super.key, required this.order, this.photoPicker});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  late DeliveryOrder _order;
  final _otpController = TextEditingController();
  final _notesController = TextEditingController();
  // Photo is the required proof-of-delivery (backend now rejects marking an
  // order delivered without one — see DELIVERY_PROOF_AND_STATS_FIX.md).
  // Signature is a separate, optional piece of evidence; kept independent so
  // capturing only a signature can never satisfy the required-photo check.
  Uint8List? _photoBytes;
  String? _photoName;
  bool _uploadingPhoto = false; // true while the proof is being submitted
  String? _photoError;
  String? _signatureUrl;
  bool _uploadingSignature = false;
  String? _signatureError;
  bool _recipientVerified = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    // Bind the Map tab to the delivery being worked on (NF-4).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeliverySession.instance.selectOrder(widget.order.id);
    });
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
      OrderStatus.onTheWay => OrderStatus.arrived,
      _ => _order.status,
    };
    if (next == _order.status) return;
    try {
      await DeliverySession.instance.updateOrderStatus(_order.id, next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString()), backgroundColor: DColors.red));
      }
      return;
    }
    if (mounted) setState(() => _order = _order.copyWith(status: next));
  }

  /// Submit (or resubmit) the chosen photo as the delivery proof. This never
  /// completes the order: it goes to "proof under review" and an admin must
  /// approve it.
  Future<void> _submitProof() async {
    final bytes = _photoBytes;
    if (bytes == null) {
      setState(() => _photoError = 'Choose a delivery photo first.');
      return;
    }
    if (_order.requiresOtp && _otpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter the delivery OTP first.'),
          backgroundColor: DColors.red));
      return;
    }
    if (_order.isPrescriptionRequired && !_recipientVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Confirm you verified the recipient before submitting.'),
          backgroundColor: DColors.red));
      return;
    }
    setState(() {
      _uploadingPhoto = true;
      _photoError = null;
    });
    try {
      final updated = await DeliverySession.instance.submitProof(
        _order.id, bytes, _photoName ?? 'proof.jpg',
        otpCode: _order.requiresOtp ? _otpController.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _uploadingPhoto = false;
        _photoBytes = null;
        _photoName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Proof submitted — waiting for admin review.'),
          backgroundColor: DColors.accent));
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
          _photoError = error.toString();
        });
      }
    }
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

  Future<void> _pickPhoto() async {
    final picked = await (widget.photoPicker ?? _defaultPhotoPicker)();
    if (picked == null || !mounted) return;
    setState(() {
      _photoBytes = picked.bytes;
      _photoName = picked.name;
      _photoError = null;
    });
  }

  Future<void> _uploadSignatureBytes(Uint8List bytes, String filename) async {
    setState(() {
      _uploadingSignature = true;
      _signatureError = null;
    });
    try {
      final url = await DeliverySession.instance.uploadProof(bytes, filename);
      if (mounted) setState(() { _signatureUrl = url; _uploadingSignature = false; });
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadingSignature = false;
          _signatureError = error.toString();
        });
      }
    }
  }

  Future<void> _captureSignature() async {
    final bytes = await Navigator.push<Uint8List>(
        context, MaterialPageRoute(builder: (_) => const SignaturePadScreen()));
    if (bytes == null) return;
    await _uploadSignatureBytes(bytes, 'signature.png');
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
            if (_order.requiresOtp && _canSubmitProof)
              _section('OTP Handover', _buildOtpField()),
            if (_order.isPrescriptionRequired && _canSubmitProof)
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

  bool get _canSubmitProof =>
      _order.status == OrderStatus.arrived ||
      _order.status == OrderStatus.proofRejected;

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
        if (_order.pickupLat != null && _order.pickupLng != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text('Pickup pin: ${_order.pickupLat!.toStringAsFixed(5)}, ${_order.pickupLng!.toStringAsFixed(5)}',
                key: const Key('pickupPin'),
                style: const TextStyle(color: DColors.textSecondary, fontSize: 11)),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
          child: Container(width: 1, height: 16, color: DColors.cardBorder),
        ),
        _infoRow(Icons.location_on, DColors.red, 'Drop', _order.dropAddress),
        if (_order.dropLat != null && _order.dropLng != null)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text('Drop pin: ${_order.dropLat!.toStringAsFixed(5)}, ${_order.dropLng!.toStringAsFixed(5)}',
                key: const Key('dropPin'),
                style: const TextStyle(color: DColors.textSecondary, fontSize: 11)),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_order.status == OrderStatus.proofRejected) ...[
          Container(
            key: const Key('proofRejectedBanner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DColors.redLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DColors.red.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Proof rejected — resubmission required',
                    style: TextStyle(
                        color: DColors.red, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_order.proofRejectionReason ?? 'Please upload a new proof photo.',
                    key: const Key('proofRejectionReason'),
                    style: const TextStyle(color: DColors.textPrimary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_order.status == OrderStatus.proofSubmitted) ...[
          Container(
            key: const Key('proofUnderReviewBanner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DColors.orangeLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
                'Proof under review. The order completes once an admin approves it.',
                style: TextStyle(color: DColors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Text('Delivery Photo',
                style: TextStyle(
                    color: DColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: DColors.redLight, borderRadius: BorderRadius.circular(6)),
              child: const Text('Required',
                  style: TextStyle(color: DColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _photoCapture(),
        const SizedBox(height: 16),
        const Text('Signature (optional)',
            style: TextStyle(
                color: DColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _signatureCapture(),
      ],
    );
  }

  Widget _photoCapture() {
    final canSubmit = _order.status == OrderStatus.arrived ||
        _order.status == OrderStatus.proofRejected;
    if (_order.status == OrderStatus.proofSubmitted ||
        _order.status == OrderStatus.delivered) {
      return Text(
        _order.status == OrderStatus.delivered
            ? 'Proof approved — delivery completed.'
            : 'Proof submitted — waiting for admin review.',
        key: const Key('proofStatusText'),
        style: const TextStyle(color: DColors.textSecondary, fontSize: 13),
      );
    }
    if (!canSubmit) {
      return const Text('Mark the order as arrived to upload your proof photo.',
          style: TextStyle(color: DColors.textSecondary, fontSize: 13));
    }
    if (_uploadingPhoto) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(color: DColors.accent)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_photoBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(_photoBytes!,
                key: const Key('proofPreview'),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('proofRetakeButton'),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.refresh, size: 16, color: DColors.red),
            label: const Text('Choose a different photo',
                style: TextStyle(color: DColors.red)),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('proofPickButton'),
              onPressed: _pickPhoto,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Take / Upload Delivery Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        if (_photoError != null) ...[
          const SizedBox(height: 6),
          Text(_photoError!,
              key: const Key('proofError'),
              style: const TextStyle(color: DColors.red, fontSize: 12)),
          if (_photoBytes != null)
            TextButton(
              key: const Key('proofRetryButton'),
              onPressed: _submitProof,
              child: const Text('Try again'),
            ),
        ],
      ],
    );
  }

  Widget _signatureCapture() {
    if (_uploadingSignature) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(color: DColors.accent)),
      );
    }
    if (_signatureUrl != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(image: AuthedNetworkImage(_signatureUrl!), height: 80, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                      height: 60,
                      color: DColors.accentLight,
                      alignment: Alignment.center,
                      child: const Icon(Icons.check_circle, color: DColors.accent, size: 24),
                    )),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _signatureUrl = null),
            icon: const Icon(Icons.refresh, size: 16, color: DColors.red),
            label: const Text('Retake', style: TextStyle(color: DColors.red)),
          ),
        ],
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _captureSignature,
            icon: const Icon(Icons.draw_outlined, size: 16),
            label: const Text('Capture Signature'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        if (_signatureError != null) ...[
          const SizedBox(height: 6),
          Text(_signatureError!,
              style: const TextStyle(color: DColors.red, fontSize: 12)),
          TextButton(
            onPressed: _captureSignature,
            child: const Text('Try again'),
          ),
        ],
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
      OrderStatus.arrived,
      OrderStatus.proofRejected,
    }.contains(_order.status);
    if (_order.status == OrderStatus.proofSubmitted) {
      return Container(
        key: const Key('proofAwaitingReview'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: DColors.orangeLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text('Proof under review',
              style: TextStyle(
                  color: DColors.orange, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );
    }
    final submitting = _canSubmitProof;
    final needsPhotoFirst = submitting && _photoBytes == null;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: Key(submitting ? 'submitProofButton' : 'progressButton'),
            onPressed: (needsPhotoFirst || _uploadingPhoto)
                ? null
                : (submitting ? _submitProof : _progressStatus),
            style: ElevatedButton.styleFrom(
              backgroundColor: DColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: DColors.greyDark,
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
        if (needsPhotoFirst) ...[
          const SizedBox(height: 6),
          const Text('Add a delivery photo above to continue',
              style: TextStyle(color: DColors.textSecondary, fontSize: 12)),
        ],
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
          'Out for delivery',
          DColors.accentLight,
          DColors.accentMid
        ),
      OrderStatus.arrived => ('Arrived', DColors.accentLight, DColors.accentMid),
      OrderStatus.proofSubmitted =>
        ('Proof under review', DColors.orangeLight, DColors.orange),
      OrderStatus.proofRejected => ('Proof rejected', DColors.redLight, DColors.red),
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
        OrderStatus.onTheWay => 'Mark Arrived',
        OrderStatus.arrived => 'Submit Delivery Proof',
        OrderStatus.proofRejected => 'Resubmit Delivery Proof',
        _ => 'Update',
      };
}
