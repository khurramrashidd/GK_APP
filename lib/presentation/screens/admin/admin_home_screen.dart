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
import 'admin_user_stats_screen.dart';
import 'admin_tabs_screen.dart';
import 'admin_reset_stats_screen.dart';
import 'admin_publish_update_screen.dart';
import 'admin_export_screen.dart';
import 'admin_bulk_upload_screen.dart';
import 'admin_suggestions_screen.dart';
import 'admin_error_logs_screen.dart';
import 'admin_answer_fix_screen.dart';
import 'admin_recycle_bin_screen.dart';
import 'admin_structure_upload_screen.dart';

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
            icon: Icons.account_tree_rounded,
            title: 'Create structure from JSON',
            subtitle: 'Build domains, subjects and topics in bulk',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminStructureUploadScreen())),
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
            icon: Icons.system_update_rounded,
            title: 'Publish app update',
            subtitle: 'Notify users of a new APK (GitHub Releases)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminPublishUpdateScreen())),
          ),
          _tile(
            context,
            icon: Icons.menu_rounded,
            title: 'Sidebar menu',
            subtitle: 'Show or hide menu items for users',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminTabsScreen())),
          ),
          _tile(
            context,
            icon: Icons.insights_rounded,
            title: 'User statistics',
            subtitle: 'Totals, gender split, state breakdown',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminUserStatsScreen())),
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
            icon: Icons.shuffle_rounded,
            title: 'Fix answer positions',
            subtitle: 'Stop the correct answer always being option A',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminAnswerFixScreen())),
          ),
          _tile(
            context,
            icon: Icons.manage_search_rounded,
            title: 'Rebuild username index',
            subtitle: 'Makes older usernames findable by name search',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                  const SnackBar(content: Text('Rebuilding...')));
              try {
                final n = await ref
                    .read(firestoreServiceProvider)
                    .rebuildUsernameIndex();
                messenger.showSnackBar(
                    SnackBar(content: Text('Indexed $n username(s).')));
              } catch (e) {
                messenger
                    .showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
          ),
          _tile(
            context,
            icon: Icons.restart_alt_rounded,
            title: 'Reset all stats',
            subtitle: 'Wipe scores, streaks and history — start a fresh season',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminResetStatsScreen())),
          ),
          _tile(
            context,
            icon: Icons.restore_from_trash_rounded,
            title: 'Recycle bin',
            subtitle: 'Restore deleted domains, subjects and topics',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminRecycleBinScreen())),
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
          // Global switch: makes Reels the landing experience for everyone.
          // Users can always reach Reels from their drawer regardless.
          Builder(builder: (_) {
            final on = ref.watch(reelsDefaultProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.video_library_rounded),
              value: on,
              title: const Text('Reels mode for everyone'),
              subtitle: Text(on
                  ? 'All users land in Reels by default'
                  : 'Users can still open Reels from the menu'),
              onChanged: (v) => ref
                  .read(firestoreServiceProvider)
                  .setAppSetting('reelsModeDefault', v),
            );
          }),
          Builder(builder: (_) {
            final on = ref.watch(adsEnabledProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.campaign_rounded),
              value: on,
              title: const Text('Advertising enabled'),
              subtitle: Text(on
                  ? 'Ads shown to non-premium users'
                  : 'No ads. (No ad SDK is bundled yet — this is the '
                      'remote switch for when one is.)'),
              onChanged: (v) => ref
                  .read(firestoreServiceProvider)
                  .setAppSetting('adsEnabled', v),
            );
          }),
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
