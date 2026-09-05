import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1v1 quiz match. Both players answer the same set of questions;
/// scores are compared once both finish. No negative marking — straight
/// +2-per-correct, kept simple for a head-to-head format.
///
/// Lifecycle: 'waiting' (created, no opponent yet) -> 'active' (both players
/// present, playing) -> 'finished' (both submitted).
class MatchModel {
  final String id;
  final String status; // 'waiting' | 'active' | 'finished'
  final String inviteCode;

  final String domainId;
  final String domainName;
  final String subjectId;
  final String subjectName;
  final String? subLevelId;
  final String? subLevelName;

  final List<String> questionIds;

  final String player1Uid;
  final String player1Name;
  final String? player2Uid;
  final String? player2Name;

  /// questionId -> chosen option index, per player.
  final Map<String, int> player1Answers;
  final Map<String, int> player2Answers;

  final bool player1Finished;
  final bool player2Finished;
  final int player1Score;
  final int player2Score;

  final DateTime? createdAt;

  MatchModel({
    required this.id,
    required this.status,
    required this.inviteCode,
    required this.domainId,
    required this.domainName,
    required this.subjectId,
    required this.subjectName,
    this.subLevelId,
    this.subLevelName,
    required this.questionIds,
    required this.player1Uid,
    required this.player1Name,
    this.player2Uid,
    this.player2Name,
    this.player1Answers = const {},
    this.player2Answers = const {},
    this.player1Finished = false,
    this.player2Finished = false,
    this.player1Score = 0,
    this.player2Score = 0,
    this.createdAt,
  });

  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';
  bool get bothFinished => player1Finished && player2Finished;

  /// Which player slot [uid] occupies, or null if they're not in this match.
  int? slotFor(String uid) {
    if (uid == player1Uid) return 1;
    if (uid == player2Uid) return 2;
    return null;
  }

  factory MatchModel.fromMap(String id, Map<String, dynamic> m) {
    Map<String, int> toIntMap(dynamic v) => v == null
        ? {}
        : Map<String, int>.from((v as Map).map((k, val) => MapEntry(k as String, val as int)));
    return MatchModel(
      id: id,
      status: (m['status'] ?? 'waiting') as String,
      inviteCode: (m['inviteCode'] ?? '') as String,
      domainId: (m['domainId'] ?? '') as String,
      domainName: (m['domainName'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      subLevelId: m['subLevelId'] as String?,
      subLevelName: m['subLevelName'] as String?,
      questionIds: List<String>.from(m['questionIds'] ?? const []),
      player1Uid: (m['player1Uid'] ?? '') as String,
      player1Name: (m['player1Name'] ?? '') as String,
      player2Uid: m['player2Uid'] as String?,
      player2Name: m['player2Name'] as String?,
      player1Answers: toIntMap(m['player1Answers']),
      player2Answers: toIntMap(m['player2Answers']),
      player1Finished: (m['player1Finished'] ?? false) as bool,
      player2Finished: (m['player2Finished'] ?? false) as bool,
      player1Score: (m['player1Score'] ?? 0) as int,
      player2Score: (m['player2Score'] ?? 0) as int,
      createdAt: m['createdAt'] is Timestamp
          ? (m['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'status': 'waiting',
        'inviteCode': inviteCode,
        'domainId': domainId,
        'domainName': domainName,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'subLevelId': subLevelId,
        'subLevelName': subLevelName,
        'questionIds': questionIds,
        'player1Uid': player1Uid,
        'player1Name': player1Name,
        'player2Uid': null,
        'player2Name': null,
        'player1Answers': <String, int>{},
        'player2Answers': <String, int>{},
        'player1Finished': false,
        'player2Finished': false,
        'player1Score': 0,
        'player2Score': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
