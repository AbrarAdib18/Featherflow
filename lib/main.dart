import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n/app_localizations.dart';
import 'core/l10n/language_notifier.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme.dart';

void main() {
  runApp(const FeatherflowApp());
}

class FeatherflowApp extends StatelessWidget {
  const FeatherflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageNotifier.instance,
      builder: (_, __) => MaterialApp.router(
        title: 'Featherflow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: appRouter,
        locale: LanguageNotifier.instance.locale,
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
