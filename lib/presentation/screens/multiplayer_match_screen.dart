import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/multiplayer_provider.dart';
import 'multiplayer_result_screen.dart';

/// The live match itself. Answers write straight to Firestore as they're
/// picked (so the opponent's progress chip updates in real time), lock
/// immediately, and auto-advance — no back navigation, no reveal, no
/// negative marking. It's a race, kept simple on purpose.
class MultiplayerMatchScreen extends ConsumerStatefulWidget {
  final String matchId;
  final int playerSlot;
  const MultiplayerMatchScreen(
      {super.key, required this.matchId, required this.playerSlot});

  @override
  ConsumerState<MultiplayerMatchScreen> createState() =>
      _MultiplayerMatchScreenState();
}

class _MultiplayerMatchScreenState extends ConsumerState<MultiplayerMatchScreen> {
  bool _loaded = false;
  bool _navigatedToResult = false;
  bool _answering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchAsync = ref.watch(matchStreamProvider(widget.matchId));
    final gameArgs = (matchId: widget.matchId, slot: widget.playerSlot);
    final game = ref.watch(multiplayerGameProvider(gameArgs));

    return matchAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (match) {
        if (match == null) {
          return const Scaffold(
              body: Center(child: Text('Match no longer exists.')));
        }

        if (!_loaded) {
          _loaded = true;
          Future.microtask(() => ref
              .read(multiplayerGameProvider(gameArgs).notifier)
              .load(match.questionIds));
        }

        final myFinished =
            widget.playerSlot == 1 ? match.player1Finished : match.player2Finished;
        if (myFinished && !_navigatedToResult) {
          _navigatedToResult = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => MultiplayerResultScreen(
                  matchId: widget.matchId, playerSlot: widget.playerSlot),
            ));
          });
        }

        if (game.isLoading || game.questions.isEmpty) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final q = game.current;
        if (q == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final myProgress = game.answeredCount;
        final oppAnswers =
            widget.playerSlot == 1 ? match.player2Answers : match.player1Answers;
        final oppProgress = oppAnswers.length;
        final oppName = (widget.playerSlot == 1
            ? match.player2Name
            : match.player1Name) ?? 'Opponent';
        final total = game.questions.length;
        final selected = game.myAnswers[q.id];

        return PopScope(
          canPop: false,
          child: Scaffold(
            appBar:
                AppBar(title: const Text('Quiz Battle'), automaticallyImplyLeading: false),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _progressChip(theme, 'You', myProgress, total, true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _progressChip(
                                theme, oppName, oppProgress, total, false)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Question ${game.currentIndex + 1} of $total',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(height: 8),
                    Text(q.question,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = 0; i < q.options.length; i++)
                            _option(context, gameArgs, i, q.options[i], selected,
                                game),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _progressChip(
      ThemeData theme, String name, int done, int total, bool isMe) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text('$done/$total',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, ({String matchId, int slot}) args,
      int index, String text, int? selected, MultiplayerGameState game) {
    final theme = Theme.of(context);
    final isSelected = selected == index;
    // Locked the instant any option is picked for this question — no
    // changing your mind, no double-fires while the auto-advance is pending.
    final locked = selected != null || _answering;
    return Card(
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(
          isSelected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: isSelected ? theme.colorScheme.primary : theme.hintColor,
        ),
        title: Text(text),
        onTap: locked
            ? null
            : () async {
                setState(() => _answering = true);
                final notifier =
                    ref.read(multiplayerGameProvider(args).notifier);
                await notifier.answer(index);
                await Future.delayed(const Duration(milliseconds: 300));
                if (!mounted) return;
                if (game.isLast) {
                  await notifier.finish();
                } else {
                  notifier.next();
                }
                if (mounted) setState(() => _answering = false);
              },
      ),
    );
  }
}
