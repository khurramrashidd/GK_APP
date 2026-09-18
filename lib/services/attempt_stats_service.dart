import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-question outcome, stored on THIS DEVICE only.
///
/// Why local: knowing that a specific question was skipped before and is now
/// answered needs one record per question per user. In Firestore that is one
/// document and one write per question answered — a single active user could
/// burn a quarter of the daily free-tier write budget. Locally it costs
/// nothing.
///
/// The trade-off, stated plainly: these figures live on one device. They are
/// lost on uninstall and do not follow the user to a new phone. The
/// leaderboard totals (which DO sync) are unaffected.
///
/// Stored as one JSON map of questionId -> status and saved ONCE per quiz,
/// not once per answer, so a 200-question session is a single write.
enum AttemptOutcome { skipped, correct, wrong }

class AttemptStats {
  final int correct;
  final int wrong;
  final int skipped;

  const AttemptStats({
    required this.correct,
    required this.wrong,
    required this.skipped,
  });

  /// Questions actually answered. A question that was skipped and later
  /// answered counts here and NOT in [skipped] — the status is overwritten,
  /// so the shift happens automatically.
  int get attempted => correct + wrong;

  /// Every distinct question seen, answered or not.
  int get seen => attempted + skipped;

  double get accuracy => attempted == 0 ? 0 : correct / attempted * 100;

  static const empty = AttemptStats(correct: 0, wrong: 0, skipped: 0);
}

class AttemptStatsService {
  static const _key = 'question_attempt_status_v1';

  Future<Map<String, int>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      // Corrupt or unreadable — start clean rather than crash the screen.
      return {};
    }
  }

  /// Merges one quiz's outcomes in and saves once.
  ///
  /// Re-answering a previously skipped question simply overwrites its status,
  /// which is what moves it from "skipped" to "attempted".
  Future<void> recordQuiz(Map<String, AttemptOutcome> outcomes) async {
    if (outcomes.isEmpty) return;
    try {
      final map = await _load();
      outcomes.forEach((id, outcome) => map[id] = outcome.index);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {
      // Stats are a nicety — never let them break finishing a quiz.
    }
  }

  Future<AttemptStats> stats() async {
    final map = await _load();
    var c = 0, w = 0, s = 0;
    for (final v in map.values) {
      switch (v) {
        case 1:
          c++;
          break;
        case 2:
          w++;
          break;
        default:
          s++;
      }
    }
    return AttemptStats(correct: c, wrong: w, skipped: s);
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
