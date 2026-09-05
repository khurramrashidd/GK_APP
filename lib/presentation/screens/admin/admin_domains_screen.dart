import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/domain_model.dart';
import '../../providers/database_provider.dart';

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
              decoration: InputDecoration(hintText: hint),
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
    await _persist(DomainModel(id: slugify(name), name: name));
    _snack('Domain "$name" created.');
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
        'It has no questions, so this is safe — but it cannot be undone.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

    setState(() => _busy = true);
    try {
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
      _snack('That subject already exists.');
      return;
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
        'It has no questions, so this is safe — but it cannot be undone.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

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
        'It has no questions, so this is safe — but it cannot be undone.',
        confirmLabel: 'Delete', danger: true);
    if (!ok) return;

    final updatedSubj = s.copyWith(
        subLevels: s.subLevels.where((x) => x.id != sl.id).toList());
    await _persist(d.copyWith(subjects: _replaceSubject(d, updatedSubj)));
  }

  // ==================================== UI =====================================

  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(adminDomainsProvider);

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

  Widget _overallCountBanner() {
    final totalAsync = ref.watch(totalQuestionCountProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: totalAsync.when(
        loading: () => const Row(
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Counting questions...'),
          ],
        ),
        error: (e, _) => Text('Could not load total: $e'),
        data: (n) => Text(
          '$n question${n == 1 ? '' : 's'} total across the app',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Small "N questions" label for a domain or subject, backed by a
  /// Firestore count() aggregation query — cheap since it never fetches the
  /// actual question documents.
  Widget _questionCountLabel(QuestionCountKey key) {
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
      error: (_, __) =>
          Text('—', style: TextStyle(color: Theme.of(context).hintColor)),
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

    return [
      for (final s in sorted) _subjectTile(d, s),
    ];
  }

  Widget _subjectTile(DomainModel d, SubjectModel s) {
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
          leading: const Icon(Icons.menu_book_outlined, size: 20),
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
        leading: const Icon(Icons.folder_open_outlined, size: 20),
        title: Row(children: [
          Flexible(child: Text(s.name)),
          if (!s.isActive) _hiddenChip(),
          if (s.isShared) _sharedChip(),
        ]),
        subtitle: Text('id: ${s.id}  •  ${subSorted.length} $label(s)'),
        trailing: menu,
        children: [
          for (final sl in subSorted) _subLevelTile(d, s, sl),
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
