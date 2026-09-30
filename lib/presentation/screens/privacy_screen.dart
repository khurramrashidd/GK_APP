import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';

/// Your data: export it, or delete the account.
///
/// Both are required by law in several places (India's DPDP Act, GDPR in
/// the EU/UK, CCPA in California) and by Play Store policy for any app with
/// accounts. Keeping them on one screen makes the rights easy to find,
/// which is itself part of what those rules ask for.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _busy = false;

  Future<void> _export() async {
    final me = ref.read(profileProvider);
    if (me == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data =
          await ref.read(firestoreServiceProvider).exportUserData(me.uid);
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await SharePlus.instance.share(ShareParams(
        text: pretty,
        subject: 'My GK Quiz Hero data',
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final me = ref.read(profileProvider);
    if (me == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account is disabled straight away and you are removed from '
          'the leaderboard.\n\n'
          'Everything is permanently deleted after 30 days: your profile, '
          'quiz history, bookmarks, friends and username.\n\n'
          'Changed your mind? Sign in again within 30 days and your account '
          'comes back exactly as it was.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep my account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(firestoreServiceProvider)
          .requestAccountDeletion(me.uid);
      await ref.read(profileProvider.notifier).signOut();
      messenger.showSnackBar(const SnackBar(
          content: Text('Account scheduled for deletion. Sign in within '
              '30 days to restore it.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion() async {
    final me = ref.read(profileProvider);
    if (me == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(firestoreServiceProvider).cancelAccountDeletion(me.uid);
      await ref.read(profileProvider.notifier).refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Your account is active again.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(profileProvider);
    final pending = me?.isPendingDeletion ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Your data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),

          if (pending)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Deletion scheduled',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onErrorContainer)),
                    const SizedBox(height: 6),
                    Text(
                      'Your account will be permanently deleted in '
                      '${me!.daysUntilPurge} day'
                      '${me.daysUntilPurge == 1 ? '' : 's'}.',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _busy ? null : _cancelDeletion,
                      child: const Text('Keep my account'),
                    ),
                  ],
                ),
              ),
            ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.download_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('Download your data',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'A copy of everything we hold about you — your profile, '
                    'quiz history, bookmarks and friends — as a JSON file '
                    'you can save or send anywhere.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 46)),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Export my data'),
                    onPressed: _busy ? null : _export,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (!pending)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.delete_forever_rounded,
                          color: theme.colorScheme.error),
                      const SizedBox(width: 10),
                      Text('Delete your account',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                      'Disabled immediately, permanently deleted after 30 '
                      'days. You can restore it by signing in during that '
                      'time.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 46),
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete my account'),
                      onPressed: _busy ? null : _requestDeletion,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
          Text(
            'Questions, domains and subjects are shared app content rather '
            'than your personal data, so they are not included in an export '
            'and are unaffected by deletion.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
