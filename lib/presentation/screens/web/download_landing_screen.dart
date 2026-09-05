import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';

/// What a signed-in-but-non-admin visitor sees on the web build. There's no
/// quiz-playing here on purpose — play happens in the app. This is a plain
/// "go get the app" page.
class DownloadLandingScreen extends ConsumerWidget {
  const DownloadLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.appName),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            onPressed: () => ref.read(profileProvider.notifier).signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.quiz_rounded, size: 88, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  'Practice general knowledge for SSC, UPSC, and other '
                  'competitive exams — offline-friendly, with AI explanations '
                  'and live 1v1 quiz battles.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(280, 56),
                    textStyle:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.shop_rounded),
                  label: const Text('Get it on Google Play'),
                  onPressed: () => launchUrl(Uri.parse(AppConstants.playStoreUrl),
                      mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 40),
                Text(
                  'Playing quizzes and 1v1 battles happens in the app — this '
                  'website is for the team managing the question bank.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
