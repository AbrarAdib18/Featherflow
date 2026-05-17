import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';

class DoctorSignupScreen extends StatefulWidget {
  const DoctorSignupScreen({super.key});

  @override
  State<DoctorSignupScreen> createState() => _DoctorSignupScreenState();
}

class _DoctorSignupScreenState extends State<DoctorSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _clinicCtrl = TextEditingController();
  final _practiceAddrCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _uniCtrl = TextEditingController();
  final _gradYearCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _specialtyCtrl = TextEditingController();
  final _yearsCtrl = TextEditingController();
  final _workplaceCtrl = TextEditingController();
  final _prescriptionCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _feesCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();

  DateTime? _licenseExpiry;
  String _consultMode = 'Online';
  bool _platformConsent = false;

  static const List<String> _consultModes = ['Online', 'Field Visit', 'Both'];

  @override
  void dispose() {
    _clinicCtrl.dispose();
    _practiceAddrCtrl.dispose();
    _degreeCtrl.dispose();
    _uniCtrl.dispose();
    _gradYearCtrl.dispose();
    _licenseCtrl.dispose();
    _authorityCtrl.dispose();
    _specialtyCtrl.dispose();
    _yearsCtrl.dispose();
    _workplaceCtrl.dispose();
    _prescriptionCtrl.dispose();
    _emergencyCtrl.dispose();
    _feesCtrl.dispose();
    _referralCtrl.dispose();
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
    if (picked != null) setState(() => _licenseExpiry = picked);
  }

  void _onSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_licenseExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License expiry date is required.')),
      );
      return;
    }
    if (!_platformConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please consent to platform guidelines to continue.')),
      );
      return;
    }
    context.go(AppRoutes.doctorDashboard);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF01291E),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go(AppRoutes.roleSelection),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Veterinarian Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Professional Details',
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
              const _SectionHeader('Clinic / Workplace'),
              const SizedBox(height: 16),

              const _FieldLabel('Clinic / Hospital Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _clinicCtrl,
                hint: 'Name of your clinic or hospital',
                icon: Icons.local_hospital_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Clinic name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Practice Address', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _practiceAddrCtrl,
                hint: 'Street, City, District',
                icon: Icons.location_on_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Practice address is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Current Workplace', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _workplaceCtrl,
                hint: 'Hospital, clinic, or organisation',
                icon: Icons.business_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Current workplace is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Academic Credentials'),
              const SizedBox(height: 16),

              const _FieldLabel('Veterinary Degree', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _degreeCtrl,
                hint: 'e.g. DVM, BVSc',
                icon: Icons.school_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Degree is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('University Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _uniCtrl,
                hint: 'University or college name',
                icon: Icons.account_balance_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'University name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Graduation Year', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _gradYearCtrl,
                hint: 'e.g. 2015',
                icon: Icons.calendar_today_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Graduation year is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('License & Registration'),
              const SizedBox(height: 16),

              const _FieldLabel('License / Registration Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _licenseCtrl,
                hint: 'Your license number',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'License number is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('License Issuing Authority', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _authorityCtrl,
                hint: 'e.g. Bangladesh Veterinary Council',
                icon: Icons.verified_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Issuing authority is required' : null,
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
              const SizedBox(height: 16),

              const _FieldLabel('Council Registration Proof', required: true),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload Council Registration', icon: Icons.upload_file_outlined),
              const SizedBox(height: 24),

              const _SectionHeader('Practice Details'),
              const SizedBox(height: 16),

              const _FieldLabel('Specialty / Poultry Focus Area', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _specialtyCtrl,
                hint: 'e.g. Broiler disease, Layer health',
                icon: Icons.biotech_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Specialty is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Years of Experience', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _yearsCtrl,
                hint: 'e.g. 10',
                icon: Icons.timeline_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Years of experience is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Consultation Mode', required: true),
              const SizedBox(height: 6),
              _LightDropdown<String>(
                value: _consultMode,
                items: _consultModes,
                icon: Icons.videocam_outlined,
                onChanged: (v) => setState(() => _consultMode = v ?? _consultMode),
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Service Fees / Consultation Rate', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _feesCtrl,
                hint: 'e.g. ৳ 500 per consultation',
                icon: Icons.payments_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Service fees is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Prescription Authority'),
              const SizedBox(height: 6),
              _LightField(
                controller: _prescriptionCtrl,
                hint: 'e.g. Licensed to prescribe Schedule H',
                icon: Icons.edit_document,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Emergency / On-Call Availability'),
              const SizedBox(height: 6),
              _LightField(
                controller: _emergencyCtrl,
                hint: 'e.g. Available on weekends',
                icon: Icons.emergency_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Referral Network'),
              const SizedBox(height: 6),
              _LightField(
                controller: _referralCtrl,
                hint: 'e.g. Linked with Dhaka Vet Hospital',
                icon: Icons.hub_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Documents'),
              const SizedBox(height: 16),

              const _FieldLabel('Professional Photo', required: true),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload Professional Photo', icon: Icons.photo_camera_outlined),
              const SizedBox(height: 16),

              const _FieldLabel('CV / Resume'),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload CV / Resume', icon: Icons.description_outlined),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _platformConsent,
                label: 'I consent to follow platform treatment guidelines and professional conduct standards. *',
                onChanged: (v) => setState(() => _platformConsent = v ?? false),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB584),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Create Doctor Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () => context.go(AppRoutes.roleSelection),
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
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFF01291E), fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
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
          TextSpan(
            text: text,
            style: const TextStyle(color: Color(0xFF2A2A2A), fontSize: 13, fontWeight: FontWeight.w500),
          ),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFFF5C6A), fontSize: 13, fontWeight: FontWeight.w600),
            ),
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

  const _LightField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.action,
    this.validator,
  });

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
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Row(children: [Icon(icon, color: Colors.grey.shade400, size: 20), const SizedBox(width: 8), Text('$item')]),
                  ))
              .toList(),
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
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Text(
              value != null ? formatDate(value!) : hint,
              style: TextStyle(color: value != null ? const Color(0xFF1A1A1A) : Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadButton extends StatelessWidget {
  final String label;
  final IconData icon;
  const _UploadButton({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            const Spacer(),
            Icon(Icons.add_circle_outline, color: Colors.grey.shade400, size: 18),
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
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF1DB584),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5))),
      ],
    );
  }
}
