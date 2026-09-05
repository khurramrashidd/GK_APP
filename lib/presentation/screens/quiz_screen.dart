import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/quiz_provider.dart';
import '../widgets/google_search_button.dart';
import '../widgets/report_issue_button.dart';
import '../widgets/bookmark_button.dart';
import 'result_screen.dart';

/// The quiz. Answers are stored per-question and can be changed via
/// Previous/Next navigation until the user finishes. Score (with optional
/// negative marking) is computed at the end, not per-tap.
class QuizScreen extends ConsumerWidget {
  final String domainName;
  final String subjectName;
  final String? subLevelName;

  const QuizScreen({
    super.key,
    required this.domainName,
    required this.subjectName,
    this.subLevelName,
  });

  String get _title => subLevelName ?? subjectName;

  Future<bool> _confirmQuit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave quiz?'),
        content: const Text('Your progress in this quiz will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    return ok ?? false;
  }

  static const _skipEncouragements = [
    "No worries — a wrong guess teaches you more than a skip!",
    "Skipped! Next time take the shot, mistakes are how you learn.",
    "That's okay. Try guessing next time — you might surprise yourself.",
    "Moving on! Don't fear wrong answers, they're part of getting better.",
    "Skipped. Remember: every expert was once a beginner who guessed wrong.",
  ];

  /// Skips the current question. It simply stays unanswered (scored as
  /// skipped, never as wrong) and we advance — or finish if it was the last.
  void _skip(BuildContext context, WidgetRef ref, bool isLast) {
    // NOTE: _skipEncouragements is const, so it can't be shuffled in place —
    // pick an index instead.
    final msg = _skipEncouragements[
        DateTime.now().microsecondsSinceEpoch % _skipEncouragements.length];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
    if (isLast) {
      _finish(context, ref);
    } else {
      ref.read(quizProvider.notifier).next();
    }
  }

  void _finish(BuildContext context, WidgetRef ref) {
    ref.read(quizProvider.notifier).finish();
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ResultScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quiz = ref.watch(quizProvider);
    final theme = Theme.of(context);

    if (quiz.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (quiz.error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text('Could not start this quiz.\n\n${quiz.error}',
                  textAlign: TextAlign.center)),
        ),
      );
    }
    if (quiz.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(
            child: Text('No questions available for this subject yet.')),
      );
    }

    final q = quiz.current!;
    final selected = quiz.selectedForCurrent;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmQuit(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            // Skip: move on without answering. Deliberately encouraging —
            // hesitating to guess is the main reason people stall on a
            // question, so the message nudges them to try next time.
            if (!quiz.isCurrentRevealed)
              TextButton(
                onPressed: () => _skip(context, ref, quiz.isLast),
                child: const Text('Skip'),
              ),
            BookmarkButton(question: q),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: LinearProgressIndicator(
              value: (quiz.currentQuestionIndex + 1) / quiz.questions.length,
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Question ${quiz.currentQuestionIndex + 1} of ${quiz.questions.length}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const Spacer(),
                    if (quiz.negativeMarking)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('Negative marking'),
                        labelStyle: theme.textTheme.labelSmall,
                        backgroundColor: theme.colorScheme.errorContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(q.question,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      for (var i = 0; i < q.options.length; i++)
                        _option(context, ref, i, q.options[i], selected,
                            quiz.isCurrentRevealed, q.correctOptionIndex),
                      const SizedBox(height: 12),

                      // Show-answer button (only before reveal, and only once
                      // an option is chosen). Revealing locks the answer.
                      if (!quiz.isCurrentRevealed)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: const Text('Show answer'),
                            onPressed: selected == -1
                                ? null
                                : () => ref
                                    .read(quizProvider.notifier)
                                    .revealCurrent(),
                          ),
                        ),
                      if (!quiz.isCurrentRevealed && selected == -1)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 2),
                          child: Text('Pick an option first to reveal the answer.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                        ),

                      // Inline reveal: correct/wrong verdict + explanation.
                      if (quiz.isCurrentRevealed)
                        _revealPanel(context, q, selected),

                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: [
                          GoogleSearchButton(query: q.question, compact: true),
                          ReportIssueButton(question: q, compact: true),
                          // Share this question — the native sheet includes
                          // WhatsApp (and anything else installed).
                          TextButton.icon(
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text('Share'),
                            onPressed: () {
                              final opts = [
                                for (var i = 0; i < q.options.length; i++)
                                  '${String.fromCharCode(65 + i)}. ${q.options[i]}'
                              ].join('\n');
                              SharePlus.instance.share(ShareParams(
                                text: 'Can you answer this?\n\n'
                                    '${q.question}\n\n$opts\n\n'
                                    'Play more on GK Quiz Hero!',
                              ));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (!quiz.isFirst)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52)),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                      onPressed: () =>
                          ref.read(quizProvider.notifier).previous(),
                    ),
                  ),
                if (!quiz.isFirst) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    icon: Icon(quiz.isLast
                        ? Icons.flag_rounded
                        : Icons.chevron_right_rounded),
                    label: Text(quiz.isLast ? 'Finish' : 'Next'),
                    onPressed: () {
                      if (quiz.isLast) {
                        _finish(context, ref);
                      } else {
                        ref.read(quizProvider.notifier).next();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, WidgetRef ref, int index, String text,
      int selected, bool revealed, int correctIndex) {
    final theme = Theme.of(context);
    final isSelected = selected == index;
    final isCorrect = index == correctIndex;

    // Colors only apply after reveal.
    Color? bg;
    Color iconColor = isSelected ? theme.colorScheme.primary : theme.hintColor;
    IconData icon = isSelected
        ? Icons.radio_button_checked_rounded
        : Icons.radio_button_unchecked_rounded;

    if (revealed) {
      if (isCorrect) {
        bg = Colors.green.withOpacity(0.15);
        iconColor = Colors.green;
        icon = Icons.check_circle_rounded;
      } else if (isSelected) {
        bg = Colors.red.withOpacity(0.15);
        iconColor = Colors.red;
        icon = Icons.cancel_rounded;
      }
    } else if (isSelected) {
      bg = theme.colorScheme.primaryContainer;
    }

    return Card(
      color: bg,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(text),
        // Locked once revealed.
        onTap: revealed
            ? null
            : () => ref.read(quizProvider.notifier).selectOption(index),
      ),
    );
  }

  Widget _revealPanel(BuildContext context, question, int selected) {
    final theme = Theme.of(context);
    final correct = selected == question.correctOptionIndex;
    return Card(
      color: (correct ? Colors.green : Colors.red).withOpacity(0.10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    correct
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: correct ? Colors.green : Colors.red,
                    size: 20),
                const SizedBox(width: 6),
                Text(correct ? 'Correct!' : 'Not quite',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: correct ? Colors.green : Colors.red)),
              ],
            ),
            if (!correct) ...[
              const SizedBox(height: 6),
              Text(
                'Correct answer: ${question.options[question.correctOptionIndex]}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if ((question.explanation as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Explanation',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(question.explanation),
            ],
          ],
        ),
      ),
    );
  }
}
