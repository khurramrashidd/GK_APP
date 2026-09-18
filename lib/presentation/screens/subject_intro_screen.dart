import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import 'quiz_start_screen.dart';
import 'sub_level_screen.dart';

/// Shown when a subject has an admin-written summary. Users read the intro,
/// then start the quiz.
///
/// This screen is only reached when [SubjectModel.description] is non-empty —
/// subjects without a summary skip straight to the quiz, so adding intros is
/// entirely opt-in per subject and never adds a step where there's nothing
/// to read.
///
/// The Start button is pinned to the bottom rather than placed after the
/// text, so it stays tappable no matter how long the summary is.
class SubjectIntroScreen extends ConsumerWidget {
  final DomainModel domain;
  final SubjectModel subject;
  const SubjectIntroScreen(
      {super.key, required this.domain, required this.subject});

  void _start(BuildContext context) {
    final hasSubLevels =
        subject.subLevels.any((sl) => sl.isActive) || subject.isShared;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => hasSubLevels
          ? SubLevelScreen(domain: domain, subject: subject)
          : QuizStartScreen(
              domainId: domain.id,
              domainName: domain.name,
              subjectId: subject.id,
              subjectName: subject.name,
              isShared: subject.isShared,
            ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(subject.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories_rounded,
                    color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(subject.name,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(domain.name,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 20),
            Text(
              subject.description ?? '',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
      // Pinned so it's reachable however long the summary runs.
      bottomNavigationBar: Material(
        elevation: 12,
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Quiz',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () => _start(context),
            ),
          ),
        ),
      ),
    );
  }
}
