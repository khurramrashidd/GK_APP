import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/local/isar_service.dart';
import '../data/remote/firestore_service.dart';
import '../data/models/question_model.dart';
import '../data/models/domain_model.dart';
import '../services/gemini_service.dart';

class QuestionRepository {
  final IsarService _local;
  final FirestoreService _remote;
  final GeminiService _gemini;

  QuestionRepository(this._local, this._remote, this._gemini);

  // ------------------------- Domain catalogue ------------------------------

  /// Fetch domains from Firestore. Falls back silently to whatever is cached if
  /// the network is unavailable (handled by caller if needed).
  Future<List<DomainModel>> fetchDomains() => _remote.fetchDomains();

  // ------------------------ Per-domain delta sync --------------------------

  /// Ensure the given domain's questions are cached locally and up to date.
  /// - First open: downloads everything for the domain.
  /// - Later opens: downloads only questions with version > local version.
  /// - Offline: throws only if there is genuinely nothing cached; otherwise
  ///   uses the cache.
  Future<void> ensureDomainSynced(String domainId) async {
    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getInt(AppConstants.domainVersionKey(domainId)) ?? 0;

    try {
      final serverVersion = await _remote.fetchDomainVersion(domainId);
      final cachedCount = await _local.countForDomain(domainId);

      final needsSync = serverVersion > localVersion || cachedCount == 0;
      if (needsSync) {
        final updates =
            await _remote.fetchDomainQuestionsAfter(domainId, localVersion);
        if (updates.isNotEmpty) {
          await _local.upsertQuestions(updates);
        }
        if (serverVersion > 0) {
          await prefs.setInt(
              AppConstants.domainVersionKey(domainId), serverVersion);
        }
      }
    } catch (e) {
      // Offline / transient error: rely on cache. Rethrow only if empty.
      final cachedCount = await _local.countForDomain(domainId);
      if (cachedCount == 0) {
        rethrow;
      }
    }
  }

  Future<List<QuestionModel>> getQuestions(String domainId, String subjectId,
      {String? subLevelId}) {
    return _local.getQuestions(domainId, subjectId, subLevelId: subLevelId);
  }

  /// Questions for a SHARED subject: pulled straight from Firestore across
  /// every domain that uses this subject id, rather than from the per-domain
  /// Isar cache.
  ///
  /// Shared subjects are online-only by design — see the note on
  /// FirestoreService.fetchSharedSubjectQuestions. A shared question belongs
  /// to several domains at once, which the per-domain cache (keyed by
  /// domainId + a domain version counter) can't represent. Rather than
  /// silently return partial results from a cache that was never built for
  /// this, we go to the network and let the caller surface an error if
  /// offline.
  Future<List<QuestionModel>> getSharedSubjectQuestions(String subjectId,
      {String? subLevelId}) {
    return _remote.fetchSharedSubjectQuestions(subjectId,
        subLevelId: subLevelId);
  }

  /// Download-on-demand for ONE subject.
  ///
  /// Replaces "sync the whole domain the first time you open it". With
  /// domains holding up to 50 subjects, pulling everything to read one
  /// subject wastes the user's data and time — especially on first launch
  /// after a Play Store install. This fetches just the tapped subject,
  /// caches it locally, and falls back to whatever is cached when offline.
  Future<List<QuestionModel>> getSubjectQuestionsOnDemand(
    String domainId,
    String subjectId, {
    String? subLevelId,
  }) async {
    try {
      final fresh = await _remote.fetchSubjectQuestions(domainId, subjectId,
          subLevelId: subLevelId);
      if (fresh.isNotEmpty) {
        await _local.upsertQuestions(fresh);
      }
      // Read back through the cache so the caller always sees a consistent
      // local view (including anything cached from an earlier session).
      return _local.getQuestions(domainId, subjectId, subLevelId: subLevelId);
    } catch (_) {
      // Offline or transient failure: serve whatever is already cached.
      return _local.getQuestions(domainId, subjectId, subLevelId: subLevelId);
    }
  }

  // --------------------------- AI explanation ------------------------------

  /// Cache-first AI explanation:
  ///   1. If already on the local question -> return it.
  ///   2. Else check Firestore (another user may have generated it) -> cache + return.
  ///   3. Else call Gemini, save to Firestore + local, return.
  Future<String> getOrCreateAiExplanation(QuestionModel q) async {
    if (q.aiExplanation != null && q.aiExplanation!.trim().isNotEmpty) {
      return q.aiExplanation!;
    }

    // Check remote cache first (shared across all users).
    final remoteCached = await _remote.fetchAiExplanation(q.id);
    if (remoteCached != null && remoteCached.trim().isNotEmpty) {
      await _local.setAiExplanation(q.id, remoteCached);
      q.aiExplanation = remoteCached;
      return remoteCached;
    }

    // Generate fresh, then persist for everyone.
    final generated = await _gemini.explainQuestion(
      question: q.question,
      options: q.options,
      correctIndex: q.correctOptionIndex,
      shortExplanation: q.explanation,
    );

    try {
      await _remote.saveAiExplanation(q.id, generated);
    } catch (_) {
      // If the write fails (e.g. rules), we still show it to this user.
    }
    await _local.setAiExplanation(q.id, generated);
    q.aiExplanation = generated;
    return generated;
  }
}
