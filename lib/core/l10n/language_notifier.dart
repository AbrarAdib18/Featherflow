import 'package:flutter/material.dart';

class LanguageNotifier extends ChangeNotifier {
  LanguageNotifier._();
  static final LanguageNotifier instance = LanguageNotifier._();

  Locale _locale = const Locale('en');
  bool _hasShownInitialDialog = false;

  Locale get locale => _locale;
  bool get isBengali => _locale.languageCode == 'bn';
  bool get hasShownInitialDialog => _hasShownInitialDialog;

  void setLocale(Locale locale) {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    notifyListeners();
  }

  void markInitialDialogShown() {
    _hasShownInitialDialog = true;
  }
}
