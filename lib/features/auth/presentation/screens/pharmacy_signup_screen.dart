import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';

class PharmacySignupScreen extends StatefulWidget {
  const PharmacySignupScreen({super.key});

  @override
  State<PharmacySignupScreen> createState() => _PharmacySignupScreenState();
}

class _PharmacySignupScreenState extends State<PharmacySignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _bizNameCtrl = TextEditingController();
  final _contactPersonCtrl = TextEditingController();
  final _bizRegCtrl = TextEditingController();
  final _tradeLicCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _bizAddrCtrl = TextEditingController();
  final _warehouseAddrCtrl = TextEditingController();
  final _numPharmacistsCtrl = TextEditingController();
  final _responsiblePharCtrl = TextEditingController();
  final _pharLicCtrl = TextEditingController();
  final _pharCouncilCtrl = TextEditingController();
  final _permittedProductsCtrl = TextEditingController();
  final _storageCtrl = TextEditingController();
  final _deliveryCovCtrl = TextEditingController();
  final _returnsCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _signatoryCtrl = TextEditingController();

  DateTime? _licenseExpiry;
  bool _policyAgreement = false;

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _contactPersonCtrl.dispose();
    _bizRegCtrl.dispose();
    _tradeLicCtrl.dispose();
    _taxCtrl.dispose();
    _bizAddrCtrl.dispose();
    _warehouseAddrCtrl.dispose();
    _numPharmacistsCtrl.dispose();
    _responsiblePharCtrl.dispose();
    _pharLicCtrl.dispose();
    _pharCouncilCtrl.dispose();
    _permittedProductsCtrl.dispose();
    _storageCtrl.dispose();
    _deliveryCovCtrl.dispose();
    _returnsCtrl.dispose();
    _bankAccountCtrl.dispose();
    _signatoryCtrl.dispose();
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
        const SnackBar(content: Text('Professional license expiry date is required.')),
      );
      return;
    }
    if (!_policyAgreement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agreement to quality, prescription and audit policies is required.')),
      );
      return;
    }
    context.go(AppRoutes.pharmacyDashboard);
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
              'Pharmacy Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Business Details',
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
              const _SectionHeader('Business Information'),
              const SizedBox(height: 16),

              const _FieldLabel('Business / Organization Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _bizNameCtrl,
                hint: 'Registered business name',
                icon: Icons.store_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Authorized Contact Person', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _contactPersonCtrl,
                hint: 'Full name of authorized person',
                icon: Icons.person_outline,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Contact person is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Business Registration Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _bizRegCtrl,
                hint: 'Company registration number',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Trade License', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _tradeLicCtrl,
                hint: 'Trade license number',
                icon: Icons.description_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Trade license is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Tax / VAT / TIN Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _taxCtrl,
                hint: 'Tax identification number',
                icon: Icons.receipt_long_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Tax/VAT/TIN number is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Business Address', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _bizAddrCtrl,
                hint: 'Street, City, District',
                icon: Icons.location_on_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Business address is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Warehouse Address', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _warehouseAddrCtrl,
                hint: 'If different from business address',
                icon: Icons.warehouse_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Warehouse address is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Pharmacist Details'),
              const SizedBox(height: 16),

              const _FieldLabel('Number of Pharmacists', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _numPharmacistsCtrl,
                hint: 'e.g. 3',
                icon: Icons.people_outline,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Number of pharmacists is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Responsible Pharmacist Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _responsiblePharCtrl,
                hint: 'Full name of responsible pharmacist',
                icon: Icons.person_pin_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Responsible pharmacist name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Pharmacist License Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _pharLicCtrl,
                hint: 'Pharmacy license / registration number',
                icon: Icons.local_pharmacy_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Pharmacist license is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Pharmacy Council / Board Registration', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _pharCouncilCtrl,
                hint: 'Council registration number',
                icon: Icons.verified_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Council registration is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Professional License Expiry Date', required: true),
              const SizedBox(height: 6),
              _DatePickerField(
                value: _licenseExpiry,
                hint: 'DD / MM / YYYY',
                onTap: _pickLicenseExpiry,
                formatDate: _formatDate,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Documents'),
              const SizedBox(height: 16),

              const _FieldLabel('Business Registration Certificate', required: true),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload Business Registration Certificate', icon: Icons.upload_file_outlined),
              const SizedBox(height: 16),

              const _FieldLabel('Pharmacy License / Certification', required: true),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload Pharmacy License', icon: Icons.upload_file_outlined),
              const SizedBox(height: 16),

              const _FieldLabel('Responsible Pharmacist Certificate', required: true),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload Pharmacist Certificate', icon: Icons.upload_file_outlined),
              const SizedBox(height: 24),

              const _SectionHeader('Operations'),
              const SizedBox(height: 16),

              const _FieldLabel('List of Permitted Products', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _permittedProductsCtrl,
                hint: 'e.g. Vaccines, antibiotics, vitamins',
                icon: Icons.medication_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Permitted products list is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Storage / Cold-Chain Capability', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _storageCtrl,
                hint: 'e.g. Refrigerated -20°C, dry storage',
                icon: Icons.kitchen_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Storage capability is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Delivery Coverage Area', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _deliveryCovCtrl,
                hint: 'Districts or areas covered',
                icon: Icons.map_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Delivery coverage area is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Returns / Expiry Handling Policy', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _returnsCtrl,
                hint: 'Describe your returns and expiry handling policy',
                icon: Icons.assignment_return_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Returns/expiry policy is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Financial & Legal'),
              const SizedBox(height: 16),

              const _FieldLabel('Bank Account for Settlement', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _bankAccountCtrl,
                hint: 'Bank name, account number',
                icon: Icons.account_balance_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank account is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Authorized Signatory Details', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _signatoryCtrl,
                hint: 'Name and designation',
                icon: Icons.draw_outlined,
                action: TextInputAction.done,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Authorized signatory is required' : null,
              ),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _policyAgreement,
                label: 'I agree to Featherflow product quality standards, prescription rules, and audit policies. *',
                onChanged: (v) => setState(() => _policyAgreement = v ?? false),
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
                    'Create Pharmacy Account',
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
        decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 14))),
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
          child: Checkbox(value: value, onChanged: onChanged, activeColor: const Color(0xFF1DB584), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5))),
      ],
    );
  }
}
