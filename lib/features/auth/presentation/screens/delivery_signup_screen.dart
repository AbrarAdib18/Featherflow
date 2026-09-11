import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';

class DeliverySignupScreen extends StatefulWidget {
  const DeliverySignupScreen({super.key});

  @override
  State<DeliverySignupScreen> createState() => _DeliverySignupScreenState();
}

class _DeliverySignupScreenState extends State<DeliverySignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _driverLicCtrl = TextEditingController();
  final _licClassCtrl = TextEditingController();
  final _vehicleRegCtrl = TextEditingController();
  final _vehicleInsCtrl = TextEditingController();
  final _proofWorkCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _priorDelivCtrl = TextEditingController();
  final _areaCovCtrl = TextEditingController();
  final _availCtrl = TextEditingController();
  final _bankingCtrl = TextEditingController();

  DateTime? _licenseExpiry;
  String _vehicleType = 'Motorcycle';
  bool _bgConsent = false;
  bool _submitting = false;
  String? _licensePhotoUrl;
  String? _vehiclePhotoUrl;

  static const List<String> _vehicleTypes = ['Bike', 'Motorcycle', 'Van', 'Pickup'];

  late final SignupFormDraft _draft = SignupFormDraft(
    cacheKey: 'delivery',
    fields: {
      'license_number': _driverLicCtrl,
      'license_class': _licClassCtrl,
      'vehicle_registration': _vehicleRegCtrl,
      'insurance_details': _vehicleInsCtrl,
      'proof_of_right_to_work': _proofWorkCtrl,
      'emergency_contact': _emergencyCtrl,
      'prior_delivery_experience': _priorDelivCtrl,
      'area_coverage': _areaCovCtrl,
      'availability': _availCtrl,
      'banking_details': _bankingCtrl,
    },
    readExtra: () => {
      'vehicle_type': _vehicleType,
      'bg_consent': _bgConsent,
      'license_expiry': _licenseExpiry?.toIso8601String(),
      'license_photo_url': _licensePhotoUrl,
      'vehicle_photo_url': _vehiclePhotoUrl,
    },
    writeExtra: (d) {
      _vehicleType = (d['vehicle_type'] as String?) ?? _vehicleType;
      _bgConsent = (d['bg_consent'] as bool?) ?? false;
      final expiry = d['license_expiry'];
      if (expiry is String && expiry.isNotEmpty) {
        _licenseExpiry = DateTime.tryParse(expiry);
      }
      _licensePhotoUrl = d['license_photo_url'] as String?;
      _vehiclePhotoUrl = d['vehicle_photo_url'] as String?;
    },
  );

  @override
  void initState() {
    super.initState();
    _draft.restore();
    _draft.bind();
  }

  @override
  void dispose() {
    _draft.unbind();
    _driverLicCtrl.dispose();
    _licClassCtrl.dispose();
    _vehicleRegCtrl.dispose();
    _vehicleInsCtrl.dispose();
    _proofWorkCtrl.dispose();
    _emergencyCtrl.dispose();
    _priorDelivCtrl.dispose();
    _areaCovCtrl.dispose();
    _availCtrl.dispose();
    _bankingCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLicenseExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenseExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2060),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1DB584),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF01291E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _licenseExpiry = picked);
      _draft.save();
    }
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_licenseExpiry == null) {
      _snack('License expiry date is required.');
      return;
    }
    if (_licensePhotoUrl == null) {
      _snack('Upload a photo of your license to continue.');
      return;
    }
    if (!_bgConsent) {
      _snack('Background check consent is required.');
      return;
    }

    final pending = await AuthService.instance.getPendingRegistration();
    if (pending.isEmpty) {
      if (!mounted) return;
      _snack('Please complete the basic signup information first.');
      context.go(AppRoutes.signup);
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await AuthService.instance.register(
        email: pending['email']?.toString() ?? '',
        password: pending['password']?.toString() ?? '',
        phone: pending['phone']?.toString() ?? '',
        fullName: pending['full_name']?.toString() ?? '',
        role: 'delivery',
        address: pending['address']?.toString() ?? '',
        dateOfBirth: pending['date_of_birth']?.toString() ?? '',
        consentTerms: pending['consent_terms'] == true,
        nationalId: pending['national_id']?.toString() ?? '',
        emergencyContact: pending['emergency_contact']?.toString() ?? '',
        preferredLanguage: pending['preferred_language']?.toString() ?? 'en',
        profilePhotoUrl: pending['profile_photo_url']?.toString() ?? '',
        roleData: {
          'license_number': _driverLicCtrl.text.trim(),
          'license_class': _licClassCtrl.text.trim(),
          'license_expiry': _licenseExpiry!.toIso8601String(),
          'license_photo_url': _licensePhotoUrl,
          if (_vehiclePhotoUrl != null) 'vehicle_photo_url': _vehiclePhotoUrl,
          'vehicle_type': _vehicleType,
          'vehicle_registration': _vehicleRegCtrl.text.trim(),
          'insurance_details': _vehicleInsCtrl.text.trim(),
          'proof_of_right_to_work': _proofWorkCtrl.text.trim(),
          'emergency_contact': _emergencyCtrl.text.trim(),
          'prior_delivery_experience': _priorDelivCtrl.text.trim(),
          'area_coverage': _areaCovCtrl.text.trim(),
          'availability': _availCtrl.text.trim(),
          'banking_details': _bankingCtrl.text.trim(),
          'background_consent': true,
        },
      );
      if (!mounted) return;
      await routeAfterRegistration(context, result);
    } on AuthException catch (error) {
      if (!mounted) return;
      _snack(error.message, seconds: 5);
    } catch (_) {
      if (!mounted) return;
      _snack('Unable to reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message, {int seconds = 3}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: seconds),
      ));
  }

  Future<void> _leave() async {
    if (_submitting) return;
    await handleSignupLeave(
      context,
      hasData: _draft.hasData,
      cacheKey: _draft.cacheKey,
      destination: AppRoutes.roleSelection,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF01291E),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _leave,
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delivery Agent Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Rider Details',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader('License Information'),
              const SizedBox(height: 16),

              const _FieldLabel("Driver's License Number", required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _driverLicCtrl,
                hint: 'Your driving license number',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? "Driver's license is required" : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('License Class', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _licClassCtrl,
                hint: 'e.g. Class A, B, C',
                icon: Icons.class_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'License class is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('License Expiry Date', required: true),
              const SizedBox(height: 6),
              _DatePickerField(
                value: _licenseExpiry,
                hint: 'DD / MM / YYYY',
                onTap: _pickLicenseExpiry,
                formatDate: _formatDate,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Vehicle Information'),
              const SizedBox(height: 16),

              const _FieldLabel('Vehicle Type', required: true),
              const SizedBox(height: 6),
              _LightDropdown<String>(
                value: _vehicleType,
                items: _vehicleTypes,
                icon: Icons.two_wheeler_outlined,
                onChanged: (v) {
                  setState(() => _vehicleType = v ?? _vehicleType);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Vehicle Registration Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _vehicleRegCtrl,
                hint: 'Vehicle plate number',
                icon: Icons.directions_car_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle registration is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Vehicle Insurance Details'),
              const SizedBox(height: 6),
              _LightField(
                controller: _vehicleInsCtrl,
                hint: 'Insurance policy number, if applicable',
                icon: Icons.shield_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Vehicle Photo'),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload a vehicle photo (optional)',
                kind: 'vehicle_photo',
                imageOnly: true,
                initialUrl: _vehiclePhotoUrl,
                onUploaded: (url) {
                  setState(() => _vehiclePhotoUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('License Photo', required: true),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload license photo (PDF or image)',
                kind: 'license_photo',
                required: true,
                initialUrl: _licensePhotoUrl,
                onUploaded: (url) {
                  setState(() => _licensePhotoUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Work Details'),
              const SizedBox(height: 16),

              const _FieldLabel('Proof of Right to Work', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _proofWorkCtrl,
                hint: 'e.g. NID number or work permit',
                icon: Icons.verified_user_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Proof of right to work is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Emergency Contact', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _emergencyCtrl,
                hint: 'Name and phone number',
                icon: Icons.emergency_outlined,
                keyboard: TextInputType.phone,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Emergency contact is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Area Coverage', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _areaCovCtrl,
                hint: 'Districts or zones you can cover',
                icon: Icons.map_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Area coverage is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Availability / Schedule', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _availCtrl,
                hint: 'e.g. Weekdays 8am–6pm',
                icon: Icons.schedule_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Availability is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Prior Delivery Experience'),
              const SizedBox(height: 6),
              _LightField(
                controller: _priorDelivCtrl,
                hint: 'e.g. 2 years with Pathao',
                icon: Icons.history_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Payment Information'),
              const SizedBox(height: 16),

              const _FieldLabel('Banking / Mobile Wallet', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _bankingCtrl,
                hint: 'bKash, Nagad, or bank account number',
                icon: Icons.account_balance_wallet_outlined,
                action: TextInputAction.done,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Banking details are required' : null,
              ),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _bgConsent,
                label: 'I consent to a background check as part of the onboarding process. *',
                onChanged: (v) {
                  setState(() => _bgConsent = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 32),

              SignupSubmitButton(
                label: 'Submit Rider Application',
                submitting: _submitting,
                onPressed: _onSubmit,
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _leave,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 4),
                      Text('Back to Role Selection', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Color(0xFF01291E), fontSize: 15, fontWeight: FontWeight.w700));
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: text, style: const TextStyle(color: Color(0xFF2A2A2A), fontSize: 13, fontWeight: FontWeight.w500)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFFF5C6A), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LightField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final String? Function(String?)? validator;

  const _LightField({required this.controller, required this.hint, required this.icon, this.keyboard, this.action, this.validator});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textInputAction: action,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        errorStyle: const TextStyle(color: Color(0xFFFF5C6A), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFF1DB584), width: 1.5)),
        errorBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFFFF5C6A))),
        focusedErrorBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFFFF5C6A), width: 1.5)),
      ),
      validator: validator,
    );
  }
}

class _LightDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final IconData icon;
  final void Function(T?)? onChanged;

  const _LightDropdown({required this.value, required this.items, required this.icon, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          items: items.map((item) => DropdownMenuItem<T>(value: item, child: Row(children: [Icon(icon, color: Colors.grey.shade400, size: 20), const SizedBox(width: 8), Text('$item')]))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final String Function(DateTime) formatDate;

  const _DatePickerField({required this.value, required this.hint, required this.onTap, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Text(value != null ? formatDate(value!) : hint, style: TextStyle(color: value != null ? const Color(0xFF1A1A1A) : Colors.grey.shade400, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}


class _ConsentRow extends StatelessWidget {
  final bool value;
  final String label;
  final void Function(bool?)? onChanged;

  const _ConsentRow({required this.value, required this.label, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: onChanged, activeColor: const Color(0xFF1DB584), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5))),
      ],
    );
  }
}
