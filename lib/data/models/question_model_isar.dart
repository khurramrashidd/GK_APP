import 'package:isar/isar.dart';

part 'question_model_isar.g.dart';

/// A single quiz question, cached locally in Isar and mirrored in Firestore.
///
/// After editing this file you MUST regenerate the Isar adapter:
///   flutter pub run build_runner build --delete-conflicting-outputs
@collection
class QuestionModel {
  Id localId = Isar.autoIncrement;

  /// Stable Firestore document id (also the logical question id).
  @Index()
  late String id;

  /// Domain (e.g. "SSC CGL").
  @Index()
  late String domainId;
  late String domainName;

  /// Subject within the domain (e.g. "Ancient History").
  @Index()
  late String subjectId;
  late String subjectName;

  /// Optional third tier (e.g. a "Topic" or "Month" — admin-labeled per
  /// domain). Null when this question attaches directly to the subject,
  /// which is the original/default behavior.
  @Index()
  String? subLevelId;
  String? subLevelName;

  late int difficulty; // 1 = easy, 2 = medium, 3 = hard

  late String question;

  late List<String> options;

  late int correctOptionIndex;

  /// Short factual explanation authored with the question.
  late String explanation;

  /// Long AI-generated concept explanation (cached globally). Null until first
  /// time any user taps "Deep Review with AI" for this question.
  String? aiExplanation;

  late bool isActive;

  late List<String> tags;

  /// Per-domain content version at which this question was added/updated.
  /// Used by the delta-sync to fetch only new/changed questions.
  late int version;

  QuestionModel();

  /// Build from a Firestore document map.
  factory QuestionModel.fromMap(Map<String, dynamic> data, {String? docId}) {
    return QuestionModel()
      ..id = (data['id'] ?? docId ?? '') as String
      ..domainId = (data['domainId'] ?? '') as String
      ..domainName = (data['domainName'] ?? '') as String
      ..subjectId = (data['subjectId'] ?? '') as String
      ..subjectName = (data['subjectName'] ?? '') as String
      ..subLevelId = data['subLevelId'] as String?
      ..subLevelName = data['subLevelName'] as String?
      ..difficulty = (data['difficulty'] ?? 1) as int
      ..question = (data['question'] ?? '') as String
      ..options = List<String>.from(data['options'] ?? const [])
      ..correctOptionIndex = (data['correctOptionIndex'] ?? 0) as int
      ..explanation = (data['explanation'] ?? '') as String
      ..aiExplanation = data['aiExplanation'] as String?
      ..isActive = (data['isActive'] ?? true) as bool
      ..tags = List<String>.from(data['tags'] ?? const [])
      ..version = (data['version'] ?? 1) as int;
  }
}
