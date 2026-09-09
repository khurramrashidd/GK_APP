import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';

/// Admin > Users. Lists every registered user and lets an admin grant or
/// revoke ordinary admin rights.
///
/// Guard rails:
///  * Super admins (AppConstants.superAdminEmails) are shown but can never be
///    demoted from here — that's what stops admins locking each other out.
///  * Only a super admin sees the grant/revoke control at all.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';
  bool _busy = false;

  bool _isSuper(UserProfile u) => AppConstants.superAdminEmails
      .map((e) => e.toLowerCase())
      .contains(u.email.toLowerCase());

  Future<void> _toggleAdmin(UserProfile u) async {
    final granting = !u.isAdminUser;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(granting ? 'Grant admin rights?' : 'Revoke admin rights?'),
        content: Text(granting
            ? '${u.email} will be able to add, edit and delete questions, '
                'manage domains and subjects, and handle reports.'
            : '${u.email} will lose all admin access immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(granting ? 'Grant' : 'Revoke')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).setUserAdmin(u.uid, granting);
      ref.invalidate(allUsersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usersAsync = ref.watch(allUsersProvider);
    final amSuper = ref.read(profileProvider.notifier).isSuperAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          if (!amSuper)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Only a super admin can grant or revoke admin rights.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (users) {
                final filtered = _query.isEmpty
                    ? users
                    : users
                        .where((u) =>
                            u.email.toLowerCase().contains(_query) ||
                            u.name.toLowerCase().contains(_query) ||
                            u.displayName.toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final u = filtered[i];
                    final isSuper = _isSuper(u);
                    final label = u.name.isNotEmpty ? u.name : u.displayName;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSuper
                            ? Colors.amber.shade100
                            : (u.isAdminUser
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest),
                        child: Icon(
                            isSuper
                                ? Icons.shield_rounded
                                : (u.isAdminUser
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.person_rounded),
                            size: 20),
                      ),
                      title: Text(label.isEmpty ? u.email : label),
                      subtitle: Text(u.email,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: isSuper
                          ? const Chip(
                              label: Text('SUPER',
                                  style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact)
                          : (amSuper
                              ? Switch(
                                  value: u.isAdminUser,
                                  onChanged:
                                      _busy ? null : (_) => _toggleAdmin(u),
                                )
                              : (u.isAdminUser
                                  ? const Chip(
                                      label: Text('ADMIN',
                                          style: TextStyle(fontSize: 10)),
                                      visualDensity: VisualDensity.compact)
                                  : null)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
