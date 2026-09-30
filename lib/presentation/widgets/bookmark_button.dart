import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/question_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/features_provider.dart';

/// A bookmark (save) toggle for a question. Reads live bookmark ids so it
/// reflects the saved state instantly and stays in sync across screens.
class BookmarkButton extends ConsumerWidget {
  final QuestionModel question;
  const BookmarkButton({super.key, required this.question});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(bookmarkIdsProvider).valueOrNull ?? const <String>{};
    final saved = ids.contains(question.id);
    final profile = ref.read(profileProvider);

    return IconButton(
      tooltip: saved ? 'Saved' : 'Save question',
      icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
      onPressed: profile == null
          ? null
          : () async {
              final fs = ref.read(firestoreServiceProvider);
              try {
                if (saved) {
                  await fs.removeBookmark(profile.uid, question.id);
                } else {
                  await fs.addBookmark(profile.uid, question);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not update bookmark: $e')));
                }
              }
            },
    );
  }
}
