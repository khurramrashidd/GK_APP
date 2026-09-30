import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';
import '../admin/admin_home_screen.dart';
import 'web_sign_in_screen.dart';
import 'download_landing_screen.dart';

/// The entire web experience, in one router: this is the ONLY entry point
/// reachable on Flutter Web (see main.dart, which shows this instead of the
/// mobile SplashScreen when kIsWeb). Nothing else — no quiz-playing, no
/// consumer home screen — is reachable from here, which is what keeps the
/// web build from ever touching Isar (which doesn't support web at all).
///
///   not signed in        -> WebSignInScreen
///   signed in, is admin   -> AdminHomeScreen (same screen mobile admins use)
///   signed in, not admin  -> DownloadLandingScreen ("get the app" page)
class WebAppRoot extends ConsumerStatefulWidget {
  const WebAppRoot({super.key});

  @override
  ConsumerState<WebAppRoot> createState() => _WebAppRootState();
}

class _WebAppRootState extends ConsumerState<WebAppRoot> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user != null) {
      await ref.read(profileProvider.notifier).loadForUser(user);
    }
    if (mounted) setState(() => _checked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = ref.watch(profileProvider);
    if (profile == null) {
      return const WebSignInScreen();
    }

    final isAdmin = ref.read(profileProvider.notifier).isAdmin;
    return isAdmin ? const AdminHomeScreen() : const DownloadLandingScreen();
  }
}
