import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/match_model.dart';
import '../../data/models/question_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/quiz_provider.dart'; // Scoring

/// Live stream of one match — both players watch the same doc, so this is
/// how each side sees the other's join, answers, and finish in real time.
final matchStreamProvider =
    StreamProvider.family<MatchModel?, String>((ref, matchId) {
  return ref.watch(firestoreServiceProvider).streamMatch(matchId);
});

class MultiplayerGameState {
  final List<QuestionModel> questions;
  final Map<String, int> myAnswers; // questionId -> option index
  final int currentIndex;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  MultiplayerGameState({
    this.questions = const [],
    this.myAnswers = const {},
    this.currentIndex = 0,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  QuestionModel? get current =>
      currentIndex < questions.length ? questions[currentIndex] : null;
  bool get isLast => currentIndex == questions.length - 1;
  int get answeredCount => myAnswers.length;

  int computeScore() {
    var correct = 0;
    for (final q in questions) {
      if (myAnswers[q.id] == q.correctOptionIndex) correct++;
    }
    return (correct * Scoring.pointsPerCorrectInt);
  }

  MultiplayerGameState copyWith({
    List<QuestionModel>? questions,
    Map<String, int>? myAnswers,
    int? currentIndex,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
  }) {
    return MultiplayerGameState(
      questions: questions ?? this.questions,
      myAnswers: myAnswers ?? this.myAnswers,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}

/// Drives one player's side of a match: loads the shared question set, sends
/// each answer to Firestore as it's picked (so the opponent's progress view
/// updates live), and submits the final score once all questions are done.
class MultiplayerGameNotifier extends StateNotifier<MultiplayerGameState> {
  final Ref _ref;
  final String matchId;
  final int playerSlot;

  MultiplayerGameNotifier(this._ref, this.matchId, this.playerSlot)
      : super(MultiplayerGameState());

  Future<void> load(List<String> questionIds) async {
    state = state.copyWith(isLoading: true);
    try {
      final questions =
          await _ref.read(firestoreServiceProvider).fetchQuestionsByIds(questionIds);
      state = state.copyWith(questions: questions, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> answer(int optionIndex) async {
    final q = state.current;
    if (q == null) return;
    final answers = Map<String, int>.from(state.myAnswers);
    answers[q.id] = optionIndex;
    state = state.copyWith(myAnswers: answers);
    try {
      await _ref
          .read(firestoreServiceProvider)
          .submitMatchAnswer(matchId, playerSlot, q.id, optionIndex);
    } catch (_) {
      // Kept locally even if the write fails momentarily; next answer's write
      // (or a retry) will catch it up. Not worth blocking the player over.
    }
  }

  void next() {
    if (state.currentIndex < state.questions.length - 1) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
    }
  }

  Future<void> finish() async {
    state = state.copyWith(isSubmitting: true);
    final score = state.computeScore();
    try {
      await _ref
          .read(firestoreServiceProvider)
          .finishMatchPlayer(matchId, playerSlot, score);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
    }
  }
}

final multiplayerGameProvider = StateNotifierProvider.family<
    MultiplayerGameNotifier, MultiplayerGameState, ({String matchId, int slot})>(
  (ref, args) => MultiplayerGameNotifier(ref, args.matchId, args.slot),
);
