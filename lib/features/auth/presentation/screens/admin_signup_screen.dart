import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';

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
  final _priorExpCtrl = TextEditingController();
  final _techSkillCtrl = TextEditingController();
  final _prevWorkCtrl = TextEditingController();
  final _approvedByNameCtrl = TextEditingController();
  final _approvedByIdCtrl = TextEditingController();
  final _twoFaContactCtrl = TextEditingController();

  // Access level requested — maps 1:1 to a real admin sub-role so the backend
  // can resolve RBAC on approval. "Super Admin" is deliberately excluded.
  static const _accessLevels = <String, String>{
    'operations': 'Operations Admin',
    'finance': 'Finance Admin',
    'content': 'Content Admin',
    'research': 'Research Admin',
    'delivery': 'Delivery Admin',
    'pharmacy': 'Pharmacy Admin',
    'support': 'Support Admin',
    'doctor': 'Doctor Ops Admin',
  };
  static const _employmentTypes = ['Full-time', 'Part-time', 'Contract'];

  String _accessLevel = 'support';
  String _employmentType = 'Full-time';
  DateTime? _startDate;
  bool _confidentialityAgreement = false;
  bool _bgConsent = false;
  bool _submitting = false;
  String? _cvUrl;

  late final SignupFormDraft _draft = SignupFormDraft(
    cacheKey: 'admin',
    fields: {
      'account_id': _accountIdCtrl,
      'job_title': _jobTitleCtrl,
      'department': _deptCtrl,
      'reporting_manager': _reportingManagerCtrl,
      'work_location': _workLocationCtrl,
      'prior_admin_operations_experience': _priorExpCtrl,
      'tech_skills': _techSkillCtrl,
      'previous_work': _prevWorkCtrl,
      'approved_by_name': _approvedByNameCtrl,
      'approved_by_id': _approvedByIdCtrl,
      'two_factor_contact': _twoFaContactCtrl,
    },
    readExtra: () => {
      'access_level': _accessLevel,
      'employment_type': _employmentType,
      'start_date': _startDate?.toIso8601String(),
      'confidentiality_agreement': _confidentialityAgreement,
      'bg_consent': _bgConsent,
      'cv_url': _cvUrl,
    },
    writeExtra: (d) {
      _accessLevel = (d['access_level'] as String?) ?? _accessLevel;
      _employmentType = (d['employment_type'] as String?) ?? _employmentType;
      final start = d['start_date'];
      if (start is String && start.isNotEmpty) {
        _startDate = DateTime.tryParse(start);
      }
      _confidentialityAgreement =
          (d['confidentiality_agreement'] as bool?) ?? false;
      _bgConsent = (d['bg_consent'] as bool?) ?? false;
      _cvUrl = d['cv_url'] as String?;
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
    _accountIdCtrl.dispose();
    _jobTitleCtrl.dispose();
    _deptCtrl.dispose();
    _reportingManagerCtrl.dispose();
    _workLocationCtrl.dispose();
    _priorExpCtrl.dispose();
    _techSkillCtrl.dispose();
    _prevWorkCtrl.dispose();
    _approvedByNameCtrl.dispose();
    _approvedByIdCtrl.dispose();
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
    if (picked != null) {
      setState(() => _startDate = picked);
      _draft.save();
    }
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate == null) {
      _snack('Start date is required.');
      return;
    }
    if (!_confidentialityAgreement) {
      _snack('Confidentiality agreement acceptance is required.');
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
        role: 'admin',
        address: pending['address']?.toString() ?? '',
        dateOfBirth: pending['date_of_birth']?.toString() ?? '',
        consentTerms: pending['consent_terms'] == true,
        nationalId: pending['national_id']?.toString() ?? '',
        emergencyContact: pending['emergency_contact']?.toString() ?? '',
        preferredLanguage: pending['preferred_language']?.toString() ?? 'en',
        profilePhotoUrl: pending['profile_photo_url']?.toString() ?? '',
        roleData: {
          'account_id': _accountIdCtrl.text.trim(),
          'job_title': _jobTitleCtrl.text.trim(),
          'department': _deptCtrl.text.trim(),
          'reporting_manager': _reportingManagerCtrl.text.trim(),
          'work_location': _workLocationCtrl.text.trim(),
          'employment_type': _employmentType,
          'access_level': _accessLevel,
          'prior_admin_operations_experience': _priorExpCtrl.text.trim(),
          'tech_skills': _techSkillCtrl.text.trim(),
          'previous_work': _prevWorkCtrl.text.trim(),
          'approved_by_name': _approvedByNameCtrl.text.trim(),
          'approved_by_id': _approvedByIdCtrl.text.trim(),
          'start_date': _startDate!.toIso8601String(),
          'two_factor_contact': _twoFaContactCtrl.text.trim(),
          if (_cvUrl != null) 'cv_url': _cvUrl,
          'confidentiality_agreement': true,
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

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
              _Dropdown(
                value: _employmentType,
                items: _employmentTypes,
                icon: Icons.business_center_outlined,
                onChanged: (v) {
                  setState(() => _employmentType = v ?? _employmentType);
                  _draft.save();
                },
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
              _Dropdown(
                value: _accessLevel,
                items: _accessLevels.keys.toList(),
                labels: _accessLevels,
                icon: Icons.admin_panel_settings_outlined,
                onChanged: (v) {
                  setState(() => _accessLevel = v ?? _accessLevel);
                  _draft.save();
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Super Admin cannot be requested here. Operations / Super Admin '
                'will confirm your final access level on approval.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
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
              const SizedBox(height: 8),
              Text(
                'Your account password was set in Step 1. Two-factor '
                'authentication is configured after your application is approved.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
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

              const _SectionHeader('Referral (optional)'),
              const SizedBox(height: 16),

              const _FieldLabel('Referring / Sponsoring Admin — Name'),
              const SizedBox(height: 6),
              _LightField(
                controller: _approvedByNameCtrl,
                hint: 'Name of an admin who can vouch for you',
                icon: Icons.verified_user_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Referring / Sponsoring Admin — ID'),
              const SizedBox(height: 6),
              _LightField(
                controller: _approvedByIdCtrl,
                hint: 'Their admin ID, if you have it',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Documents'),
              const SizedBox(height: 16),

              const _FieldLabel('CV / Resume'),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload CV / resume (optional)',
                kind: 'cv',
                initialUrl: _cvUrl,
                onUploaded: (url) {
                  setState(() => _cvUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _confidentialityAgreement,
                label: 'I accept the Featherflow confidentiality agreement and data protection policy. *',
                onChanged: (v) {
                  setState(() => _confidentialityAgreement = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 12),
              _ConsentRow(
                value: _bgConsent,
                label: 'I consent to a background check as part of the admin onboarding process. *',
                onChanged: (v) {
                  setState(() => _bgConsent = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 32),

              SignupSubmitButton(
                label: 'Submit Admin Application',
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

class _Dropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final Map<String, String>? labels;
  final IconData icon;
  final void Function(String?)? onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.icon,
    this.labels,
    this.onChanged,
  });

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
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Row(children: [
                      Icon(icon, color: Colors.grey.shade400, size: 20),
                      const SizedBox(width: 8),
                      Text(labels?[item] ?? item),
                    ]),
                  ))
              .toList(),
          onChanged: onChanged,
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

class _DatePickerField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final String Function(DateTime) formatDate;

  const _DatePickerField(
      {required this.value,
      required this.hint,
      required this.onTap,
      required this.formatDate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Text(value != null ? formatDate(value!) : hint,
                style: TextStyle(
                    color: value != null
                        ? const Color(0xFF1A1A1A)
                        : Colors.grey.shade400,
                    fontSize: 14)),
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
