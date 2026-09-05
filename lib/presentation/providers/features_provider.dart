import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/question_model.dart';
import '../../data/models/quiz_result.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

/// The user's saved (bookmarked) questions, live.
final bookmarksProvider = StreamProvider<List<QuestionModel>>((ref) {
  final profile = ref.watch(profileProvider);
  if (profile == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).streamBookmarks(profile.uid);
});

/// Just the ids, for quick "is this bookmarked?" checks on the quiz screen.
final bookmarkIdsProvider = StreamProvider<Set<String>>((ref) {
  final profile = ref.watch(profileProvider);
  if (profile == null) return Stream.value(<String>{});
  return ref
      .watch(firestoreServiceProvider)
      .streamBookmarks(profile.uid)
      .map((list) => list.map((q) => q.id).toSet());
});

/// The user's quiz history (most recent first).
final historyProvider = StreamProvider<List<QuizResult>>((ref) {
  final profile = ref.watch(profileProvider);
  if (profile == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).streamHistory(profile.uid);
});

/// Public leaderboard (name + score only).
final leaderboardProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(firestoreServiceProvider).streamLeaderboard();
});
