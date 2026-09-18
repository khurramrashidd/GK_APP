import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/features_provider.dart';
import '../providers/quiz_provider.dart';
import '../widgets/refreshable.dart';
import '../../services/attempt_stats_service.dart';
import '../widgets/attempt_pie_chart.dart';

/// Three leaderboards in one swipeable pager: Score, Accuracy, Streak.
///
/// One Firestore stream feeds all three — the same rows are re-sorted
/// client-side — so adding boards costs no extra reads.
///
/// Accuracy has NO minimum attempt threshold by design; instead every row
/// shows how many questions that person attempted, so a 100% from 2 answers
/// is visibly different from a 91% from 4,000.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _boards = [
    (title: 'Top Scores', icon: Icons.emoji_events_rounded),
    (title: 'Best Accuracy', icon: Icons.track_changes_rounded),
    (title: 'Longest Streaks', icon: Icons.local_fire_department_rounded),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  static double _accuracy(Map<String, dynamic> r) {
    final a = (r['questionsAnswered'] as int?) ?? 0;
    if (a <= 0) return 0;
    return ((r['correctAnswers'] as int?) ?? 0) / a * 100;
  }

  List<Map<String, dynamic>> _sorted(
      List<Map<String, dynamic>> rows, int board) {
    final list = List<Map<String, dynamic>>.from(rows);
    switch (board) {
      case 1:
        list.sort((a, b) {
          final c = _accuracy(b).compareTo(_accuracy(a));
          // Tie-break on attempts so the more-tested person ranks higher.
          if (c != 0) return c;
          return ((b['questionsAnswered'] as int?) ?? 0)
              .compareTo((a['questionsAnswered'] as int?) ?? 0);
        });
        break;
      case 2:
        list.sort((a, b) => ((b['currentStreak'] as int?) ?? 0)
            .compareTo((a['currentStreak'] as int?) ?? 0));
        break;
      default:
        list.sort((a, b) => ((b['totalScore'] as int?) ?? 0)
            .compareTo((a['totalScore'] as int?) ?? 0));
    }
    return list;
  }

  String _metric(Map<String, dynamic> r, int board) {
    switch (board) {
      case 1:
        return '${_accuracy(r).toStringAsFixed(1)}%';
      case 2:
        final s = (r['currentStreak'] as int?) ?? 0;
        return '$s day${s == 1 ? '' : 's'}';
      default:
        return '${(r['totalScore'] as int?) ?? 0} pts';
    }
  }

  String _sub(Map<String, dynamic> r, int board) {
    final attempted = (r['questionsAnswered'] as int?) ?? 0;
    switch (board) {
      case 1:
        // Attempts shown alongside accuracy — the context that makes a
        // percentage meaningful without needing a minimum threshold.
        return '${(r['correctAnswers'] as int?) ?? 0} of $attempted correct';
      case 2:
        return '$attempted questions attempted';
      default:
        return '$attempted questions attempted';
    }
  }

  /// Explains each board's maths. Figures are taken from the real scoring
  /// constants, so this can't drift from what the app actually does.
  void _showHowCalculated() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        Widget section(IconData icon, String title, List<String> lines) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, size: 20, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(title,
                        style: t.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(left: 28, bottom: 3),
                      child: Text(l, style: t.textTheme.bodyMedium),
                    ),
                ],
              ),
            );

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('How the boards work',
                    style: t.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                section(Icons.emoji_events_rounded, 'Top Scores', [
                  '+${Scoring.pointsPerCorrectInt} points for every correct answer.',
                  'Skipped questions score nothing — they never count against you.',
                  'In UPSC mode, a wrong answer costs '
                      '${Scoring.negativePerWrong.abs()} points, and your quiz '
                      'score cannot go below zero.',
                  'Your total is the sum across every quiz you finish.',
                ]),
                section(Icons.track_changes_rounded, 'Best Accuracy', [
                  'Correct answers ÷ questions attempted, as a percentage.',
                  'Skipped questions are not counted as attempted.',
                  'There is no minimum — but every row shows how many '
                      'questions that person attempted, so a 100% from 2 '
                      'answers reads differently from 91% from 4,000.',
                  'Equal accuracy is broken by who attempted more.',
                ]),
                section(Icons.local_fire_department_rounded, 'Longest Streaks', [
                  'Consecutive days on which you finished at least one quiz.',
                  'Playing more than once in a day does not add to it.',
                  'Missing a full day resets it to zero.',
                ]),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Only your display name and these figures are public. '
                    'Your email, location and quiz history are never shown '
                    'on the leaderboard.',
                    style: t.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Lets a user wipe their own figures and start over.
  ///
  /// Touches only their own documents, so it needs no admin rights. Also
  /// clears the on-device question breakdown, otherwise the pie chart would
  /// keep showing history the user just asked to forget.
  Future<void> _resetMyStats() async {
    final me = ref.read(profileProvider);
    if (me == null) return;

    // Captured BEFORE the dialog: showDialog is itself an async gap, so
    // grabbing the messenger afterwards still touches a context that may no
    // longer be valid.
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset your stats?'),
        content: const Text(
          'This clears YOUR score, streaks, question counts and quiz '
          'history, and removes you from the leaderboard until you play '
          'again.\n\n'
          'Other players are not affected. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset mine'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(firestoreServiceProvider).resetMyStats(me.uid);
      await AttemptStatsService().clear();
      ref.invalidate(leaderboardProvider);
      ref.invalidate(historyProvider);
      ref.invalidate(attemptStatsProvider);
      await ref.read(profileProvider.notifier).refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Your stats have been reset.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(leaderboardProvider);
    final myUid = ref.watch(profileProvider)?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            tooltip: 'Reset my stats',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _resetMyStats,
          ),
          IconButton(
            tooltip: 'How is this calculated?',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _showHowCalculated,
          ),
          RefreshAction(onRefresh: () async => ref.invalidate(leaderboardProvider)),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load the leaderboard.\n\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
                child: Text('No scores yet. Finish a quiz to appear here.'));
          }
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: AttemptPieChart(title: null),
              ),
              _header(theme),
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _boards.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, board) =>
                      _board(theme, _sorted(rows, board), board, myUid),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Title + dots. Dots are tappable as well as swipeable — swiping alone
  /// isn't discoverable, and some people never try it.
  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_boards[_page].icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(_boards[_page].title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _boards.length; i++)
                GestureDetector(
                  onTap: () => _pageCtrl.animateToPage(i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _board(ThemeData theme, List<Map<String, dynamic>> rows, int board,
      String? myUid) {
    final myIndex = myUid == null
        ? -1
        : rows.indexWhere((r) => r['uid'] == myUid);
    // Pin my row only when I'm outside the visible top — otherwise it would
    // appear twice.
    final showPinned = myIndex >= 10;

    return Column(
      children: [
        Expanded(
          child: PullToRefresh(
            onRefresh: () async => ref.invalidate(leaderboardProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  _row(theme, rows[i], i, board, rows[i]['uid'] == myUid),
            ),
          ),
        ),
        if (showPinned)
          Material(
            elevation: 8,
            color: theme.colorScheme.primaryContainer,
            child: _row(theme, rows[myIndex], myIndex, board, true,
                pinned: true),
          ),
      ],
    );
  }

  Widget _row(ThemeData theme, Map<String, dynamic> r, int index, int board,
      bool isMe,
      {bool pinned = false}) {
    final rank = index + 1;
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };

    return Container(
      margin: pinned
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 3),
      decoration: pinned
          ? null
          : BoxDecoration(
              color: isMe
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 40,
          child: Center(
            child: medal != null
                ? Text(medal, style: const TextStyle(fontSize: 20))
                : Text('$rank',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.hintColor)),
          ),
        ),
        title: Text(
          isMe ? 'You' : (r['displayName'] as String? ?? 'Anonymous'),
          style: TextStyle(
              fontWeight: isMe ? FontWeight.bold : FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(_sub(r, board), style: theme.textTheme.bodySmall),
        trailing: Text(
          _metric(r, board),
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
