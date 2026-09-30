import 'package:cloud_firestore/cloud_firestore.dart';

/// An announcement that new content landed — a new domain, subject, or a
/// batch of questions. Written by admin actions, read by users so they find
/// out something new is available without having to go looking.
class ContentUpdateModel {
  final String id;

  /// 'domain' | 'subject' | 'questions'
  final String kind;

  final String title;   // e.g. "New subject: Indian States"
  final String? detail; // e.g. "42 questions added under India"

  /// Where to send the user when they tap it (optional deep-link hints).
  final String? domainId;
  final String? subjectId;

  final DateTime? createdAt;

  ContentUpdateModel({
    required this.id,
    required this.kind,
    required this.title,
    this.detail,
    this.domainId,
    this.subjectId,
    this.createdAt,
  });

  factory ContentUpdateModel.fromMap(String id, Map<String, dynamic> m) =>
      ContentUpdateModel(
        id: id,
        kind: (m['kind'] ?? 'questions') as String,
        title: (m['title'] ?? '') as String,
        detail: m['detail'] as String?,
        domainId: m['domainId'] as String?,
        subjectId: m['subjectId'] as String?,
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toCreateMap() => {
        'kind': kind,
        'title': title,
        'detail': detail,
        'domainId': domainId,
        'subjectId': subjectId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
