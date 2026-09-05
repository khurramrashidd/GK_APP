import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/features_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History & Stats')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No quizzes yet.\nFinish a quiz and it shows up here.',
                    textAlign: TextAlign.center),
              ),
            );
          }

          final totalQuizzes = history.length;
          final totalQ = history.fold<int>(0, (s, r) => s + r.total);
          final totalCorrect = history.fold<int>(0, (s, r) => s + r.correct);
          final overallAcc = totalQ == 0 ? 0.0 : totalCorrect / totalQ;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Summary cards
              Row(
                children: [
                  _statCard(theme, 'Quizzes', '$totalQuizzes',
                      Icons.quiz_rounded),
                  _statCard(theme, 'Accuracy',
                      '${(overallAcc * 100).round()}%', Icons.percent_rounded),
                  _statCard(theme, 'Answered', '$totalQ',
                      Icons.check_circle_outline_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Text('Recent quizzes', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...history.map((r) {
                final acc = (r.accuracy * 100).round();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _accColor(r.accuracy).withOpacity(0.15),
                      child: Text('$acc%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _accColor(r.accuracy))),
                    ),
                    title: Text(
                      '${r.subjectName}'
                      '${r.subLevelName != null ? ' • ${r.subLevelName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${r.correct}/${r.total} correct'
                      '${r.negativeMarking ? ' • negative marking' : ''}'
                      '${r.takenAt != null ? ' • ${r.takenAt!.day}/${r.takenAt!.month}/${r.takenAt!.year}' : ''}',
                    ),
                    trailing: Text(
                      r.score == r.score.roundToDouble()
                          ? r.score.toStringAsFixed(0)
                          : r.score.toStringAsFixed(1),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Color _accColor(double acc) {
    if (acc >= 0.7) return Colors.green;
    if (acc >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(label,
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
