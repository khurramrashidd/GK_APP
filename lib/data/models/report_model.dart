import 'package:cloud_firestore/cloud_firestore.dart';

/// A user-submitted report that something about a question is wrong.
///
/// Stored in the `reports` collection. `seenByReporter` is how the in-app
/// notification badge works: it's reset to false whenever an admin resolves
/// a report, and set back to true once the reporter has viewed it on their
/// "My Reports" screen.
class ReportModel {
  final String id;

  // Snapshot of the question at report time, so it's still readable even if
  // the question is later edited or deleted.
  final String questionId;
  final String questionText;
  final String domainId;
  final String domainName;
  final String subjectId;
  final String subjectName;
  final String? subLevelId;
  final String? subLevelName;

  final String reportedByUid;
  final String reporterName;
  final String reporterEmail;

  final String reason;
  final String note;

  final String status; // 'open' | 'resolved'
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final bool seenByReporter;

  static const List<String> reasons = [
    'Wrong answer marked correct',
    'Question or option has a typo',
    'Question is unclear or ambiguous',
    'Duplicate question',
    'Other',
  ];

  ReportModel({
    required this.id,
    required this.questionId,
    required this.questionText,
    required this.domainId,
    required this.domainName,
    required this.subjectId,
    required this.subjectName,
    this.subLevelId,
    this.subLevelName,
    required this.reportedByUid,
    required this.reporterName,
    required this.reporterEmail,
    required this.reason,
    this.note = '',
    this.status = 'open',
    this.createdAt,
    this.resolvedAt,
    this.resolutionNote,
    this.seenByReporter = false,
  });

  bool get isOpen => status == 'open';
  bool get isResolved => status == 'resolved';

  factory ReportModel.fromMap(String id, Map<String, dynamic> m) {
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return ReportModel(
      id: id,
      questionId: (m['questionId'] ?? '') as String,
      questionText: (m['questionText'] ?? '') as String,
      domainId: (m['domainId'] ?? '') as String,
      domainName: (m['domainName'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      subLevelId: m['subLevelId'] as String?,
      subLevelName: m['subLevelName'] as String?,
      reportedByUid: (m['reportedByUid'] ?? '') as String,
      reporterName: (m['reporterName'] ?? '') as String,
      reporterEmail: (m['reporterEmail'] ?? '') as String,
      reason: (m['reason'] ?? '') as String,
      note: (m['note'] ?? '') as String,
      status: (m['status'] ?? 'open') as String,
      createdAt: toDate(m['createdAt']),
      resolvedAt: toDate(m['resolvedAt']),
      resolutionNote: m['resolutionNote'] as String?,
      seenByReporter: (m['seenByReporter'] ?? false) as bool,
    );
  }

  /// Fields sent when creating a new report. `id` is assigned by Firestore.
  Map<String, dynamic> toCreateMap() => {
        'questionId': questionId,
        'questionText': questionText,
        'domainId': domainId,
        'domainName': domainName,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'subLevelId': subLevelId,
        'subLevelName': subLevelName,
        'reportedByUid': reportedByUid,
        'reporterName': reporterName,
        'reporterEmail': reporterEmail,
        'reason': reason,
        'note': note,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'seenByReporter': false,
      };
}
