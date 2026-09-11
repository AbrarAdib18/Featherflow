import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';

class FarmerSignupScreen extends StatefulWidget {
  const FarmerSignupScreen({super.key});

  @override
  State<FarmerSignupScreen> createState() => _FarmerSignupScreenState();
}

class _FarmerSignupScreenState extends State<FarmerSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _farmNameCtrl = TextEditingController();
  final _farmOwnerCtrl = TextEditingController();
  final _farmLocationCtrl = TextEditingController();
  final _farmBirdsCtrl = TextEditingController();
  final _farmRegCtrl = TextEditingController();
  final _farmYearsCtrl = TextEditingController();
  final _farmDiseaseCtrl = TextEditingController();
  final _farmFeedCtrl = TextEditingController();
  final _farmVetCtrl = TextEditingController();
  final _farmWorkersCtrl = TextEditingController();

  String _farmType = 'Broiler';
  String _experienceLevel = 'Beginner';
  bool _farmConsent = false;
  bool _submitting = false;
  String? _farmPhotoUrl;

  static const List<String> _farmTypes = [
    'Broiler', 'Layer', 'Breeder', 'Hatchery', 'Mixed', 'Backyard',
  ];
  static const List<String> _expLevels = [
    'Beginner', 'Intermediate', 'Expert',
  ];

  late final SignupFormDraft _draft = SignupFormDraft(
    cacheKey: 'farmer',
    fields: {
      'farm_name': _farmNameCtrl,
      'farm_owner': _farmOwnerCtrl,
      'farm_location': _farmLocationCtrl,
      'bird_count': _farmBirdsCtrl,
      'farm_registration': _farmRegCtrl,
      'years_in_farming': _farmYearsCtrl,
      'primary_disease': _farmDiseaseCtrl,
      'feed_type': _farmFeedCtrl,
      'vet_contact': _farmVetCtrl,
      'active_workers': _farmWorkersCtrl,
    },
    readExtra: () => {
      'farm_type': _farmType,
      'experience_level': _experienceLevel,
      'consent': _farmConsent,
      'farm_photo_url': _farmPhotoUrl,
    },
    writeExtra: (d) {
      _farmType = (d['farm_type'] as String?) ?? _farmType;
      _experienceLevel = (d['experience_level'] as String?) ?? _experienceLevel;
      _farmConsent = (d['consent'] as bool?) ?? false;
      _farmPhotoUrl = d['farm_photo_url'] as String?;
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
    _farmNameCtrl.dispose();
    _farmOwnerCtrl.dispose();
    _farmLocationCtrl.dispose();
    _farmBirdsCtrl.dispose();
    _farmRegCtrl.dispose();
    _farmYearsCtrl.dispose();
    _farmDiseaseCtrl.dispose();
    _farmFeedCtrl.dispose();
    _farmVetCtrl.dispose();
    _farmWorkersCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_farmConsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please consent to data collection to continue.')),
      );
      return;
    }

    final pending = await AuthService.instance.getPendingRegistration();
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the basic signup information first.')),
      );
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
        role: 'farmer',
        address: pending['address']?.toString() ?? '',
        dateOfBirth: pending['date_of_birth']?.toString() ?? '',
        consentTerms: pending['consent_terms'] == true,
        nationalId: pending['national_id']?.toString() ?? '',
        emergencyContact: pending['emergency_contact']?.toString() ?? '',
        preferredLanguage: pending['preferred_language']?.toString() ?? 'en',
        profilePhotoUrl: pending['profile_photo_url']?.toString() ?? '',
        roleData: {
          'farm_name': _farmNameCtrl.text.trim(),
          'farm_owner': _farmOwnerCtrl.text.trim(),
          'farm_location': _farmLocationCtrl.text.trim(),
          'farm_type': _farmType,
          'bird_count': _farmBirdsCtrl.text.trim(),
          'farm_registration': _farmRegCtrl.text.trim(),
          'years_in_farming': _farmYearsCtrl.text.trim(),
          'experience_level': _experienceLevel,
          'primary_disease': _farmDiseaseCtrl.text.trim(),
          'feed_type': _farmFeedCtrl.text.trim(),
          'vet_contact': _farmVetCtrl.text.trim(),
          'active_workers': _farmWorkersCtrl.text.trim(),
          if (_farmPhotoUrl != null) 'farm_photos': [_farmPhotoUrl],
          'consent': true,
        },
      );
      if (!mounted) return;
      await routeAfterRegistration(context, result);
    } on AuthException catch (error) {
      if (!mounted) return;
      _showError(error);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Unable to reach the server. Check your connection and try again.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(AuthException error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(error.message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
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
              'Farmer Registration',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              'Step 3 of 3 — Farm Details',
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
              const _SectionHeader('Farm Information'),
              const SizedBox(height: 16),

              const _FieldLabel('Farm Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmNameCtrl,
                hint: 'Name of your farm',
                icon: Icons.home_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Farm name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Farm Owner / Manager Name', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmOwnerCtrl,
                hint: 'Full name',
                icon: Icons.person_outline,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Owner name is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Farm Location & Address', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmLocationCtrl,
                hint: 'Village, Upazila, District',
                icon: Icons.location_on_outlined,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Farm location is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Farm Type', required: true),
              const SizedBox(height: 6),
              _LightDropdown<String>(
                value: _farmType,
                items: _farmTypes,
                icon: Icons.category_outlined,
                onChanged: (v) {
                  setState(() => _farmType = v ?? _farmType);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Number of Birds Currently Kept', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmBirdsCtrl,
                hint: 'e.g. 500',
                icon: Icons.egg_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Number of birds is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Farm Registration / License Number'),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmRegCtrl,
                hint: 'If available',
                icon: Icons.badge_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Years in Poultry Farming', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmYearsCtrl,
                hint: 'e.g. 5',
                icon: Icons.timeline_outlined,
                keyboard: TextInputType.number,
                action: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Years in farming is required' : null,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Experience Level', required: true),
              const SizedBox(height: 6),
              _LightDropdown<String>(
                value: _experienceLevel,
                items: _expLevels,
                icon: Icons.star_outline,
                onChanged: (v) {
                  setState(() => _experienceLevel = v ?? _experienceLevel);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Primary Disease / Issues Faced'),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmDiseaseCtrl,
                hint: 'e.g. Newcastle, Coccidiosis',
                icon: Icons.coronavirus_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Feed Type & Sourcing Method'),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmFeedCtrl,
                hint: 'e.g. Commercial pellet, local supplier',
                icon: Icons.grass_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Vet / Consultant They Work With'),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmVetCtrl,
                hint: 'Name and contact of your vet',
                icon: Icons.medical_services_outlined,
                action: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Farm / Shed / Bird Photo'),
              const SizedBox(height: 6),
              SignupUploadField(
                label: 'Upload a farm photo (optional)',
                kind: 'farm_photo',
                imageOnly: true,
                initialUrl: _farmPhotoUrl,
                onUploaded: (url) {
                  setState(() => _farmPhotoUrl = url);
                  _draft.save();
                },
              ),
              const SizedBox(height: 16),

              const _FieldLabel('Number of Active Workers', required: true),
              const SizedBox(height: 6),
              _LightField(
                controller: _farmWorkersCtrl,
                hint: 'e.g. 3',
                icon: Icons.people_outline,
                keyboard: TextInputType.number,
                action: TextInputAction.done,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Number of workers is required' : null,
              ),
              const SizedBox(height: 24),

              _ConsentRow(
                value: _farmConsent,
                label: 'I consent to data collection for flock health and performance tracking. *',
                onChanged: (v) {
                  setState(() => _farmConsent = v ?? false);
                  _draft.save();
                },
              ),
              const SizedBox(height: 32),

              SignupSubmitButton(
                label: 'Create Farmer Account',
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
                      Text(
                        'Back to Role Selection',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: GestureDetector(
                          onTap: () => context.go(AppRoutes.login),
                          child: const Text('Sign in',
                              style: TextStyle(
                                  color: Color(0xFF1DB584),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
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
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF01291E),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
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

  const _LightDropdown({
    required this.value,
    required this.items,
    required this.icon,
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
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
          style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.grey.shade400, size: 20),
                        const SizedBox(width: 8),
                        Text('$item'),
                      ],
                    ),
                  ))
              .toList(),
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
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF1DB584),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5),
          ),
        ),
      ],
    );
  }
}
