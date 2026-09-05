import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/question_model.dart';

/// Local offline cache. Questions are stored per-domain and upserted by their
/// stable string `id` so repeated delta-syncs never create duplicates.
class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = openDB();
  }

  Future<Isar> openDB() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      return await Isar.open(
        [QuestionModelSchema],
        directory: dir.path,
        inspector: true,
      );
    }
    return Isar.getInstance()!;
  }

  /// Upsert a batch of questions, matching existing rows by their string `id`
  /// so that updates overwrite instead of creating duplicates.
  Future<void> upsertQuestions(List<QuestionModel> incoming) async {
    if (incoming.isEmpty) return;
    final isar = await db;

    // Group by domain so we only load the existing rows we might collide with.
    final domainIds = incoming.map((q) => q.domainId).toSet();
    final Map<String, int> idToLocal = {};
    for (final d in domainIds) {
      final existing =
          await isar.questionModels.filter().domainIdEqualTo(d).findAll();
      for (final q in existing) {
        idToLocal[q.id] = q.localId;
      }
    }

    for (final q in incoming) {
      final localId = idToLocal[q.id];
      if (localId != null) q.localId = localId;
    }

    await isar.writeTxn(() async {
      await isar.questionModels.putAll(incoming);
    });
  }

  /// All active questions for a domain+subject, optionally narrowed to one
  /// sub-level. When [subLevelId] is null, returns only questions attached
  /// directly to the subject (i.e. subLevelId is null on the question too) —
  /// this keeps direct-to-subject and sub-level questions cleanly separated.
  Future<List<QuestionModel>> getQuestions(String domainId, String subjectId,
      {String? subLevelId}) async {
    final isar = await db;
    if (subLevelId != null) {
      return await isar.questionModels
          .filter()
          .domainIdEqualTo(domainId)
          .subjectIdEqualTo(subjectId)
          .subLevelIdEqualTo(subLevelId)
          .isActiveEqualTo(true)
          .findAll();
    }
    return await isar.questionModels
        .filter()
        .domainIdEqualTo(domainId)
        .subjectIdEqualTo(subjectId)
        .subLevelIdIsNull()
        .isActiveEqualTo(true)
        .findAll();
  }

  /// How many questions of a domain are already cached (to know if first-open).
  Future<int> countForDomain(String domainId) async {
    final isar = await db;
    return await isar.questionModels.filter().domainIdEqualTo(domainId).count();
  }

  /// Persist an AI explanation locally for a single question.
  Future<void> setAiExplanation(String questionId, String aiText) async {
    final isar = await db;
    final rows =
        await isar.questionModels.filter().idEqualTo(questionId).findAll();
    if (rows.isEmpty) return;
    await isar.writeTxn(() async {
      for (final r in rows) {
        r.aiExplanation = aiText;
        await isar.questionModels.put(r);
      }
    });
  }

  Future<void> clearAllQuestions() async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.questionModels.clear();
    });
  }
}
