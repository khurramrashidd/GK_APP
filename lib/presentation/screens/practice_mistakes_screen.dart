import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/question_model.dart';
import '../../services/attempt_stats_service.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/features_provider.dart';
import '../widgets/attempt_pie_chart.dart';

/// Replay the questions you got wrong.
///
/// Getting one right converts it from wrong to correct WITHOUT adding to
/// your total attempted — so accuracy improves by fixing a mistake rather
/// than by answering more questions. That is the whole point: the number
/// moves because you learned something, not because you ground out volume.
///
/// Self-limiting by design: a question leaves the wrong-pool as soon as you
/// answer it correctly, so it cannot be redeemed twice.
class PracticeMistakesScreen extends ConsumerStatefulWidget {
  const PracticeMistakesScreen({super.key});

  @override
  ConsumerState<PracticeMistakesScreen> createState() =>
      _PracticeMistakesScreenState();
}

class _PracticeMistakesScreenState
    extends ConsumerState<PracticeMistakesScreen> {
  List<QuestionModel> _questions = [];
  bool _loading = true;
  String? _error;

  int _index = 0;
  int? _picked;
  int _redeemed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final wrongIds = await AttemptStatsService().wrongQuestionIds();
      if (wrongIds.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Chunked: Firestore's whereIn is capped, and a user can easily have
      // more than ten wrong answers. Capped overall so this screen can't
      // turn into hundreds of reads for someone with a long history.
      final found = await ref
          .read(firestoreServiceProvider)
          .fetchQuestionsByIdsChunked(wrongIds.toList());

      if (mounted) {
        setState(() {
          _questions = found..shuffle();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pick(int i) async {
    if (_picked != null) return;
    final q = _questions[_index];
    final correct = i == q.correctOptionIndex;
    setState(() => _picked = i);

    if (correct) {
      // Flip the local record; this is what moves it out of the wrong slice.
      await AttemptStatsService()
          .recordQuiz({q.id: AttemptOutcome.correct});
      _redeemed++;
    }
  }

  Future<void> _next() async {
    if (_index >= _questions.length - 1) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
    });
  }

  Future<void> _finish() async {
    final me = ref.read(profileProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_redeemed > 0 && me != null) {
      try {
        await ref
            .read(firestoreServiceProvider)
            .redeemWrongAnswers(me.uid, _redeemed);
        await ref.read(profileProvider.notifier).refresh();
      } catch (_) {
        // Offline: the local chart is already corrected; the synced figure
        // simply won't move this time. Better than blocking the user.
      }
    }
    ref.invalidate(attemptStatsProvider);
    ref.invalidate(leaderboardProvider);

    messenger.showSnackBar(SnackBar(
      content: Text(_redeemed == 0
          ? 'No mistakes fixed this time — try again.'
          : 'Fixed $_redeemed mistake${_redeemed == 1 ? '' : 's'}. '
              'Your accuracy went up.'),
    ));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice your mistakes')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice your mistakes')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load your mistakes.\n\n$_error',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice your mistakes')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.celebration_rounded,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 14),
                Text('Nothing to fix',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'You have no wrong answers recorded on this device. '
                  'Play some quizzes and anything you get wrong will show '
                  'up here to practise.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = _questions[_index];
    final answered = _picked != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice your mistakes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            minHeight: 4,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${_index + 1} of ${_questions.length}   •   fixed $_redeemed',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('${q.domainName} • ${q.subjectName}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 16),
          Text(q.question,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, height: 1.4)),
          const SizedBox(height: 20),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _option(theme, i, q),
            ),
          if (answered && q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(q.explanation, style: theme.textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: 20),
          if (answered)
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              onPressed: _next,
              child: Text(_index >= _questions.length - 1 ? 'Finish' : 'Next'),
            ),
        ],
      ),
    );
  }

  Widget _option(ThemeData theme, int i, QuestionModel q) {
    Color? bg;
    Color? border;
    if (_picked != null) {
      if (i == q.correctOptionIndex) {
        bg = Colors.green.withValues(alpha: 0.15);
        border = Colors.green;
      } else if (i == _picked) {
        bg = theme.colorScheme.error.withValues(alpha: 0.12);
        border = theme.colorScheme.error;
      }
    }
    return InkWell(
      onTap: () => _pick(i),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg ?? theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: border ?? Colors.transparent,
              width: border == null ? 0 : 2),
        ),
        child: Text(q.options[i]),
      ),
    );
  }
}
