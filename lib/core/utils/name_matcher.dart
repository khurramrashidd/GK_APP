/// Matches a file name against subject names by shared DISTINCTIVE words.
///
/// Exact slug comparison alone is too brittle for real files: an export
/// named `first-tarain.json` plainly refers to "First Battle of Tarain", but
/// the slugs differ entirely. Comparing word sets catches that, while
/// ignoring filler words that would otherwise link everything to everything
/// ("Battle of X" and "Battle of Y" share *battle* and *of*, which tells you
/// nothing).
class NameMatcher {
  /// Words too common to carry meaning here. Deliberately short: over-
  /// filtering would drop genuinely distinguishing words. "Battle" and
  /// "war" are included because this catalogue is full of them.
  static const stopWords = <String>{
    'a', 'an', 'the', 'of', 'or', 'and', 'by', 'for', 'in', 'on', 'at',
    'to', 'from', 'with', 'is', 'was', 'as', 'its', 'it',
    // domain-specific filler
    'battle', 'battles', 'war', 'wars', 'quiz', 'questions', 'question',
    'mcq', 'mcqs', 'part', 'batch', 'set', 'test',
  };

  /// Splits a name into lowercase distinctive words.
  ///
  /// Numbers are kept (a "Second Battle" differs from a "First Battle"),
  /// but single characters are dropped as noise.
  static Set<String> tokens(String input) {
    final words = input
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]+$'), '') // drop file extension
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 1 && !stopWords.contains(w))
        .toSet();
    return words;
  }

  /// How well [fileName] matches [candidateName], 0.0 to 1.0.
  ///
  /// Scored as the share of the FILE's distinctive words that appear in the
  /// candidate. Anchoring on the file (not the candidate) matters: a short
  /// file name fully contained in a long subject name is a strong signal,
  /// and dividing by the longer name would wrongly punish it.
  static double score(String fileName, String candidateName) {
    final a = tokens(fileName);
    final b = tokens(candidateName);
    if (a.isEmpty || b.isEmpty) return 0;

    final shared = a.intersection(b);
    if (shared.isEmpty) return 0;

    final containment = shared.length / a.length;
    // A small bonus when the candidate is also well covered, so an exact
    // word-for-word match outranks a partial one.
    final reverse = shared.length / b.length;
    return (containment * 0.75) + (reverse * 0.25);
  }

  /// Human-readable reason, for showing the admin why something was
  /// suggested — a suggestion you can't audit is just a guess.
  static String reason(String fileName, String candidateName) {
    final shared = tokens(fileName).intersection(tokens(candidateName));
    if (shared.isEmpty) return 'no shared words';
    final list = shared.toList()..sort();
    return 'shares ${list.map((w) => '"$w"').join(', ')}';
  }
}
