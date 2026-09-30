import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../data/models/error_log_model.dart';

/// Best-effort crash/error reporting to Firestore.
///
/// Called from global handlers in main.dart (FlutterError.onError,
/// PlatformDispatcher.onError) which run OUTSIDE the widget tree, before any
/// Riverpod ProviderScope is necessarily available — so this talks to
/// Firebase directly rather than through FirestoreService/Riverpod, the same
/// way crash-reporting SDKs like Crashlytics work.
///
/// [report] must NEVER throw, and never awaits anything the caller depends
/// on — a failure to log an error must not cause a second error, and must
/// not delay the user seeing the "something went wrong" screen.
class ErrorReporter {
  static void report(
    Object error,
    StackTrace? stackTrace, {
    String? context,
  }) {
    // Always visible in a dev console, regardless of whether Firestore
    // logging succeeds.
    debugPrint('ErrorReporter: $error');
    if (stackTrace != null) debugPrint(stackTrace.toString());

    // Fire-and-forget: intentionally not awaited by callers.
    _tryLog(error, stackTrace, context);
  }

  static Future<void> _tryLog(
      Object error, StackTrace? stackTrace, String? context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final log = ErrorLogModel(
        id: '',
        message: error.toString(),
        stackTrace: stackTrace?.toString() ?? '(no stack trace)',
        userUid: user?.uid,
        userEmail: user?.email,
        platform: defaultTargetPlatform.name,
        appVersion: AppConstants.appVersion,
        context: context,
      );
      await FirebaseFirestore.instance
          .collection('error_logs')
          .add(log.toCreateMap());
    } catch (_) {
      // Logging itself failed (offline, not signed in yet, rules rejected
      // it, whatever) — swallow it. The user already sees the friendly
      // fallback screen; we must not throw a second error on top of it.
    }
  }
}
