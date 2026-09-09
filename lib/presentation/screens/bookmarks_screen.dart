import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/features_provider.dart';
import '../providers/quiz_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import 'quiz_screen.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Questions')),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved questions yet.\nTap the bookmark icon on any '
                  'question during a quiz to save it here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50)),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text('Revise all ${bookmarks.length} saved '
                      'question${bookmarks.length == 1 ? '' : 's'}'),
                  onPressed: () {
                    // Launch a quiz built directly from the saved questions.
                    ref.read(quizProvider.notifier).startQuiz(
                          '', '',
                          preloaded: bookmarks,
                        );
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const QuizScreen(
                        domainName: 'Revision',
                        subjectName: 'Saved Questions',
                      ),
                    ));
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: bookmarks.length,
                  itemBuilder: (context, i) {
                    final q = bookmarks[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(q.question,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${q.domainName} • ${q.subjectName}'
                          '${q.subLevelName != null ? ' • ${q.subLevelName}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final profile = ref.read(profileProvider);
                            if (profile == null) return;
                            await ref
                                .read(firestoreServiceProvider)
                                .removeBookmark(profile.uid, q.id);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
