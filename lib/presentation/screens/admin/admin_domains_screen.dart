import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/domain_model.dart';
import '../../../data/models/recycle_bin_model.dart';
import '../../../data/models/content_update_model.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';

String slugify(String input) {
  final s = input
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '-');
  return s.isEmpty ? 'item' : s;
}

class AdminDomainsScreen extends ConsumerStatefulWidget {
  const AdminDomainsScreen({super.key});

  @override
  ConsumerState<AdminDomainsScreen> createState() => _AdminDomainsScreenState();
}

class _AdminDomainsScreenState extends ConsumerState<AdminDomainsScreen> {
  bool _busy = false;

  // Which domains the admin has expanded — subject-level question counts
  // only fetch once a domain is actually opened, so opening this screen
  // doesn't fire a burst of hundreds of count queries at once (one per
  // subject across every domain). Domain-level counts are cheap enough
  // (one per domain, ~30 total) to always fetch eagerly.
  final Set<String> _expandedDomains = {};

  /// Question counts are OFF by default. Each count is a Firestore
  /// aggregation query = one billed read; with ~30 domains that's 30 reads
  /// every time this screen opens, plus one per subject once expanded. On
  /// the Spark free tier that adds up fast, and it was a real contributor to
  /// hitting the daily quota. Turn it on when you actually want the numbers.
  bool _showCounts = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------- Dialog helpers ----------------------------

  Future<String?> _promptText({
    required String title,
    String initial = '',
    String hint = '',
    String? helperText,
    String confirmLabel = 'Save',
    int maxLines = 1,
  }) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: maxLines,
              minLines: maxLines > 1 ? 3 : 1,
              decoration: InputDecoration(
                hintText: hint,
                border: maxLines > 1 ? const OutlineInputBorder() : null,
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(height: 8),
              Text(helperText,
                  style: Theme.of(ctx).textTheme.bodySmall,
                  textAlign: TextAlign.start),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(confirmLabel)),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message,
      {String confirmLabel = 'Confirm', bool danger = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --------------------------------- Persist ----------------------------------

  Future<void> _persist(DomainModel domain) async {
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).createOrUpdateDomain(domain);
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ================================ DOMAIN actions ============================

  Future<void> _createDomain() async {
    final name = await _promptText(
        title: 'New domain', hint: 'e.g. SSC CGL', confirmLabel: 'Create');
    if (name == null || name.isEmpty) return;

    // Warn about an existing domain with a similar name before creating a
    // near-duplicate ("World Geography" vs "world geography").
    final all = ref.read(adminDomainsStreamProvider).valueOrNull ?? const [];
    final clash = all.where((d) => _similarName(d.name, name)).toList();
    if (clash.isNotEmpty) {
      final proceed = await _confirm(
        'Similar domain already exists',
        'Found: ${clash.map((d) => '"${d.name}"').join(', ')}.\n\n'
            'Create "$name" anyway?',
        confirmLabel: 'Create anyway',
      );
      if (!proceed) return;
    }
    await _persist(DomainModel(id: slugify(name), name: name));
    await _announce('domain', 'New category: $name',
        domainId: slugify(name));
    _snack('Domain "$name" created.');
  }

  /// Loose name comparison for duplicate detection: case-insensitive, and
  /// ignores punctuation/spacing so "Art & Culture", "art and culture" and
  /// "ArtCulture" are all treated as candidates worth warning about.
  bool _similarName(String a, String b) {
    String norm(String x) => x
        .toLowerCase()
        .replaceAll(RegExp(r'\b(and|the|of|in)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(a) == norm(b);
  }

  Future<void> _renameDomain(DomainModel d) async {
    final name = await _promptText(title: 'Rename domain', initial: d.name);
    if (name == null || name.isEmpty || name == d.name) return;
    await _persist(d.copyWith(name: name));
  }

  Future<void> _toggleDomainActive(DomainModel d) async {
    if (d.isActive) {
      final ok = await _confirm(
        'Hide "${d.name}"?',
        'It disappears from every user\'s home screen immediately. All its '
            'subjects and questions stay exactly as they are — unhide it any '
            'time from here.',
        confirmLabel: 'Hide',
      );
      if (!ok) return;
    }
    await _persist(d.copyWith(isActive: !d.isActive));
  }

  /// Shows/hides every domain in one action — the whole app's category list.
  Future<void> _bulkSetDomainsActive(
      List<DomainModel> domains, bool active) async {
    final verb = active ? 'Show' : 'Hide';
    final ok = await _confirm(
      '$verb all ${domains.length} domains?',
      active
          ? 'Every domain becomes visible to users. Subjects inside each '
              'domain keep whatever visibility they already have.'
          : 'Every domain disappears from users\' home screens at once. '
              'Nothing is deleted — unhide any of them any time.',
      confirmLabel: verb,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      for (final d in domains) {
        if (d.isActive != active) {
          await fs.createOrUpdateDomain(d.copyWith(isActive: active));
        }
      }
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
    } catch (e) {
      _snack('Bulk update failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows/hides every SUBJECT across every domain, leaving domain-level
  /// visibility untouched. A hidden domain with visible subjects still shows
  /// nothing to users (the domain gate comes first) — this just controls
  /// what's revealed if/when a domain is shown.
  Future<void> _bulkSetAllSubjectsActive(
      List<DomainModel> domains, bool active) async {
    final totalSubjects =
        domains.fold<int>(0, (sum, d) => sum + d.subjects.length);
    final verb = active ? 'Show' : 'Hide';
    final ok = await _confirm(
      '$verb every subject in all domains?',
      'This changes all $totalSubjects subjects across every domain at '
          'once. Domain-level visibility is not affected. This cannot be '
          'undone in bulk — you would need to unhide subjects one by one.',
      confirmLabel: verb,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      for (final d in domains) {
        final needsUpdate = d.subjects.any((s) => s.isActive != active);
        if (!needsUpdate) continue;
        final updatedSubjects =
            d.subjects.map((s) => s.copyWith(isActive: active)).toList();
        await fs.createOrUpdateDomain(d.copyWith(subjects: updatedSubjects));
      }
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
    } catch (e) {
      _snack('Bulk update failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows/hides every subject WITHIN one domain only.
  Future<void> _bulkSetDomainSubjectsActive(DomainModel d, bool active) async {
    final verb = active ? 'Show' : 'Hide';
    final ok = await _confirm(
      '$verb all ${d.subjects.length} subjects in "${d.name}"?',
      active
          ? 'Every subject in this domain becomes visible (subject to the '
              'domain itself being visible).'
          : 'Every subject in this domain disappears from users at once. '
              'Unhide any of them individually any time.',
      confirmLabel: verb,
    );
    if (!ok) return;
    final updated =
        d.subjects.map((s) => s.copyWith(isActive: active)).toList();
    await _persist(d.copyWith(subjects: updated));
  }

  Future<void> _setSubLevelLabel(DomainModel d) async {
    final label = await _promptText(
      title: 'Nesting level name',
      initial: d.subLevelLabel ?? '',
      hint: 'e.g. Topic, Month, Chapter',
      helperText:
          'What the third tier is called for every subject in "${d.name}".',
    );
    if (label == null) return;
    await _persist(d.copyWith(subLevelLabel: label));
  }

  /// Snapshots an item into the recycle bin before it's removed, so a
  /// mistaken delete can be undone. Failure here aborts the delete — losing
  /// the item without a backup is worse than not deleting it.
  /// Posts a "what's new" entry so users find out content was added.
  /// Best-effort: an announcement failing must never block the actual
  /// content change that just succeeded.
  Future<void> _announce(String kind, String title,
      {String? detail, String? domainId, String? subjectId}) async {
    try {
      await ref.read(firestoreServiceProvider).postContentUpdate(
            ContentUpdateModel(
              id: '',
              kind: kind,
              title: title,
              detail: detail,
              domainId: domainId,
              subjectId: subjectId,
            ),
          );
    } catch (_) {
      // Silent: the domain/subject was still created successfully.
    }
  }

  Future<bool> _sendToRecycleBin({
    required String type,
    required String name,
    required Map<String, dynamic> payload,
    String? parentDomainId,
    String? parentDomainName,
    String? parentSubjectId,
    String? parentSubjectName,
  }) async {
    try {
      final me = ref.read(profileProvider)?.email;
      await ref.read(firestoreServiceProvider).addToRecycleBin(RecycleBinItem(
            id: '',
            type: type,
            name: name,
            parentDomainId: parentDomainId,
            parentDomainName: parentDomainName,
            parentSubjectId: parentSubjectId,
            parentSubjectName: parentSubjectName,
            payload: payload,
            deletedByEmail: me,
          ));
      return true;
    } catch (e) {
      _snack('Could not back up before deleting: $e');
      return false;
    }
  }

  Future<void> _deleteDomain(DomainModel d) async {
    setState(() => _busy = true);
    final count = await ref
        .read(firestoreServiceProvider)
        .countQuestions(domainId: d.id);
    setState(() => _busy = false);

    if (count > 0) {
      _snack('"${d.name}" still has $count question(s) — hide it instead, '
          'or remove its questions first.');
      return;
    }
    final ok = await _confirm('Delete "${d.name}"?',
        'It has no questions. A copy goes to the recycle bin, so you can '
            'restore it if this was a mistake.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

    setState(() => _busy = true);
    try {
      if (!await _sendToRecycleBin(
          type: 'domain', name: d.name, payload: d.toMap())) {
        return;
      }
      await ref.read(firestoreServiceProvider).deleteDomainDoc(d.id);
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
      _snack('"${d.name}" deleted.');
    } catch (e) {
      _snack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =============================== SUBJECT actions ============================

  SubjectModel _findSubject(DomainModel d, String subjectId) =>
      d.subjects.firstWhere((s) => s.id == subjectId);

  List<SubjectModel> _replaceSubject(DomainModel d, SubjectModel updated) =>
      d.subjects.map((s) => s.id == updated.id ? updated : s).toList();

  Future<void> _addSubject(DomainModel d) async {
    final name = await _promptText(
        title: 'Add subject to ${d.name}',
        hint: 'e.g. Ancient History',
        confirmLabel: 'Add');
    if (name == null || name.isEmpty) return;
    final newSubject =
        SubjectModel(id: slugify(name), name: name, order: d.subjects.length);
    if (d.subjects.any((s) => s.id == newSubject.id)) {
      _snack('That subject already exists in this domain.');
      return;
    }

    // Check EVERY domain, not just this one — the same subject existing
    // elsewhere is usually worth knowing about (and may be a candidate for
    // the shared-subject feature instead of a second copy).
    final all = ref.read(adminDomainsStreamProvider).valueOrNull ?? const [];
    final elsewhere = <String>[];
    for (final other in all) {
      for (final os in other.subjects) {
        if (_similarName(os.name, name)) {
          elsewhere.add('${other.name} > ${os.name}');
        }
      }
    }
    if (elsewhere.isNotEmpty) {
      final proceed = await _confirm(
        'This subject already exists elsewhere',
        'Found in:\n${elsewhere.map((e) => '  • $e').join('\n')}\n\n'
            'Tip: if it should share the same questions, use "Share across '
            'domains" on both instead of creating a separate copy.\n\n'
            'Create "$name" here anyway?',
        confirmLabel: 'Create anyway',
      );
      if (!proceed) return;
    }
    await _persist(d.copyWith(subjects: [...d.subjects, newSubject]));
    _snack('Subject "$name" added.');
  }

  Future<void> _renameSubject(DomainModel d, SubjectModel s) async {
    final name = await _promptText(title: 'Rename subject', initial: s.name);
    if (name == null || name.isEmpty || name == s.name) return;
    await _persist(
        d.copyWith(subjects: _replaceSubject(d, s.copyWith(name: name))));
  }

  Future<void> _toggleSubjectActive(DomainModel d, SubjectModel s) async {
    if (s.isActive) {
      final ok = await _confirm(
        'Hide "${s.name}"?',
        'It disappears from users immediately. Its data stays — unhide it '
            'any time from here.',
        confirmLabel: 'Hide',
      );
      if (!ok) return;
    }
    await _persist(d.copyWith(
        subjects: _replaceSubject(d, s.copyWith(isActive: !s.isActive))));
  }

  /// Marks a subject as drawing from (or leaving) the shared cross-domain
  /// question pool keyed on its id. Sharing is MUTUAL: turning it on here
  /// only merges with other domains that have also turned it on for the same
  /// subject id, so one domain can never pull in another's content
  /// unilaterally.
  Future<void> _toggleSubjectShared(DomainModel d, SubjectModel s) async {
    if (!s.isShared) {
      // Show which other domains have the same subject id, and which of them
      // are already sharing — so the admin knows exactly what will merge.
      final all = await ref.read(firestoreServiceProvider).fetchAllDomainsForAdmin();
      final sameId = [
        for (final other in all)
          if (other.id != d.id)
            for (final os in other.subjects)
              if (os.id == s.id) '${other.name}${os.isShared ? ' (already sharing)' : ''}',
      ]..sort();

      final body = StringBuffer()
        ..writeln('"${s.name}" will draw from one question pool shared with '
            'every other domain that also marks a subject "${s.id}" as shared.')
        ..writeln()
        ..writeln('Sub-levels from all sharing domains get merged into one '
            'combined list.');
      if (sameId.isEmpty) {
        body
          ..writeln()
          ..writeln('No other domain currently has a subject with this id, so '
              'nothing merges yet — but any that adds one later and shares it '
              'will join this pool.');
      } else {
        body
          ..writeln()
          ..writeln('Other domains with this subject id:')
          ..writeln(sameId.map((x) => '  • $x').join('\n'));
      }
      body
        ..writeln()
        ..writeln('Note: shared subjects load from the network and do not work '
            'offline, unlike normal subjects.');

      final ok = await _confirm(
        'Share "${s.name}" across domains?',
        body.toString(),
        confirmLabel: 'Share',
      );
      if (!ok) return;
    }
    await _persist(d.copyWith(
        subjects: _replaceSubject(d, s.copyWith(isShared: !s.isShared))));
    ref.invalidate(mergedSubLevelsProvider);
    ref.invalidate(domainsSharingSubjectProvider);
  }

  /// Adds/edits the summary a user sees before starting this subject's quiz.
  /// Leaving it empty removes the intro screen entirely for that subject.
  Future<void> _editSubjectDescription(DomainModel d, SubjectModel s) async {
    final text = await _promptText(
      title: 'Summary for "${s.name}"',
      initial: s.description ?? '',
      hint: 'e.g. The Nobel Prize is awarded annually in six categories...',
      helperText:
          'Shown before the quiz starts. Leave empty to skip the intro screen.',
      maxLines: 8,
    );
    if (text == null) return; // cancelled
    final cleaned = text.trim();
    await _persist(d.copyWith(
      subjects: _replaceSubject(
          d, s.copyWith(description: cleaned.isEmpty ? null : cleaned)),
    ));
    _snack(cleaned.isEmpty ? 'Summary removed.' : 'Summary saved.');
  }

  /// Moves or copies a subject (and its questions) into another domain.
  ///
  /// MOVE removes it from the source domain and repoints every question.
  /// COPY leaves the original intact and duplicates the questions under the
  /// target. Either way the admin sees the question count and write cost
  /// before committing, because questions store their domainId and each one
  /// genuinely has to be rewritten.
  Future<void> _moveOrCopySubject(DomainModel from, SubjectModel s) async {
    final all = ref.read(adminDomainsStreamProvider).valueOrNull ?? const [];
    final targets = all.where((d) => d.id != from.id).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (targets.isEmpty) {
      _snack('There is no other domain to move it to.');
      return;
    }

    // 1) Pick move vs copy.
    final copy = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move or copy "${s.name}"?'),
        content: const Text(
          'MOVE takes the subject and its questions out of this domain.\n\n'
          'COPY leaves everything here and creates a duplicate in the other '
          'domain.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Copy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Move')),
        ],
      ),
    );
    if (copy == null || !mounted) return;

    // 2) Pick the destination domain.
    final target = await showDialog<DomainModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${copy ? 'Copy' : 'Move'} "${s.name}" to...'),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: ListView.builder(
            itemCount: targets.length,
            itemBuilder: (_, i) {
              final t = targets[i];
              final clash = t.subjects.any((x) => x.id == s.id);
              return ListTile(
                title: Text(t.name),
                subtitle: Text(clash
                    ? 'Already has a subject with this id'
                    : '${t.subjects.length} subjects'),
                enabled: !clash,
                onTap: clash ? null : () => Navigator.pop(ctx, t),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (target == null || !mounted) return;

    // 3) Show the real cost, then confirm.
    setState(() => _busy = true);
    int qCount;
    try {
      qCount = await ref
          .read(firestoreServiceProvider)
          .countSubjectQuestionsInDomain(from.id, s.id);
    } catch (e) {
      _snack('Could not count questions: $e');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    // Build the message in pieces — nesting quotes inside a ${} interpolation
    // is legal Dart but hard to read and easy to get wrong.
    final verb = copy ? 'Copy' : 'Move';
    final verbed = copy ? 'copied to' : 'moved to';
    final batchNote = qCount > 500
        ? '\n\nOnly the first 500 are handled per run — repeat the action '
            'to continue.'
        : '';

    final ok = await _confirm(
      '$verb $qCount question(s)?',
      '"${s.name}" will be $verbed "${target.name}".\n\n'
          'This rewrites $qCount question document(s), which counts against '
          'your Firebase daily write quota.$batchNote',
      confirmLabel: verb,
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      final newVersion = target.version + 1;

      final written = await fs.moveOrCopySubjectQuestions(
        fromDomainId: from.id,
        toDomainId: target.id,
        toDomainName: target.name,
        subjectId: s.id,
        copy: copy,
        newVersion: newVersion,
      );

      // Add the subject entry to the target domain.
      await fs.createOrUpdateDomain(target.copyWith(
        version: newVersion,
        subjects: [...target.subjects, s],
      ));

      // On a move, drop it from the source.
      if (!copy) {
        await fs.createOrUpdateDomain(from.copyWith(
          subjects: from.subjects.where((x) => x.id != s.id).toList(),
        ));
      }

      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
      _snack('${copy ? 'Copied' : 'Moved'} "${s.name}" to "${target.name}" '
          '($written question(s)).');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSubject(DomainModel d, SubjectModel s) async {
    setState(() => _busy = true);
    final count = await ref
        .read(firestoreServiceProvider)
        .countQuestions(domainId: d.id, subjectId: s.id);
    setState(() => _busy = false);

    if (count > 0) {
      _snack('"${s.name}" still has $count question(s) — hide it instead.');
      return;
    }
    final ok = await _confirm('Delete "${s.name}"?',
        'It has no questions. A copy goes to the recycle bin, so you can '
            'restore it if this was a mistake.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

    if (!await _sendToRecycleBin(
      type: 'subject',
      name: s.name,
      payload: s.toMap(),
      parentDomainId: d.id,
      parentDomainName: d.name,
    )) {
      return;
    }
    await _persist(d.copyWith(
        subjects: d.subjects.where((x) => x.id != s.id).toList()));
  }

  Future<void> _addSubLevel(DomainModel d, SubjectModel s) async {
    // Guard: if this subject currently has questions attached directly (no
    // sub-level) and none yet, adding a sub-level would strand those questions
    // — they'd stay in the DB but drop out of normal browsing. Warn first.
    if (s.subLevels.isEmpty) {
      setState(() => _busy = true);
      final direct = await ref
          .read(firestoreServiceProvider)
          .countDirectQuestions(domainId: d.id, subjectId: s.id);
      setState(() => _busy = false);
      if (direct > 0) {
        final proceed = await _confirm(
          'Heads up',
          '"${s.name}" already has $direct question(s) attached directly to it. '
              'Once you add a level here, those $direct question(s) will no '
              'longer appear in the app (they stay saved, but users reach '
              'questions only through the new levels). Re-upload them under a '
              'level to make them visible again. Continue?',
          confirmLabel: 'Continue',
        );
        if (!proceed) return;
      }
    }

    var label = d.subLevelLabel?.trim() ?? '';
    var workingDomain = d;

    if (label.isEmpty) {
      final entered = await _promptText(
        title: 'Name this level',
        hint: 'e.g. Topic, Month, Chapter',
        helperText: 'This name applies to every subject in "${d.name}".',
        confirmLabel: 'Next',
      );
      if (entered == null || entered.isEmpty) return;
      label = entered;
      workingDomain = d.copyWith(subLevelLabel: label);
      await _persist(workingDomain);
    }

    final name = await _promptText(title: 'Add $label', hint: '$label name');
    if (name == null || name.isEmpty) return;

    final subj = _findSubject(workingDomain, s.id);
    final newLevel =
        SubLevelModel(id: slugify(name), name: name, order: subj.subLevels.length);
    if (subj.subLevels.any((sl) => sl.id == newLevel.id)) {
      _snack('That $label already exists here.');
      return;
    }
    final updatedSubj =
        subj.copyWith(subLevels: [...subj.subLevels, newLevel]);
    await _persist(workingDomain.copyWith(
        subjects: _replaceSubject(workingDomain, updatedSubj)));
    _snack('$label "$name" added.');
  }

  // ============================== SUB-LEVEL actions ============================

  Future<void> _renameSubLevel(
      DomainModel d, SubjectModel s, SubLevelModel sl) async {
    final name = await _promptText(title: 'Rename', initial: sl.name);
    if (name == null || name.isEmpty || name == sl.name) return;
    final updatedSubj = s.copyWith(
        subLevels:
            s.subLevels.map((x) => x.id == sl.id ? x.copyWith(name: name) : x).toList());
    await _persist(d.copyWith(subjects: _replaceSubject(d, updatedSubj)));
  }

  Future<void> _toggleSubLevelActive(
      DomainModel d, SubjectModel s, SubLevelModel sl) async {
    if (sl.isActive) {
      final ok = await _confirm('Hide "${sl.name}"?',
          'It disappears from users immediately. Its data stays.',
          confirmLabel: 'Hide');
      if (!ok) return;
    }
    final updatedSubj = s.copyWith(
        subLevels: s.subLevels
            .map((x) => x.id == sl.id ? x.copyWith(isActive: !x.isActive) : x)
            .toList());
    await _persist(d.copyWith(subjects: _replaceSubject(d, updatedSubj)));
  }

  Future<void> _deleteSubLevel(
      DomainModel d, SubjectModel s, SubLevelModel sl) async {
    setState(() => _busy = true);
    final count = await ref.read(firestoreServiceProvider).countQuestions(
        domainId: d.id, subjectId: s.id, subLevelId: sl.id);
    setState(() => _busy = false);

    if (count > 0) {
      _snack('"${sl.name}" still has $count question(s) — hide it instead.');
      return;
    }
    final ok = await _confirm('Delete "${sl.name}"?',
        'It has no questions. A copy goes to the recycle bin, so you can '
            'restore it if this was a mistake.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

    if (!await _sendToRecycleBin(
      type: 'subLevel',
      name: sl.name,
      payload: sl.toMap(),
      parentDomainId: d.id,
      parentDomainName: d.name,
      parentSubjectId: s.id,
      parentSubjectName: s.name,
    )) {
      return;
    }
    final updatedSubj = s.copyWith(
        subLevels: s.subLevels.where((x) => x.id != sl.id).toList());
    await _persist(d.copyWith(subjects: _replaceSubject(d, updatedSubj)));
  }

  // ==================================== UI =====================================

  @override
  Widget build(BuildContext context) {
    // Live stream rather than a cached future: an admin editing content
    // should see their own change land immediately.
    final domainsAsync = ref.watch(adminDomainsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Domains & Subjects'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Bulk visibility',
            icon: const Icon(Icons.visibility_rounded),
            onSelected: (action) async {
              final domains = domainsAsync.valueOrNull;
              if (domains == null) return;
              switch (action) {
                case 'showAllDomains':
                  await _bulkSetDomainsActive(domains, true);
                  break;
                case 'hideAllDomains':
                  await _bulkSetDomainsActive(domains, false);
                  break;
                case 'showAllSubjects':
                  await _bulkSetAllSubjectsActive(domains, true);
                  break;
                case 'hideAllSubjects':
                  await _bulkSetAllSubjectsActive(domains, false);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'showAllDomains',
                  child: Text('Show all domains')),
              PopupMenuItem(
                  value: 'hideAllDomains',
                  child: Text('Hide all domains')),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'showAllSubjects',
                  child: Text('Show every subject (all domains)')),
              PopupMenuItem(
                  value: 'hideAllSubjects',
                  child: Text('Hide every subject (all domains)')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _createDomain,
        icon: const Icon(Icons.add),
        label: const Text('New domain'),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          _overallCountBanner(),
          Expanded(
            child: domainsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (domains) {
                final sorted = List<DomainModel>.from(domains)
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                if (sorted.isEmpty) {
                  return const Center(
                      child: Text('No domains yet. Tap "New domain".'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) => _domainCard(sorted[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _hiddenChip() => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('HIDDEN', style: TextStyle(fontSize: 10)),
      );

  /// Marks a subject that draws from the cross-domain shared question pool.
  /// Small numbered badge shown at the left of each subject row.
  Widget _serialBadge(int n) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Text('$n',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _sharedChip() => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('SHARED',
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onTertiaryContainer)),
      );

  /// Translates Firestore's unhelpful quota error into something actionable.
  String _friendlyError(Object e) {
    final t = e.toString();
    if (t.contains('RESOURCE_EXHAUSTED') ||
        t.contains('resource-exhausted') ||
        t.contains('Quota exceeded')) {
      return 'Firebase daily quota reached — counts unavailable until it '
          'resets (midnight Pacific Time).';
    }
    return 'Could not load: $t';
  }

  Widget _overallCountBanner() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          Expanded(
            child: !_showCounts
                ? const Text('Question counts hidden (saves Firebase reads)',
                    style: TextStyle(fontSize: 13))
                : ref.watch(totalQuestionCountProvider).when(
                      loading: () => const Text('Counting...',
                          style: TextStyle(fontSize: 13)),
                      error: (e, _) => Text(_friendlyError(e),
                          style: const TextStyle(fontSize: 12)),
                      data: (n) => Text(
                        '$n question${n == 1 ? '' : 's'} total across the app',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
          ),
          Switch(
            value: _showCounts,
            onChanged: (v) => setState(() => _showCounts = v),
          ),
        ],
      ),
    );
  }

  /// Small "N questions" label for a domain or subject, backed by a
  /// Firestore count() aggregation query — cheap since it never fetches the
  /// actual question documents.
  Widget _questionCountLabel(QuestionCountKey key) {
    // Skip the query entirely when counts are switched off.
    if (!_showCounts) return const SizedBox.shrink();
    final countAsync = ref.watch(questionCountProvider(key));
    return countAsync.when(
      data: (n) => Text(
        '$n question${n == 1 ? '' : 's'}',
        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
      ),
      loading: () => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: Theme.of(context).hintColor),
      ),
      error: (_, __) => Text('—',
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).hintColor)),
    );
  }

  Widget _domainCard(DomainModel d) {
    final isExpanded = _expandedDomains.contains(d.id);
    return Card(
      child: Opacity(
        opacity: d.isActive ? 1 : 0.6,
        child: ExpansionTile(
          onExpansionChanged: (expanded) {
            if (expanded && !_expandedDomains.contains(d.id)) {
              setState(() => _expandedDomains.add(d.id));
            }
          },
          title: Row(children: [
            Flexible(
                child: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            if (!d.isActive) _hiddenChip(),
          ]),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  'id: ${d.id}  •  v${d.version}'
                  '${d.subLevelLabel != null && d.subLevelLabel!.isNotEmpty ? '  •  nests as "${d.subLevelLabel}"' : ''}'
                  '  •  ${d.subjects.length} subjects',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _questionCountLabel(
                  (domainId: d.id, subjectId: null, subLevelId: null)),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  _renameDomain(d);
                  break;
                case 'toggle':
                  _toggleDomainActive(d);
                  break;
                case 'showAllSubjects':
                  _bulkSetDomainSubjectsActive(d, true);
                  break;
                case 'hideAllSubjects':
                  _bulkSetDomainSubjectsActive(d, false);
                  break;
                case 'label':
                  _setSubLevelLabel(d);
                  break;
                case 'delete':
                  _deleteDomain(d);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                  value: 'toggle', child: Text(d.isActive ? 'Hide' : 'Show')),
              if (d.subjects.isNotEmpty) ...[
                const PopupMenuItem(
                    value: 'showAllSubjects',
                    child: Text('Show all subjects here')),
                const PopupMenuItem(
                    value: 'hideAllSubjects',
                    child: Text('Hide all subjects here')),
              ],
              const PopupMenuItem(
                  value: 'label', child: Text('Set nesting level name')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'delete',
                  child:
                      Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
          children: [
            if (isExpanded) ..._subjectRows(d),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add subject'),
                  onPressed: _busy ? null : () => _addSubject(d),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _subjectRows(DomainModel d) {
    final sorted = List<SubjectModel>.from(d.subjects)
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Serial numbers (1, 2, 3...) so a long subject list is easy to refer to
    // and count. Numbering follows the displayed (alphabetical) order.
    return [
      for (var i = 0; i < sorted.length; i++) _subjectTile(d, sorted[i], i + 1),
    ];
  }

  Widget _subjectTile(DomainModel d, SubjectModel s, int serial) {
    final label = (d.subLevelLabel?.trim().isNotEmpty ?? false)
        ? d.subLevelLabel!.trim()
        : 'sub-level';

    final menu = PopupMenuButton<String>(
      onSelected: (action) {
        switch (action) {
          case 'rename':
            _renameSubject(d, s);
            break;
          case 'toggle':
            _toggleSubjectActive(d, s);
            break;
          case 'share':
            _toggleSubjectShared(d, s);
            break;
          case 'describe':
            _editSubjectDescription(d, s);
            break;
          case 'move':
            _moveOrCopySubject(d, s);
            break;
          case 'addSub':
            _addSubLevel(d, s);
            break;
          case 'delete':
            _deleteSubject(d, s);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'toggle', child: Text(s.isActive ? 'Hide' : 'Show')),
        PopupMenuItem(
            value: 'share',
            child: Text(s.isShared
                ? 'Stop sharing across domains'
                : 'Share across domains')),
        PopupMenuItem(
            value: 'describe',
            child: Text((s.description ?? '').trim().isEmpty
                ? 'Add summary'
                : 'Edit summary')),
        const PopupMenuItem(
            value: 'move', child: Text('Move / copy to another domain')),
        PopupMenuItem(value: 'addSub', child: Text('Add $label')),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    );

    if (s.subLevels.isEmpty) {
      return Opacity(
        opacity: s.isActive ? 1 : 0.6,
        child: ListTile(
          dense: true,
          onTap: _busy ? null : () => _addSubLevel(d, s),
          leading: _serialBadge(serial),
          title: Row(children: [
            Flexible(child: Text(s.name)),
            if (!s.isActive) _hiddenChip(),
            if (s.isShared) _sharedChip(),
          ]),
          subtitle: Row(
            children: [
              Expanded(
                  child: Text('id: ${s.id}', overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _questionCountLabel(
                  (domainId: d.id, subjectId: s.id, subLevelId: null)),
            ],
          ),
          trailing: menu,
        ),
      );
    }

    // Subject WITH sub-levels: nest one more ExpansionTile.
    final subSorted = List<SubLevelModel>.from(s.subLevels)
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Opacity(
      opacity: s.isActive ? 1 : 0.6,
      child: ExpansionTile(
        leading: _serialBadge(serial),
        title: Row(children: [
          Flexible(child: Text(s.name)),
          if (!s.isActive) _hiddenChip(),
          if (s.isShared) _sharedChip(),
        ]),
        subtitle: Text('id: ${s.id}  •  ${subSorted.length} $label(s)'),
        trailing: menu,
        children: [
          for (final sl in subSorted) _subLevelTile(d, s, sl),
          // Visible button rather than hiding this in the three-dot menu —
          // adding the third tier was hard to discover otherwise.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add $label'),
                onPressed: _busy ? null : () => _addSubLevel(d, s),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLevelTile(DomainModel d, SubjectModel s, SubLevelModel sl) {
    return Opacity(
      opacity: sl.isActive ? 1 : 0.6,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 48, right: 16),
        leading: const Icon(Icons.label_outline, size: 18),
        title: Row(children: [
          Flexible(child: Text(sl.name)),
          if (!sl.isActive) _hiddenChip(),
        ]),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'rename':
                _renameSubLevel(d, s, sl);
                break;
              case 'toggle':
                _toggleSubLevelActive(d, s, sl);
                break;
              case 'delete':
                _deleteSubLevel(d, s, sl);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
                value: 'toggle', child: Text(sl.isActive ? 'Hide' : 'Show')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
