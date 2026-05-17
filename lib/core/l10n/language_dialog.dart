import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'language_notifier.dart';

void showLanguageDialog(BuildContext context, {bool dismissible = true}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (_, __, ___) =>
        _LanguageDialogPage(dismissible: dismissible),
  );
}

class _LanguageDialogPage extends StatefulWidget {
  final bool dismissible;
  const _LanguageDialogPage({required this.dismissible});

  @override
  State<_LanguageDialogPage> createState() => _LanguageDialogPageState();
}

class _LanguageDialogPageState extends State<_LanguageDialogPage> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = LanguageNotifier.instance.locale.languageCode;
  }

  void _apply() {
    LanguageNotifier.instance.setLocale(Locale(_selected));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isBn = _selected == 'bn';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── blurred backdrop ───────────────────────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: Colors.black.withValues(alpha: 0.48),
            ),
          ),
          // ── dialog card ────────────────────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.xlAll,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 40,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // icon
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.language,
                        color: AppColors.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // bilingual title
                    const Text(
                      'Select Language',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'ভাষা নির্বাচন করুন',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Choose your preferred language\nপছন্দের ভাষা বেছে নিন',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black38,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // language options
                    Row(
                      children: [
                        Expanded(
                          child: _LanguageOption(
                            emoji: '🇺🇸',
                            label: 'English',
                            sublabel: 'English',
                            code: 'en',
                            selected: _selected == 'en',
                            onTap: () => setState(() => _selected = 'en'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _LanguageOption(
                            emoji: '🇧🇩',
                            label: 'বাংলা',
                            sublabel: 'Bengali',
                            code: 'bn',
                            selected: _selected == 'bn',
                            onTap: () => setState(() => _selected = 'bn'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // continue button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _apply,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.mdAll),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(isBn ? 'চালিয়ে যান' : 'Continue'),
                      ),
                    ),
                    if (widget.dismissible) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          isBn ? 'বাতিল করুন' : 'Cancel',
                          style: const TextStyle(
                            color: Colors.black38,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String emoji;
  final String label;
  final String sublabel;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.emoji,
    required this.label,
    required this.sublabel,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.05)
              : const Color(0xFFF8FAFB),
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: selected ? AppColors.secondary : const Color(0xFFE0E0E0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.secondary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
