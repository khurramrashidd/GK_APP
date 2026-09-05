import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/domain_model.dart';
import '../../providers/database_provider.dart';

/// Upload questions either by picking a .json file (recommended for large
/// batches — thousands of questions) or by pasting JSON directly (handy for
/// quick tests). Every uploaded question is stamped with the domain's NEXT
/// version so existing users' devices pull exactly these as a delta.
class AdminUploadScreen extends ConsumerStatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  ConsumerState<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends ConsumerState<AdminUploadScreen> {
  final _jsonCtrl = TextEditingController();
  DomainModel? _domain;
  SubjectModel? _subject;
  SubLevelModel? _subLevel;
  bool _busy = false;
  String? _status;

  // Progress (used mainly for large file uploads).
  int? _uploadTotal;
  int _uploadDone = 0;

  // Picked-file state. When non-null, the file path takes priority over the
  // paste box on Upload — this avoids ever loading thousands of questions'
  // worth of text into a TextField, which is slow to render and scroll.
  String? _pickedFileName;
  int? _pickedFileSizeBytes;
  List<Map<String, dynamic>>? _pickedValid;
  List<String> _pickedProblems = [];

  static const _sample = '''[
  {
    "question": "Who founded the Maurya Empire?",
    "options": ["Chandragupta Maurya", "Ashoka", "Bindusara", "Bimbisara"],
    "correctOptionIndex": 0,
    "explanation": "Chandragupta Maurya founded the empire in 322 BCE.",
    "difficulty": 1,
    "tags": ["mauryan", "ancient"]
  }
]''';

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Validates one decoded JSON item. Returns null if valid, else an error string.
  String? _validationError(dynamic decodedItem) {
    if (decodedItem is! Map) return 'not a JSON object';
    final q = (decodedItem['question'] ?? '').toString().trim();
    final opts = List<String>.from(decodedItem['options'] ?? const []);
    final correct = decodedItem['correctOptionIndex'];
    if (q.isEmpty) return 'empty question';
    if (opts.length < 2) return 'needs at least 2 options';
    if (correct is! int || correct < 0 || correct >= opts.length) {
      return 'correctOptionIndex must be 0..${opts.length - 1}';
    }
    return null;
  }

  /// Parses + validates a JSON array string. Returns (validItems, problems).
  (List<Map<String, dynamic>>, List<String>) _parseAndValidate(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw const FormatException('Top level JSON must be an array [ ... ]');
    }
    final valid = <Map<String, dynamic>>[];
    final problems = <String>[];
    for (var i = 0; i < decoded.length; i++) {
      final err = _validationError(decoded[i]);
      if (err != null) {
        problems.add('Item ${i + 1}: $err');
        continue;
      }
      valid.add(Map<String, dynamic>.from(decoded[i] as Map));
    }
    return (valid, problems);
  }

  // --------------------------- File picking ---------------------------------

  Future<void> _pickFile() async {
    // file_picker 11+ uses static methods (no more `.platform`), and 12+
    // returns the PlatformFile directly instead of a FilePickerResult wrapper.
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return;

    setState(() {
      _status = 'Reading ${picked.name}...';
      _busy = true;
      _pickedFileName = picked.name;
      // Size is derived from the bytes we read below rather than from the
      // picked file's metadata — that metadata getter has moved around
      // between file_picker versions, and the byte count is exact anyway.
      _pickedFileSizeBytes = null;
      _pickedValid = null;
      _pickedProblems = [];
    });

    // Yield one frame so the "Reading..." state actually paints before the
    // (synchronous) parse work runs — matters for large files (thousands of
    // questions), which can take a noticeable fraction of a second to parse.
    await Future.delayed(Duration.zero);

    try {
      // readAsBytes() works whether or not the file has a real on-disk path
      // (Android SAF picks sometimes don't), so it's safer than File(path).
      final bytes = await picked.readAsBytes();
      final text = utf8.decode(bytes);
      final (valid, problems) = _parseAndValidate(text);
      if (!mounted) return;
      setState(() {
        _pickedFileSizeBytes = bytes.length;
        _pickedValid = valid;
        _pickedProblems = problems;
        _jsonCtrl.clear(); // file takes priority over any pasted text
        _status = '${picked.name}: ${valid.length} valid question(s)'
            '${problems.isEmpty ? '' : ', ${problems.length} problem(s)'} found.';
      });
    } on FormatException catch (e) {
      _snack('Invalid JSON in file: ${e.message}');
      _clearPickedFile();
    } catch (e) {
      _snack('Could not read file: $e');
      _clearPickedFile();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearPickedFile() {
    setState(() {
      _pickedFileName = null;
      _pickedFileSizeBytes = null;
      _pickedValid = null;
      _pickedProblems = [];
    });
  }

  // ------------------------------- Upload ------------------------------------

  Map<String, dynamic> _buildDoc(
      Map<String, dynamic> raw, int index, int version) {
    final opts = List<String>.from(raw['options'] ?? const []);
    final id = (raw['id'] ?? '').toString().trim().isNotEmpty
        ? raw['id'].toString().trim()
        : '${_domain!.id}_${_subject!.id}_${DateTime.now().millisecondsSinceEpoch}_$index';

    return {
      'id': id,
      'domainId': _domain!.id,
      'domainName': _domain!.name,
      'subjectId': _subject!.id,
      'subjectName': _subject!.name,
      'subLevelId': _subLevel?.id,
      'subLevelName': _subLevel?.name,
      'question': (raw['question'] ?? '').toString().trim(),
      'options': opts,
      'correctOptionIndex': raw['correctOptionIndex'],
      'explanation': (raw['explanation'] ?? '').toString(),
      'difficulty': raw['difficulty'] is int ? raw['difficulty'] : 1,
      'tags': List<String>.from(raw['tags'] ?? const []),
      'isActive': raw['isActive'] is bool ? raw['isActive'] : true,
      'version': version,
    };
  }

  Future<void> _upload() async {
    if (_domain == null || _subject == null) {
      _snack('Pick a domain and subject first.');
      return;
    }
    final activeLevels = _subject!.subLevels.where((sl) => sl.isActive).toList();
    if (activeLevels.isNotEmpty && _subLevel == null) {
      final label = (_domain!.subLevelLabel?.trim().isNotEmpty ?? false)
          ? _domain!.subLevelLabel!.trim()
          : 'sub-level';
      _snack('"${_subject!.name}" is split into ${label}s — pick one.');
      return;
    }

    List<Map<String, dynamic>> sourceItems;
    if (_pickedValid != null) {
      if (_pickedValid!.isEmpty) {
        _snack('The selected file has no valid questions to upload.');
        return;
      }
      sourceItems = _pickedValid!;
    } else {
      if (_jsonCtrl.text.trim().isEmpty) {
        _snack('Pick a JSON file, or paste your questions JSON.');
        return;
      }
      try {
        final (valid, problems) = _parseAndValidate(_jsonCtrl.text);
        if (valid.isEmpty) {
          setState(() => _status =
              'No valid questions found.\n${problems.take(10).join('\n')}');
          _snack('Invalid JSON — see details below.');
          return;
        }
        sourceItems = valid;
        if (problems.isNotEmpty) {
          _snack('${problems.length} item(s) skipped — see details after upload.');
        }
      } on FormatException catch (e) {
        setState(() => _status = 'Invalid JSON: ${e.message}');
        _snack('Invalid JSON — see details.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _uploadTotal = sourceItems.length;
      _uploadDone = 0;
      _status = 'Checking for duplicates...';
    });

    // ── Duplicate blocking ──────────────────────────────────────────────
    // Exact question text (case-insensitive) within the SAME subject is
    // treated as a duplicate — both against questions already in Firestore
    // and against repeats within this same batch. Duplicates are dropped and
    // reported; the rest still upload.
    final fs = ref.read(firestoreServiceProvider);
    int droppedExisting = 0;
    int droppedInBatch = 0;
    try {
      final existing =
          await fs.fetchQuestionTextsForSubject(_domain!.id, _subject!.id);
      final seenThisBatch = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final item in sourceItems) {
        final key =
            (item['question'] ?? '').toString().trim().toLowerCase();
        if (key.isEmpty) continue;
        if (existing.contains(key)) {
          droppedExisting++;
          continue;
        }
        if (!seenThisBatch.add(key)) {
          droppedInBatch++;
          continue;
        }
        deduped.add(item);
      }
      sourceItems = deduped;
    } catch (e) {
      // If the duplicate check itself fails (e.g. offline), stop rather than
      // risk uploading duplicates silently.
      setState(() {
        _busy = false;
        _uploadTotal = null;
        _status = 'Could not check for duplicates: $e';
      });
      _snack('Duplicate check failed — nothing uploaded.');
      return;
    }

    if (sourceItems.isEmpty) {
      setState(() {
        _busy = false;
        _uploadTotal = null;
        _status = 'Nothing to upload — every question was a duplicate '
            '($droppedExisting already in this subject, '
            '$droppedInBatch repeated in the file).';
      });
      _snack('All questions were duplicates.');
      return;
    }

    final dupNote = (droppedExisting + droppedInBatch) > 0
        ? ' (skipped $droppedExisting already-present + $droppedInBatch repeated)'
        : '';

    setState(() {
      _uploadTotal = sourceItems.length;
      _status = 'Preparing ${sourceItems.length} questions$dupNote...';
    });

    try {
      final newVersion = _domain!.version + 1;
      final docs = [
        for (var i = 0; i < sourceItems.length; i++)
          _buildDoc(sourceItems[i], i, newVersion)
      ];

      final written = await fs.bulkUploadQuestions(
        docs,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _uploadDone = done;
            _status = 'Uploading... $done / $total';
          });
        },
      );

      setState(() => _status = 'Bumping domain version...');
      await fs.bumpDomainVersion(_domain!.id, newVersion);

      ref.invalidate(domainsProvider);
      ref.invalidate(adminDomainsProvider);
      setState(() {
        _status = 'Done. Uploaded $written questions$dupNote (domain now v$newVersion).';
        _jsonCtrl.clear();
      });
      _clearPickedFile();
      _snack('Uploaded $written questions.');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
      _snack('Upload failed.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadTotal = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(adminDomainsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Questions')),
      body: domainsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (domains) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy)
              _uploadTotal != null
                  ? LinearProgressIndicator(
                      value: _uploadDone / (_uploadTotal ?? 1))
                  : const LinearProgressIndicator(),
            if (_busy) const SizedBox(height: 12),

            DropdownButtonFormField<DomainModel>(
              value: _domain,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Domain', border: OutlineInputBorder()),
              items: domains
                  .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d.isActive ? d.name : '${d.name} (hidden)')))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (d) => setState(() {
                        _domain = d;
                        _subject = null;
                        _subLevel = null;
                      }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SubjectModel>(
              value: _subject,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Subject', border: OutlineInputBorder()),
              items: (_domain?.subjects ?? const <SubjectModel>[])
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.isActive ? s.name : '${s.name} (hidden)')))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (s) => setState(() {
                        _subject = s;
                        _subLevel = null;
                      }),
            ),
            if ((_subject?.subLevels ?? const <SubLevelModel>[]).isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<SubLevelModel>(
                value: _subLevel,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: (_domain?.subLevelLabel?.trim().isNotEmpty ?? false)
                      ? _domain!.subLevelLabel!.trim()
                      : 'Sub-level',
                  border: const OutlineInputBorder(),
                ),
                items: _subject!.subLevels
                    .map((sl) => DropdownMenuItem(
                        value: sl,
                        child:
                            Text(sl.isActive ? sl.name : '${sl.name} (hidden)')))
                    .toList(),
                onChanged: _busy ? null : (sl) => setState(() => _subLevel = sl),
              ),
            ],
            const SizedBox(height: 20),

            // ── File upload (recommended for large batches) ──────────────────
            Text('Upload a .json file',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Best for thousands of questions at once.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 8),

            if (_pickedFileName == null)
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open_rounded),
                label: const Text('Choose JSON file'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                onPressed: _busy ? null : _pickFile,
              )
            else
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.description_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_pickedFileName!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                            Text(
                              '${_pickedFileSizeBytes != null ? _formatBytes(_pickedFileSizeBytes!) : 'reading...'}'
                              '${_pickedValid != null ? '  •  ${_pickedValid!.length} valid' : ''}'
                              '${_pickedProblems.isNotEmpty ? '  •  ${_pickedProblems.length} problem(s)' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Remove file',
                        onPressed: _busy ? null : _clearPickedFile,
                      ),
                    ],
                  ),
                ),
              ),

            if (_pickedProblems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _pickedProblems.take(5).join('\n') +
                    (_pickedProblems.length > 5
                        ? '\n...and ${_pickedProblems.length - 5} more'
                        : ''),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],

            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('or paste JSON',
                    style: TextStyle(color: theme.hintColor)),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text('Questions JSON',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _jsonCtrl.text = _sample;
                            _clearPickedFile();
                          }),
                  child: const Text('Insert sample'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _jsonCtrl,
              maxLines: 10,
              enabled: _pickedFileName == null,
              onChanged: (_) {
                if (_pickedFileName != null) _clearPickedFile();
              },
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '[ { "question": "...", "options": [...], ... } ]',
                helperText: _pickedFileName != null
                    ? 'A file is selected above — remove it to paste instead.'
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(_pickedValid != null
                  ? 'Upload ${_pickedValid!.length} questions'
                  : 'Upload to Firestore'),
              onPressed: _busy ? null : _upload,
            ),

            if (_status != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_status!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
