import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/quiz_result.dart';
import 'database_provider.dart';

/// Holds the currently signed-in user's profile (null when logged out).
class ProfileNotifier extends StateNotifier<UserProfile?> {
  final Ref _ref;
  ProfileNotifier(this._ref) : super(null);

  /// Super admins are hardcoded and can never be removed from inside the app.
  bool get isSuperAdmin {
    final email = state?.email.toLowerCase();
    if (email == null) return false;
    return AppConstants.superAdminEmails
        .map((e) => e.toLowerCase())
        .contains(email);
  }

  /// Admin = a hardcoded super admin, OR a user granted rights at runtime by
  /// another admin (stored as isAdminUser on their profile).
  bool get isAdmin => isSuperAdmin || (state?.isAdminUser ?? false);

  /// Records acceptance of the current Terms version.
  Future<void> acceptCurrentTerms() async {
    if (state == null) return;
    await _ref
        .read(firestoreServiceProvider)
        .acceptTerms(state!.uid, AppConstants.termsVersion);
    state = state!.copyWith(acceptedTermsVersion: AppConstants.termsVersion);
  }

  /// True when this user still needs to see the Terms gate.
  bool get needsTermsAcceptance =>
      state != null && state!.acceptedTermsVersion < AppConstants.termsVersion;

  /// Stores an optional location, or clears it when the user declines.
  Future<void> saveLocation({
    double? latitude,
    double? longitude,
    String? locationName,
    String? timeZoneName,
  }) async {
    if (state == null) return;
    await _ref.read(firestoreServiceProvider).saveUserLocation(
          state!.uid,
          latitude: latitude,
          longitude: longitude,
          locationName: locationName,
          timeZoneName: timeZoneName,
        );
    state = latitude == null
        ? state!.copyWith(clearLocation: true)
        : state!.copyWith(
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            timeZoneName: timeZoneName,
          );
  }

  /// After a successful sign-in: make sure users/{uid} exists, then load it.
  Future<UserProfile> loadForUser(User user) async {
    final repo = _ref.read(userRepositoryProvider);
    final profile = await repo.ensureProfile(user);
    state = profile;
    return profile;
  }

  Future<void> refresh() async {
    final user = _ref.read(authServiceProvider).currentUser;
    if (user == null) {
      state = null;
      return;
    }
    final repo = _ref.read(userRepositoryProvider);
    state = await repo.load(user.uid) ?? state;
  }

  /// Save profile edits (name*, state*, dob, mobile, city, pincode).
  Future<void> saveProfile({
    required String name,
    required String state,
    String? dob,
    String? mobile,
    String? city,
    String? pincode,
    String? gender,
  }) async {
    if (this.state == null) return;
    final complete = name.trim().isNotEmpty && state.trim().isNotEmpty;
    final updated = this.state!.copyWith(
          name: name.trim(),
          state: state.trim(),
          dob: dob,
          mobile: mobile,
          city: city,
          pincode: pincode,
          gender: gender,
          profileComplete: complete,
        );
    await _ref.read(userRepositoryProvider).save(updated);
    this.state = updated;
  }

  Future<void> addScore(int points) async {
    if (state == null) return;
    await _ref.read(userRepositoryProvider).addScore(state!.uid, points);
    state = state!.copyWith(totalScore: state!.totalScore + points);
  }

  /// Called once when a quiz finishes: adds points, saves history, updates the
  /// daily streak, and publishes to the public leaderboard — all together.
  Future<void> recordQuizCompletion(QuizResult result, int points) async {
    if (state == null) return;
    final fs = _ref.read(firestoreServiceProvider);
    final uid = state!.uid;

    // --- streak ---
    final today = DateTime.now();
    final todayStr = _dateKey(today);
    final yesterdayStr = _dateKey(today.subtract(const Duration(days: 1)));
    int newStreak;
    if (state!.lastActiveDate == todayStr) {
      newStreak = state!.currentStreak; // already practiced today
    } else if (state!.lastActiveDate == yesterdayStr) {
      newStreak = state!.currentStreak + 1; // consecutive day
    } else {
      newStreak = 1; // streak reset / first ever
    }
    final newLongest =
        newStreak > state!.longestStreak ? newStreak : state!.longestStreak;

    final newTotal = state!.totalScore + points;
    final displayName =
        state!.name.isNotEmpty ? state!.name : state!.displayName;

    // Persist everything. Score increment + profile fields via the repo/save,
    // history + leaderboard via the dedicated batch.
    try {
      await fs.saveQuizResult(uid, result, displayName, newTotal);
    } catch (_) {/* offline: history simply not saved this time */}

    final updated = state!.copyWith(
      totalScore: newTotal,
      currentStreak: newStreak,
      longestStreak: newLongest,
      lastActiveDate: todayStr,
    );
    try {
      await _ref.read(userRepositoryProvider).save(updated);
    } catch (_) {}
    state = updated;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> signOut() async {
    await _ref.read(authServiceProvider).signOut();
    state = null;
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, UserProfile?>((ref) {
  return ProfileNotifier(ref);
});
