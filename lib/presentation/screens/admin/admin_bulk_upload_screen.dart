import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/answer_shuffler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/models/domain_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/models/content_update_model.dart';
import '../../providers/database_provider.dart';

/// Admin > Bulk upload.
///
/// The normal upload screen makes you pick a domain and subject first, then
/// upload questions into it — fine for one batch, tedious once you're adding
/// content across many subjects at once.
///
/// This screen takes ONE file containing questions for MANY subjects and
/// routes each question automatically, by reading `domain` and `subject`
/// fields on each question object:
///
/// [
///   { "domain": "UPSC", "subject": "History",  "question": "...", ... },
///   { "domain": "Country", "subject": "Japan", "question": "...", ... }
/// ]
///
/// Matching is case-insensitive on the slugified name, so "History",
/// "HISTORY" and "hISTory" all land in the same subject. Domains/subjects
/// that don't exist are reported rather than silently created — that keeps a
/// typo from spawning a junk category.
class AdminBulkUploadScreen extends ConsumerStatefulWidget {
  const AdminBulkUploadScreen({super.key});

  @override
  ConsumerState<AdminBulkUploadScreen> createState() =>
      _AdminBulkUploadScreenState();
}

/// A resolved destination: the full path a file's questions will land in.
typedef _Target = ({
  DomainModel domain,
  SubjectModel subject,
  SubLevelModel subLevel,
});

class _AdminBulkUploadScreenState
    extends ConsumerState<AdminBulkUploadScreen> {
  bool _busy = false;
  final List<String> _log = [];
  bool _createMissing = false;

  static String slugify(String input) {
    final lower = input.toLowerCase().trim();
    return lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _say(String s) => setState(() => _log.add(s));

  /// Files staged for upload. Built one pick at a time rather than with a
  /// multi-select picker: the picker API that is known to compile in this
  /// project is single-file, and guessing at a multi-select variant risks
  /// breaking the build for no real gain — adding three files is three taps.
  /// Shown in the "What should the JSON look like?" panel.
  static const _sampleJson = '''[
  {
    "question": "Which river is the longest in India?",
    "options": ["Godavari", "Ganga", "Yamuna", "Narmada"],
    "correctOptionIndex": 1,
    "explanation": "The Ganga runs about 2,525 km within India.",
    "difficulty": 1,
    "classLevel": 6,
    "tags": ["india", "rivers"]
  },
  {
    "domain": "Country",
    "subject": "Thailand",
    "question": "What is the capital of Thailand?",
    "options": ["Chiang Mai", "Phuket", "Bangkok", "Pattaya"],
    "correctOptionIndex": 2,
    "explanation": "Bangkok has been the capital since 1782.",
    "difficulty": 1,
    "tags": ["thailand", "capitals"]
  }
]''';

  final List<({String name, String content})> _queued = [];

  /// When set, EVERY row in every queued file goes to this domain,
  /// regardless of what its "domain" field says. For the common case of
  /// uploading a folder of subject files that all belong to one domain.
  DomainModel? _forceDomain;

  /// Optional: force every row into ONE subject, and optionally one of its
  /// sub-levels. A sub-level belongs to a specific subject, so choosing a
  /// sub-level requires a subject — the pickers cascade for that reason.
  SubjectModel? _forceSubject;
  SubLevelModel? _forceSubLevel;

  /// Remembered answers to conflict prompts, so the admin is asked once per
  /// unknown name rather than once per question row.
  final Map<String, String?> _resolved = {};

  /// Picks one or MANY json files in a single dialog.
  ///
  /// file_picker 12 is a federated plugin: `pickFiles` returns a plain
  /// `List<PlatformFile>` (FilePickerResult was removed in v12) and yields an
  /// empty list when the user cancels — so there is no null to check.
  /// `pickFile` remains the single-file variant.
  /// Turns a file name into a probable subject name.
  ///
  /// Question files are usually named after their subject and carry no
  /// "subject" field inside — thailand.json, srilanka_batch2.json,
  /// antarctic-desert_quiz.json. Deriving the subject from the name is what
  /// makes "drop in a folder of subject files" actually work.
  ///
  /// Strips the extension and common decorations (quiz/questions, batch/part
  /// numbers, trailing digits), then turns separators into spaces.
  static String subjectNameFromFile(String fileName) {
    var n = fileName;
    final dot = n.lastIndexOf('.');
    if (dot > 0) n = n.substring(0, dot);

    n = n.toLowerCase();
    for (final pat in [
      RegExp(r'[_-]?batch\s*\d+'),
      RegExp(r'[_-]?part\s*\d+'),
      RegExp(r'[_-]?quiz'),
      RegExp(r'[_-]?questions?'),
      RegExp(r'[_-]?mcqs?'),
      RegExp(r'[_-]?v\d+'),
      RegExp(r'[_-]?\d+' r'$'),
    ]) {
      n = n.replaceAll(pat, '');
    }

    n = n.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (n.isEmpty) return '';

    // Title Case each word so it matches a subject named "Sri Lanka".
    return n
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Pulls every .json out of a zip, however deeply it is buried.
  ///
  /// Walks the archive recursively: a nested .zip is opened and walked in
  /// turn, and ordinary folders are simply part of the entry path. Only the
  /// FILE NAME matters — the folder and zip names above it are ignored,
  /// because they carry no reliable meaning (they might be a domain, a
  /// batch date, or someone's export folder).
  ///
  /// Guarded against zip bombs and runaway nesting: [depth] is capped, and
  /// the whole archive is held in memory, so a very large upload will be
  /// slow rather than instant.
  void _collectJsonFromArchive(
    Archive archive,
    List<({String name, String content})> out, {
    int depth = 0,
    List<String> problems = const [],
  }) {
    if (depth > 5) return; // pathological nesting; stop rather than hang

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final lower = entry.name.toLowerCase();

      // Skip macOS/Windows archive noise, which otherwise shows up as
      // bogus "subjects" named things like __MACOSX.
      if (lower.contains('__macosx') ||
          lower.split('/').last.startsWith('.') ||
          lower.endsWith('thumbs.db')) {
        continue;
      }

      final bytes = entry.content as List<int>;

      if (lower.endsWith('.zip')) {
        try {
          _collectJsonFromArchive(
            ZipDecoder().decodeBytes(bytes),
            out,
            depth: depth + 1,
          );
        } catch (_) {
          _say('Could not open nested zip: ${entry.name}');
        }
        continue;
      }

      if (!lower.endsWith('.json')) continue;

      try {
        final content = utf8.decode(bytes);
        final decoded = jsonDecode(content);
        if (decoded is! List) {
          _say('SKIPPED ${entry.name}: not a JSON array.');
          continue;
        }
        // Keep only the file name — the path above it is deliberately
        // discarded. subjectNameFromFile turns it into a subject name.
        final fileName = entry.name.split('/').last;
        if (out.any((q) => q.name == fileName) ||
            _queued.any((q) => q.name == fileName)) {
          _say('Already queued: $fileName');
          continue;
        }
        out.add((name: fileName, content: content));
      } on FormatException {
        _say('SKIPPED ${entry.name}: not valid JSON.');
      } catch (e) {
        _say('SKIPPED ${entry.name}: $e');
      }
    }
  }

  Future<void> _addZip() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (picked.isEmpty) return;

      setState(() => _busy = true);
      final found = <({String name, String content})>[];

      for (final file in picked) {
        _say('Opening ${file.name}...');
        try {
          final archive =
              ZipDecoder().decodeBytes(await file.readAsBytes());
          _collectJsonFromArchive(archive, found);
        } catch (e) {
          _say('Could not read ${file.name}: $e');
        }
      }

      if (found.isEmpty) {
        _say('No .json question files found inside.');
        return;
      }

      setState(() => _queued.addAll(found));
      _say('Found ${found.length} question file(s):');
      for (final f in found) {
        _say('   ${f.name}  ->  subject "${subjectNameFromFile(f.name)}"');
      }
    } catch (e) {
      _say('Could not open the file picker: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked.isEmpty) return; // cancelled

      var added = 0;
      for (final file in picked) {
        try {
          final content = utf8.decode(await file.readAsBytes());
          // Validate on add, not at upload time — a bad file should be
          // flagged while the admin still remembers which one it was.
          final decoded = jsonDecode(content);
          if (decoded is! List) {
            _say('SKIPPED ${file.name}: not a JSON array.');
            continue;
          }
          // Don't queue the same file twice if it's picked again later.
          if (_queued.any((q) => q.name == file.name)) {
            _say('Already queued: ${file.name}');
            continue;
          }
          setState(() => _queued.add((name: file.name, content: content)));
          // Surface the derived subject now — if it's wrong, the admin sees
          // it before uploading rather than after 300 rows are skipped.
          final firstRow = decoded.isEmpty ? null : decoded.first;
          final hasSubjectField = firstRow is Map &&
              (firstRow['subject'] ?? firstRow['subjectName'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty;
          final derived = subjectNameFromFile(file.name);
          _say('Queued ${file.name} (${decoded.length} rows)'
              '${hasSubjectField ? '' : '  →  subject: "$derived"'}');
          added++;
        } on FormatException {
          _say('SKIPPED ${file.name}: not valid JSON.');
        } catch (e) {
          _say('SKIPPED ${file.name}: $e');
        }
      }
      if (added > 1) _say('Added $added files.');
    } catch (e) {
      _say('Could not open the file picker: $e');
    }
  }

  /// Asks the admin where an unmatched name should go.
  ///
  /// Returns the chosen id, or null to skip. The answer is cached in
  /// [_resolved] so a file with 200 rows for one unknown subject prompts
  /// once, not 200 times.
  Future<String?> _resolveConflict({
    required String label,
    required String fromJson,
    required List<({String id, String name})> options,
  }) async {
    final cacheKey = '$label::${fromJson.toLowerCase()}';
    if (_resolved.containsKey(cacheKey)) return _resolved[cacheKey];

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('$label not found'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The file says:',
                  style: Theme.of(ctx).textTheme.bodySmall),
              Text('"$fromJson"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Pick where these questions should go:'),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        title: Text(o.name),
                        onTap: () => Navigator.pop(ctx, o.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, '__skip__'),
            child: const Text('Skip these'),
          ),
        ],
      ),
    );

    final result = (choice == null || choice == '__skip__') ? null : choice;
    _resolved[cacheKey] = result;
    return result;
  }

  /// Works out which subject names in the queue don't exist yet, and asks
  /// the admin to map them ALL in one screen before anything is written.
  ///
  /// Doing this upfront rather than mid-import matters: a 40-file upload
  /// that stops to ask a question every few seconds is worse than one
  /// decision screen, and being interrupted halfway means you can't see
  /// the whole picture before committing.
  ///
  /// Returns false if the admin cancelled.
  Future<bool> _resolveNamesUpfront(DomainModel domain) async {
    // Distinct subject names implied by the queued files.
    final wanted = <String, String>{}; // slug -> display name
    for (final f in _queued) {
      final name = _forceSubject?.name ?? subjectNameFromFile(f.name);
      if (name.isEmpty) continue;
      wanted[slugify(name)] = name;
    }

    final existing = {for (final s in domain.subjects) s.id};
    final unmatched = wanted.entries
        .where((e) => !existing.contains(e.key))
        .map((e) => e.value)
        .toList()
      ..sort();

    if (unmatched.isEmpty) return true;

    // name -> chosen subject id, or null to skip
    final mapping = <String, String?>{for (final n in unmatched) n: null};

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${unmatched.length} name(s) not found'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These come from your file names but do not exist in '
                  '"${domain.name}". Choose where each should go, or leave '
                  'it unset to skip those questions.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      for (final name in unmatched)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('"$name"',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              DropdownButton<String?>(
                                value: mapping[name],
                                isExpanded: true,
                                hint: const Text('Skip these questions'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Skip these questions')),
                                  for (final sub in domain.subjects)
                                    DropdownMenuItem<String?>(
                                        value: sub.id,
                                        child: Text(sub.name)),
                                ],
                                onChanged: (v) =>
                                    setLocal(() => mapping[name] = v),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue')),
          ],
        ),
      ),
    );

    if (done != true) return false;

    // Seed the per-import cache the upload loop already consults, so it
    // never stops to ask again.
    mapping.forEach((name, chosen) {
      _resolved['Subject in ${domain.name}::${name.toLowerCase()}'] = chosen;
    });
    return true;
  }

  // ---------------------- Auto-match upload (zip / files) --------------------

  /// Sends every queued file to the SUBJECT whose name matches its file
  /// name, anywhere in the catalogue — no domain or sub-domain picking.
  ///
  /// Matching is against the DEEPEST tier (sub-levels), because that is what
  /// "subject" means in this app's tier naming. Names are slugified, so
  /// "Mummies", "mummies" and "Mummies.json" all resolve the same way.
  ///
  /// Anything ambiguous (a name existing in several places) or unmatched is
  /// collected and shown in ONE review screen before a single write happens.
  Future<void> _autoMatchAndUpload() async {
    if (_queued.isEmpty) {
      _say('Add at least one file or zip first.');
      return;
    }

    setState(() {
      _busy = true;
      _log.clear();
    });

    try {
      final fs = ref.read(firestoreServiceProvider);
      final domains = await fs.fetchAllDomainsForAdmin();

      // slug -> every place that name exists
      final index = <String, List<_Target>>{};
      for (final d in domains) {
        for (final sub in d.subjects) {
          for (final sl in sub.subLevels) {
            index
                .putIfAbsent(slugify(sl.name), () => [])
                .add((domain: d, subject: sub, subLevel: sl));
          }
        }
      }
      _say('Catalogue: ${index.length} distinct subject name(s).');

      final resolved = <String, _Target>{};
      final needsReview = <String, List<_Target>>{};
      for (final f in _queued) {
        final name = subjectNameFromFile(f.name);
        if (name.isEmpty) {
          needsReview[f.name] = const [];
          continue;
        }
        final hits = index[slugify(name)] ?? const <_Target>[];
        if (hits.length == 1) {
          resolved[f.name] = hits.first;
        } else {
          // Zero hits or several — both need a human decision.
          needsReview[f.name] = hits;
        }
      }

      _say('Matched automatically: ${resolved.length}');
      if (needsReview.isNotEmpty) {
        _say('Needs your decision: ${needsReview.length}');
        if (!mounted) return;
        final choices = await _reviewTargets(needsReview, index);
        if (choices == null) {
          _say('Cancelled — nothing was uploaded.');
          return;
        }
        choices.forEach((file, target) {
          if (target != null) resolved[file] = target;
        });
      }

      if (resolved.isEmpty) {
        _say('Nothing to upload.');
        return;
      }

      await _writeResolved(resolved, fs);
    } catch (e) {
      _say('FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens a full screen where every unplaced file gets Domain -> Sub-domain
  /// -> Subject dropdowns.
  ///
  /// A full screen rather than a dialog: with three cascading pickers per
  /// file, a dialog box is too cramped to use. And cascading rather than one
  /// flat list because the catalogue runs to hundreds of subjects — scrolling
  /// a single list that long to find one name is not a workable interface.
  ///
  /// Returns null if cancelled; a null value for a file means "skip it".
  Future<Map<String, _Target?>?> _reviewTargets(
    Map<String, List<_Target>> needsReview,
    Map<String, List<_Target>> index,
  ) async {
    final domains = ref.read(adminDomainsProvider).valueOrNull ??
        await ref.read(firestoreServiceProvider).fetchAllDomainsForAdmin();

    return Navigator.of(context).push<Map<String, _Target?>>(
      MaterialPageRoute(
        builder: (_) => _ReviewTargetsScreen(
          needsReview: needsReview,
          domains: domains,
        ),
      ),
    );
  }

  /// Writes the resolved files, one destination at a time.
  Future<void> _writeResolved(
      Map<String, _Target> resolved, FirestoreService fs) async {
    var totalAdded = 0, totalDupes = 0;

    for (final entry in resolved.entries) {
      final file = _queued.firstWhere((q) => q.name == entry.key);
      final t = entry.value;

      final decoded = jsonDecode(file.content);
      if (decoded is! List) continue;

      final existing =
          await fs.fetchQuestionTextsForSubject(t.domain.id, t.subject.id);
      final seen = <String>{};
      final fresh = <Map<String, dynamic>>[];

      for (final row in decoded) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final text = (m['question'] ?? '').toString().trim().toLowerCase();
        if (text.isEmpty) continue;
        if (existing.contains(text) || seen.contains(text)) continue;
        seen.add(text);
        fresh.add(m);
      }

      final dupes = decoded.length - fresh.length;
      totalDupes += dupes;

      if (fresh.isEmpty) {
        _say('${t.subLevel.name}: nothing new'
            '${dupes > 0 ? ' ($dupes duplicate(s))' : ''}');
        continue;
      }

      final newVersion = t.domain.version + 1;
      final docs = <Map<String, dynamic>>[];
      for (var i = 0; i < fresh.length; i++) {
        final raw = AnswerShuffler.shuffleRow(fresh[i]);
        final opts = List<String>.from(raw['options'] ?? const []);
        docs.add({
          'id': (raw['id'] ?? '').toString().trim().isNotEmpty
              ? raw['id'].toString().trim()
              : '${t.domain.id}_${t.subject.id}_${t.subLevel.id}_'
                  '${DateTime.now().millisecondsSinceEpoch}_$i',
          'domainId': t.domain.id,
          'domainName': t.domain.name,
          'subjectId': t.subject.id,
          'subjectName': t.subject.name,
          'subLevelId': t.subLevel.id,
          'subLevelName': t.subLevel.name,
          'question': (raw['question'] ?? '').toString().trim(),
          'options': opts,
          'correctOptionIndex': raw['correctOptionIndex'],
          'explanation': (raw['explanation'] ?? '').toString(),
          'difficulty': raw['difficulty'] is int ? raw['difficulty'] : 1,
          'classLevel': raw['classLevel'] is int ? raw['classLevel'] : null,
          'tags': List<String>.from(raw['tags'] ?? const []),
          'isActive': raw['isActive'] is bool ? raw['isActive'] : true,
          'version': newVersion,
        });
      }

      final written = await fs.bulkUploadQuestions(docs);
      await fs.createOrUpdateDomain(t.domain.copyWith(version: newVersion));
      totalAdded += written;
      _say('${t.domain.name} > ${t.subject.name} > ${t.subLevel.name}: '
          '+$written${dupes > 0 ? ' ($dupes duplicate(s) skipped)' : ''}');
    }

    _say('');
    _say('DONE — $totalAdded added, $totalDupes duplicate(s) skipped.');

    if (totalAdded > 0) {
      try {
        await fs.postContentUpdate(ContentUpdateModel(
          id: '',
          kind: 'questions',
          title: '$totalAdded new question${totalAdded == 1 ? '' : 's'} added',
        ));
      } catch (_) {}
    }
    ref.invalidate(adminDomainsProvider);
    ref.invalidate(domainsProvider);
  }
  Future<void> _pickAndUpload() async {
    setState(() {
      _busy = true;
      _log.clear();
    });
    try {
      if (_queued.isEmpty) {
        _say('Add at least one JSON file first.');
        return;
      }

      final fs = ref.read(firestoreServiceProvider);
      final domains = await fs.fetchAllDomainsForAdmin();
      final domainBySlug = {for (final d in domains) d.id: d};

      // With a target domain chosen, every unknown name can be resolved in
      // one screen before a single write happens.
      if (_forceDomain != null && !_createMissing) {
        final target = domainBySlug[_forceDomain!.id] ?? _forceDomain!;
        if (!await _resolveNamesUpfront(target)) {
          _say('Cancelled — nothing was uploaded.');
          return;
        }
      }

      var ok = 0, skipped = 0;
      final missing = <String>{};
      final grouped = <String, List<Map<String, dynamic>>>{};

      // Why rows were skipped. Previously the log just said "118 skipped"
      // with no reason, which is useless for fixing the input.
      final reasons = <String, int>{};
      void skip(String why) {
        skipped++;
        reasons[why] = (reasons[why] ?? 0) + 1;
      }

      // Walk every queued file. Rows are grouped by destination so each
      // subject is written once, however many files contributed to it.
      for (final file in _queued) {
        final decoded = jsonDecode(file.content);
        if (decoded is! List) {
          _say('SKIPPED ${file.name}: not a JSON array.');
          continue;
        }
        _say('${file.name}: ${decoded.length} row(s)');

        // Subject implied by the file name, used when a row carries no
        // "subject" field of its own.
        final fileSubject = subjectNameFromFile(file.name);

        for (final row in decoded) {
          if (row is! Map) {
            skip('Row is not a JSON object');
            continue;
          }
          final m = Map<String, dynamic>.from(row);

          // Domain: forced selection wins, otherwise read from the row.
          String dSlug;
          String dName;
          if (_forceDomain != null) {
            dSlug = _forceDomain!.id;
            dName = _forceDomain!.name;
          } else {
            dName = (m['domain'] ?? m['domainName'] ?? '').toString().trim();
            if (dName.isEmpty) {
              skip('No "domain" field in the row — pick a domain above, '
                  'or add a "domain" key to the JSON');
              continue;
            }
            // slugify lowercases and strips punctuation, so "Art & Culture",
            // "art and culture" and "ART&CULTURE" all resolve to the same
            // domain — the case-insensitive matching you wanted.
            dSlug = slugify(dName);
            if (!domainBySlug.containsKey(dSlug) && !_createMissing) {
              final chosen = await _resolveConflict(
                label: 'Domain',
                fromJson: dName,
                options: [
                  for (final d in domains) (id: d.id, name: d.name)
                ],
              );
              if (chosen == null) {
                skip('Domain "$dName" not found and no destination chosen');
                missing.add(dName);
                continue;
              }
              dSlug = chosen;
              dName = domainBySlug[chosen]?.name ?? dName;
            }
          }

          // Subject: a forced pick wins; otherwise the row's field, else the
          // file name. The file-name fallback is what lets a folder of plain
          // question files (thailand.json, srilanka.json) upload unedited.
          var sName = _forceSubject?.name ??
              (m['subject'] ?? m['subjectName'] ?? '').toString().trim();
          if (sName.isEmpty) sName = fileSubject;
          if (sName.isEmpty) {
            skip('No "subject" field and the file name gave no usable name');
            continue;
          }
          var sSlug = slugify(sName);

          final domain = domainBySlug[dSlug];
          final subjectExists =
              domain?.subjects.any((x) => x.id == sSlug) ?? false;

          // A forced subject was picked from this domain's real list, so it
          // exists by definition — no conflict to resolve.
          if (_forceSubject == null &&
              domain != null &&
              !subjectExists &&
              !_createMissing) {
            final chosen = await _resolveConflict(
              label: 'Subject in ${domain.name}',
              fromJson: sName,
              options: [
                for (final x in domain.subjects) (id: x.id, name: x.name)
              ],
            );
            if (chosen == null) {
              skip('Subject "$sName" not found in ${domain.name} and no '
                  'destination chosen');
              missing.add('${domain.name} > $sName');
              continue;
            }
            sSlug = chosen;
          }

          // Carry the resolved names so the writer below uses them.
          m['domain'] = dName;
          m['subject'] = sName;
          if (_forceSubLevel != null) {
            m['subLevelId'] = _forceSubLevel!.id;
            m['subLevelName'] = _forceSubLevel!.name;
          }
          grouped.putIfAbsent('$dSlug|$sSlug', () => []).add(m);
        }
      }

      if (reasons.isNotEmpty) {
        _say('');
        _say('WHY ROWS WERE SKIPPED:');
        for (final e in reasons.entries) {
          _say('   ${e.value} x  ${e.key}');
        }
      }

      // Upload each group into its subject.
      for (final entry in grouped.entries) {
        final parts = entry.key.split('|');
        final dSlug = parts[0], sSlug = parts[1];
        var domain = domainBySlug[dSlug];
        final firstRow = entry.value.first;

        if (domain == null && _createMissing) {
          final dName = (firstRow['domain'] ?? firstRow['domainName']).toString();
          domain = DomainModel(id: dSlug, name: dName, isActive: false);
          await fs.createOrUpdateDomain(domain);
          domainBySlug[dSlug] = domain;
          _say('Created hidden domain "$dName".');
        }
        if (domain == null) continue;

        final subjMatches =
            domain.subjects.where((x) => x.id == sSlug).toList();
        var subject = subjMatches.isEmpty ? null : subjMatches.first;
        if (subject == null && _createMissing) {
          final sName =
              (firstRow['subject'] ?? firstRow['subjectName']).toString();
          subject = SubjectModel(id: sSlug, name: sName, isActive: false);
          domain = domain.copyWith(subjects: [...domain.subjects, subject]);
          await fs.createOrUpdateDomain(domain);
          domainBySlug[dSlug] = domain;
          _say('Created hidden subject "$sName".');
        }
        if (subject == null) continue;

        // Skip questions whose text already exists in this subject, so
        // re-running the same file is safe.
        final existing =
            await fs.fetchQuestionTextsForSubject(domain.id, subject.id);
        final seen = <String>{};
        final fresh = <Map<String, dynamic>>[];
        for (final row in entry.value) {
          final text = (row['question'] ?? '').toString().trim().toLowerCase();
          if (text.isEmpty) continue;
          if (existing.contains(text) || seen.contains(text)) continue;
          seen.add(text);
          fresh.add(row);
        }
        final dupes = entry.value.length - fresh.length;
        if (fresh.isEmpty) {
          _say('${domain.name} > ${subject.name}: nothing new '
              '($dupes duplicate(s) skipped)');
          skipped += dupes;
          continue;
        }

        // Bumping the domain version is what tells cached clients to re-sync.
        final newVersion = domain.version + 1;
        final docs = <Map<String, dynamic>>[];
        for (var i = 0; i < fresh.length; i++) {
          // Shuffle answer position — see AnswerShuffler for why.
          final raw = AnswerShuffler.shuffleRow(fresh[i]);
          final rawId = (raw['id'] ?? '').toString().trim();
          docs.add({
            'id': rawId.isNotEmpty
                ? rawId
                : '${domain.id}_${subject.id}_${DateTime.now().millisecondsSinceEpoch}_$i',
            'domainId': domain.id,
            'domainName': domain.name,
            'subjectId': subject.id,
            'subjectName': subject.name,
            // Previously hard-coded null, which made it impossible to put
            // uploaded questions into a sub-level at all.
            'subLevelId': raw['subLevelId'],
            'subLevelName': raw['subLevelName'],
            'question': (raw['question'] ?? '').toString().trim(),
            'options': List<String>.from(raw['options'] ?? const []),
            'correctOptionIndex': raw['correctOptionIndex'],
            'explanation': (raw['explanation'] ?? '').toString(),
            'difficulty': raw['difficulty'] is int ? raw['difficulty'] : 1,
            'classLevel': raw['classLevel'],
            'tags': List<String>.from(raw['tags'] ?? const []),
            'isActive': raw['isActive'] is bool ? raw['isActive'] : true,
            'version': newVersion,
          });
        }

        final written = await fs.bulkUploadQuestions(docs);
        await fs.createOrUpdateDomain(domain.copyWith(version: newVersion));
        domainBySlug[dSlug] = domain.copyWith(version: newVersion);
        ok += written;
        skipped += dupes;
        _say('${domain.name} > ${subject.name}: added $written'
            '${dupes > 0 ? ', skipped $dupes duplicate(s)' : ''}');
      }

      // Tell users something new is available. Best-effort — a failed
      // announcement must not undo a successful upload.
      if (ok > 0) {
        try {
          await fs.postContentUpdate(ContentUpdateModel(
            id: '',
            kind: 'questions',
            title: '$ok new question${ok == 1 ? '' : 's'} added',
            detail: 'Across ${grouped.length} subject'
                '${grouped.length == 1 ? '' : 's'}',
          ));
        } catch (_) {}
      }

      _say('');
      _say('DONE — $ok added, $skipped skipped.');
      ref.invalidate(adminDomainsProvider);
      ref.invalidate(domainsProvider);
      ref.invalidate(totalQuestionCountProvider);
    } catch (e) {
      _say('ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk upload (multi-subject)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('One file, many subjects',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      'Add "domain" and "subject" to each question and this '
                      'screen files it in the right place automatically. '
                      'Names are matched case-insensitively.'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const SelectableText(
                      '[\n'
                      '  {\n'
                      '    "domain": "UPSC",\n'
                      '    "subject": "History",\n'
                      '    "question": "Who founded the Maurya Empire?",\n'
                      '    "options": ["Chandragupta", "Ashoka", "Bindusara", "Bimbisara"],\n'
                      '    "correctOptionIndex": 0,\n'
                      '    "explanation": "...",\n'
                      '    "difficulty": 1,\n'
                      '    "classLevel": 8,\n'
                      '    "tags": ["ancient"]\n'
                      '  }\n'
                      ']',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('What should the JSON look like?'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Two accepted shapes. A) Plain question list — the SUBJECT '
                  'comes from the file name (thailand.json → Thailand) and '
                  'the domain from the picker below. B) Self-describing rows '
                  'that name their own domain and subject.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  _sampleJson,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy sample'),
                      onPressed: () async {
                        await Clipboard.setData(
                            const ClipboardData(text: _sampleJson));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Sample copied')));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Optional: force every row into one domain. For the common case
          // of uploading a folder of subject files that all belong together.
          Consumer(builder: (context, ref, _) {
            final domains =
                ref.watch(adminDomainsProvider).valueOrNull ?? const [];
            return Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<DomainModel?>(
                      value: _forceDomain,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Put everything in one domain (optional)',
                        border: InputBorder.none,
                      ),
                      items: [
                        const DropdownMenuItem<DomainModel?>(
                          value: null,
                          child: Text('Use the "domain" field in each file'),
                        ),
                        for (final d in domains)
                          DropdownMenuItem<DomainModel?>(
                              value: d, child: Text(d.name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _forceDomain = v;
                                // Subject/sub-level belong to the old domain.
                                _forceSubject = null;
                                _forceSubLevel = null;
                              }),
                    ),
                    if (_forceDomain != null) ...[
                      DropdownButtonFormField<SubjectModel?>(
                        value: _forceSubject,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Force one subject (optional)',
                          border: InputBorder.none,
                        ),
                        items: [
                          const DropdownMenuItem<SubjectModel?>(
                            value: null,
                            child: Text('Match subjects by name / file name'),
                          ),
                          for (final sub in _forceDomain!.subjects)
                            DropdownMenuItem<SubjectModel?>(
                                value: sub, child: Text(sub.name)),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _forceSubject = v;
                                  _forceSubLevel = null;
                                }),
                      ),
                      if (_forceSubject != null &&
                          _forceSubject!.subLevels.isNotEmpty)
                        DropdownButtonFormField<SubLevelModel?>(
                          value: _forceSubLevel,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText:
                                'Force one ${_forceDomain!.subLevelLabel ?? 'sub-level'} (optional)',
                            border: InputBorder.none,
                          ),
                          items: [
                            const DropdownMenuItem<SubLevelModel?>(
                              value: null,
                              child: Text('Put questions at subject level'),
                            ),
                            for (final sl in _forceSubject!.subLevels)
                              DropdownMenuItem<SubLevelModel?>(
                                  value: sl, child: Text(sl.name)),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _forceSubLevel = v),
                        ),
                      Text(
                        _forceSubLevel != null
                            ? 'Everything goes into "${_forceDomain!.name} > '
                                '${_forceSubject!.name} > ${_forceSubLevel!.name}".'
                            : _forceSubject != null
                                ? 'Everything goes into "${_forceDomain!.name} > '
                                    '${_forceSubject!.name}".'
                                : 'Every question goes into "${_forceDomain!.name}", '
                                    'matched to subjects by name.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 12),
          SwitchListTile(
            value: _createMissing,
            onChanged: _busy ? null : (v) => setState(() => _createMissing = v),
            title: const Text('Create missing domains/subjects'),
            subtitle: const Text(
                'Off by default. When off, anything that does not match is '
                'shown in a pop-up so you can choose where it goes.'),
          ),

          const SizedBox(height: 8),
          // Queue of staged files
          if (_queued.isNotEmpty)
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _queued.length; i++)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 20),
                      title: Text(_queued[i].name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _queued.removeAt(i)),
                      ),
                    ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(_queued.clear),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('JSON files'),
                  onPressed: _busy ? null : _addFile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('ZIP archive'),
                  onPressed: _busy ? null : _addZip,
                ),
              ),
            ],
          ),
          if (_queued.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_queued.length} file(s) queued',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          // Primary path: match by file name across the whole catalogue,
          // no domain or sub-domain picking needed.
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(_queued.isEmpty
                ? 'Match and upload'
                : 'Match and upload ${_queued.length} file'
                    '${_queued.length == 1 ? '' : 's'}'),
            onPressed: (_busy || _queued.isEmpty) ? null : _autoMatchAndUpload,
          ),
          const SizedBox(height: 8),
          // Manual path, kept for files that carry their own domain/subject
          // fields or when you want to force a destination.
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46)),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Upload using the pickers above'),
            onPressed: (_busy || _queued.isEmpty) ? null : _pickAndUpload,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_log.join('\n'),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen destination picker for files the auto-matcher could not place.
///
/// One row per file, with three cascading dropdowns. Choosing a domain
/// narrows the sub-domains; choosing a sub-domain narrows the subjects. That
/// is the whole point — picking from ~860 subjects in one flat list is not
/// something anyone can do reliably.
class _ReviewTargetsScreen extends StatefulWidget {
  final Map<String, List<_Target>> needsReview;
  final List<DomainModel> domains;

  const _ReviewTargetsScreen({
    required this.needsReview,
    required this.domains,
  });

  @override
  State<_ReviewTargetsScreen> createState() => _ReviewTargetsScreenState();
}

class _ReviewTargetsScreenState extends State<_ReviewTargetsScreen> {
  // Per file, the current state of each dropdown.
  final Map<String, DomainModel?> _domain = {};
  final Map<String, SubjectModel?> _subject = {};
  final Map<String, SubLevelModel?> _subLevel = {};

  @override
  void initState() {
    super.initState();
    // Pre-fill from a candidate when the file matched somewhere. With
    // exactly one route through a multi-match this saves the admin work;
    // they can still change it.
    for (final e in widget.needsReview.entries) {
      if (e.value.isNotEmpty) {
        final t = e.value.first;
        _domain[e.key] = t.domain;
        _subject[e.key] = t.subject;
        _subLevel[e.key] = t.subLevel;
      }
    }
  }

  int get _decided =>
      widget.needsReview.keys.where((k) => _subLevel[k] != null).length;

  void _finish() {
    final out = <String, _Target?>{};
    for (final file in widget.needsReview.keys) {
      final d = _domain[file];
      final s = _subject[file];
      final sl = _subLevel[file];
      // A partial selection is treated as "skip": writing questions to a
      // half-chosen destination would be worse than not writing them.
      out[file] = (d != null && s != null && sl != null)
          ? (domain: d, subject: s, subLevel: sl)
          : null;
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = widget.needsReview.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose destinations'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text('$_decided / ${files.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'These files did not match exactly one subject. Pick a '
                'destination for each, or leave it blank to skip that file. '
                'Nothing is uploaded until you press Confirm.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final file in files) _fileCard(theme, file),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 12,
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _finish,
                    child: Text(_decided == files.length
                        ? 'Confirm all'
                        : 'Confirm ($_decided of ${files.length}, '
                            'rest skipped)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileCard(ThemeData theme, String file) {
    final candidates = widget.needsReview[file] ?? const <_Target>[];
    final d = _domain[file];
    final s = _subject[file];

    // Only sub-domains of the chosen domain, and subjects of the chosen
    // sub-domain — that narrowing is what makes this usable.
    final subjects = d?.subjects ?? const <SubjectModel>[];
    final subLevels = s?.subLevels ?? const <SubLevelModel>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _subLevel[file] != null
                      ? Icons.check_circle_rounded
                      : Icons.help_outline_rounded,
                  size: 18,
                  color: _subLevel[file] != null
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(file,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text(
                candidates.isEmpty
                    ? 'No match found'
                    : '${candidates.length} possible matches — first one '
                        'pre-selected',
                style: theme.textTheme.bodySmall,
              ),
            ),

            DropdownButtonFormField<DomainModel?>(
              value: d,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Domain',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<DomainModel?>(
                    value: null, child: Text('— skip this file —')),
                for (final x in widget.domains)
                  DropdownMenuItem<DomainModel?>(
                      value: x,
                      child: Text(x.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _domain[file] = v;
                // Child selections belonged to the old domain.
                _subject[file] = null;
                _subLevel[file] = null;
              }),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<SubjectModel?>(
              value: s,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: d?.subjectTierName ?? 'Sub-domain',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<SubjectModel?>(
                    value: null, child: Text('— choose —')),
                for (final x in subjects)
                  DropdownMenuItem<SubjectModel?>(
                      value: x,
                      child: Text(x.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: d == null
                  ? null
                  : (v) => setState(() {
                        _subject[file] = v;
                        _subLevel[file] = null;
                      }),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<SubLevelModel?>(
              value: _subLevel[file],
              isExpanded: true,
              decoration: InputDecoration(
                labelText: d?.subLevelTierName ?? 'Subject',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<SubLevelModel?>(
                    value: null, child: Text('— choose —')),
                for (final x in subLevels)
                  DropdownMenuItem<SubLevelModel?>(
                      value: x,
                      child: Text(x.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: s == null
                  ? null
                  : (v) => setState(() => _subLevel[file] = v),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
