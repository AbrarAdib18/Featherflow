import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageNotifier extends ChangeNotifier {
  LanguageNotifier._();
  static final LanguageNotifier instance = LanguageNotifier._();

  static const _kLocale = 'pref_locale';
  static const _kShownDialog = 'pref_language_dialog_shown';

  Locale _locale = const Locale('en');
  bool _hasShownInitialDialog = false;

  Locale get locale => _locale;
  bool get isBengali => _locale.languageCode == 'bn';
  bool get hasShownInitialDialog => _hasShownInitialDialog;

  /// Restore the saved language + "already asked" flag. Call once from main()
  /// before runApp so a page refresh / app restart keeps the user's choice
  /// instead of resetting to English and re-prompting every time.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_kLocale);
      if (code != null && code.isNotEmpty) _locale = Locale(code);
      _hasShownInitialDialog = prefs.getBool(_kShownDialog) ?? false;
    } catch (_) {
      // storage unavailable (private mode, etc.) — fall back to defaults
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocale, _locale.languageCode);
      await prefs.setBool(_kShownDialog, _hasShownInitialDialog);
    } catch (_) {}
  }

  void setLocale(Locale locale) {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    _persist();
    notifyListeners();
  }

  void markInitialDialogShown() {
    _hasShownInitialDialog = true;
    _persist();
  }
}
