import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import '../../data/models/question_model.dart';
import '../providers/database_provider.dart';
import '../providers/quiz_provider.dart';
import 'quiz_screen.dart';

/// The big "Play" entry point. Two modes:
///  * Random  — pull from everything in the app.
///  * Custom  — tick any mix of domains/subjects and pull only from those.
/// Then choose how many questions, and whether negative marking applies.
class CustomQuizScreen extends ConsumerStatefulWidget {
  const CustomQuizScreen({super.key});

  @override
  ConsumerState<CustomQuizScreen> createState() => _CustomQuizScreenState();
}

class _CustomQuizScreenState extends ConsumerState<CustomQuizScreen> {
  bool? _isRandom; // null = not chosen yet
  final Set<String> _pickedSubjects = {}; // "domainId|subjectId"
  int _count = 10;
  bool _negativeMarking = false;
  bool _busy = false;

  static const _countPresets = [5, 10, 20, 50, 100];
  static const _maxCount = 200;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _start(List<DomainModel> domains) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(questionRepositoryProvider);
      final pool = <QuestionModel>[];

      // Which (domain, subject) pairs to draw from.
      final targets = <(DomainModel, SubjectModel)>[];
      for (final d in domains.where((d) => d.isActive)) {
        for (final s in d.subjects.where((s) => s.isActive)) {
          final key = '${d.id}|${s.id}';
          if (_isRandom == true || _pickedSubjects.contains(key)) {
            targets.add((d, s));
          }
        }
      }

      if (targets.isEmpty) {
        _snack('Pick at least one subject.');
        return;
      }

      // Fetch each subject's questions on demand. For a big random quiz this
      // can be several reads, so cap how many subjects we pull from — we only
      // need enough to fill _count questions, and shuffling the target list
      // first keeps the selection varied.
      targets.shuffle();
      final maxSubjects = _isRandom == true ? 12 : targets.length;
      for (final (d, s) in targets.take(maxSubjects)) {
        try {
          final qs = s.isShared
              ? await repo.getSharedSubjectQuestions(s.id)
              : await repo.getSubjectQuestionsOnDemand(d.id, s.id);
          pool.addAll(qs);
        } catch (_) {
          // Skip a subject that fails rather than aborting the whole quiz.
        }
        if (pool.length >= _count * 3) break; // plenty to shuffle from
      }

      if (pool.isEmpty) {
        _snack('No questions found for that selection.');
        return;
      }

      // Deduplicate (a shared subject can appear under several domains).
      final unique = {for (final q in pool) q.id: q}.values.toList()..shuffle();
      final picked = unique.take(_count).toList();

      ref.read(quizProvider.notifier).startQuiz(
            '', '',
            preloaded: picked,
            negativeMarking: _negativeMarking,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => QuizScreen(
          domainName: _isRandom == true ? 'Random' : 'Custom',
          subjectName: '${picked.length} questions',
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domainsAsync = ref.watch(domainsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Play')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : domainsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (domains) => _body(theme, domains),
            ),
      // Pinned only once a mode is chosen — the mode screen has its own
      // full-width buttons and needs no bar.
      bottomNavigationBar: (_busy || _isRandom == null)
          ? null
          : domainsAsync.maybeWhen(
              data: (domains) => _startBar(domains),
              orElse: () => null,
            ),
    );
  }

  Widget _body(ThemeData theme, List<DomainModel> domains) {
    // Step 1 — mode.
    if (_isRandom == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_esports_rounded,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('How do you want to play?',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60)),
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Random — anything goes'),
              onPressed: () => setState(() => _isRandom = true),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 60)),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Customise — pick your subjects'),
              onPressed: () => setState(() => _isRandom = false),
            ),
          ],
        ),
      );
    }

    // Step 2 — selection (custom only) + count + marking.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isRandom == false) ...[
          Text('Pick subjects to mix',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text('You can combine any subjects from any domains.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 8),
          if (_pickedSubjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('${_pickedSubjects.length} selected',
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(_pickedSubjects.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ...domains.where((d) => d.isActive).map((d) {
            final subjects = d.subjects.where((s) => s.isActive).toList();
            if (subjects.isEmpty) return const SizedBox.shrink();
            return Card(
              child: ExpansionTile(
                title: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${subjects.length} subjects'),
                children: [
                  for (final s in subjects)
                    CheckboxListTile(
                      dense: true,
                      value: _pickedSubjects.contains('${d.id}|${s.id}'),
                      title: Text(s.name),
                      onChanged: (v) => setState(() {
                        final key = '${d.id}|${s.id}';
                        if (v == true) {
                          _pickedSubjects.add(key);
                        } else {
                          _pickedSubjects.remove(key);
                        }
                      }),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        Text('How many questions?',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // Stepper + slider so the count can be dialled in without typing —
        // presets for the common cases, fine control for anything else.
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove_rounded),
                      onPressed: _count <= 1
                          ? null
                          : () => setState(() => _count = (_count - 1).clamp(1, _maxCount)),
                    ),
                    Expanded(
                      child: Center(
                        child: Text('$_count',
                            style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary)),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _count >= _maxCount
                          ? null
                          : () => setState(() => _count = (_count + 1).clamp(1, _maxCount)),
                    ),
                  ],
                ),
                Slider(
                  value: _count.toDouble().clamp(1, _maxCount.toDouble()),
                  min: 1,
                  max: _maxCount.toDouble(),
                  divisions: _maxCount - 1,
                  label: '$_count',
                  onChanged: (v) => setState(() => _count = v.round()),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in _countPresets)
                      ChoiceChip(
                        label: Text('$n'),
                        selected: _count == n,
                        onSelected: (_) => setState(() => _count = n),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'If fewer questions exist than you pick, you get everything '
                  'available.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: SwitchListTile(
            value: _negativeMarking,
            onChanged: (v) => setState(() => _negativeMarking = v),
            title: const Text('Negative marking'),
            subtitle: Text(_negativeMarking
                ? 'UPSC style: +2 correct, -0.66 wrong'
                : 'Relaxed: +2 correct, 0 for wrong'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _isRandom = null;
            _pickedSubjects.clear();
          }),
          child: const Text('Back'),
        ),
        // Bottom padding so the last item isn't hidden behind the pinned
        // Start bar below.
        const SizedBox(height: 90),
      ],
    );
  }

  /// Start button pinned to the bottom of the screen so it's reachable
  /// without scrolling past a long subject list.
  Widget _startBar(List<DomainModel> domains) {
    final theme = Theme.of(context);
    final count = _isRandom == false ? _pickedSubjects.length : null;
    return Material(
      elevation: 12,
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    count == 0
                        ? 'Pick at least one subject'
                        : '$count subject${count == 1 ? '' : 's'} selected  •  '
                            '$_count questions',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Quiz',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: (_isRandom == false && _pickedSubjects.isEmpty)
                    ? null
                    : () => _start(domains),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
