import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n/app_localizations.dart';
import 'core/l10n/language_notifier.dart';
import 'core/network/auth_service.dart';
import 'core/network/realtime_toast.dart';
import 'core/network/user_updates_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep the "changes since" poller running whenever a session exists so admin
  // actions reflect on the affected user's side in near real-time.
  void syncPoller() {
    if (AuthService.instance.currentSession != null) {
      UserUpdatesService.instance.start();
    } else {
      UserUpdatesService.instance.stop();
    }
  }

  AuthService.instance.addListener(syncPoller);

  // Restore the stored session AND the saved language before the first frame.
  // On web a hard refresh of a deep link re-runs main(); the router's first
  // redirect must already see the restored session (or it bounces a
  // logged-in user to /login), and the language must be settled so we don't
  // repaint MaterialApp mid-navigation.
  await Future.wait([
    AuthService.instance.getStoredSession(),
    LanguageNotifier.instance.load(),
  ]);
  syncPoller();

  runApp(const FeatherflowApp());
}

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

class FeatherflowApp extends StatelessWidget {
  const FeatherflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageNotifier.instance,
      builder: (_, __) => MaterialApp.router(
        title: 'Featherflow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        scaffoldMessengerKey: _messengerKey,
        routerConfig: appRouter,
        builder: (context, child) => RealtimeToastHost(
          messengerKey: _messengerKey,
          child: child ?? const SizedBox.shrink(),
        ),
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
