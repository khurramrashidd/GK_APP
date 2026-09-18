import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../data/local/isar_service.dart';
import '../../data/remote/firestore_service.dart';
import '../../data/models/domain_model.dart';
import 'auth_provider.dart';
import 'admin_prefs_provider.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/suggestion_model.dart';
import '../../data/models/error_log_model.dart';
import '../../data/models/recycle_bin_model.dart';
import '../../data/models/content_update_model.dart';
import '../../data/models/friend_models.dart';
import '../../repositories/question_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../services/gemini_service.dart';

// ------------------------------- Services ----------------------------------
final isarServiceProvider = Provider<IsarService>((ref) => IsarService());
final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());
final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// ----------------------------- Repositories --------------------------------
final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(
    ref.watch(isarServiceProvider),
    ref.watch(firestoreServiceProvider),
    ref.watch(geminiServiceProvider),
  );
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(firestoreServiceProvider));
});

// ----------------------- Domain catalogue (with cache) ----------------------
/// Loads domains from Firestore, caching the result to SharedPreferences so the
/// home screen still works offline after the first successful load.
final domainsProvider = FutureProvider<List<DomainModel>>((ref) async {
  final repo = ref.watch(questionRepositoryProvider);
  final prefs = await SharedPreferences.getInstance();
  try {
    final domains = await repo.fetchDomains();
    prefs.setString(
      AppConstants.keyDomainsCache,
      jsonEncode(domains.map((d) => d.toMap()).toList()),
    );
    return domains;
  } catch (e) {
    final cached = prefs.getString(AppConstants.keyDomainsCache);
    if (cached != null) {
      final list = (jsonDecode(cached) as List)
          .map((m) => DomainModel.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
      return list;
    }
    rethrow;
  }
});

/// Admin-only view: includes hidden (isActive: false) domains, so the admin
/// screen can manage and unhide them. Not cached offline — admin needs a
/// live connection to manage content anyway.
final adminDomainsProvider = FutureProvider<List<DomainModel>>((ref) async {
  final fs = ref.watch(firestoreServiceProvider);
  return await fs.fetchAllDomainsForAdmin();
});

// ----------------------------- Question counts ------------------------------
// A stable key for the family provider. domainId is required (matching
// FirestoreService.countQuestions) — pass subjectId/subLevelId to narrow it
// further, or leave them null for a domain-wide total.
typedef QuestionCountKey = ({
  String domainId,
  String? subjectId,
  String? subLevelId,
});

final questionCountProvider =
    FutureProvider.family<int, QuestionCountKey>((ref, key) {
  return ref.watch(firestoreServiceProvider).countQuestions(
        domainId: key.domainId,
        subjectId: key.subjectId,
        subLevelId: key.subLevelId,
      );
});

/// Total question count across the entire app, no filters — the one thing
/// countQuestions can't do since it requires a domainId.
final totalQuestionCountProvider = FutureProvider<int>((ref) {
  return ref.watch(firestoreServiceProvider).countAllQuestions();
});

// ----------------------------- Shared subjects ------------------------------

/// The merged sub-level list for a shared subject — the union contributed by
/// every domain that also marks this subject shared. Keyed by subject id.
final mergedSubLevelsProvider =
    FutureProvider.family<List<SubLevelModel>, String>((ref, subjectId) {
  return ref.watch(firestoreServiceProvider).fetchMergedSubLevels(subjectId);
});

/// Names of the domains currently sharing a given subject id — shown in the
/// admin panel so the toggle's effect is visible before/after flipping it.
final domainsSharingSubjectProvider =
    FutureProvider.family<List<String>, String>((ref, subjectId) {
  return ref.watch(firestoreServiceProvider).domainsSharingSubject(subjectId);
});

/// Question count for a shared subject's pool (spans all domains).
final sharedSubjectCountProvider =
    FutureProvider.family<int, String>((ref, subjectId) {
  return ref
      .watch(firestoreServiceProvider)
      .countSharedSubjectQuestions(subjectId);
});

// ------------------------------ Admin / users -------------------------------

final allUsersProvider = FutureProvider<List<UserProfile>>((ref) {
  return ref.watch(firestoreServiceProvider).fetchAllUsers();
});

// ------------------------------- Suggestions --------------------------------

final allSuggestionsProvider =
    StreamProvider<List<SuggestionModel>>((ref) {
  return ref.watch(firestoreServiceProvider).streamAllSuggestions();
});

final mySuggestionsProvider =
    StreamProvider<List<SuggestionModel>>((ref) {
  final profile = ref.watch(profileProvider);
  if (profile == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).streamMySuggestions(profile.uid);
});

// ------------------------------- Error logs ---------------------------------

final errorLogsProvider = StreamProvider<List<ErrorLogModel>>((ref) {
  return ref.watch(firestoreServiceProvider).streamErrorLogs();
});

// ------------------------------ Recycle bin ---------------------------------

final recycleBinProvider = StreamProvider<List<RecycleBinItem>>((ref) {
  return ref.watch(firestoreServiceProvider).streamRecycleBin();
});

// ---------------------------- Content updates -------------------------------

/// Announcements from the last 48 hours only.
///
/// Filtered client-side rather than by query because Firestore can't express
/// "newer than a moving timestamp" without re-issuing the query as time
/// passes; the feed is capped at 30 docs anyway, so the filter is free.
/// Older entries stay in Firestore (useful history for you) but drop out of
/// what users see.
final contentUpdatesProvider =
    StreamProvider<List<ContentUpdateModel>>((ref) {
  return ref.watch(firestoreServiceProvider).streamContentUpdates().map((all) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    return all
        .where((u) => u.createdAt == null || u.createdAt!.isAfter(cutoff))
        .toList();
  });
});

/// How many updates this user hasn't seen yet — drives the home badge.
final unseenUpdateCountProvider = Provider<int>((ref) {
  final updates = ref.watch(contentUpdatesProvider).valueOrNull ?? const [];
  final since = ref.watch(profileProvider)?.lastSeenUpdatesAt;
  // updates is already limited to the last 48h by contentUpdatesProvider,
  // so a never-opened feed simply counts everything still inside the window.
  if (since == null) return updates.length;
  return updates
      .where((u) => u.createdAt != null && u.createdAt!.isAfter(since))
      .length;
});

/// Live domain list for ADMIN screens, so edits appear instantly.
final adminDomainsStreamProvider =
    StreamProvider<List<DomainModel>>((ref) {
  return ref.watch(firestoreServiceProvider).streamAllDomainsForAdmin();
});

// ------------------------------ App settings --------------------------------

final appSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return ref.watch(firestoreServiceProvider).streamAppSettings();
});

/// Master switch for advertising, controlled by an admin from the dashboard.
///
/// No ad SDK is bundled yet, so this does nothing today. It exists now so
/// that when ads ARE added, they can be turned off remotely and instantly —
/// without shipping an app update and waiting for Play review. That's the
/// part you cannot retrofit later, which is why the flag goes in now.
final adsEnabledProvider = Provider<bool>((ref) {
  final s = ref.watch(appSettingsProvider).valueOrNull ?? const {};
  return (s['adsEnabled'] ?? false) as bool;
});

/// Whether THIS user should see ads: ads globally on, and they aren't
/// premium. Every future ad placement should check this one getter.
final shouldShowAdsProvider = Provider<bool>((ref) {
  if (!ref.watch(adsEnabledProvider)) return false;
  return !(ref.watch(profileProvider)?.isPremium ?? false);
});

/// Whether Reels is the DEFAULT experience for everyone (admin-controlled).
final reelsDefaultProvider = Provider<bool>((ref) {
  final s = ref.watch(appSettingsProvider).valueOrNull ?? const {};
  return (s['reelsModeDefault'] ?? false) as bool;
});

/// What the home screen should ACTUALLY show.
///
/// The user's own choice wins if they've made one; otherwise the admin's
/// default applies. Previously reelsDefaultProvider was only read by the
/// admin switch itself, so flipping it changed nothing for anyone — this is
/// the provider the user-facing UI watches.
final reelsModeActiveProvider = Provider<bool>((ref) {
  final userChoice = ref.watch(reelsUserChoiceProvider);
  if (userChoice != null) return userChoice;
  return ref.watch(reelsDefaultProvider);
});

// ------------------------------ App updates ---------------------------------

/// Details of the newest release an admin has published, or null when there
/// is nothing newer than this build.
///
/// Used for side-loaded APK distribution (GitHub Releases) before the app is
/// on the Play Store. Once it IS on Play, Play handles updates and this can
/// simply be left unset.
class AppUpdateInfo {
  final int buildNumber;
  final String versionName;
  final String url;
  final String? notes;
  final bool mandatory;

  /// true = only admins are told about this build. For releases that only
  /// change the admin panel, there's no reason to push every user through a
  /// 60 MB download.
  final bool adminsOnly;

  const AppUpdateInfo({
    required this.buildNumber,
    required this.versionName,
    required this.url,
    this.notes,
    this.mandatory = false,
    this.adminsOnly = false,
  });
}

final availableUpdateProvider = Provider<AppUpdateInfo?>((ref) {
  final s = ref.watch(appSettingsProvider).valueOrNull ?? const {};

  final build = (s['latestBuildNumber'] as num?)?.toInt() ?? 0;
  final url = (s['apkUrl'] ?? '').toString();

  // Nothing to offer unless the published build is genuinely newer AND an
  // actual download link exists — a version bump with no URL would show a
  // banner that goes nowhere.
  if (build <= AppConstants.appBuildNumber || url.isEmpty) return null;

  // An admin-only release is invisible to regular users.
  final adminsOnly = (s['updateAdminsOnly'] ?? false) as bool;
  if (adminsOnly) {
    ref.watch(profileProvider);
    if (!ref.read(profileProvider.notifier).isAdmin) return null;
  }

  return AppUpdateInfo(
    buildNumber: build,
    versionName: (s['latestVersionName'] ?? '').toString(),
    url: url,
    notes: (s['releaseNotes'] ?? '').toString().trim().isEmpty
        ? null
        : s['releaseNotes'].toString().trim(),
    mandatory: (s['updateMandatory'] ?? false) as bool,
    adminsOnly: adminsOnly,
  );
});

// --------------------------------- Friends ----------------------------------

final friendsProvider = StreamProvider<List<FriendModel>>((ref) {
  final uid = ref.watch(profileProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).streamFriends(uid);
});

final friendRequestsProvider =
    StreamProvider<List<FriendRequestModel>>((ref) {
  final uid = ref.watch(profileProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).streamFriendRequests(uid);
});

// ----------------------- Sidebar visibility (admin) --------------------------

/// Which optional drawer entries are switched on, admin-controlled.
///
/// Stored as one map in app_settings so toggling costs a single write and
/// reading costs nothing extra (the settings doc is already streamed).
/// Everything defaults to ON — a missing key must never hide a feature that
/// worked yesterday.
const kHideableTabs = <String, String>{
  'bookmarks': 'Saved Questions',
  'history': 'History & Stats',
  'leaderboard': 'Leaderboard',
  'battle': '1v1 Quiz Battle',
  'search': 'Search',
  'reports': 'My Reports',
  'friends': 'Friends',
  'whatsNew': "What's New",
  'reels': 'Reels mode',
  'suggestions': 'Suggest content',
};

final tabVisibilityProvider = Provider<Map<String, bool>>((ref) {
  final s = ref.watch(appSettingsProvider).valueOrNull ?? const {};
  final raw = s['hiddenTabs'];
  final hidden = raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
  return {for (final k in kHideableTabs.keys) k: !hidden.contains(k)};
});

/// True when [key] should be shown to THIS user.
///
/// Admins always see everything, whatever the switches say — otherwise an
/// admin could hide the leaderboard and then be unable to check it, and
/// hiding the admin panel itself would be unrecoverable from inside the app.
final tabVisibleProvider = Provider.family<bool, String>((ref, key) {
  // Admins see everything. isAdmin lives on the profile notifier, so watch
  // the profile to stay reactive if rights are granted mid-session.
  ref.watch(profileProvider);
  if (ref.read(profileProvider.notifier).isAdmin) return true;
  return ref.watch(tabVisibilityProvider)[key] ?? true;
});
