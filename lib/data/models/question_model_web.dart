/// A single quiz question — WEB VARIANT.
///
/// Same public shape as question_model_isar.dart (which is what's actually
/// used on mobile) but with no Isar import, no @collection, no local-id
/// field — because Isar's classic package (v3, FFI-based) cannot compile for
/// web at all, not even just "not run": dart:ffi doesn't exist there.
///
/// question_model.dart picks between this file and question_model_isar.dart
/// automatically at compile time (see that file's conditional export). The
/// web build only ever reaches Firestore-direct code (admin screens), so a
/// plain data holder with the same fields and the same fromMap is all it
/// needs — nothing on web ever caches a question locally.
///
/// Keep this in sync with question_model_isar.dart's public fields and
/// fromMap logic whenever you change one.
class QuestionModel {
  late String id;

  late String domainId;
  late String domainName;

  late String subjectId;
  late String subjectName;

  String? subLevelId;
  String? subLevelName;

  late int difficulty;

  late String question;
  late List<String> options;
  late int correctOptionIndex;
  late String explanation;
  String? aiExplanation;

  late bool isActive;
  late List<String> tags;
  late int version;

  QuestionModel();

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
