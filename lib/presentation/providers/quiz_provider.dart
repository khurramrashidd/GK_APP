import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/question_model.dart';
import '../../repositories/question_repository.dart';
import '../../core/constants/app_constants.dart';
import 'database_provider.dart';

/// Scoring constants. +2 per correct. When negative marking is on, UPSC Prelims
/// scheme docks 1/3 of the marks per wrong answer (0.66). Unanswered = 0.
class Scoring {
  static const double pointsPerCorrect = 2.0;
  static const double negativePerWrong = -0.66; // 1/3 of 2, UPSC Prelims
  static const int pointsPerCorrectInt = 2; // for whole-number leaderboard math
}

class QuizState {
  final List<QuestionModel> questions;
  final int currentQuestionIndex;

  /// Answer picked for each question (-1 = not answered yet). Persists across
  /// back/next navigation so users can change answers before finishing.
  final List<int> selectedAnswers;

  /// Which questions the user has tapped "Show answer" on. A revealed question
  /// is LOCKED — its answer can no longer change (matches real-test feel).
  final List<bool> revealed;

  final bool negativeMarking;
  final bool isLoading;
  final bool isFinished;
  final String? error;

  QuizState({
    required this.questions,
    this.currentQuestionIndex = 0,
    this.selectedAnswers = const [],
    this.revealed = const [],
    this.negativeMarking = false,
    this.isLoading = false,
    this.isFinished = false,
    this.error,
  });

  QuestionModel? get current =>
      questions.isEmpty ? null : questions[currentQuestionIndex];

  int get selectedForCurrent => currentQuestionIndex < selectedAnswers.length
      ? selectedAnswers[currentQuestionIndex]
      : -1;

  bool get isFirst => currentQuestionIndex == 0;
  bool get isLast => currentQuestionIndex == questions.length - 1;

  /// Whether the current question's answer has been revealed (and thus locked).
  bool get isCurrentRevealed =>
      currentQuestionIndex < revealed.length &&
      revealed[currentQuestionIndex];

  int get correctCount {
    var n = 0;
    for (var i = 0; i < questions.length; i++) {
      if (i < selectedAnswers.length &&
          selectedAnswers[i] == questions[i].correctOptionIndex) {
        n++;
      }
    }
    return n;
  }

  int get wrongCount {
    var n = 0;
    for (var i = 0; i < questions.length; i++) {
      final a = i < selectedAnswers.length ? selectedAnswers[i] : -1;
      if (a != -1 && a != questions[i].correctOptionIndex) n++;
    }
    return n;
  }

  int get answeredCount =>
      selectedAnswers.where((a) => a != -1).length;

  int get skippedCount => questions.length - answeredCount;

  /// Final score with (optional) negative marking, never below zero.
  double get score {
    final raw = correctCount * Scoring.pointsPerCorrect +
        (negativeMarking ? wrongCount * Scoring.negativePerWrong.abs() * -1 : 0);
    return raw < 0 ? 0 : raw;
  }

  /// Points added to the user's running total (whole number, floored at 0).
  int get pointsEarned => score.floor();

  QuizState copyWith({
    List<QuestionModel>? questions,
    int? currentQuestionIndex,
    List<int>? selectedAnswers,
    List<bool>? revealed,
    bool? negativeMarking,
    bool? isLoading,
    bool? isFinished,
    String? error,
  }) {
    return QuizState(
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      selectedAnswers: selectedAnswers ?? this.selectedAnswers,
      revealed: revealed ?? this.revealed,
      negativeMarking: negativeMarking ?? this.negativeMarking,
      isLoading: isLoading ?? this.isLoading,
      isFinished: isFinished ?? this.isFinished,
      error: error,
    );
  }
}

class QuizNotifier extends StateNotifier<QuizState> {
  final QuestionRepository _repository;
  QuizNotifier(this._repository) : super(QuizState(questions: []));

  /// Sync the domain if needed, then load a shuffled subset for the subject
  /// (or, when [subLevelId] is given, for that specific sub-level within it).
  Future<void> startQuiz(
    String domainId,
    String subjectId, {
    String? subLevelId,
    bool negativeMarking = false,
    List<QuestionModel>? preloaded,
    bool isShared = false,
  }) async {
    state = QuizState(questions: [], isLoading: true);
    try {
      List<QuestionModel> pool;
      if (preloaded != null) {
        pool = preloaded; // used by the bookmarked-revision quiz (Pass 2)
      } else if (isShared) {
        // Shared subject: one pool keyed on the subject id, spanning every
        // domain that uses it. Online-only — see QuestionRepository.
        pool = await _repository.getSharedSubjectQuestions(subjectId,
            subLevelId: subLevelId);
      } else {
        // Download-on-demand: fetch just this subject rather than syncing the
        // entire domain (a domain can hold 50 subjects).
        pool = await _repository.getSubjectQuestionsOnDemand(
            domainId, subjectId,
            subLevelId: subLevelId);
      }
      final shuffled = List<QuestionModel>.from(pool)..shuffle();
      final picked = shuffled.take(AppConstants.questionsPerQuiz).toList();

      state = QuizState(
        questions: picked,
        selectedAnswers: List<int>.filled(picked.length, -1),
        revealed: List<bool>.filled(picked.length, false),
        negativeMarking: negativeMarking,
      );
    } catch (e) {
      state = QuizState(questions: [], error: e.toString());
    }
  }

  /// Select (or change) the answer for the current question. Re-selecting the
  /// same option deselects it (lets a user un-answer to avoid the negative mark).
  /// No-op once the question has been revealed (revealing locks the answer).
  void selectOption(int optionIndex) {
    final i = state.currentQuestionIndex;
    if (i >= state.selectedAnswers.length) return;
    if (i < state.revealed.length && state.revealed[i]) return; // locked
    final answers = List<int>.from(state.selectedAnswers);
    answers[i] = (answers[i] == optionIndex) ? -1 : optionIndex;
    state = state.copyWith(selectedAnswers: answers);
  }

  /// Reveal the current question's correct answer + explanation, locking it.
  /// Requires an option to already be selected — the UI enforces this too.
  void revealCurrent() {
    final i = state.currentQuestionIndex;
    if (i >= state.revealed.length) return;
    if (state.selectedAnswers[i] == -1) return; // nothing chosen to lock
    final r = List<bool>.from(state.revealed);
    r[i] = true;
    state = state.copyWith(revealed: r);
  }

  void goTo(int index) {
    if (index < 0 || index >= state.questions.length) return;
    state = state.copyWith(currentQuestionIndex: index);
  }

  void next() => goTo(state.currentQuestionIndex + 1);
  void previous() => goTo(state.currentQuestionIndex - 1);

  void finish() => state = state.copyWith(isFinished: true);
}

final quizProvider = StateNotifierProvider<QuizNotifier, QuizState>((ref) {
  return QuizNotifier(ref.watch(questionRepositoryProvider));
});
