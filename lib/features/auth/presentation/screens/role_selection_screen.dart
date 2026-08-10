import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/router/app_router.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedRole;
  late final AnimationController _waveController;

  static const List<_RoleOption> _roles = [
    _RoleOption(
      id: 'farmer',
      title: 'Farmer',
      description: 'Manage your poultry farm, flocks, and health records',
      icon: Icons.agriculture_outlined,
    ),
    _RoleOption(
      id: 'doctor',
      title: 'Veterinarian / Doctor',
      description: 'Provide consultations, prescriptions, and case notes',
      icon: Icons.medical_services_outlined,
    ),
    _RoleOption(
      id: 'pharmacy',
      title: 'Pharmacy',
      description: 'Manage medicine inventory, orders, and delivery',
      icon: Icons.local_pharmacy_outlined,
    ),
    _RoleOption(
      id: 'delivery',
      title: 'Delivery Agent',
      description: 'Accept orders, navigate routes, and confirm handovers',
      icon: Icons.delivery_dining_outlined,
    ),
    _RoleOption(
      id: 'researcher',
      title: 'Researcher',
      description: 'Publish papers, disease updates, and innovations',
      icon: Icons.science_outlined,
    ),
    _RoleOption(
      id: 'admin',
      title: 'Admin',
      description: 'Manage platform operations, users, and content',
      icon: Icons.admin_panel_settings_outlined,
    ),
  ];

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
    _waveController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_selectedRole == null) return;
    const routes = {
      'farmer': AppRoutes.farmerSignup,
      'doctor': AppRoutes.doctorSignup,
      'pharmacy': AppRoutes.pharmacySignup,
      'delivery': AppRoutes.deliverySignup,
      'researcher': AppRoutes.researcherSignup,
      'admin': AppRoutes.adminSignup,
    };
    context.go(routes[_selectedRole] ?? AppRoutes.farmerSignup);
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
                      _StepIndicator(current: 2, total: 3, label: 'Choose Your Role'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select your role',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Choose how you will use Featherflow. This determines your dashboard and available features.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ..._roles.map((role) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _RoleCard(
                              option: role,
                              selected: _selectedRole == role.id,
                              onTap: () =>
                                  setState(() => _selectedRole = role.id),
                            ),
                          )),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _selectedRole != null ? _onNext : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade400,
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
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => context.go(AppRoutes.signup),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_back,
                                    color: AppColors.secondary, size: 15),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Back to Basic Info',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _RoleOption {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const _RoleOption({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });
}

class _RoleCard extends StatelessWidget {
  final _RoleOption option;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.secondary.withValues(alpha: 0.07)
              : const Color(0xFFF7F7F7),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected ? AppColors.secondary : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected ? AppColors.secondary : Colors.grey.shade200,
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                option.icon,
                color: selected ? Colors.white : Colors.grey.shade500,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.description,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.secondary : Colors.grey.shade300,
                  width: 2,
                ),
                color: selected ? AppColors.secondary : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 13)
                  : null,
            ),
          ],
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
