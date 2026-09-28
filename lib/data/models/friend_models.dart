import 'package:cloud_firestore/cloud_firestore.dart';

/// A confirmed friend, stored at users/{uid}/friends/{friendUid}.
///
/// Denormalised on purpose: the username and name are copied in so the
/// friends list renders from ONE subcollection read instead of one profile
/// read per friend. With a 50k/day free-tier budget that difference matters.
/// The trade-off is a stale display name if they rename — acceptable, and
/// refreshed whenever their profile is opened.
class FriendModel {
  final String uid;
  final String username;
  final String displayName;
  final DateTime? since;

  /// Lightweight activity, refreshed when the friends list is opened.
  final int totalScore;
  final int questionsAnswered;
  final int currentStreak;

  FriendModel({
    required this.uid,
    required this.username,
    required this.displayName,
    this.since,
    this.totalScore = 0,
    this.questionsAnswered = 0,
    this.currentStreak = 0,
  });

  factory FriendModel.fromMap(String id, Map<String, dynamic> m) => FriendModel(
        uid: id,
        username: (m['username'] ?? '') as String,
        displayName: (m['displayName'] ?? '') as String,
        since: m['since'] is Timestamp ? (m['since'] as Timestamp).toDate() : null,
        totalScore: (m['totalScore'] as num?)?.toInt() ?? 0,
        questionsAnswered: (m['questionsAnswered'] as num?)?.toInt() ?? 0,
        currentStreak: (m['currentStreak'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'username': username,
        'displayName': displayName,
        'since': since == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(since!),
        'totalScore': totalScore,
        'questionsAnswered': questionsAnswered,
        'currentStreak': currentStreak,
      };
}

/// A pending request, stored at users/{toUid}/friend_requests/{fromUid}.
/// Keyed by sender uid so the same person can't queue duplicate requests.
class FriendRequestModel {
  final String fromUid;
  final String fromUsername;
  final String fromName;
  final DateTime? createdAt;

  FriendRequestModel({
    required this.fromUid,
    required this.fromUsername,
    required this.fromName,
    this.createdAt,
  });

  factory FriendRequestModel.fromMap(String id, Map<String, dynamic> m) =>
      FriendRequestModel(
        fromUid: id,
        fromUsername: (m['fromUsername'] ?? '') as String,
        fromName: (m['fromName'] ?? '') as String,
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toCreateMap() => {
        'fromUsername': fromUsername,
        'fromName': fromName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
