import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import 'home_screen.dart';
import 'terms_gate.dart';
import 'login_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Small delay so the splash is visible and Firebase is fully ready.
    await Future.delayed(const Duration(milliseconds: 400));

    final auth = ref.read(authServiceProvider);
    final user = auth.currentUser;

    if (user != null) {
      // Ensure a profile doc exists / is loaded before entering.
      try {
        await ref.read(profileProvider.notifier).loadForUser(user);
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => user != null ? const TermsGate(child: HomeScreen()) : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: theme.colorScheme.primaryContainer,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_rounded,
                size: 100, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text('GK QUIZ HERO',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onPrimaryContainer,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 8),
            Text('Getting things ready...',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                )),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
