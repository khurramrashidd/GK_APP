import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/web/web_app_root.dart';
import 'presentation/screens/error_fallback_screen.dart';
import 'services/error_reporter.dart';

void main() async {
  // Global error capture, in three layers, all funnelling into ErrorReporter
  // (which is best-effort and never throws):
  //   * FlutterError.onError    — framework errors (build, layout, paint)
  //   * PlatformDispatcher      — async errors that bypass FlutterError
  //   * runZonedGuarded         — anything genuinely uncaught
  //
  // IMPORTANT: ensureInitialized() and runApp() must be in the SAME zone.
  // Initializing bindings outside runZonedGuarded and calling runApp inside
  // it triggers Flutter's "Zone mismatch" warning, because zone-specific
  // behaviour would then depend on which zone happened to be active.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      ErrorReporter.report(details.exception, details.stack,
          context: details.context?.toString());
      // Keep the familiar red-screen detail while developing; in release the
      // ErrorWidget.builder below shows users something friendlier instead.
      if (!kReleaseMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorReporter.report(error, stack, context: 'PlatformDispatcher');
      return true; // handled — don't take down the isolate
    };

    // Replaces Flutter's red error screen. Display only — the error was
    // already logged by FlutterError.onError above.
    ErrorWidget.builder = (FlutterErrorDetails details) =>
        ErrorFallbackScreen(details: details.exceptionAsString());

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const ProviderScope(child: MyApp()));
  }, (error, stack) {
    ErrorReporter.report(error, stack, context: 'runZonedGuarded');
  });
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'GK Quiz Hero',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Web is admin-console + download-page only (see WebAppRoot) — it
      // never reaches the mobile quiz-playing flow, so it never touches
      // Isar, which doesn't support web at all.
      home: kIsWeb ? const WebAppRoot() : const SplashScreen(),
    );
  }
}
