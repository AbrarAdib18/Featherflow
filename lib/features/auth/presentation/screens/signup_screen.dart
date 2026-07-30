import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/router/app_router.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _dobError = false;

  late final AnimationController _waveController;

  static const List<String> _languages = ['English', 'বাংলা (Bengali)'];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nidController.dispose();
    _emergencyController.dispose();
    _waveController.dispose();
    super.dispose();
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
    }
  }

  Future<void> _onNext() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final dobMissing = _dateOfBirth == null;
    setState(() => _dobError = dobMissing);
    if (formValid && !dobMissing) {
      await AuthService.instance.savePendingRegistration(
        email: _emailController.text,
        password: _passwordController.text,
        phone: _phoneController.text,
        fullName: _nameController.text,
        address: _addressController.text,
        dateOfBirth: _dateOfBirth!.toIso8601String().split('T').first,
      );
      if (!mounted) return;
      context.go(AppRoutes.roleSelection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                left: 0,
                right: 0,
                height: topHeight,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
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
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _StepIndicator(current: 1, total: 3, label: 'Basic Information'),
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
                            onTap: () {},
                            child: Stack(
                              children: [
                                Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.secondary.withValues(alpha: 0.35),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
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
                                    child: const Icon(
                                      Icons.camera_alt,
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
                            'Upload Photo',
                            style: TextStyle(
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
                        const _FieldLabel('Password', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _passwordController,
                          hint: 'At least 8 characters',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          action: TextInputAction.next,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password is required';
                            }
                            if (v.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('Confirm Password', required: true),
                        const SizedBox(height: AppSpacing.xs),
                        _LightField(
                          controller: _confirmPasswordController,
                          hint: 'Re-enter password',
                          icon: Icons.lock_outline,
                          obscure: _obscureConfirm,
                          action: TextInputAction.next,
                          suffix: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (v != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
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
                              onChanged: (v) => setState(
                                  () => _selectedLanguage = v ?? _selectedLanguage),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _onNext,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
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
  final Widget? suffix;
  final bool obscure;
  final String? Function(String?)? validator;
  const _LightField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.action,
    this.suffix,
    this.obscure = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      textInputAction: action,
      obscureText: obscure,
      style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        errorStyle:
            const TextStyle(color: Color(0xFFFF5C6A), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        suffixIcon: suffix,
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
