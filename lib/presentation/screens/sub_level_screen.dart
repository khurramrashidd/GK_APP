import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import '../providers/database_provider.dart';
import 'quiz_start_screen.dart';

/// Shows the sub-level list within a subject (e.g. "Topics" for Ancient
/// History, or "Months" for Current Affairs) — whatever the admin named this
/// tier for the domain via [DomainModel.subLevelLabel].
///
/// For a SHARED subject, the list shown is the MERGED union of sub-levels
/// contributed by every domain that also marks this subject shared — so
/// UPSC > History (Ancient, Medieval) and Academics > History (Class 6,
/// Class 7) both display all four. That merge needs a Firestore read, so
/// shared subjects load asynchronously here; non-shared ones render
/// instantly from the domain data already in hand.
class SubLevelScreen extends ConsumerWidget {
  final DomainModel domain;
  final SubjectModel subject;
  const SubLevelScreen({super.key, required this.domain, required this.subject});

  String get _label => (domain.subLevelLabel?.trim().isNotEmpty ?? false)
      ? domain.subLevelLabel!.trim()
      : 'Topic';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!subject.isShared) {
      final levels = subject.subLevels.where((sl) => sl.isActive).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return _scaffold(context, levels);
    }

    // Shared: merge sub-levels from every domain that shares this subject.
    final mergedAsync = ref.watch(mergedSubLevelsProvider(subject.id));
    return mergedAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(subject.name)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(subject.name)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Could not load shared topics.\n\nShared subjects need an '
              'internet connection.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (levels) => _scaffold(context, levels),
    );
  }

  Widget _scaffold(BuildContext context, List<SubLevelModel> levels) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name),
        actions: [
          if (subject.isShared)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Shared question pool across domains',
                child: Icon(Icons.hub_rounded, color: theme.hintColor),
              ),
            ),
        ],
      ),
      body: levels.isEmpty
          // A shared subject with no sub-levels anywhere still has a question
          // pool — offer it directly rather than dead-ending the user.
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No ${_label.toLowerCase()}s here yet.'),
                    if (subject.isShared) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start quiz anyway'),
                        onPressed: () => _openQuiz(context, null),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: levels.length,
              itemBuilder: (context, i) {
                final sl = levels[i];
                return Card(
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.label_rounded,
                          color: theme.colorScheme.primary),
                    ),
                    title: Text(sl.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openQuiz(context, sl),
                  ),
                );
              },
            ),
    );
  }

  void _openQuiz(BuildContext context, SubLevelModel? sl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuizStartScreen(
        domainId: domain.id,
        domainName: domain.name,
        subjectId: subject.id,
        subjectName: subject.name,
        subLevelId: sl?.id,
        subLevelName: sl?.name,
        isShared: subject.isShared,
      ),
    ));
  }
}
