import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';

class ResearcherSignupScreen extends StatefulWidget {
  const ResearcherSignupScreen({super.key});

  @override
  State<ResearcherSignupScreen> createState() => _ResearcherSignupScreenState();
}

class _ResearcherSignupScreenState extends State<ResearcherSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _institutionCtrl = TextEditingController();
  final _instEmailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _fieldStudyCtrl = TextEditingController();
  final _uniCtrl = TextEditingController();
  final _gradYearCtrl = TextEditingController();
  final _publicationsCtrl = TextEditingController();
  final _expertiseCtrl = TextEditingController();
  final _resYearsCtrl = TextEditingController();
  final _poultryExpCtrl = TextEditingController();
  final _softwareCtrl = TextEditingController();
  final _labAccessCtrl = TextEditingController();
  final _refNameCtrl = TextEditingController();
  final _refTitleCtrl = TextEditingController();
  final _refEmailCtrl = TextEditingController();

  String _researchRole = 'Disease';
  bool _conflictDeclaration = false;
  bool _publicationConsent = false;
  bool _submitting = false;
  String? _cvUrl;
  String? _ethicsCertUrl;

  static const List<String> _researchRoles = [
    'Nutrition', 'Disease', 'Genetics', 'Welfare', 'Growth', 'Economics',
  ];

  late final SignupFormDraft _draft = SignupFormDraft(
    cacheKey: 'researcher',
    fields: {
      'institution': _institutionCtrl,
      'institutional_email': _instEmailCtrl,
      'phone': _phoneCtrl,
      'department': _deptCtrl,
      'degree': _degreeCtrl,
      'field_of_study': _fieldStudyCtrl,
      'university': _uniCtrl,
      'graduation_year': _gradYearCtrl,
      'publications': _publicationsCtrl,
      'areas_of_expertise': _expertiseCtrl,
      'years_experience': _resYearsCtrl,
      'poultry_experience': _poultryExpCtrl,
      'software_experience': _softwareCtrl,
      'lab_access': _labAccessCtrl,
      'reference_name': _refNameCtrl,
      'reference_title': _refTitleCtrl,
      'reference_email': _refEmailCtrl,
    },
    readExtra: () => {
      'research_role': _researchRole,
      'conflict_declaration': _conflictDeclaration,
      'publication_consent': _publicationConsent,
      'cv_url': _cvUrl,
      'ethics_certificate_url': _ethicsCertUrl,
    },
    writeExtra: (d) {
      _researchRole = (d['research_role'] as String?) ?? _researchRole;
      _conflictDeclaration = (d['conflict_declaration'] as bool?) ?? false;
      _publicationConsent = (d['publication_consent'] as bool?) ?? false;
      _cvUrl = d['cv_url'] as String?;
      _ethicsCertUrl = d['ethics_certificate_url'] as String?;
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
    _institutionCtrl.dispose();
    _instEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _degreeCtrl.dispose();
    _fieldStudyCtrl.dispose();
    _uniCtrl.dispose();
    _gradYearCtrl.dispose();
    _publicationsCtrl.dispose();
    _expertiseCtrl.dispose();
    _resYearsCtrl.dispose();
    _poultryExpCtrl.dispose();
    _softwareCtrl.dispose();
    _labAccessCtrl.dispose();
    _refNameCtrl.dispose();
    _refTitleCtrl.dispose();
    _refEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_cvUrl == null) {
      _snack('Upload your CV / resume to continue.');
      return;
    }
    if (!_conflictDeclaration) {
      _snack('Conflict of interest declaration is required.');
      return;
    }
    if (!_publicationConsent) {
      _snack('Publication consent is required.');
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
        role: 'researcher',
        address: pending['address']?.toString() ?? '',
        dateOfBirth: pending['date_of_birth']?.toString() ?? '',
        consentTerms: pending['consent_terms'] == true,
        nationalId: pending['national_id']?.toString() ?? '',
        emergencyContact: pending['emergency_contact']?.toString() ?? '',
        preferredLanguage: pending['preferred_language']?.toString() ?? 'en',
        profilePhotoUrl: pending['profile_photo_url']?.toString() ?? '',
        roleData: {
          'institution': _institutionCtrl.text.trim(),
          'institutional_email': _instEmailCtrl.text.trim(),
          'department': _deptCtrl.text.trim(),
          'degree': _degreeCtrl.text.trim(),
          'field_of_study': _fieldStudyCtrl.text.trim(),
          'university': _uniCtrl.text.trim(),
          'graduation_year': _gradYearCtrl.text.trim(),
          'publications': _publicationsCtrl.text.trim(),
          'areas_of_expertise': _expertiseCtrl.text.trim(),
          'years_experience': _resYearsCtrl.text.trim(),
          'poultry_experience': _poultryExpCtrl.text.trim(),
          'software_experience': _softwareCtrl.text.trim(),
          'lab_access': _labAccessCtrl.text.trim(),
          'cv_url': _cvUrl,
          if (_ethicsCertUrl != null) 'ethics_certificate_url': _ethicsCertUrl,
          'reference_name': _refNameCtrl.text.trim(),
          'reference_title': _refTitleCtrl.text.trim(),
          'reference_email': _refEmailCtrl.text.trim(),
          'research_role': _researchRole,
          'conflict_declaration': true,
          'publication_consent': true,
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
              'Researcher Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Research Profile',
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
              const _SectionHeader('Institution & Contact'),
              const SizedBox(height: 16),

              const _FieldLabel('Institution / Company Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _institutionCtrl,
                hint: 'University, research institute, or company',
                icon: Icons.account_balance_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Institution name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Institutional Email', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _instEmailCtrl,
                hint: 'you@institution.edu',
                icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress,
                action: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Institutional email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Phone Number', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _phoneCtrl,
                hint: '+880 1X-XXXX-XXXX',
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Department', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _deptCtrl,
                hint: 'e.g. Poultry Science, Animal Health',
                icon: Icons.domain_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Department is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Academic Background'),
              const SizedBox(height: 16),

              const _FieldLabel('Highest Academic Degree', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _degreeCtrl,
                hint: 'e.g. PhD, MSc, BSc',
                icon: Icons.school_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Academic degree is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Field of Study', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _fieldStudyCtrl,
                hint: 'e.g. Veterinary Medicine, Animal Nutrition',
                icon: Icons.biotech_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Field of study is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('University / College Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _uniCtrl,
                hint: 'Where you studied',
                icon: Icons.account_balance_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'University name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Year of Graduation', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _gradYearCtrl,
                hint: 'e.g. 2018',
                icon: Icons.calendar_today_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Graduation year is required' : null,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Research Experience'),
              const SizedBox(height: 16),

              const _FieldLabel('Areas of Expertise', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _expertiseCtrl,
                hint: 'e.g. Avian pathology, Feed formulation',
                icon: Icons.psychology_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Areas of expertise is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Years of Research Experience', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _resYearsCtrl,
                hint: 'e.g. 7',
                icon: Icons.timeline_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Years of experience is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Research Role Type', required: true),
              const SizedBox(height: 6),
              _LightDropdown<String>(
                value: _researchRole,
                items: _researchRoles,
                icon: Icons.science_outlined,
                onChanged: (v) {
                  setState(() => _researchRole = v ?? _researchRole);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Publications / Portfolio'),
              const SizedBox(height: 6),
              _LightField(
                controller: _publicationsCtrl,
                hint: 'Links or titles of published works',
                icon: Icons.article_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Poultry-Specific Experience'),
              const SizedBox(height: 6),
              _LightField(
                controller: _poultryExpCtrl,
                hint: 'e.g. 3 years broiler nutrition research',
                icon: Icons.egg_alt_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Software / Data Analysis Skills'),
              const SizedBox(height: 6),
              _LightField(
                controller: _softwareCtrl,
                hint: 'e.g. R, Python, SPSS, SAS',
                icon: Icons.code_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Access to Lab / Institution'),
              const SizedBox(height: 6),
              _LightField(
                controller: _labAccessCtrl,
                hint: 'e.g. Full access to BSL-2 lab',
                icon: Icons.science_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Documents'),
              const SizedBox(height: 16),

              const _FieldLabel('CV / Resume', required: true),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload CV / resume (PDF or image)',
                kind: 'cv',
                required: true,
                initialUrl: _cvUrl,
                onUploaded: (url) {
                  setState(() => _cvUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Ethics / Training Certificate'),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload ethics certificate (optional)',
                kind: 'certificate',
                initialUrl: _ethicsCertUrl,
                onUploaded: (url) {
                  setState(() => _ethicsCertUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 24),

              const _SectionHeader('Reference'),
              const SizedBox(height: 16),

              const _FieldLabel('Reference Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _refNameCtrl,
                hint: 'Full name of your reference',
                icon: Icons.person_outline,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Reference name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Reference Title', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _refTitleCtrl,
                hint: 'e.g. Professor, Dr.',
                icon: Icons.title_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Reference title is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Reference Email', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _refEmailCtrl,
                hint: 'reference@institution.edu',
                icon: Icons.email_outlined,
                keyboard: TextInputType.emailAddress,
                action: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Reference email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _conflictDeclaration,
                label: 'I declare that I have no conflict of interest that could affect my research integrity. *',
                onChanged: (v) {
                  setState(() => _conflictDeclaration = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 12),
              _ConsentRow(
                value: _publicationConsent,
                label: 'I consent to publication of my research on Featherflow and agree to the IP terms. *',
                onChanged: (v) {
                  setState(() => _publicationConsent = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 32),

              SignupSubmitButton(
                label: 'Submit Researcher Application',
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
