import '../models/question_model.dart';

/// IsarService — WEB VARIANT.
///
/// A no-op stand-in with the exact same public method signatures as
/// isar_service_mobile.dart (the real implementation). It exists purely so
/// that files like database_provider.dart — which construct an `IsarService`
/// as part of wiring up `QuestionRepository`, whether or not anything on the
/// current platform ever actually calls it — still compile cleanly on web.
///
/// Every method here throws if actually called. That's intentional: nothing
/// reachable from the web build (see WebAppRoot) ever calls into
/// QuestionRepository or IsarService — the web app only ever talks to
/// FirestoreService directly. If you ever see one of these errors at
/// runtime, it means some new code path accidentally pulled local caching
/// into the web build, which shouldn't happen since Isar can't run there.
class IsarService {
  Never _unsupported() => throw UnsupportedError(
      'IsarService is not available on web — the web build only uses '
      'FirestoreService directly. If you hit this, some new code path is '
      'reaching local-cache logic that should stay mobile-only.');

  Future<void> upsertQuestions(List<QuestionModel> incoming) async =>
      _unsupported();

  Future<List<QuestionModel>> getQuestions(String domainId, String subjectId,
          {String? subLevelId}) async =>
      _unsupported();

  Future<int> countForDomain(String domainId) async => _unsupported();

  Future<void> setAiExplanation(String questionId, String aiText) async =>
      _unsupported();

  Future<void> clearAllQuestions() async => _unsupported();
}
