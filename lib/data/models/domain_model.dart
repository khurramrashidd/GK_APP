/// A leaf-level nested group inside a subject (e.g. a "Topic" or "Month" —
/// the label itself is admin-defined per domain, see [DomainModel.subLevelLabel]).
/// A subject that has no sub-levels behaves exactly as before: its questions
/// are attached directly to it.
class SubLevelModel {
  final String id;
  final String name;
  // Unused for display — everything now sorts alphabetically by name.
  // Kept only so existing Firestore documents don't need a migration.
  final int order;
  final bool isActive;

  SubLevelModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.isActive = true,
  });

  factory SubLevelModel.fromMap(Map<String, dynamic> m) => SubLevelModel(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        order: (m['order'] ?? 0) as int,
        isActive: (m['isActive'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'order': order, 'isActive': isActive};

  SubLevelModel copyWith({String? name, int? order, bool? isActive}) =>
      SubLevelModel(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        isActive: isActive ?? this.isActive,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SubLevelModel && other.id == id);
  @override
  int get hashCode => id.hashCode;
}

/// A subject inside a domain. If [subLevels] is empty, questions attach
/// directly to the subject (original, simplest behavior). If it's non-empty,
/// the subject is a "branch": questions attach to one of its sub-levels
/// instead, and browsing shows the sub-level list before quiz start.
class SubjectModel {
  final String id;
  final String name;
  // Unused for display — everything now sorts alphabetically by name.
  // Kept only so existing Firestore documents don't need a migration.
  final int order;
  final bool isActive;

  /// When true, this subject draws from a SHARED question pool keyed on its
  /// id (the slugified name), rather than being scoped to this one domain.
  /// So "History" marked shared under UPSC and under Academics both show the
  /// same questions — and their sub-levels are merged into one combined list.
  /// Opt-in per subject: same-named subjects stay separate unless BOTH are
  /// marked shared.
  final bool isShared;

  final List<SubLevelModel> subLevels;

  SubjectModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.isActive = true,
    this.isShared = false,
    this.subLevels = const [],
  });

  factory SubjectModel.fromMap(Map<String, dynamic> m) {
    final rawLevels = (m['subLevels'] as List?) ?? const [];
    return SubjectModel(
      id: (m['id'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      order: (m['order'] ?? 0) as int,
      isActive: (m['isActive'] ?? true) as bool,
      isShared: (m['isShared'] ?? false) as bool,
      subLevels: rawLevels
          .map((e) => SubLevelModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'order': order,
        'isActive': isActive,
        'isShared': isShared,
        'subLevels': subLevels.map((s) => s.toMap()).toList(),
      };

  SubjectModel copyWith({
    String? name,
    int? order,
    bool? isActive,
    bool? isShared,
    List<SubLevelModel>? subLevels,
  }) =>
      SubjectModel(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        isActive: isActive ?? this.isActive,
        isShared: isShared ?? this.isShared,
        subLevels: subLevels ?? this.subLevels,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SubjectModel && other.id == id);
  @override
  int get hashCode => id.hashCode;
}

/// A domain (e.g. "SSC CGL") with its list of subjects.
///
/// [subLevelLabel] is the admin-chosen name for the optional third tier
/// within this domain's subjects (e.g. "Topic", "Month", "Chapter"). It's
/// domain-wide so every subject in the same domain uses consistent wording.
/// Null/empty until the admin adds the first sub-level under this domain.
class DomainModel {
  final String id;
  final String name;
  // Unused for display — everything now sorts alphabetically by name.
  // Kept only so existing Firestore documents don't need a migration.
  final int order;
  final bool isActive;
  final int version;
  final String? subLevelLabel;
  final List<SubjectModel> subjects;

  DomainModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.isActive = true,
    this.version = 1,
    this.subLevelLabel,
    this.subjects = const [],
  });

  factory DomainModel.fromMap(Map<String, dynamic> m, {String? docId}) {
    final rawSubjects = (m['subjects'] as List?) ?? const [];
    return DomainModel(
      id: (m['id'] ?? docId ?? '') as String,
      name: (m['name'] ?? '') as String,
      order: (m['order'] ?? 0) as int,
      isActive: (m['isActive'] ?? true) as bool,
      version: (m['version'] ?? 1) as int,
      subLevelLabel: m['subLevelLabel'] as String?,
      subjects: rawSubjects
          .map((e) => SubjectModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'order': order,
        'isActive': isActive,
        'version': version,
        'subLevelLabel': subLevelLabel,
        'subjects': subjects.map((s) => s.toMap()).toList(),
      };

  DomainModel copyWith({
    String? name,
    int? order,
    bool? isActive,
    int? version,
    String? subLevelLabel,
    List<SubjectModel>? subjects,
  }) =>
      DomainModel(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        isActive: isActive ?? this.isActive,
        version: version ?? this.version,
        subLevelLabel: subLevelLabel ?? this.subLevelLabel,
        subjects: subjects ?? this.subjects,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DomainModel && other.id == id);
  @override
  int get hashCode => id.hashCode;
}
