import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's request for a new domain or subject to be added.
/// Lifecycle: 'open' -> 'accepted' | 'declined' -> (once built) 'added'.
class SuggestionModel {
  final String id;
  final String userUid;
  final String userName;
  final String userEmail;

  /// 'domain' or 'subject'
  final String kind;
  final String suggestedName;

  /// For a subject suggestion: which domain it should live under.
  final String? parentDomainName;
  final String? note;

  /// open | accepted | declined | added
  final String status;
  final String? adminResponse;

  /// Set true once the user has seen the outcome, so the badge can clear.
  final bool seenByUser;

  final DateTime? createdAt;

  SuggestionModel({
    required this.id,
    required this.userUid,
    required this.userName,
    required this.userEmail,
    required this.kind,
    required this.suggestedName,
    this.parentDomainName,
    this.note,
    this.status = 'open',
    this.adminResponse,
    this.seenByUser = false,
    this.createdAt,
  });

  bool get isOpen => status == 'open';
  bool get isResolved => status != 'open';

  factory SuggestionModel.fromMap(String id, Map<String, dynamic> m) =>
      SuggestionModel(
        id: id,
        userUid: (m['userUid'] ?? '') as String,
        userName: (m['userName'] ?? '') as String,
        userEmail: (m['userEmail'] ?? '') as String,
        kind: (m['kind'] ?? 'subject') as String,
        suggestedName: (m['suggestedName'] ?? '') as String,
        parentDomainName: m['parentDomainName'] as String?,
        note: m['note'] as String?,
        status: (m['status'] ?? 'open') as String,
        adminResponse: m['adminResponse'] as String?,
        seenByUser: (m['seenByUser'] ?? false) as bool,
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toCreateMap() => {
        'userUid': userUid,
        'userName': userName,
        'userEmail': userEmail,
        'kind': kind,
        'suggestedName': suggestedName,
        'parentDomainName': parentDomainName,
        'note': note,
        'status': 'open',
        'adminResponse': null,
        'seenByUser': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
