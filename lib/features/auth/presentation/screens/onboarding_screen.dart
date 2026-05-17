import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  int _currentPage = 0;

  static const List<_OnboardingData> _slides = [
    _OnboardingData(
      icon: Icons.agriculture,
      title: 'Manage Your Farm',
      body: 'Track your flock, costs, and performance all in one place',
    ),
    _OnboardingData(
      icon: Icons.biotech,
      title: 'Detect Diseases Early',
      body:
          'Upload chicken images and get instant AI-powered disease detection',
    ),
    _OnboardingData(
      icon: Icons.medical_services,
      title: 'Connect With Vets',
      body:
          'Book online or offline consultations with certified poultry vets',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    _fadeController.reset();
    _fadeController.forward();
    setState(() => _currentPage = index);
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  void _goToLogin() => context.go(AppRoutes.login);

  @override
  Widget build(BuildContext context) {
    final bool isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.egg_alt,
                            color: AppColors.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Featherflow',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      AnimatedOpacity(
                        opacity: isLastPage ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: TextButton(
                          onPressed: isLastPage ? null : _goToLogin,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              color: AppColors.hint,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) => _OnboardingPage(
                      data: _slides[index],
                      fadeAnimation: _fadeAnimation,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _slides.length,
                          (index) =>
                              _DotIndicator(active: index == _currentPage),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLastPage ? _goToLogin : _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: AppColors.background,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.lgAll,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isLastPage ? 'Get Started' : 'Next',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                isLastPage
                                    ? Icons.rocket_launch_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingData data;
  final Animation<double> fadeAnimation;

  const _OnboardingPage({
    required this.data,
    required this.fadeAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: FadeTransition(
        opacity: fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.08),
                borderRadius: AppRadius.xxlAll,
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                data.icon,
                size: 120,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              data.title,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.25,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              data.body,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                height: 1.7,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final bool active;

  const _DotIndicator({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 28 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.secondary : const Color(0xFFD0D0D0),
        borderRadius: AppRadius.fullAll,
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

