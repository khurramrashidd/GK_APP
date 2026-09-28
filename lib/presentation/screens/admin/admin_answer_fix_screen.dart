import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';

/// Admin > Fix answer positions.
///
/// Shows how many questions currently have the correct answer at each option
/// position, and lets you reshuffle every question in one action.
///
/// This exists because question sets are almost always authored with the
/// correct answer written first. If ~100% of answers sit at option A, a user
/// can score full marks by always tapping the first option without reading —
/// which makes the whole question bank worthless for learning. New uploads
/// are shuffled automatically; this repairs everything already stored.
class AdminAnswerFixScreen extends ConsumerStatefulWidget {
  const AdminAnswerFixScreen({super.key});

  @override
  ConsumerState<AdminAnswerFixScreen> createState() =>
      _AdminAnswerFixScreenState();
}

class _AdminAnswerFixScreenState extends ConsumerState<AdminAnswerFixScreen> {
  Map<int, int>? _stats;
  int? _remaining; // questions still sitting at option A
  bool _busy = false;
  String? _result;

  /// How many to rewrite per run. Kept well under the Spark tier's 20k
  /// writes/day so several runs are possible in one day alongside normal use.
  int _batchSize = 500;
  static const _batchOptions = [100, 250, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      final s = await fs.answerPositionStats();
      final left = await fs.countAnswersAtFirstPosition();
      if (mounted) {
        setState(() {
          _stats = s;
          _remaining = left;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _result = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firestore quota errors are common on the free tier and the raw message
  /// is unhelpful — translate it into something actionable.
  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('RESOURCE_EXHAUSTED') ||
        text.contains('resource-exhausted') ||
        text.contains('Quota exceeded')) {
      return 'Firebase daily quota reached.\n\n'
          'The free (Spark) plan allows roughly 50,000 reads and 20,000 '
          'writes per day, and it resets at midnight Pacific Time. Try again '
          'after the reset, or use a smaller batch size.';
    }
    return 'Failed: $text';
  }

  Future<void> _runFix() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reshuffle $_batchSize questions?'),
        content: Text(
          'This rewrites the option order of up to $_batchSize questions so '
          'the correct answer lands in a random position.\n\n'
          'It changes only the ORDER of options and the stored answer index — '
          'no question text, explanation or tag is touched, and nothing is '
          'deleted.\n\n'
          'Uses up to $_batchSize writes against your Firebase daily quota '
          '(free plan allows ~20,000/day). Run it again as many times as you '
          'need — each run continues where the last left off.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reshuffle')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final n = await ref
          .read(firestoreServiceProvider)
          .shuffleAllQuestionAnswers(limit: _batchSize);
      if (mounted) {
        setState(() => _result = n == 0
            ? 'Nothing left to reshuffle in this batch.'
            : 'Reshuffled $n question(s). Run again to continue.');
      }
      await _loadStats();
    } catch (e) {
      if (mounted) setState(() => _result = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _stats;
    final total = stats?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    // "Healthy" means no single position holds a dominant share of answers.
    final worst = (stats == null || stats.isEmpty || total == 0)
        ? 0.0
        : stats.values.reduce((a, b) => a > b ? a : b) / total;

    return Scaffold(
      appBar: AppBar(title: const Text('Answer positions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Card(
            color: worst > 0.5
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(worst > 0.5
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        worst > 0.5
                            ? 'Answers are predictable'
                            : 'Answer spread looks healthy',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(worst > 0.5
                      ? '${(worst * 100).toStringAsFixed(1)}% of answers sit in '
                          'the same position. Users can score highly by always '
                          'picking that option without reading the question.'
                      : 'No single option position dominates.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Current distribution (sample)',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            'Based on a sample of up to 300 questions, to keep read usage low.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 8),
          if (stats == null)
            const Text('Loading...')
          else if (stats.isEmpty)
            const Text('No questions found.')
          else
            ...(stats.keys.toList()..sort()).map((k) {
              final n = stats[k]!;
              final pct = total == 0 ? 0.0 : n / total;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 70,
                        child: Text('Option ${String.fromCharCode(65 + k)}')),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 14,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 92,
                        child: Text('$n  (${(pct * 100).toStringAsFixed(1)}%)',
                            style: theme.textTheme.bodySmall)),
                  ],
                ),
              );
            }),
          const SizedBox(height: 20),
          if (_remaining != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.pending_actions_rounded),
                title: Text('$_remaining still at option A'),
                subtitle: const Text(
                    'Keep running batches until this reaches roughly a '
                    'quarter of your total (even spread across 4 options).'),
              ),
            ),
          const SizedBox(height: 12),
          Text('Batch size',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            'Firebase free plan allows ~20,000 writes per day. Pick a size, '
            'run it, and repeat — each run continues where the last stopped.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final n in _batchOptions)
                ChoiceChip(
                  label: Text('$n'),
                  selected: _batchSize == n,
                  onSelected:
                      _busy ? null : (_) => setState(() => _batchSize = n),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.shuffle_rounded),
            label: Text('Reshuffle $_batchSize questions'),
            onPressed: _busy ? null : _runFix,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh stats'),
            onPressed: _busy ? null : _loadStats,
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!,
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 16),
          Text(
            'New uploads are shuffled automatically, so this only needs '
            'running for questions uploaded before that change.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
