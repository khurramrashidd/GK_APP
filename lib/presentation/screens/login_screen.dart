import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import 'home_screen.dart';
import 'terms_gate.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _afterAuth(User user) async {
    final profile = await ref.read(profileProvider.notifier).loadForUser(user);
    if (!mounted) return;
    if (!profile.profileComplete) {
      _snack('Welcome! Please add your name and state in your profile.');
    }
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const TermsGate(child: HomeScreen())));
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      final cred = await ref.read(authServiceProvider).signInWithGoogle();
      if (cred?.user != null) {
        await _afterAuth(cred!.user!);
      } else {
        _snack('Google sign-in cancelled.');
      }
    } catch (e) {
      _snack('Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _snack('Enter email and password.');
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await ref
          .read(authServiceProvider)
          .loginWithEmail(_emailCtrl.text, _passCtrl.text);
      if (cred.user != null) await _afterAuth(cred.user!);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Login failed.');
    } catch (e) {
      _snack('Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailRegister() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.length < 6) {
      _snack('Enter email and a password of at least 6 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await ref.read(authServiceProvider).registerWithEmail(
          _emailCtrl.text, _passCtrl.text, _nameCtrl.text);
      if (cred.user != null) await _afterAuth(cred.user!);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Registration failed.');
    } catch (e) {
      _snack('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_emailCtrl.text.trim().isEmpty) {
      _snack('Enter your email first, then tap Forgot password.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_emailCtrl.text);
      _snack('Password reset email sent.');
    } catch (e) {
      _snack('Could not send reset email: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(Icons.quiz_rounded, size: 90, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('GK Quiz Hero',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Sign in to start quizzing',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 24),
              if (_loading) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                icon: const Icon(Icons.account_circle),
                label: const Text('Continue with Google'),
                onPressed: _loading ? null : _google,
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child:
                        Text('or', style: TextStyle(color: theme.hintColor))),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              TabBar(controller: _tabs, tabs: const [
                Tab(text: 'Login'),
                Tab(text: 'Register'),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: TabBarView(
                  controller: _tabs,
                  children: [_loginTab(), _registerTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emailField() => TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
            labelText: 'Email', border: OutlineInputBorder()),
      );

  Widget _passField() => TextField(
        controller: _passCtrl,
        obscureText: true,
        decoration: const InputDecoration(
            labelText: 'Password', border: OutlineInputBorder()),
      );

  Widget _loginTab() {
    return Column(
      children: [
        _emailField(),
        const SizedBox(height: 12),
        _passField(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: _loading ? null : _reset,
              child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 4),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50)),
          onPressed: _loading ? null : _emailLogin,
          child: const Text('Login'),
        ),
      ],
    );
  }

  Widget _registerTab() {
    return Column(
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        _emailField(),
        const SizedBox(height: 12),
        _passField(),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50)),
          onPressed: _loading ? null : _emailRegister,
          child: const Text('Create account'),
        ),
      ],
    );
  }
}
