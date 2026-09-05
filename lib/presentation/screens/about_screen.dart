import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import 'terms_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Icon(Icons.quiz_rounded,
                    size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(AppConstants.appName,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Version ${AppConstants.appVersion}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.business_rounded),
                  title: const Text('Company'),
                  subtitle: const Text(AppConstants.companyName),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_rounded),
                  title: const Text('Contact'),
                  subtitle: const Text(AppConstants.companyEmail),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(
                      Uri.parse('mailto:${AppConstants.companyEmail}')),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_rounded),
                  title: const Text('Terms & Conditions'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TermsScreen(readOnly: true))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text('© ${DateTime.now().year} ${AppConstants.companyName}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ),
        ],
      ),
    );
  }
}
