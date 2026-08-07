import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF01291E);
  static const Color primaryContainer = Color(0xFF023D2D);
  static const Color secondary = Color(0xFF1DB584);
  static const Color secondaryContainer = Color(0xFF00896A);
  static const Color background = Color(0xFF010E0A);
  static const Color surface = Color(0xFF021F16);
  static const Color surfaceContainerHighest = Color(0xFF032A1E);
  static const Color error = Color(0xFFFF5C6A);
  static const Color errorContainer = Color(0xFF8B0000);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFB2DFDB);
  static const Color onSecondary = Color(0xFF000000);
  static const Color onSecondaryContainer = Color(0xFFE0F2EE);
  static const Color onBackground = Color(0xFFE0F2EE);
  static const Color onSurface = Color(0xFFE0F2EE);
  static const Color onSurfaceVariant = Color(0xFFA8C5BC);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFFFFCDD2);
  static const Color outline = Color(0xFF2A5C47);
  static const Color outlineVariant = Color(0xFF1A3D2E);
  static const Color divider = Color(0xFF1A4030);
  static const Color shadow = Color(0xFF000000);
  static const Color scrim = Color(0x80000000);
  static const Color hint = Color(0xFF6A9A86);
  static const Color disabled = Color(0xFF3A6A55);
  static const Color disabledText = Color(0x61E0F2EE);
}

class AppSpacing {
  AppSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
}

class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double full = 999.0;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlAll = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.primaryContainer,
          onPrimaryContainer: AppColors.onPrimaryContainer,
          secondary: AppColors.secondary,
          onSecondary: AppColors.onSecondary,
          secondaryContainer: AppColors.secondaryContainer,
          onSecondaryContainer: AppColors.onSecondaryContainer,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          surfaceContainerHighest: AppColors.surfaceContainerHighest,
          onSurfaceVariant: AppColors.onSurfaceVariant,
          error: AppColors.error,
          onError: AppColors.onError,
          errorContainer: AppColors.errorContainer,
          onErrorContainer: AppColors.onErrorContainer,
          outline: AppColors.outline,
          outlineVariant: AppColors.outlineVariant,
          shadow: AppColors.shadow,
          scrim: AppColors.scrim,
          inverseSurface: AppColors.onSurface,
          onInverseSurface: AppColors.surface,
          inversePrimary: AppColors.secondary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        dividerColor: AppColors.divider,
        textTheme: _textTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        textButtonTheme: _textButtonTheme,
        inputDecorationTheme: _inputDecorationTheme,
        cardTheme: _cardTheme,
        dialogTheme: _dialogTheme,
        bottomSheetTheme: _bottomSheetTheme,
        snackBarTheme: _snackBarTheme,
        tooltipTheme: _tooltipTheme,
        popupMenuTheme: _popupMenuTheme,
      );

  static const TextTheme _textTheme = TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: AppColors.onBackground,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
      color: AppColors.onBackground,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: AppColors.onBackground,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: AppColors.onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      color: AppColors.onSurface,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      color: AppColors.onSurface,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      color: AppColors.onBackground,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      color: AppColors.onBackground,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      color: AppColors.hint,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.25,
      color: AppColors.onSurface,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.0,
      color: AppColors.onSurface,
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w400,
      letterSpacing: 1.5,
      color: AppColors.hint,
    ),
  );

  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.secondary,
      foregroundColor: AppColors.onSecondary,
      disabledBackgroundColor: AppColors.disabled,
      disabledForegroundColor: AppColors.disabledText,
      elevation: 0,
      shadowColor: Colors.transparent,
      overlayColor: AppColors.onPrimary.withValues(alpha: .12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.25,
      ),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.secondary,
      disabledForegroundColor: AppColors.disabled,
      overlayColor: AppColors.secondary.withValues(alpha: .12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      side: const BorderSide(color: AppColors.secondary, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.25,
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.secondary,
      disabledForegroundColor: AppColors.disabled,
      overlayColor: AppColors.secondary.withValues(alpha: .1),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.smAll,
      ),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.25,
      ),
    ),
  );

  static const InputDecorationTheme _inputDecorationTheme =
      InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: TextStyle(
      color: AppColors.hint,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    labelStyle: TextStyle(
      color: AppColors.hint,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    floatingLabelStyle: TextStyle(
      color: AppColors.secondary,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    errorStyle: TextStyle(
      color: AppColors.error,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    ),
    border: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.outline, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.outline, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.error, width: 1),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.error, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: AppRadius.mdAll,
      borderSide: BorderSide(color: AppColors.disabled, width: 1),
    ),
  );

  static const CardThemeData _cardTheme = CardThemeData(
    color: AppColors.surface,
    shadowColor: AppColors.shadow,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.lgAll,
      side: BorderSide(color: AppColors.outline, width: 1),
    ),
    margin: EdgeInsets.all(AppSpacing.xs),
  );

  static const DialogThemeData _dialogTheme = DialogThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 24,
    shadowColor: AppColors.shadow,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.xlAll,
      side: BorderSide(color: AppColors.outline, width: 1),
    ),
    titleTextStyle: TextStyle(
      color: AppColors.onSurface,
      fontSize: 19,
      fontWeight: FontWeight.w700,
    ),
    contentTextStyle: TextStyle(
      color: AppColors.onSurfaceVariant,
      fontSize: 13,
      height: 1.4,
    ),
  );

  static const BottomSheetThemeData _bottomSheetTheme = BottomSheetThemeData(
    backgroundColor: AppColors.surface,
    modalBackgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 20,
    modalElevation: 24,
    showDragHandle: true,
    dragHandleColor: AppColors.outline,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      side: BorderSide(color: AppColors.outline),
    ),
  );

  static const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    backgroundColor: AppColors.primaryContainer,
    contentTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    actionTextColor: AppColors.secondary,
    behavior: SnackBarBehavior.floating,
    elevation: 10,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
  );

  static const TooltipThemeData _tooltipTheme = TooltipThemeData(
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: AppRadius.smAll,
      border: Border.fromBorderSide(BorderSide(color: AppColors.outline)),
    ),
    textStyle: TextStyle(color: Colors.white, fontSize: 12),
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    waitDuration: Duration(milliseconds: 350),
  );

  static const PopupMenuThemeData _popupMenuTheme = PopupMenuThemeData(
    color: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 14,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.mdAll,
      side: BorderSide(color: AppColors.outline),
    ),
    textStyle: TextStyle(color: AppColors.onSurface, fontSize: 13),
  );
}
