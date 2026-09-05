import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/multiplayer_provider.dart';

/// Shown once you've finished your side. Shows a spinner until your opponent
/// also finishes (the match stream tells us the moment they do), then the
/// final score comparison.
class MultiplayerResultScreen extends ConsumerWidget {
  final String matchId;
  final int playerSlot;
  const MultiplayerResultScreen(
      {super.key, required this.matchId, required this.playerSlot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final matchAsync = ref.watch(matchStreamProvider(matchId));

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
                  tied ? "It's a tie!" : (won ? 'You Won! 🎉' : 'You Lost'),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
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
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52)),
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
