import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/quiz_provider.dart';
import 'quiz_screen.dart';

/// Sits between picking a subject/sub-level and the quiz itself. Lets the user
/// choose negative marking before starting.
class QuizStartScreen extends ConsumerStatefulWidget {
  final String domainId;
  final String domainName;
  final String subjectId;
  final String subjectName;
  final String? subLevelId;
  final String? subLevelName;

  /// True when this subject is marked shared: questions come from one pool
  /// spanning every domain that uses this subject id.
  final bool isShared;

  const QuizStartScreen({
    super.key,
    required this.domainId,
    required this.domainName,
    required this.subjectId,
    required this.subjectName,
    this.subLevelId,
    this.subLevelName,
    this.isShared = false,
  });

  @override
  ConsumerState<QuizStartScreen> createState() => _QuizStartScreenState();
}

class _QuizStartScreenState extends ConsumerState<QuizStartScreen> {
  bool _negativeMarking = false;

  String get _title => widget.subLevelName ?? widget.subjectName;

  void _start() {
    ref.read(quizProvider.notifier).startQuiz(
          widget.domainId,
          widget.subjectId,
          subLevelId: widget.subLevelId,
          negativeMarking: _negativeMarking,
          isShared: widget.isShared,
        );
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => QuizScreen(
        domainName: widget.domainName,
        subjectName: widget.subjectName,
        subLevelName: widget.subLevelName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Icon(Icons.quiz_rounded, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Ready to start?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              '${widget.domainName} • $_title',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 28),

            // Scoring summary card
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rule(Icons.check_circle_rounded, Colors.green,
                        '+${Scoring.pointsPerCorrect.toStringAsFixed(0)} for each correct answer'),
                    const SizedBox(height: 8),
                    _rule(
                      Icons.cancel_rounded,
                      _negativeMarking ? Colors.red : theme.hintColor,
                      _negativeMarking
                          ? '${Scoring.negativePerWrong.toStringAsFixed(2)} for each wrong answer (UPSC scheme)'
                          : '0 for wrong answers',
                    ),
                    const SizedBox(height: 8),
                    _rule(Icons.remove_circle_outline_rounded, theme.hintColor,
                        '0 for skipped questions'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Negative marking toggle
            Card(
              child: SwitchListTile(
                value: _negativeMarking,
                onChanged: (v) => setState(() => _negativeMarking = v),
                title: const Text('Negative marking',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_negativeMarking
                    ? 'On — wrong answers cost you marks, like the real exam.'
                    : 'Off — wrong answers simply score 0.'),
                secondary: Icon(Icons.balance_rounded,
                    color: theme.colorScheme.primary),
              ),
            ),

            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Quiz',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _start,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _rule(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
