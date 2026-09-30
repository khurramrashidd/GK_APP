import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'multiplayer_setup_screen.dart';
import 'multiplayer_match_screen.dart';
import '../providers/multiplayer_provider.dart';
import '../../data/models/match_model.dart';
import '../providers/database_provider.dart';
import '../providers/auth_provider.dart';

/// Shown once you've finished your side. Shows a spinner until your opponent
/// also finishes (the match stream tells us the moment they do), then the
/// final score comparison.
class MultiplayerResultScreen extends ConsumerStatefulWidget {
  final String matchId;
  final int playerSlot;
  const MultiplayerResultScreen(
      {super.key, required this.matchId, required this.playerSlot});

  @override
  ConsumerState<MultiplayerResultScreen> createState() =>
      _MultiplayerResultScreenState();
}

class _MultiplayerResultScreenState
    extends ConsumerState<MultiplayerResultScreen> {
  bool _busy = false;

  String get matchId => widget.matchId;
  int get playerSlot => widget.playerSlot;

  /// Rotating encouragement. Losing messages are written to keep someone
  /// playing rather than to console them — a flat "You Lost" is the moment
  /// people quit.
  static const _winMessages = [
    'Sharp work — your knowledge showed up today.',
    'Well played! That was a convincing win.',
    'Champion form. Keep that streak rolling.',
    'You out-thought them. Nicely done.',
  ];
  static const _loseMessages = [
    'So close — every match makes the next one easier.',
    'Good fight! Review the answers and take the rematch.',
    'They edged it this time. You learn more from these.',
    'Not your round — but the comeback is the best part.',
  ];
  static const _tieMessages = [
    'Perfectly matched — go again to settle it!',
    'Dead even. Rematch decides everything.',
    'Neck and neck. Impressive from both of you.',
  ];

  static String _pick(List<String> pool, int seed) => pool[seed % pool.length];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Ask the opponent to keep going with more questions.
  Future<void> _propose(int count) async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).proposeMatchExtension(
            matchId: matchId,
            byUid: profile.uid,
            byName: profile.name.isNotEmpty
                ? profile.name
                : profile.displayName,
            count: count,
          );
      _snack('Asked your opponent for $count more questions...');
    } catch (e) {
      _snack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Accept: pull fresh questions for the match's subject and hand them to
  /// the transactional accept, which puts both players back into play.
  Future<void> _accept(MatchModel match) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(questionRepositoryProvider);
      final pool = await repo.getSubjectQuestionsOnDemand(
          match.domainId, match.subjectId,
          subLevelId: match.subLevelId);

      final unused = pool
          .where((q) => !match.questionIds.contains(q.id))
          .toList()
        ..shuffle();

      if (unused.isEmpty) {
        _snack('No unused questions left in this subject.');
        await ref.read(firestoreServiceProvider).clearMatchExtension(matchId);
        return;
      }

      final take = unused.take(match.extendCount ?? 5).map((q) => q.id).toList();
      await ref.read(firestoreServiceProvider).acceptMatchExtension(
            matchId: matchId,
            newQuestionIds: take,
          );
      // The match stream flips to 'active' and the listener below sends both
      // players back into the match screen.
    } catch (e) {
      _snack('Could not extend: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    try {
      await ref.read(firestoreServiceProvider).clearMatchExtension(matchId);
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchAsync = ref.watch(matchStreamProvider(matchId));

    // When the match goes back to 'active' (an extension was accepted), both
    // players are returned to the match screen automatically.
    ref.listen(matchStreamProvider(matchId), (prev, next) {
      final m = next.valueOrNull;
      if (m != null && m.isActive && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => MultiplayerMatchScreen(
              matchId: matchId, playerSlot: playerSlot),
        ));
      }
    });

    return Scaffold(
      appBar:
          AppBar(title: const Text('Battle Result'), automaticallyImplyLeading: false),
      body: matchAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (match) {
          if (match == null) {
            return const Center(child: Text('Match no longer exists.'));
          }
          if (!match.bothFinished) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Waiting for your opponent to finish...',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }

          final myScore = playerSlot == 1 ? match.player1Score : match.player2Score;
          final oppScore = playerSlot == 1 ? match.player2Score : match.player1Score;
          final oppName =
              (playerSlot == 1 ? match.player2Name : match.player1Name) ??
                  'Opponent';
          final won = myScore > oppScore;
          final tied = myScore == oppScore;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Icon(
                  tied
                      ? Icons.handshake_rounded
                      : (won
                          ? Icons.emoji_events_rounded
                          : Icons.sentiment_neutral_rounded),
                  size: 80,
                  color: tied
                      ? theme.colorScheme.secondary
                      : (won ? Colors.amber : theme.hintColor),
                ),
                const SizedBox(height: 16),
                Text(
                  tied
                      ? "It's a tie!"
                      : (won ? 'You Won! 🎉' : 'Good game!'),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    tied
                        ? _pick(_tieMessages, myScore + oppScore)
                        : (won
                            ? _pick(_winMessages, myScore + oppScore)
                            : _pick(_loseMessages, myScore + oppScore)),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _scoreCard(theme, 'You', myScore, true)),
                    const SizedBox(width: 12),
                    Expanded(child: _scoreCard(theme, oppName, oppScore, false)),
                  ],
                ),
                const SizedBox(height: 32),
                // --- Extend this match ---
                if (match.waitingOnMe(
                    ref.read(profileProvider)?.uid ?? ''))
                  Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Text(
                            '${match.extendProposedByName ?? 'Your opponent'} '
                            'wants to keep going with '
                            '${match.extendCount ?? 5} more questions!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    theme.colorScheme.onTertiaryContainer),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy ? null : _decline,
                                  child: const Text('No thanks'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FilledButton(
                                  onPressed:
                                      _busy ? null : () => _accept(match),
                                  child: const Text('Continue playing'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else if (match.hasExtendProposal)
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Expanded(
                            child: Text('Waiting for your opponent to '
                                'accept...')),
                      ]),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Add more questions'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final n = await showDialog<int>(
                              context: context,
                              builder: (ctx) => SimpleDialog(
                                title: const Text('How many more?'),
                                children: [
                                  for (final n in [5, 10, 15])
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(ctx, n),
                                      child: Text('$n more questions'),
                                    ),
                                ],
                              ),
                            );
                            if (n != null) await _propose(n);
                          },
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('New opponent'),
                  onPressed: () {
                    // Back to matchmaking rather than home — the moment right
                    // after a result is when someone most wants another go.
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MultiplayerSetupScreen()));
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48)),
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scoreCard(ThemeData theme, String name, int score, bool isMe) {
    return Card(
      color: isMe ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text('$score',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
