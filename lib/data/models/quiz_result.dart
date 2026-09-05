import 'package:cloud_firestore/cloud_firestore.dart';

/// One completed quiz, stored at users/{uid}/history/{autoId} for the
/// history + accuracy-stats feature.
class QuizResult {
  final String id;
  final String domainName;
  final String subjectName;
  final String? subLevelName;
  final int total;
  final int correct;
  final int wrong;
  final int skipped;
  final double score;
  final bool negativeMarking;
  final DateTime? takenAt;

  QuizResult({
    required this.id,
    required this.domainName,
    required this.subjectName,
    this.subLevelName,
    required this.total,
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.score,
    required this.negativeMarking,
    this.takenAt,
  });

  double get accuracy => total == 0 ? 0 : correct / total;

  factory QuizResult.fromMap(String id, Map<String, dynamic> m) {
    return QuizResult(
      id: id,
      domainName: (m['domainName'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      subLevelName: m['subLevelName'] as String?,
      total: (m['total'] ?? 0) as int,
      correct: (m['correct'] ?? 0) as int,
      wrong: (m['wrong'] ?? 0) as int,
      skipped: (m['skipped'] ?? 0) as int,
      score: ((m['score'] ?? 0) as num).toDouble(),
      negativeMarking: (m['negativeMarking'] ?? false) as bool,
      takenAt: m['takenAt'] is Timestamp
          ? (m['takenAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'domainName': domainName,
        'subjectName': subjectName,
        'subLevelName': subLevelName,
        'total': total,
        'correct': correct,
        'wrong': wrong,
        'skipped': skipped,
        'score': score,
        'negativeMarking': negativeMarking,
        'takenAt': FieldValue.serverTimestamp(),
      };
}
