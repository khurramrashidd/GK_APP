import 'dart:math';

/// Randomises which position holds the correct answer.
///
/// WHY THIS EXISTS: question sets are very often authored with the correct
/// answer written first (it's the natural way to write them, and AI-generated
/// sets do it almost universally). If that reaches users unchanged, someone
/// can score ~100% by always tapping option A without reading anything, which
/// destroys the app's value as a learning tool.
///
/// This is applied at UPLOAD time so it can never recur, and there is a
/// one-off admin migration that fixes questions already in the database.
class AnswerShuffler {
  static final Random _rand = Random();

  /// Shuffles [options] and returns the new list plus the new index of the
  /// answer that was originally at [correctIndex].
  ///
  /// Returns the input unchanged if the data is malformed (fewer than two
  /// options, or an out-of-range index) — a bad row should be reported by the
  /// validator, not silently mangled here.
  static ({List<String> options, int correctIndex}) shuffle(
    List<String> options,
    int correctIndex,
  ) {
    if (options.length < 2 ||
        correctIndex < 0 ||
        correctIndex >= options.length) {
      return (options: options, correctIndex: correctIndex);
    }

    // Track the correct answer by identity, not by value: duplicate option
    // text (e.g. two "None of the above") would otherwise make indexOf()
    // point at the wrong one.
    final indexed = [
      for (var i = 0; i < options.length; i++) (text: options[i], wasCorrect: i == correctIndex)
    ]..shuffle(_rand);

    return (
      options: [for (final e in indexed) e.text],
      correctIndex: indexed.indexWhere((e) => e.wasCorrect),
    );
  }

  /// Convenience for the upload path: takes a raw question map and returns a
  /// copy with 'options' and 'correctOptionIndex' shuffled.
  static Map<String, dynamic> shuffleRow(Map<String, dynamic> row) {
    final rawOpts = row['options'];
    final rawIdx = row['correctOptionIndex'];
    if (rawOpts is! List || rawIdx is! int) return row;

    final result = shuffle(List<String>.from(rawOpts), rawIdx);
    return {
      ...row,
      'options': result.options,
      'correctOptionIndex': result.correctIndex,
    };
  }
}
