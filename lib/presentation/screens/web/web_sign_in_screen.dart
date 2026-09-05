import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';
import '../../../core/constants/app_constants.dart';

/// Sign-in for the web build. Anyone can sign in — WebAppRoot decides what
/// they see next (admin panel vs. the download page) based on whether their
/// email is in the admin allowlist. There's no separate "web account type";
/// it's the exact same users/{uid} profile system as mobile.
class WebSignInScreen extends ConsumerStatefulWidget {
  const WebSignInScreen({super.key});

  @override
  ConsumerState<WebSignInScreen> createState() => _WebSignInScreenState();
}

class _WebSignInScreenState extends ConsumerState<WebSignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _afterSignIn() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    await ref.read(profileProvider.notifier).loadForUser(user);
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = await ref.read(authServiceProvider).signInWithGoogle();
      if (cred != null) await _afterSignIn();
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithEmail() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Enter both email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .loginWithEmail(_emailCtrl.text.trim(), _passwordCtrl.text);
      await _afterSignIn();
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.quiz_rounded, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(AppConstants.appName,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Sign in to continue',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
                const SizedBox(height: 32),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                  label: const Text('Sign in with Google'),
                  onPressed: _busy ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 20),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('or')),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _signInWithEmail(),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  onPressed: _busy ? null : _signInWithEmail,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
