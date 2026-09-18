import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the admin wants question counts shown in Domains & Subjects.
///
/// Persisted across launches, and defaults to ON — the counts are cheap now
/// that every one of them uses a count() aggregation (which bills per 1,000
/// matched documents, not per document). Opening the screen with counts on
/// costs a few hundred reads against a 50,000/day free-tier allowance.
///
/// It stays a switch rather than being hard-wired on so it can be turned off
/// on a day when the read budget is genuinely tight.
class ShowCountsNotifier extends StateNotifier<bool> {
  static const _key = 'admin_show_question_counts';

  ShowCountsNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Absent key => keep the default (true) rather than falling back to
      // false, so a fresh install shows counts straight away.
      state = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Preferences unavailable — the in-memory default still applies.
    }
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Failing to persist shouldn't undo the user's choice this session.
    }
  }
}

final showQuestionCountsProvider =
    StateNotifierProvider<ShowCountsNotifier, bool>((ref) {
  return ShowCountsNotifier();
});


/// The user's OWN choice about Reels mode, if they've made one.
///
/// null = "no preference", which means the admin default applies. This is
/// deliberately nullable rather than a plain bool: without it there'd be no
/// way to tell "user turned it off" apart from "user never chose", and the
/// admin default could never take effect for anyone.
class ReelsChoiceNotifier extends StateNotifier<bool?> {
  static const _key = 'reels_mode_user_choice';

  ReelsChoiceNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key);
    } catch (_) {}
  }

  Future<void> set(bool? value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setBool(_key, value);
      }
    } catch (_) {}
  }
}

final reelsUserChoiceProvider =
    StateNotifierProvider<ReelsChoiceNotifier, bool?>((ref) {
  return ReelsChoiceNotifier();
});
