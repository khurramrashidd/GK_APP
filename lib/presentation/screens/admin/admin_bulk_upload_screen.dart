import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/answer_shuffler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/models/domain_model.dart';
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

          // Subject: row field first, else the file name. That's what lets
          // a folder of plain question files (thailand.json, srilanka.json)
          // upload without editing every row.
          var sName = (m['subject'] ?? m['subjectName'] ?? '').toString().trim();
          if (sName.isEmpty) sName = fileSubject;
          if (sName.isEmpty) {
            skip('No "subject" field and the file name gave no usable name');
            continue;
          }
          var sSlug = slugify(sName);

          final domain = domainBySlug[dSlug];
          final subjectExists =
              domain?.subjects.any((x) => x.id == sSlug) ?? false;

          if (domain != null && !subjectExists && !_createMissing) {
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
            'subLevelId': null,
            'subLevelName': null,
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
                          : (v) => setState(() => _forceDomain = v),
                    ),
                    if (_forceDomain != null)
                      Text(
                        'Every question will go into "${_forceDomain!.name}", '
                        'matched to subjects by name.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
            icon: const Icon(Icons.add_rounded),
            label: Text(_queued.isEmpty
                ? 'Select JSON files'
                : 'Add more files (${_queued.length} queued)'),
            onPressed: _busy ? null : _addFile,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.cloud_upload_rounded),
            label: Text(_queued.isEmpty
                ? 'Upload'
                : 'Upload ${_queued.length} file'
                    '${_queued.length == 1 ? '' : 's'}'),
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
