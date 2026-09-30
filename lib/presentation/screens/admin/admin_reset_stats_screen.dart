import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/features_provider.dart';
import '../../widgets/attempt_pie_chart.dart';
import '../../../services/attempt_stats_service.dart';

/// Admin > Reset all stats. Starts a fresh season.
///
/// Gated behind typing RESET, because this deletes every user's quiz history
/// permanently and there is no undo. A tap-to-confirm dialog is too easy to
/// dismiss by reflex for something this destructive.
class AdminResetStatsScreen extends ConsumerStatefulWidget {
  const AdminResetStatsScreen({super.key});

  @override
  ConsumerState<AdminResetStatsScreen> createState() =>
      _AdminResetStatsScreenState();
}

class _AdminResetStatsScreenState
    extends ConsumerState<AdminResetStatsScreen> {
  final _confirmCtrl = TextEditingController();
  final List<String> _log = [];
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _say(String m) {
    if (!mounted) return;
    setState(() => _log.add(m));
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _log.clear();
      _done = false;
    });
    try {
      final result = await ref
          .read(firestoreServiceProvider)
          .resetAllStats(onProgress: _say);

      _say('');
      _say('DONE');
      _say('  ${result.users} user(s) reset to zero');
      _say('  ${result.historyDeleted} history record(s) deleted');
      _say('  Leaderboard cleared');

      // The on-device breakdown is separate storage — clear it too, or the
      // admin's own pie chart would survive a reset that wiped everything
      // else.
      await AttemptStatsService().clear();
      ref.invalidate(attemptStatsProvider);

      // Refresh everything that reads these numbers.
      ref.invalidate(leaderboardProvider);
      ref.invalidate(historyProvider);
      await ref.read(profileProvider.notifier).refresh();

      if (mounted) {
        setState(() {
          _done = true;
          _confirmCtrl.clear();
        });
      }
    } catch (e) {
      _say('');
      _say('FAILED: $e');
      _say('Some users may already have been reset. Running it again is '
          'safe — resetting an already-zero user changes nothing.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final armed = _confirmCtrl.text.trim().toUpperCase() == 'RESET';

    return Scaffold(
      appBar: AppBar(title: const Text('Reset all stats')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Text('This cannot be undone',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onErrorContainer)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'For EVERY user, this sets to zero:\n'
                    '  • Total score\n'
                    '  • Questions answered and correct answers\n'
                    '  • Current streak and longest streak\n\n'
                    'And permanently DELETES:\n'
                    '  • Every past quiz record in their history\n'
                    '  • The whole leaderboard\n\n'
                    'Questions, domains, subjects, bookmarks, friends and '
                    'accounts are NOT touched.',
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _confirmCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Type RESET to enable the button',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: armed ? Colors.red : null,
            ),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset everything and start fresh'),
            onPressed: (!armed || _busy) ? null : _run,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_done) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.check_circle_rounded, color: Colors.green),
                title: Text('Fresh season started'),
                subtitle: Text(
                    'Everyone begins from zero. Scores rebuild as people play.'),
              ),
            ),
          ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_log.join('\n'),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
