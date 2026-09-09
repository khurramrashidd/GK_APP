import 'package:cloud_firestore/cloud_firestore.dart';

/// A soft-deleted item held in the admin recycle bin.
///
/// Stores the deleted thing as a raw JSON snapshot rather than a typed field,
/// so one collection can hold domains, subjects and sub-levels without three
/// parallel schemas. Restoring re-creates it from that snapshot.
class RecycleBinItem {
  final String id;

  /// 'domain' | 'subject' | 'subLevel'
  final String type;

  /// Human-readable name, for the list.
  final String name;

  /// Where it came from, so it can be put back in the right place.
  final String? parentDomainId;
  final String? parentDomainName;
  final String? parentSubjectId;
  final String? parentSubjectName;

  /// Full snapshot of the deleted item (DomainModel/SubjectModel/SubLevelModel
  /// toMap output).
  final Map<String, dynamic> payload;

  final String? deletedByEmail;
  final DateTime? deletedAt;

  RecycleBinItem({
    required this.id,
    required this.type,
    required this.name,
    this.parentDomainId,
    this.parentDomainName,
    this.parentSubjectId,
    this.parentSubjectName,
    required this.payload,
    this.deletedByEmail,
    this.deletedAt,
  });

  /// Where this item lived, for display.
  String get locationLabel {
    switch (type) {
      case 'domain':
        return 'Domain';
      case 'subject':
        return 'Subject in ${parentDomainName ?? '?'}';
      case 'subLevel':
        return 'Topic in ${parentDomainName ?? '?'} > '
            '${parentSubjectName ?? '?'}';
      default:
        return type;
    }
  }

  factory RecycleBinItem.fromMap(String id, Map<String, dynamic> m) =>
      RecycleBinItem(
        id: id,
        type: (m['type'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        parentDomainId: m['parentDomainId'] as String?,
        parentDomainName: m['parentDomainName'] as String?,
        parentSubjectId: m['parentSubjectId'] as String?,
        parentSubjectName: m['parentSubjectName'] as String?,
        payload: Map<String, dynamic>.from(m['payload'] ?? const {}),
        deletedByEmail: m['deletedByEmail'] as String?,
        deletedAt: m['deletedAt'] is Timestamp
            ? (m['deletedAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toCreateMap() => {
        'type': type,
        'name': name,
        'parentDomainId': parentDomainId,
        'parentDomainName': parentDomainName,
        'parentSubjectId': parentSubjectId,
        'parentSubjectName': parentSubjectName,
        'payload': payload,
        'deletedByEmail': deletedByEmail,
        'deletedAt': FieldValue.serverTimestamp(),
      };
}
