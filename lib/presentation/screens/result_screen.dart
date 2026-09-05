import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/quiz_provider.dart';
import '../providers/auth_provider.dart';
import '../../data/models/quiz_result.dart';
import 'review_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _scoreSaved = false;

  @override
  void initState() {
    super.initState();
    // Save the score exactly once (initState, not build, to avoid double counts).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_scoreSaved) return;
      _scoreSaved = true;
      final quiz = ref.read(quizProvider);
      if (quiz.questions.isEmpty) return;
      final result = QuizResult(
        id: '',
        domainName: quiz.questions.first.domainName,
        subjectName: quiz.questions.first.subjectName,
        subLevelName: quiz.questions.first.subLevelName,
        total: quiz.questions.length,
        correct: quiz.correctCount,
        wrong: quiz.wrongCount,
        skipped: quiz.skippedCount,
        score: quiz.score,
        negativeMarking: quiz.negativeMarking,
      );
      try {
        await ref
            .read(profileProvider.notifier)
            .recordQuizCompletion(result, quiz.pointsEarned);
      } catch (_) {
        // Offline: nothing persisted this time.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quiz = ref.watch(quizProvider);
    final theme = Theme.of(context);
    final total = quiz.questions.length;
    final correct = quiz.correctCount;
    final pct = total == 0 ? 0 : ((correct / total) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Summary'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Icon(Icons.emoji_events_rounded,
                size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Quiz Completed!',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$correct correct out of $total  ($pct%)',
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),

            // Score card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Text('Score', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      quiz.score == quiz.score.roundToDouble()
                          ? quiz.score.toStringAsFixed(0)
                          : quiz.score.toStringAsFixed(2),
                      style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary),
                    ),
                    Text('+${quiz.pointsEarned} points added to your total',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Breakdown row
            Row(
              children: [
                _stat(theme, 'Correct', quiz.correctCount, Colors.green),
                _stat(theme, 'Wrong', quiz.wrongCount, Colors.red),
                _stat(theme, 'Skipped', quiz.skippedCount, theme.hintColor),
              ],
            ),
            if (quiz.negativeMarking) ...[
              const SizedBox(height: 8),
              Text('Negative marking was on (${Scoring.negativePerWrong.toStringAsFixed(2)} per wrong).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ],
            const SizedBox(height: 28),

            ElevatedButton.icon(
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('See all answers & explanations'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.tertiaryContainer,
                foregroundColor: theme.colorScheme.onTertiaryContainer,
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: total == 0
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ReviewScreen())),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, int value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text('$value',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
