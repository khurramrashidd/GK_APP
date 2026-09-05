import 'package:cloud_firestore/cloud_firestore.dart';

/// One captured crash/error, written best-effort whenever something goes
/// wrong for a user, so an admin can see it instead of it vanishing silently.
class ErrorLogModel {
  final String id;
  final String message;
  final String stackTrace;
  final String? userUid;
  final String? userEmail;
  final String platform; // android | ios | web | other
  final String appVersion;
  final String? context; // e.g. which screen/action, if known
  final DateTime? createdAt;

  ErrorLogModel({
    required this.id,
    required this.message,
    required this.stackTrace,
    this.userUid,
    this.userEmail,
    required this.platform,
    required this.appVersion,
    this.context,
    this.createdAt,
  });

  factory ErrorLogModel.fromMap(String id, Map<String, dynamic> m) =>
      ErrorLogModel(
        id: id,
        message: (m['message'] ?? '') as String,
        stackTrace: (m['stackTrace'] ?? '') as String,
        userUid: m['userUid'] as String?,
        userEmail: m['userEmail'] as String?,
        platform: (m['platform'] ?? 'other') as String,
        appVersion: (m['appVersion'] ?? '') as String,
        context: m['context'] as String?,
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toCreateMap() => {
        'message': message,
        // Cap the stack trace so one enormous trace can't blow past
        // Firestore's per-document size limit or clutter the dashboard.
        'stackTrace':
            stackTrace.length > 4000 ? stackTrace.substring(0, 4000) : stackTrace,
        'userUid': userUid,
        'userEmail': userEmail,
        'platform': platform,
        'appVersion': appVersion,
        'context': context,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
