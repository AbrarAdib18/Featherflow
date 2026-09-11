import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // Brand — same greens the landing page / dashboards use.
  static const Color primary = Color(0xFF01291E); // deep forest green (text + app bars)
  static const Color primaryContainer = Color(0xFF023D2D);
  static const Color secondary = Color(0xFF1DB584); // brand green (accent / buttons)
  static const Color secondaryContainer = Color(0xFF00896A);

  // Surfaces — the app is light: white grounds, near-black text.
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainerHighest = Color(0xFFF0F7F4);
  static const Color error = Color(0xFFE5484D);
  static const Color errorContainer = Color(0xFFFDECEC);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFE0F2EE);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF00382B);
  static const Color onBackground = Color(0xFF1A1A1A);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color onSurfaceVariant = Color(0xFF5B6B65);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF7A0C0F);
  static const Color outline = Color(0xFFDEEAE5);
  static const Color outlineVariant = Color(0xFFEDF3F1);
  static const Color divider = Color(0xFFE8EEEC);
  static const Color shadow = Color(0x1A000000);
  static const Color scrim = Color(0x66000000);
  static const Color hint = Color(0xFF9AA6A2);
  static const Color disabled = Color(0xFFBFD4CC);
  static const Color disabledText = Color(0x61000000);

  // ── Navigation surfaces ─────────────────────────────────────────────
  // Every app bar, green tab bar, sidebar/drawer header, navigation rail
  // and green "nav card" in the app is painted with [navigationSurface]
  // (the deep-forest brand green). ANYTHING drawn directly on top of it —
  // text, icons, labels, badges, back/menu buttons, selected + unselected
  // + disabled states — must resolve to one of the tokens below. Never
  // dark green, black or near-black on green.
  //
  // These are the single source of truth; do not hand-pick `Colors.white`
  // / `Colors.white70` in nav code — reference the token so the contrast
  // guarantee is enforceable (see test/navigation_contrast_test.dart).
  static const Color navigationSurface = primary; // 0xFF01291E
  static const Color navigationForegroundColor = Color(0xFFFFFFFF);
  static const Color navigationIconColor = Color(0xFFFFFFFF);
  static const Color navigationSelectedColor = Color(0xFFFFFFFF);
  static const Color navigationUnselectedColor = Color(0xCCFFFFFF); // white @ 80%
  static const Color navigationHoverColor = Color(0x1FFFFFFF); // white @ 12%
  static const Color navigationDisabledColor = Color(0x8AFFFFFF); // white @ 54%
  // A clearly visible lighter-green highlight for the selected item.
  static const Color navigationIndicator = secondary; // 0xFF1DB584

  /// Every foreground token that is permitted on a green navigation
  /// surface. The contrast test walks the shared nav widgets and asserts
  /// every rendered text/icon colour is in (or derived from) this set.
  static const List<Color> navigationForegroundTokens = <Color>[
    navigationForegroundColor,
    navigationIconColor,
    navigationSelectedColor,
    navigationUnselectedColor,
    navigationHoverColor,
    navigationDisabledColor,
  ];
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

  /// Kept for the single call site in main.dart. The app is a **light** app —
  /// white grounds, deep-green text, brand-green accents (the landing page /
  /// dashboard scheme). Previously this returned a dark ColorScheme while every
  /// screen locally painted itself white, which left un-themed widgets
  /// (dropdown menus, popup menus, screens that forgot `backgroundColor`) with
  /// dark-green-on-dark-green text.
  static ThemeData get dark => light;

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
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
          inverseSurface: AppColors.primary,
          onInverseSurface: Colors.white,
          inversePrimary: AppColors.secondary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        dividerColor: AppColors.divider,
        // `canvasColor` is what an un-themed `DropdownButton` uses for its menu.
        canvasColor: Colors.white,
        textTheme: _textTheme,
        // Every app bar in the app is the brand green — enforce white
        // foreground globally so a screen that forgets `foregroundColor`
        // (or adds an un-coloured action icon) can never render dark-on-green.
        appBarTheme: _appBarTheme,
        // Every TabBar in the app sits on a green app bar / green container.
        tabBarTheme: _tabBarTheme,
        drawerTheme: _drawerTheme,
        navigationRailTheme: _navigationRailTheme,
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
        dropdownMenuTheme: _dropdownMenuTheme,
      );

  /// Brand-green app bar, white foreground — the landing-page / dashboard
  /// look. `foregroundColor` covers the title + leading/back + action icons
  /// and `iconTheme`/`actionsIconTheme` pin icon colour even when a caller
  /// wraps an icon in its own widget.
  static const AppBarTheme _appBarTheme = AppBarTheme(
    backgroundColor: AppColors.navigationSurface,
    foregroundColor: AppColors.navigationForegroundColor,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    iconTheme: IconThemeData(color: AppColors.navigationIconColor),
    actionsIconTheme: IconThemeData(color: AppColors.navigationIconColor),
    titleTextStyle: TextStyle(
      color: AppColors.navigationForegroundColor,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    toolbarTextStyle: TextStyle(
      color: AppColors.navigationForegroundColor,
      fontSize: 14,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  /// White label + near-white unselected + brand-green indicator — the
  /// only combination that is readable on the green app bars every TabBar
  /// in this app is attached to.
  static const TabBarThemeData _tabBarTheme = TabBarThemeData(
    labelColor: AppColors.navigationSelectedColor,
    unselectedLabelColor: AppColors.navigationUnselectedColor,
    indicatorColor: AppColors.navigationIndicator,
    dividerColor: Colors.transparent,
    labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    overlayColor: WidgetStatePropertyAll(AppColors.navigationHoverColor),
  );

  /// Drawers in the app wrap a light sidebar whose only green band is its
  /// header (which paints its own white text) — so the drawer body itself
  /// stays on the light surface.
  static const DrawerThemeData _drawerTheme = DrawerThemeData(
    backgroundColor: AppColors.surface,
    surfaceTintColor: Colors.transparent,
    scrimColor: AppColors.scrim,
    elevation: 1,
  );

  /// If a navigation rail is ever used it is a green rail — white icons /
  /// labels, lighter-green selected indicator.
  static const NavigationRailThemeData _navigationRailTheme =
      NavigationRailThemeData(
    backgroundColor: AppColors.navigationSurface,
    selectedIconTheme: IconThemeData(color: AppColors.navigationSelectedColor),
    unselectedIconTheme:
        IconThemeData(color: AppColors.navigationUnselectedColor),
    selectedLabelTextStyle: TextStyle(
      color: AppColors.navigationSelectedColor,
      fontWeight: FontWeight.w700,
    ),
    unselectedLabelTextStyle:
        TextStyle(color: AppColors.navigationUnselectedColor),
    indicatorColor: AppColors.navigationIndicator,
  );

  /// White surface, brand-green text — matches the landing page / dashboard.
  static final DropdownMenuThemeData _dropdownMenuTheme = DropdownMenuThemeData(
    textStyle: const TextStyle(
      color: AppColors.primary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF7F7F7),
      border: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: BorderSide(color: Color(0xFFE0E8E4)),
      ),
    ),
    menuStyle: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(6),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
    ),
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
    fillColor: Color(0xFFF7F7F7),
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
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.mdAll,
      side: BorderSide(color: Color(0xFFE0E8E4)),
    ),
    textStyle: TextStyle(color: AppColors.primary, fontSize: 13),
  );
}
