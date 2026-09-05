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
  // Two layers of global error capture:
  //  * FlutterError.onError — framework-detected errors (widget build,
  //    layout, painting). We still forward to the default handler in debug
  //    so you see the usual red-screen detail on your own machine; in
  //    release, ErrorWidget.builder below replaces that red screen with the
  //    friendly one users actually see.
  //  * runZonedGuarded — anything that would otherwise be a genuinely
  //    uncaught async exception, escaping try/catch entirely.
  // Both funnel into ErrorReporter, which is best-effort and never throws.
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorReporter.report(details.exception, details.stack,
        context: details.context?.toString());
    if (!kReleaseMode) {
      FlutterError.presentError(details);
    }
  };

  // Belt-and-braces for platform/async errors that don't go through
  // FlutterError at all (e.g. inside a Future with no catchError).
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.report(error, stack, context: 'PlatformDispatcher');
    return true; // handled — don't crash the isolate
  };

  // Friendly fallback UI for widget-build-time errors, instead of Flutter's
  // red error screen. This only controls what's DISPLAYED — the error is
  // already logged via FlutterError.onError above.
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      ErrorFallbackScreen(details: details.exceptionAsString());

  runZonedGuarded(() async {
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
