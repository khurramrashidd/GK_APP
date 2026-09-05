import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/database_provider.dart';
import '../../../data/services/taxonomy_seeder.dart';
import '../../../core/constants/default_taxonomy.dart';
import '../login_screen.dart';
import 'admin_domains_screen.dart';
import 'admin_upload_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_users_screen.dart';
import 'admin_export_screen.dart';
import 'admin_bulk_upload_screen.dart';
import 'admin_suggestions_screen.dart';
import 'admin_error_logs_screen.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(profileProvider);
    final isAdmin = ref.read(profileProvider.notifier).isAdmin;
    final theme = Theme.of(context);
    final openReports = ref.watch(adminReportsProvider).valueOrNull
            ?.where((r) => r.isOpen)
            .length ??
        0;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('You do not have admin access.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(profileProvider.notifier).signOut();
              if (!context.mounted) return;
              // On web, AdminHomeScreen IS the app root (see WebAppRoot) —
              // it watches profileProvider and rebuilds to the sign-in
              // screen on its own, no navigation needed. On mobile this
              // screen is PUSHED on top of Home, so the stack needs an
              // explicit reset back to LoginScreen, same as the sign-out
              // button in Profile.
              if (!kIsWeb) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Manage the question bank. For very large uploads (thousands of '
                'questions), use the Node script in tools/bulk_upload from your PC '
                'instead — it is far faster and safer than a phone.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          _tile(
            context,
            icon: Icons.folder_special_rounded,
            title: 'Domains & Subjects',
            subtitle: 'Create domains, add subjects',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminDomainsScreen())),
          ),
          _tile(
            context,
            icon: Icons.upload_file_rounded,
            title: 'Upload Questions',
            subtitle: 'Paste JSON and push to Firestore',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminUploadScreen())),
          ),
          _tile(
            context,
            icon: Icons.flag_rounded,
            title: 'Reports',
            subtitle: openReports > 0
                ? '$openReports open report${openReports == 1 ? '' : 's'}'
                : 'No open reports',
            badgeCount: openReports,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminReportsScreen())),
          ),
          _tile(
            context,
            icon: Icons.upload_file_rounded,
            title: 'Bulk upload (multi-subject)',
            subtitle: 'One JSON file, routed automatically by domain/subject',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminBulkUploadScreen())),
          ),
          _tile(
            context,
            icon: Icons.download_rounded,
            title: 'Export questions as JSON',
            subtitle: 'Download a domain or subject question bank',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminExportScreen())),
          ),
          _tile(
            context,
            icon: Icons.people_rounded,
            title: 'Users & admin rights',
            subtitle: 'View all users, grant or revoke admin access',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminUsersScreen())),
          ),
          _tile(
            context,
            icon: Icons.lightbulb_rounded,
            title: 'User suggestions',
            subtitle: 'Review requested categories and subjects',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminSuggestionsScreen())),
          ),
          _tile(
            context,
            icon: Icons.bug_report_rounded,
            title: 'Error logs',
            subtitle: 'Every crash or error reported from any device',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminErrorLogsScreen())),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _tile(
            context,
            icon: Icons.auto_awesome_motion_rounded,
            title: 'Seed default taxonomy',
            subtitle:
                '${DefaultTaxonomy.domainCount} domains, '
                '${DefaultTaxonomy.subjectCount} subjects — added hidden',
            onTap: () => _seedTaxonomy(context, ref),
          ),
        ],
      ),
    );
  }

  /// Creates the default taxonomy tree. Additive and idempotent — see
  /// TaxonomySeeder. Confirms first, since it writes a lot of documents.
  Future<void> _seedTaxonomy(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seed default taxonomy?'),
        content: Text(
          'This adds ${DefaultTaxonomy.domainCount} domains and about '
          '${DefaultTaxonomy.subjectCount} subjects covering GK, academics, '
          'entertainment, sports and exam topics.\n\n'
          'Everything is added HIDDEN, so users will not see empty categories '
          '— unhide each one from "Domains & Subjects" as you upload '
          'questions for it.\n\n'
          'Anything you already have is left completely untouched, and '
          'running this twice is harmless.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Seed')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Seeding taxonomy...')),
          ],
        ),
      ),
    );

    String message;
    try {
      final seeder = TaxonomySeeder(ref.read(firestoreServiceProvider));
      final result = await seeder.seed();
      message = result.summary;
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
    } catch (e) {
      message = 'Seeding failed: $e';
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close progress dialog
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      int badgeCount = 0}) {
    return Card(
      child: ListTile(
        leading: Badge(
          isLabelVisible: badgeCount > 0,
          label: Text('$badgeCount'),
          child: Icon(icon, size: 30),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
