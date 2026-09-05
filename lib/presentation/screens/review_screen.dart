import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/gemini_config.dart';
import '../../data/models/question_model.dart';
import '../providers/quiz_provider.dart';
import '../providers/database_provider.dart';
import '../widgets/google_search_button.dart';
import '../widgets/report_issue_button.dart';

/// Per-question deep review. Each card has its own "Explain with AI" button.
/// The explanation is fetched cache-first (local -> Firestore -> Gemini) and,
/// once generated, is saved to Firestore so no user ever regenerates it.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final Map<String, String> _explanations = {};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  Future<void> _explain(QuestionModel q) async {
    if (_loading.contains(q.id)) return;
    setState(() {
      _loading.add(q.id);
      _errors.remove(q.id);
    });
    try {
      final repo = ref.read(questionRepositoryProvider);
      final text = await repo.getOrCreateAiExplanation(q);
      if (!mounted) return;
      setState(() => _explanations[q.id] = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[q.id] = e.toString());
    } finally {
      if (mounted) setState(() => _loading.remove(q.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = ref.watch(quizProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Answers & Explanations')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: quiz.questions.length,
        itemBuilder: (context, i) {
          final q = quiz.questions[i];
          final picked = i < quiz.selectedAnswers.length
              ? quiz.selectedAnswers[i]
              : -1;
          final wasCorrect = picked == q.correctOptionIndex;

          final cached = _explanations[q.id] ??
              ((q.aiExplanation != null && q.aiExplanation!.trim().isNotEmpty)
                  ? q.aiExplanation
                  : null);
          final isLoading = _loading.contains(q.id);
          final error = _errors[q.id];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        wasCorrect
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: wasCorrect ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text('Question ${i + 1}',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(q.question,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (picked == -1)
                    _line('Your answer', 'Skipped', theme.hintColor),
                  if (picked >= 0 && picked < q.options.length && !wasCorrect)
                    _line('Your answer', q.options[picked], Colors.red),
                  if (q.correctOptionIndex >= 0 &&
                      q.correctOptionIndex < q.options.length)
                    _line('Correct answer',
                        q.options[q.correctOptionIndex], Colors.green),
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(q.explanation, style: theme.textTheme.bodyMedium),
                  ],
                  const Divider(height: 28),
                  if (cached != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.auto_awesome_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text('AI Explanation',
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 8),
                          Text(cached, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: [
                              GoogleSearchButton(
                                  query: q.question, compact: true),
                              ReportIssueButton(question: q, compact: true),
                            ],
                          ),
                        ],
                      ),
                    )
                  else if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Generating explanation...'),
                      ]),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(GeminiConfig.isConfigured
                              ? 'Explain with AI'
                              : 'AI not configured'),
                          onPressed: GeminiConfig.isConfigured
                              ? () => _explain(q)
                              : null,
                        ),
                        GoogleSearchButton(query: q.question, compact: true),
                        ReportIssueButton(question: q, compact: true),
                      ],
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Could not generate: $error',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                    TextButton(
                        onPressed: () => _explain(q),
                        child: const Text('Retry')),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _line(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
