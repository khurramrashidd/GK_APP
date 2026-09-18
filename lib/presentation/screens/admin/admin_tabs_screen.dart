import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';

/// Admin > Sidebar menu. Turn individual drawer entries on or off for
/// everyone.
///
/// Admins always keep every entry regardless of these switches — hiding the
/// admin panel or the leaderboard from yourself would be unrecoverable from
/// inside the app, so the switches only ever affect regular users.
class AdminTabsScreen extends ConsumerWidget {
  const AdminTabsScreen({super.key});

  Future<void> _toggle(
      WidgetRef ref, Map<String, bool> current, String key, bool visible) async {
    // Persist the HIDDEN list rather than the visible one: that way any new
    // feature added later defaults to visible without needing a migration.
    final hidden = <String>[
      for (final e in current.entries)
        if (!(e.key == key ? visible : e.value)) e.key
    ];
    await ref.read(firestoreServiceProvider).setAppSetting('hiddenTabs', hidden);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visibility = ref.watch(tabVisibilityProvider);
    final hiddenCount = visibility.values.where((v) => !v).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Sidebar menu')),
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.secondaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hiddenCount == 0
                      ? 'All menu items are visible to users'
                      : '$hiddenCount item${hiddenCount == 1 ? '' : 's'} hidden from users',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                    'These switches affect regular users only. You will keep '
                    'seeing every item, including the Leaderboard and the '
                    'Admin Panel.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in kHideableTabs.entries)
            SwitchListTile(
              value: visibility[entry.key] ?? true,
              title: Text(entry.value),
              subtitle: Text((visibility[entry.key] ?? true)
                  ? 'Visible to users'
                  : 'Hidden from users'),
              onChanged: (v) => _toggle(ref, visibility, entry.key, v),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Home, Profile, Terms and About are always shown — an app with '
              'no way to reach its own terms or profile would be broken.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
