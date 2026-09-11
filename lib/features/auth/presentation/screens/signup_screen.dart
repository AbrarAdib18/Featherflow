import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/router/app_router.dart';
import '../../data/signup_form_cache.dart';
import '../widgets/signup_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nidController = TextEditingController();
  final _emergencyController = TextEditingController();

  DateTime? _dateOfBirth;
  String _selectedLanguage = 'English';
  bool _dobError = false;
  bool _termsAccepted = false;
  bool _termsError = false;
  String? _photoUrl;
  bool _pickingPhoto = false;
  bool _passwordSectionValid = false;

  late final AnimationController _waveController;

  static const List<String> _languages = ['English', 'বাংলা (Bengali)'];

  List<TextEditingController> get _textControllers => [
        _nameController,
        _phoneController,
        _emailController,
        _addressController,
        _passwordController,
        _confirmPasswordController,
        _nidController,
        _emergencyController,
      ];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _restoreFromCache();
    for (final c in _textControllers) {
      c.addListener(_cacheForm);
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.removeListener(_cacheForm);
      c.dispose();
    }
    _waveController.dispose();
    super.dispose();
  }

  void _restoreFromCache() {
    final cached = SignupFormCache.instance.read(SignupFormCache.basicInfoKey);
    if (cached == null) return;
    String s(String key) => (cached[key] as String?) ?? '';
    _nameController.text = s('name');
    _phoneController.text = s('phone');
    _emailController.text = s('email');
    _addressController.text = s('address');
    _passwordController.text = s('password');
    _confirmPasswordController.text = s('confirm_password');
    _nidController.text = s('nid');
    _emergencyController.text = s('emergency');
    final dob = s('date_of_birth');
    if (dob.isNotEmpty) _dateOfBirth = DateTime.tryParse(dob);
    _selectedLanguage = s('language').isNotEmpty ? s('language') : _selectedLanguage;
    _termsAccepted = (cached['terms'] as bool?) ?? false;
    _photoUrl = cached['photo_url'] as String?;
  }

  void _cacheForm() {
    SignupFormCache.instance.save(SignupFormCache.basicInfoKey, {
      'name': _nameController.text,
      'phone': _phoneController.text,
      'email': _emailController.text,
      'address': _addressController.text,
      'password': _passwordController.text,
      'confirm_password': _confirmPasswordController.text,
      'nid': _nidController.text,
      'emergency': _emergencyController.text,
      'date_of_birth': _dateOfBirth?.toIso8601String() ?? '',
      'language': _selectedLanguage,
      'terms': _termsAccepted,
      'photo_url': _photoUrl,
    });
  }

  bool get _hasData =>
      _textControllers.any((c) => c.text.trim().isNotEmpty) ||
      _dateOfBirth != null ||
      _termsAccepted ||
      _photoUrl != null;

  /// Block "Next" once the user has started a password that is not yet valid /
  /// confirmed. An untouched password keeps the button live so a tap surfaces
  /// every required-field error at once.
  bool get _nextBlocked =>
      (_passwordController.text.isNotEmpty ||
          _confirmPasswordController.text.isNotEmpty) &&
      !_passwordSectionValid;

  Future<void> _leave() async {
    await handleSignupLeave(
      context,
      hasData: _hasData,
      cacheKey: SignupFormCache.basicInfoKey,
      destination: AppRoutes.login,
    );
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the file picker.')),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo must be 5 MB or smaller.')),
        );
      }
      return;
    }
    setState(() => _pickingPhoto = true);
    try {
      final url = await AuthService.instance.uploadRegistrationDoc(
        bytes: bytes, filename: file.name, kind: 'profile_photo');
      if (mounted) {
        setState(() => _photoUrl = url);
        _cacheForm();
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not reach the server to upload the photo. '
                  'Check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.secondary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dobError = false;
      });
      _cacheForm();
    }
  }

  Future<void> _onNext() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final dobMissing = _dateOfBirth == null;
    final termsMissing = !_termsAccepted;
    setState(() {
      _dobError = dobMissing;
      _termsError = termsMissing;
    });
    if (formValid && !dobMissing && !termsMissing) {
      await AuthService.instance.savePendingRegistration(
        email: _emailController.text,
        password: _passwordController.text,
        phone: _phoneController.text,
        fullName: _nameController.text,
        address: _addressController.text,
        dateOfBirth: _dateOfBirth!.toIso8601String().split('T').first,
        nationalId: _nidController.text,
        emergencyContact: _emergencyController.text,
        preferredLanguage:
            _selectedLanguage.startsWith('English') ? 'en' : 'bn',
        consentTerms: _termsAccepted,
        profilePhotoUrl: _photoUrl ?? '',
      );
      if (!mounted) return;
      context.go(AppRoutes.roleSelection);
    }
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
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double topHeight = constraints.maxHeight * 0.26;
          const double waveOverlap = 28.0;

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topHeight + waveOverlap,
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) => CustomPaint(
                    painter: _WavePainter(
                      progress: _waveController.value,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 4,
                child: SafeArea(
                  bottom: false,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                    onPressed: _leave,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topHeight,
                child: const SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.egg_alt, color: Colors.white, size: 20),
                          SizedBox(width: AppSpacing.xs),
                          Text(
                            'Featherflow',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      _StepIndicator(current: 1, total: 3, label: 'Basic Information'),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: topHeight + waveOverlap,
                left: 0,
                right: 0,
                bottom: 0,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Stack(
                              children: [
                                Container(
                                  width: 88,
                                  height: 88,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.secondary.withValues(alpha: 0.35),
                                      width: 2,
                                    ),
                                  ),
                                  child: _pickingPhoto
                                      ? const Center(
                                          child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2)))
                                      : _photoUrl != null
                                          ? Image.network(_photoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(
                                                  Icons.person_outline,
                                                  size: 42,
                                                  color: Colors.grey.shade400))
                                          : Icon(
                                              Icons.person_outline,
                                              size: 42,
                                              color: Colors.grey.shade400,
                                            ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: AppColors.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _photoUrl != null
                                          ? Icons.edit
                                          : Icons.camera_alt,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Center(
                          child: Text(
                            _photoUrl != null ? 'Change Photo' : 'Upload Photo (optional)',
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _FieldLabel('Full Name', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _nameController,
                          hint: 'Your full name',
                          icon: Icons.person_outline,
                          action: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Full name is required'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Phone Number', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _phoneController,
                          hint: '+880 1X-XXXX-XXXX',
                          icon: Icons.phone_outlined,
                          keyboard: TextInputType.phone,
                          action: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Phone number is required'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Email', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _emailController,
                          hint: 'you@example.com',
                          icon: Icons.email_outlined,
                          keyboard: TextInputType.emailAddress,
                          action: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Date of Birth', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: AppRadius.mdAll,
                              border: Border.all(
                                color: _dobError
                                    ? const Color(0xFFFF5C6A)
                                    : Colors.grey.shade200,
                                width: _dobError ? 1.5 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  color: Colors.grey.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  _dateOfBirth != null
                                      ? '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
                                      : 'DD / MM / YYYY',
                                  style: TextStyle(
                                    color: _dateOfBirth != null
                                        ? const Color(0xFF1A1A1A)
                                        : Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_dobError)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: AppSpacing.xs, left: AppSpacing.xs),
                            child: Text(
                              'Date of birth is required',
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Present Address', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _addressController,
                          hint: 'Street, City, District',
                          icon: Icons.location_on_outlined,
                          action: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Address is required'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SignupPasswordFields(
                          passwordController: _passwordController,
                          confirmController: _confirmPasswordController,
                          emailController: _emailController,
                          nameController: _nameController,
                          phoneController: _phoneController,
                          onChanged: () {
                            // Rebuild so the "Next" button re-evaluates
                            // _nextBlocked against the latest field text.
                            if (mounted) setState(() {});
                          },
                          onValidityChanged: (valid) {
                            if (valid != _passwordSectionValid) {
                              setState(() => _passwordSectionValid = valid);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('NID / Passport Number', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _nidController,
                          hint: 'National ID or passport number',
                          icon: Icons.badge_outlined,
                          action: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'NID or passport number is required'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Emergency Contact'),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _emergencyController,
                          hint: 'Name and phone number',
                          icon: Icons.emergency_outlined,
                          keyboard: TextInputType.phone,
                          action: TextInputAction.next,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Preferred Language'),
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7F7),
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedLanguage,
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade400),
                              style: const TextStyle(
                                  color: Color(0xFF1A1A1A), fontSize: 14),
                              items: _languages
                                  .map((l) => DropdownMenuItem(
                                        value: l,
                                        child: Row(
                                          children: [
                                            Icon(Icons.language_outlined,
                                                color: Colors.grey.shade400,
                                                size: 20),
                                            const SizedBox(width: AppSpacing.sm),
                                            Text(l),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                setState(() =>
                                    _selectedLanguage = v ?? _selectedLanguage);
                                _cacheForm();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _termsAccepted,
                                activeColor: AppColors.secondary,
                                isError: _termsError,
                                onChanged: (v) {
                                  setState(() {
                                    _termsAccepted = v ?? false;
                                    if (_termsAccepted) _termsError = false;
                                  });
                                  _cacheForm();
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: 'I agree to the ',
                                  style: TextStyle(
                                      color: _termsError
                                          ? const Color(0xFFFF5C6A)
                                          : Colors.grey.shade700,
                                      fontSize: 12,
                                      height: 1.5),
                                  children: const [
                                    TextSpan(
                                        text: 'Terms of Service',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.secondary)),
                                    TextSpan(text: ' and '),
                                    TextSpan(
                                        text: 'Privacy Policy',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.secondary)),
                                    TextSpan(text: '. *'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_termsError)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: AppSpacing.xs, left: AppSpacing.xs),
                            child: Text(
                              'You must accept the Terms and Privacy Policy',
                              style: TextStyle(
                                  color: Colors.red.shade400, fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _nextBlocked ? null : _onNext,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppColors.secondary.withValues(alpha: 0.45),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: AppRadius.lgAll),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: AppSpacing.sm),
                                Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 14),
                            ),
                            GestureDetector(
                              onTap: () => context.go(AppRoutes.login),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String label;

  const _StepIndicator(
      {required this.current, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total * 2 - 1, (i) {
            if (i.isOdd) {
              return Container(
                width: 24,
                height: 2,
                color: Colors.white.withValues(alpha: 0.35),
              );
            }
            final step = i ~/ 2 + 1;
            final isActive = step == current;
            final isDone = step < current;
            return Container(
              width: isActive ? 26 : 22,
              height: isActive ? 26 : 22,
              decoration: BoxDecoration(
                color: isActive || isDone
                    ? AppColors.secondary
                    : Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : Text(
                        '$step',
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.3,
          ),
        ),
      ],
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
            style: const TextStyle(
              color: Color(0xFF2A2A2A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: Color(0xFFFF5C6A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
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
        errorStyle:
            const TextStyle(color: Color(0xFFFF5C6A), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFFF5C6A)),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: Color(0xFFFF5C6A), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const double amplitude = 14.0;
    const double waveOverlap = 28.0;
    final double baseline = size.height - waveOverlap;
    final double phase = progress * 2 * math.pi;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, baseline);

    for (double x = size.width; x >= 0; x -= 2) {
      final double y = baseline +
          amplitude * math.sin((x / size.width * 2 * math.pi) - phase);
      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
