import '../models/domain_model.dart';
import '../remote/firestore_service.dart';
import '../../core/constants/default_taxonomy.dart';

/// Result of a seeding run, so the UI can report exactly what happened.
class SeedResult {
  final int domainsCreated;
  final int subjectsAdded;
  final int domainsSkipped;
  final int subjectsSkipped;

  const SeedResult({
    this.domainsCreated = 0,
    this.subjectsAdded = 0,
    this.domainsSkipped = 0,
    this.subjectsSkipped = 0,
  });

  bool get changedNothing => domainsCreated == 0 && subjectsAdded == 0;

  String get summary {
    if (changedNothing) {
      return 'Everything was already there — nothing to add.';
    }
    final parts = <String>[];
    if (domainsCreated > 0) parts.add('$domainsCreated new domain(s)');
    if (subjectsAdded > 0) parts.add('$subjectsAdded new subject(s)');
    return 'Added ${parts.join(' and ')}, all hidden.';
  }
}

/// Creates the default content taxonomy in Firestore.
///
/// Deliberately conservative:
///  * Matches on slug id, so a domain/subject you already have is left
///    completely untouched — including its name, visibility, and questions.
///  * Only ever ADDS. Never renames, deletes, hides, or unhides anything
///    that already exists.
///  * Creates everything hidden (isActive: false) so users never see an
///    empty category. Unhide from Admin > Domains & Subjects as you add
///    questions.
///  * Safe to run repeatedly — a second run reports "nothing to add".
class TaxonomySeeder {
  final FirestoreService _fs;
  TaxonomySeeder(this._fs);

  /// Slug generator — must match the one used elsewhere in the admin UI so
  /// ids line up with anything created by hand.
  static String slugify(String input) {
    final lower = input.toLowerCase().trim();
    final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return replaced.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<SeedResult> seed() async {
    final existing = await _fs.fetchAllDomainsForAdmin();
    final byId = {for (final d in existing) d.id: d};

    var domainsCreated = 0;
    var subjectsAdded = 0;
    var domainsSkipped = 0;
    var subjectsSkipped = 0;

    for (final entry in DefaultTaxonomy.tree.entries) {
      final domainName = entry.key;
      final domainId = slugify(domainName);
      final subjectNames = entry.value;

      final current = byId[domainId];

      if (current == null) {
        // Brand new domain: create it with all its subjects, hidden.
        final subjects = [
          for (final s in subjectNames)
            SubjectModel(id: slugify(s), name: s, isActive: false),
        ];
        await _fs.createOrUpdateDomain(DomainModel(
          id: domainId,
          name: domainName,
          isActive: false,
          subjects: subjects,
        ));
        domainsCreated++;
        subjectsAdded += subjects.length;
      } else {
        // Domain exists — only append subjects it doesn't already have.
        // Everything about the existing domain is preserved as-is.
        final haveIds = current.subjects.map((s) => s.id).toSet();
        final toAdd = <SubjectModel>[];
        for (final s in subjectNames) {
          final sid = slugify(s);
          if (haveIds.contains(sid)) {
            subjectsSkipped++;
          } else {
            toAdd.add(SubjectModel(id: sid, name: s, isActive: false));
          }
        }
        domainsSkipped++;
        if (toAdd.isNotEmpty) {
          await _fs.createOrUpdateDomain(
            current.copyWith(subjects: [...current.subjects, ...toAdd]),
          );
          subjectsAdded += toAdd.length;
        }
      }
    }

    return SeedResult(
      domainsCreated: domainsCreated,
      subjectsAdded: subjectsAdded,
      domainsSkipped: domainsSkipped,
      subjectsSkipped: subjectsSkipped,
    );
  }
}
