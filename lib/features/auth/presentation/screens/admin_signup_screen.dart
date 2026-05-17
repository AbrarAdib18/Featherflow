import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';

class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});

  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _accountIdCtrl = TextEditingController();
  final _jobTitleCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _reportingManagerCtrl = TextEditingController();
  final _workLocationCtrl = TextEditingController();
  final _employmentTypeCtrl = TextEditingController();
  final _accessLevelCtrl = TextEditingController();
  final _priorExpCtrl = TextEditingController();
  final _techSkillCtrl = TextEditingController();
  final _prevWorkCtrl = TextEditingController();
  final _approvedByNameCtrl = TextEditingController();
  final _approvedByIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _twoFaContactCtrl = TextEditingController();

  DateTime? _startDate;
  bool _confidentialityAgreement = false;
  bool _bgConsent = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountIdCtrl.dispose();
    _jobTitleCtrl.dispose();
    _deptCtrl.dispose();
    _reportingManagerCtrl.dispose();
    _workLocationCtrl.dispose();
    _employmentTypeCtrl.dispose();
    _accessLevelCtrl.dispose();
    _priorExpCtrl.dispose();
    _techSkillCtrl.dispose();
    _prevWorkCtrl.dispose();
    _approvedByNameCtrl.dispose();
    _approvedByIdCtrl.dispose();
    _passwordCtrl.dispose();
    _twoFaContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
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
    if (picked != null) setState(() => _startDate = picked);
  }

  void _onSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start date is required.')),
      );
      return;
    }
    if (!_confidentialityAgreement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confidentiality agreement acceptance is required.')),
      );
      return;
    }
    if (!_bgConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Background check consent is required.')),
      );
      return;
    }
    context.go(AppRoutes.adminDashboard);
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
              'Admin Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Admin Details',
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
              const _SectionHeader('Account Information'),
              const SizedBox(height: 16),

              const _FieldLabel('Account ID Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _accountIdCtrl,
                hint: 'Assigned account ID',
                icon: Icons.fingerprint,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Account ID is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Job Title', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _jobTitleCtrl,
                hint: 'e.g. Operations Manager',
                icon: Icons.work_outline,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Job title is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Department', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _deptCtrl,
                hint: 'e.g. Operations, Finance, Content',
                icon: Icons.domain_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Department is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Reporting Manager', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _reportingManagerCtrl,
                hint: 'Name of your reporting manager',
                icon: Icons.supervisor_account_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Reporting manager is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Work Location', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _workLocationCtrl,
                hint: 'Office address or remote',
                icon: Icons.location_on_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Work location is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Employment Type', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _employmentTypeCtrl,
                hint: 'e.g. Full-time, Part-time, Contract',
                icon: Icons.business_center_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Employment type is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Start Date', required: true),
              const SizedBox(height: 6),
              _DatePickerField(
                value: _startDate,
                hint: 'DD / MM / YYYY',
                onTap: _pickStartDate,
                formatDate: _formatDate,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Access & Experience'),
              const SizedBox(height: 16),

              const _FieldLabel('Access Level Requested', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _accessLevelCtrl,
                hint: 'e.g. Operations Admin, Finance Admin',
                icon: Icons.admin_panel_settings_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Access level is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Tech Skill Level', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _techSkillCtrl,
                hint: 'e.g. Intermediate — comfortable with web dashboards',
                icon: Icons.computer_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Tech skill level is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Prior Admin / Operations Experience'),
              const SizedBox(height: 6),
              _LightField(
                controller: _priorExpCtrl,
                hint: 'e.g. 3 years platform operations at XYZ',
                icon: Icons.history_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Previous Work Experience'),
              const SizedBox(height: 6),
              _LightField(
                controller: _prevWorkCtrl,
                hint: 'Previous roles and organizations',
                icon: Icons.work_history_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Security Setup'),
              const SizedBox(height: 16),

              const _FieldLabel('Strong Password', required: true),
              const SizedBox(height: 6),
              _LightFieldWithSuffix(
                controller: _passwordCtrl,
                hint: 'Min. 8 chars, upper, lower, number, symbol',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('2FA Contact (Phone / Email)', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _twoFaContactCtrl,
                hint: 'Phone or email for 2FA codes',
                icon: Icons.security_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? '2FA contact is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Approval'),
              const SizedBox(height: 16),

              const _FieldLabel('Approved By — Admin Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _approvedByNameCtrl,
                hint: 'Full name of approving admin',
                icon: Icons.verified_user_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Approver name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Approved By — Admin ID', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _approvedByIdCtrl,
                hint: 'Admin ID of the approver',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Approver Admin ID is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Documents'),
              const SizedBox(height: 16),

              const _FieldLabel('CV / Resume'),
              const SizedBox(height: 6),
              const _UploadButton(label: 'Upload CV / Resume', icon: Icons.description_outlined),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _confidentialityAgreement,
                label: 'I accept the Featherflow confidentiality agreement and data protection policy. *',
                onChanged: (v) => setState(() => _confidentialityAgreement = v ?? false),
              ),
              const SizedBox(height: 12),
              _ConsentRow(
                value: _bgConsent,
                label: 'I consent to a background check as part of the admin onboarding process. *',
                onChanged: (v) => setState(() => _bgConsent = v ?? false),
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
                    'Submit Admin Application',
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
  final TextInputAction? action;
  final String? Function(String?)? validator;

  const _LightField({required this.controller, required this.hint, required this.icon, this.action, this.validator});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
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

class _LightFieldWithSuffix extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget suffix;
  final String? Function(String?)? validator;

  const _LightFieldWithSuffix({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.obscure,
    required this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        errorStyle: const TextStyle(color: Color(0xFFFF5C6A), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        suffixIcon: suffix,
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
