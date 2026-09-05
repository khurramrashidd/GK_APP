import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../data/local/isar_service.dart';
import '../../data/remote/firestore_service.dart';
import '../../data/models/domain_model.dart';
import 'auth_provider.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/suggestion_model.dart';
import '../../data/models/error_log_model.dart';
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
