import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../data/models/domain_model.dart';
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

  Future<void> _pickAndUpload() async {
    setState(() {
      _busy = true;
      _log.clear();
    });
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (picked == null) {
        _say('Cancelled.');
        return;
      }
      final bytes = await picked.readAsBytes();
      final raw = utf8.decode(bytes);
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _say('ERROR: file must be a JSON array of question objects.');
        return;
      }
      _say('Read ${decoded.length} row(s).');

      final fs = ref.read(firestoreServiceProvider);
      final domains = await fs.fetchAllDomainsForAdmin();

      // slug -> domain, and (domainSlug|subjectSlug) -> subject
      final domainBySlug = {for (final d in domains) d.id: d};

      var ok = 0, skipped = 0;
      final missing = <String>{};
      final grouped = <String, List<Map<String, dynamic>>>{};

      for (final row in decoded) {
        if (row is! Map) {
          skipped++;
          continue;
        }
        final m = Map<String, dynamic>.from(row);
        final dName = (m['domain'] ?? m['domainName'] ?? '').toString();
        final sName = (m['subject'] ?? m['subjectName'] ?? '').toString();
        if (dName.isEmpty || sName.isEmpty) {
          skipped++;
          continue;
        }
        final dSlug = slugify(dName);
        final sSlug = slugify(sName);
        final domain = domainBySlug[dSlug];
        final matches =
            domain?.subjects.where((x) => x.id == sSlug).toList() ?? const [];
        final subject = matches.isEmpty ? null : matches.first;

        if (domain == null || subject == null) {
          missing.add('$dName > $sName');
          if (!_createMissing) {
            skipped++;
            continue;
          }
        }
        grouped.putIfAbsent('$dSlug|$sSlug', () => []).add(m);
      }

      if (missing.isNotEmpty && !_createMissing) {
        _say('');
        _say('SKIPPED — these domain/subject pairs do not exist:');
        for (final x in missing) {
          _say('   • $x');
        }
        _say('');
        _say('Create them first in Domains & Subjects, or tick '
            '"create missing" and run again.');
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
          final raw = fresh[i];
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
          const SizedBox(height: 12),
          SwitchListTile(
            value: _createMissing,
            onChanged: _busy ? null : (v) => setState(() => _createMissing = v),
            title: const Text('Create missing domains/subjects'),
            subtitle: const Text(
                'Off by default so a typo cannot create a junk category. '
                'Anything created is hidden until you unhide it.'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52)),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose JSON file'),
            onPressed: _busy ? null : _pickAndUpload,
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
